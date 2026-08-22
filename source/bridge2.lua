-- Bridge between the Compy USB link and the robot radio.
-- Serial lines go out as radio datagrams and datagrams come
-- back as serial lines. The bridge does not read the
-- envelope: only its own control lines, which start with
-- "!", are its business. Grown from the REPL script: the
-- serial plumbing is kept as it was, the compiler, the echo
-- and the prompts are gone.

local uBit = microbit

local send = uBit.serial.send
local getChar = uBit.serial.getCharAsync
local transmit = uBit.radio.send
local recv = uBit.radio.recv

local function write(s)
  for c in string.gmatch(s, ".") do
    if c == "\n" then
      send("\r")
    end
    send(c)
  end
end

local function line_out(s)
  write(s .. "\n")
end

-- A datagram holds 32 bytes; a longer line has nowhere to go
local MAX_PAYLOAD = 32
-- Room for one payload plus a control line, then we skip
local MAX_LINE = 64

local buffer = ""
local skipping = false
local group = 0

-- Numbers never meet .. directly: the C number-to-string
-- conversion under concat is broken on this build (no float
-- printf), a number concatenated in becomes nothing. The
-- integer format works; the REPL works around it the same
-- way.
local function num(n)
  return string.format("%d", n)
end

local function bridge_control(line)
  local name, arg = string.match(line, "^!(%a)%s*(.*)$")
  name = name and string.lower(name)
  if name == "g" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 255 then
      group = n
      uBit.radio.setGroup(group)
      line_out("!ok group " .. num(group))
    else
      line_out("!err group takes 0..255")
    end
  elseif name == "p" then
    local n = tonumber(arg)
    if n and n >= 0 and n <= 7 then
      uBit.radio.setTransmitPower(n)
      line_out("!ok power " .. num(n))
    else
      line_out("!err power takes 0..7")
    end
  elseif name == "v" then
    line_out("!ok bridge 1 group " .. num(group))
  else
    line_out("!err unknown control " .. line)
  end
end

local function enter()
  local line = buffer
  buffer = ""
  if skipping then
    skipping = false
    line_out("!err line over " .. num(MAX_LINE) .. " bytes dropped")
  elseif line == "" then
  elseif string.sub(line, 1, 1) == "!" then
    bridge_control(line)
  elseif #line > MAX_PAYLOAD then
    line_out("!err line of " .. num(#line) .. " bytes over the "
      .. num(MAX_PAYLOAD) .. " byte datagram")
  elseif not transmit(line) then
    line_out("!err radio send failed")
  end
end

local function take(c)
  if c == "\r" or c == "\n" then
    enter()
  elseif skipping then
    return
  elseif #buffer >= MAX_LINE then
    buffer = ""
    skipping = true
  else
    buffer = buffer .. c
  end
end

local handler = { }

microbit.handler = handler

handler[microbit.DEVICE_ID_SERIAL] = function(value)
  if value == microbit.CODAL_SERIAL_EVT_HEAD_MATCH then
    local c = getChar()
    while c do
      take(c)
      c = getChar()
    end
    uBit.serial.eventAfterAsync(1)
  end
end

handler[microbit.DEVICE_ID_RADIO] = function(value)
  if value == microbit.MICROBIT_RADIO_EVT_DATAGRAM then
    local msg = recv()
    if msg then
      line_out(msg)
    end
  end
end

function on_event(source, value, timestamp)
  local handle = handler[source]
  if handle then
    handle(value, timestamp)
  end
end

-- The startup order of the REPL this grew from: one line
-- out, radio up, then the serial events armed.
line_out("!ok bridge 1 group " .. num(group))
uBit.radio.enable()
uBit.radio.setGroup(group)
uBit.display.scrollAsync("br2")
uBit.serial.getCharAsync()
uBit.serial.eventAfterAsync(1)
