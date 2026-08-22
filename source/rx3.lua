-- Quiet envelope receiver for radio measurements. No serial
-- IO at all: a print into a port nobody reads freezes the
-- board, and a measurement series must survive unattended.
-- Liveness is on the display: the last digit of each ACKed
-- id. Same envelope as rx2: ACK, one-previous-id dedup,
-- PING, error on bare lines.

local uBit = microbit

local transmit = uBit.radio.send
local recv = uBit.radio.recv

local last_id = nil

local function onRadioMessage(msg)
  local id = string.match(msg, "^COMMAND (%d+) ")
  if id then
    if id ~= last_id then
      last_id = id
    end
    transmit("ACK " .. id .. " 1")
    uBit.display.print(string.sub(id, -1))
  elseif msg == "PING" then
    transmit("PONG")
  else
    transmit("ERR not enveloped")
  end
end

local handler = { }

microbit.handler = handler

handler[microbit.DEVICE_ID_RADIO] = function(value)
  if value == microbit.MICROBIT_RADIO_EVT_DATAGRAM then
    local msg = recv()
    if msg then
      onRadioMessage(msg)
    end
  end
end

function on_event(source, value, timestamp)
  local handle = handler[source]
  if handle then
    handle(value, timestamp)
  end
end

uBit.radio.enable()
uBit.display.scrollAsync("r3")
