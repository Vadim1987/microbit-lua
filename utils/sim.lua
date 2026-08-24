-- Protocol simulation: does one previous identifier suffice
-- for duplicate suppression on the robot, or does it need a
-- bounded history? Discrete-event, pure Lua 5.1, no board.
--
-- The transport is stop-and-wait: send COMMAND id, wait for
-- ACK id, retry on a 30 ms timeout, next command only after
-- the ACK. The robot executes a command whose id it does
-- not remember, and acknowledges every command. The channel
-- loses a datagram with probability p per direction and
-- delivers with a latency; a delayed copy models what the
-- bridge buffer and the radio queue did on hardware.
--
-- Measured inputs (RADIO-MEASUREMENTS.md): one-way latency
-- ~2.5 ms on a healthy link, loss 0.5% typical, 3.5% weak,
-- 5% pessimistic. Delay spikes: a datagram survives but
-- arrives late, as seen at max power point-blank.
--
-- Usage: lua sim.lua [runs] [seed]

local runs = tonumber(arg and arg[1]) or 10000
local seed = tonumber(arg and arg[2]) or 42

local TIMEOUT = 30
local RETRIES = 5
local ONE_WAY = 2.5

-- One scenario: a sequence of commands through the channel
-- against a robot with the given dedup policy.
-- policy: history size; 1 is the one-previous-id design.
-- p: loss per direction. spike_p/spike_ms: a surviving
-- datagram is delayed this much with this probability.
local function run_one(commands, policy, p, spike_p, spike_ms)
  local pending = { }   -- datagrams in flight: { at, kind, id }
  local now = 0
  local history = { }   -- robot's remembered ids, newest first
  local executed = { }  -- id -> times executed
  local doubles = 0
  local gave_up = 0

  local function fly(kind, id)
    if math.random() < p then
      return
    end
    local dt = ONE_WAY
    if math.random() < spike_p then
      dt = dt + spike_ms
    end
    table.insert(pending, { at = now + dt, kind = kind, id = id })
  end

  local function deliver_due()
    local keep = { }
    local arrived = { }
    for _, d in ipairs(pending) do
      if d.at <= now then
        table.insert(arrived, d)
      else
        table.insert(keep, d)
      end
    end
    pending = keep
    table.sort(arrived, function(a, b) return a.at < b.at end)
    return arrived
  end

  local highest = 0

  local function robot_gets(id)
    local fresh
    if policy == "monotonic" then
      fresh = id > highest
      if fresh then highest = id end
    else
      fresh = true
      for _, h in ipairs(history) do
        if h == id then
          fresh = false
          break
        end
      end
      if fresh then
        table.insert(history, 1, id)
        if #history > policy then
          table.remove(history)
        end
      end
    end
    if fresh then
      executed[id] = (executed[id] or 0) + 1
      if executed[id] > 1 then
        doubles = doubles + 1
      end
    end
    fly("ack", id)
  end

  for id = 1, commands do
    local acked = false
    local tries = 0
    while not acked and tries <= RETRIES do
      fly("cmd", id)
      tries = tries + 1
      local deadline = now + TIMEOUT
      while now < deadline and not acked do
        now = now + 0.5
        for _, d in ipairs(deliver_due()) do
          if d.kind == "cmd" then
            robot_gets(d.id)
          elseif d.kind == "ack" and d.id == id then
            acked = true
          end
        end
      end
    end
    if not acked then
      gave_up = gave_up + 1
    end
  end

  -- drain: late copies keep arriving after the run
  local horizon = now + 1000
  while now < horizon and #pending > 0 do
    now = now + 0.5
    for _, d in ipairs(deliver_due()) do
      if d.kind == "cmd" then
        robot_gets(d.id)
      end
    end
  end

  return doubles, gave_up
end

local function series(name, policy, p, spike_p, spike_ms)
  math.randomseed(seed)
  local doubles, gave_up, worst = 0, 0, 0
  for _ = 1, runs do
    local d, g = run_one(20, policy, p, spike_p, spike_ms)
    doubles = doubles + d
    gave_up = gave_up + g
    if d > worst then worst = d end
  end
  local total = runs * 20
  print(string.format(
    "%-28s doubles %6d /%d (worst run %d)  gave up %d",
    name, doubles, total, worst, gave_up))
end

print(string.format("runs %d x 20 commands, seed %d", runs, seed))
print("")
print("policy: one previous id")
series("  loss 0.5%", 1, 0.005, 0, 0)
series("  loss 3.5%", 1, 0.035, 0, 0)
series("  loss 5%", 1, 0.05, 0, 0)
series("  loss 5% + spikes 40ms/5%", 1, 0.05, 0.05, 40)
series("  loss 5% + spikes 300ms/5%", 1, 0.05, 0.05, 300)
print("")
print("policy: highest id wins (monotonic)")
series("  loss 5% + spikes 40ms/5%", "monotonic", 0.05, 0.05, 40)
series("  loss 5% + spikes 300ms/5%", "monotonic", 0.05, 0.05, 300)
print("")
print("policy: history of 8")
series("  loss 5%", 8, 0.05, 0, 0)
series("  loss 5% + spikes 40ms/5%", 8, 0.05, 0.05, 40)
series("  loss 5% + spikes 300ms/5%", 8, 0.05, 0.05, 300)
