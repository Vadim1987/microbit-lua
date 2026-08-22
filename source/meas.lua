-- Radio measurement driver. Sits on the Mac under screen and
-- drives series of enveloped commands over the air; the far
-- side is the quiet envelope receiver. Controls:
--   !v          version
--   !g N        radio group 0..255
--   !p N        transmit power 0..7
--   !m N GAP    series: N commands, GAP ms between sends
-- Reports one summary line per series:
--   !res sent N ack K lost L late D min A avg B max C ms
-- Numbers go out through num(): the C number-to-string
-- conversion under concat loses the number on this build.

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

local function num(n)
  return string.format("%d", n)
end

local MAX_LINE = 64
local TIMEOUT = 250

local buffer = ""
local skipping = false
local group = 0
local next_id = 100

-- set by the radio handler, read by the series loop
local waiting = nil
local got_at = nil
local late = 0

local function series(count, gap)
  local acked, lost = 0, 0
  local dmin, dmax, dsum = nil, nil, 0
  late = 0
  local i = 1
  while i <= count do
    local id = num(next_id)
    next_id = next_id + 1
    waiting = id
    got_at = nil
    local t0 = uBit.systemTime()
    if transmit("COMMAND " .. id .. " T") then
      while not got_at and uBit.systemTime() - t0 < TIMEOUT do
        uBit.sleep(2)
      end
      if got_at then
        local dt = got_at - t0
        acked = acked + 1
        dsum = dsum + dt
        if not dmin or dt < dmin then dmin = dt end
        if not dmax or dt > dmax then dmax = dt end
      else
        lost = lost + 1
      end
    else
      lost = lost + 1
    end
    waiting = nil
    uBit.sleep(gap)
    i = i + 1
  end
  local avg = acked > 0 and (dsum - dsum % acked) / acked or 0
  line_out("!res sent " .. num(count) ..
    " ack " .. num(acked) ..
    " lost " .. num(lost) ..
    " late " .. num(late) ..
    " min " .. num(dmin or 0) ..
    " avg " .. num(avg) ..
    " max " .. num(dmax or 0) .. " ms")
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
  elseif name == "m" then
    local count, gap = string.match(arg, "^(%d+)%s+(%d+)$")
    count = tonumber(count)
    gap = tonumber(gap)
    if count and count >= 1 and count <= 1000
       and gap and gap >= 0 and gap <= 5000 then
      line_out("!run " .. num(count) .. " gap " .. num(gap))
      series(count, gap)
    else
      line_out("!err m takes count 1..1000 and gap 0..5000")
    end
  elseif name == "v" then
    line_out("!ok meas 1 group " .. num(group))
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
  elseif line ~= "" then
    if string.sub(line, 1, 1) == "!" then
      bridge_control(line)
    else
      line_out("!err not a control line")
    end
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

-- Tiny on purpose: sets flags for the sleeping series loop
-- and never sleeps itself.
handler[microbit.DEVICE_ID_RADIO] = function(value)
  if value == microbit.MICROBIT_RADIO_EVT_DATAGRAM then
    local msg = recv()
    if msg then
      local id = string.match(msg, "^ACK (%d+) ")
      if id and id == waiting then
        got_at = uBit.systemTime()
      else
        late = late + 1
      end
    end
  end
end

function on_event(source, value, timestamp)
  local handle = handler[source]
  if handle then
    handle(value, timestamp)
  end
end

line_out("!ok meas 1 group " .. num(group))
uBit.radio.enable()
uBit.radio.setGroup(group)
uBit.display.scrollAsync("m")
uBit.serial.getCharAsync()
uBit.serial.eventAfterAsync(1)
