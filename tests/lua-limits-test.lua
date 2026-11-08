-- Lua's call limits with this firmware's patches, run by
-- lua-limits-host-tests.sh: a runaway recursion stops with an error, at the
-- same depth however the frame array grew before, including after an
-- overflow caught in the last frame that fits.

local failures, checks = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then failures = failures + 1 end
  print((ok and "ok   " or "FAIL ") .. what)
end

-- A recursion with no base case; reached is how deep it got.
local reached
local function climb(n)
  reached = n
  return 1 + climb(n + 1)
end

-- How deep a runaway recursion gets before it stops, and its error.
local function edge()
  reached = 0
  local _, err = pcall(climb, 1)
  return reached, err
end

-- The first runaway, before anything has grown the array of call frames.
local fresh, err = edge()
check(err:find("stack overflow", 1, true) ~= nil,
      "a runaway recursion stops with \"stack overflow\"")
check(fresh > 100 and fresh < 128,
      "it stops at " .. fresh .. " levels, between 100 and 128")
check(edge() == fresh, "a second runaway stops at the same depth")

-- d levels down, catch a runaway; past the limit, the descent itself
-- overflows and the outer pcall catches it. One of these catches the
-- overflow in the last frame that fits.
local function catch_at(d)
  if d == 0 then return pcall(climb, 1) end
  return (catch_at(d - 1))
end
local same = true
for d = 0, 140 do
  pcall(catch_at, d)
  if edge() ~= fresh then same = false end
  if d % 16 == 0 then
    collectgarbage()
    if edge() ~= fresh then same = false end
  end
end
check(same, "after an overflow caught at each depth up to 140, and after "
      .. "collections, a runaway still stops at " .. fresh .. " levels")

print(checks .. " limit checks, " .. failures .. " failed")
os.exit(failures == 0 and 0 or 1)
