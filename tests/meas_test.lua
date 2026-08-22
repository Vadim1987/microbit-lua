-- The measurement driver against a stub with a virtual
-- clock: transmit schedules an ACK after a set delay, sleep
-- advances time and delivers what is due.
local say = print
local out, air = { }, { }
local now = 0
local pending = { }   -- { at = t, msg = s }
local plan = { }      -- per-send: delay in ms, or false = lose

local function deliver()
  local keep = { }
  for _, p in ipairs(pending) do
    if p.at <= now then
      microbit._incoming = p.msg
      on_event(2, 20)
    else
      table.insert(keep, p)
    end
  end
  pending = keep
end

microbit = {
  DEVICE_ID_SERIAL = 1,
  DEVICE_ID_RADIO = 2,
  CODAL_SERIAL_EVT_HEAD_MATCH = 10,
  MICROBIT_RADIO_EVT_DATAGRAM = 20,
  systemTime = function() return now end,
  sleep = function(ms) now = now + ms; deliver() end,
  serial = {
    send = function(s) table.insert(out, s) end,
    getCharAsync = function()
      return table.remove(microbit._chars or { }, 1)
    end,
    eventAfterAsync = function() end,
  },
  radio = {
    enable = function() return true end,
    setGroup = function() return true end,
    setTransmitPower = function() return true end,
    send = function(s)
      table.insert(air, s)
      local d = table.remove(plan, 1)
      if d ~= false and d ~= nil then
        local id = string.match(s, "^COMMAND (%d+) ")
        table.insert(pending, { at = now + d, msg = "ACK " .. id .. " 1" })
      end
      return true
    end,
    recv = function() return microbit._incoming end,
  },
  display = { scrollAsync = function() end },
}

dofile('source/meas.lua')

local function serial(s)
  microbit._chars = { }
  for c in string.gmatch(s, ".") do
    table.insert(microbit._chars, c)
  end
  on_event(1, 10)
end

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    say('FAIL ' .. name .. '\n  got:  ' .. tostring(got) ..
      '\n  want: ' .. tostring(want))
  else
    say('ok   ' .. name)
  end
end

local function stream() return table.concat(out) end
local function ends(w) return string.sub(stream(), -#w) end

-- three sends: 10 ms, lost, 30 ms
plan = { 10, false, 30 }
serial('!m 3 5\r')
local w = '!res sent 3 ack 2 lost 1 late 0 min 10 avg 20 max 30 ms\r\n'
check('series summary', ends(w), w)
check('three went to the air', #air, 3)
check('ids are sequential', air[1], 'COMMAND 100 T')
check('and keep counting', air[3], 'COMMAND 102 T')

-- a late ACK: delay beyond the 250 ms timeout
plan = { 400 }
serial('!m 1 500\r')
w = '!res sent 1 ack 0 lost 1 late 1 min 0 avg 0 max 0 ms\r\n'
check('late ack counted, not credited', ends(w), w)

serial('!m 0 5\r')
w = '!err m takes count 1..1000 and gap 0..5000\r\n'
check('count range is checked', ends(w), w)

say('')
if failures == 0 then say('all checks passed')
else say(failures .. ' failed'); os.exit(1) end
