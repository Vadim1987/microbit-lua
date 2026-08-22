-- Runs bridge2.lua against a stubbed micro:bit. The stub's
-- send receives one char at a time, as the real write does.

local out, air, chars = { }, { }, { }

local function feed(s)
  for c in string.gmatch(s, ".") do
    table.insert(chars, c)
  end
end

microbit = {
  DEVICE_ID_SERIAL = 1,
  DEVICE_ID_RADIO = 2,
  CODAL_SERIAL_EVT_HEAD_MATCH = 10,
  MICROBIT_RADIO_EVT_DATAGRAM = 20,
  serial = {
    send = function(s) table.insert(out, s) end,
    getCharAsync = function() return table.remove(chars, 1) end,
    eventAfterAsync = function() end,
  },
  radio = {
    enable = function() return true end,
    setGroup = function() return true end,
    setTransmitPower = function() return true end,
    send = function(s) table.insert(air, s) return true end,
    recv = function() return microbit._incoming end,
  },
  display = { scrollAsync = function() end },
}

dofile('source/bridge2.lua')

local function stream()
  return table.concat(out)
end

local function serial(s)
  feed(s)
  on_event(microbit.DEVICE_ID_SERIAL,
    microbit.CODAL_SERIAL_EVT_HEAD_MATCH)
end

local function radio(s)
  microbit._incoming = s
  on_event(microbit.DEVICE_ID_RADIO,
    microbit.MICROBIT_RADIO_EVT_DATAGRAM)
end

local failures = 0

local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print('FAIL ' .. name)
    print('  got:  ' .. tostring(got))
    print('  want: ' .. tostring(want))
  else
    print('ok   ' .. name)
  end
end

local function ends(want)
  local s = stream()
  return string.sub(s, -#want)
end

check('banner', stream(), '!ok bridge 1 group 0\r\n')
local mark = #stream()

serial('COMMAND 41 M 40 40 1000\r')
check('line goes to the air', air[1], 'COMMAND 41 M 40 40 1000')
check('and nothing is echoed', #stream(), mark)

radio('ACK 41 1')
local w = 'ACK 41 1\r\n'
check('datagram comes back as a line', ends(w), w)

serial('!g 7\r')
w = '!ok group 7\r\n'
check('group is set', ends(w), w)

serial('!p 2\r')
w = '!ok power 2\r\n'
check('power is set', ends(w), w)

serial('!p 9\r')
w = '!err power takes 0..7\r\n'
check('power range is checked', ends(w), w)

serial('!z\r')
w = '!err unknown control !z\r\n'
check('unknown control is named', ends(w), w)

local long = string.rep('x', 33)
serial(long .. '\r')
w = '!err line of 33 bytes over the 32 byte datagram\r\n'
check('overlong payload is refused', ends(w), w)
check('and nothing went to the air', #air, 1)

serial('PING\n')
check('a line feed ends a line too', air[2], 'PING')

serial('AB')
check('a partial line waits', #air, 2)
serial('C\r')
check('and completes on the terminator', air[3], 'ABC')

serial('X\r\n')
check('a CRLF pair makes one line, not two', air[4], 'X')
local n = #air
serial('\r\n\r\n')
check('bare terminators make no lines', #air, n)

local flood = string.rep('y', 70)
serial(flood .. '\r')
w = '!err line over 64 bytes dropped\r\n'
check('a line over the buffer is dropped', ends(w), w)

serial('PING\r')
check('and the next line is clean', air[#air], 'PING')

print('')
if failures == 0 then
  print('all checks passed')
else
  print(failures .. ' failed')
  os.exit(1)
end
