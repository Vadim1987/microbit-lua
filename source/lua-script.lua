local uBit = microbit

local heart = {
  width = 10,
  height = 5,
  data = {
      0,   0,   0,   0,   0,    0, 255,   0, 255,   0,
      0, 255,   0, 255,   0,  255,  64, 255,  64, 255,
      0, 255, 255, 255,   0,  255,  64,  64,  64, 255,
      0,   0, 255,   0,   0,    0, 255,  64, 255,   0,
      0,   0,   0,   0,   0,    0,   0, 255,   0,   0
  }
}

uBit.audio.setVolume(20)
uBit.audio.express("giggle")
uBit.display.animate(heart, 1000, 5)
uBit.display.scrollAsync(uBit.friendlyName())

local serial = {
  send = uBit.serial.send,
  getCharAsync = uBit.serial.getCharAsync,
  eventAfterAsync = uBit.serial.eventAfterAsync,
}

local ble_uart = nil
if uBit.ble and uBit.ble.uart then
  ble_uart = {
    send = uBit.ble.uart.send,
    getCharAsync = uBit.ble.uart.getCharAsync,
    eventAfterAsync = uBit.ble.uart.eventAfterAsync,
  }
end

local function serial_write(s)
  for c in string.gmatch(s, ".") do
    if c == "\n" then
      serial.send("\r")
    end
    serial.send(c)
  end
end

local function ble_write(s)
  if ble_uart then
    ble_uart.send(s)
  end
end

-- Output routing: print()/io.write() are shared globals that both the REPL
-- engine and arbitrary user code call, and their output must go back to the
-- session that issued the command. The destination can't be passed lexically:
-- user chunks compile against a shared env, and event handlers
-- (microbit.handler[...]) run with no session at all. So each session
-- saves/restores itself as `active_session` around its event processing, and
-- write() routes to that session's transport, falling back to serial when no
-- session is active.
local active_session = nil

local function write(s)
  if active_session then
    active_session.transport.write(s)
  else
    serial_write(s)
  end
end

io = {
  write = write
}

local unpack = unpack or table.unpack

local function is_identifier(str)
  return type(str) == "string"
    and str:match("^[%a_][%w_]*$")
end

local prettyprint = { }

local function serialize(value, visited)
  visited = visited or {}
  local pp = prettyprint[type(value)]
  if pp then
    return pp(value, visited)
  end
  return tostring(value)
end

function prettyprint.string(value)
  return string.format("%q", value)
end

local function key(k, visited)
  if is_identifier(k) then
    return k
  else
    return "[" .. serialize(k, visited) .. "]"
  end
end

local function table_tokens(value, visited)
  local out = {"{"}
  local first = true
  for k, v in pairs(value) do
    if not first then
       table.insert(out, ", ")
    end
    first = false
    table.insert(out, key(k, visited) .. " = " .. serialize(v, visited))
  end
  table.insert(out, "}")
  return out
end

function prettyprint.table(value, visited)
  if visited[value] then
    return "<cycle>"
  end
  visited[value] = true
  local out = table_tokens(value, visited)
  visited[value] = nil
  return table.concat(out)
end

local function print_values(serialize, ...)
  local n = select("#", ...)
  if n == 0 then
    return
  end
  local out = { }
  for i = 1, n do
    table.insert(out, serialize(select(i, ...)))
  end
  write(table.concat(out, "\t") .. "\n")
end

local env = { }
setmetatable(env, {
  __index = _G
})

local function load_with_env(code, chunkname)
  local fn, err = loadstring(code, chunkname)
  if fn then
    setfenv(fn, env)
  end
  return fn, err
end

local function is_incomplete(err)
  return err and err:find("near '<eof>'", 1, true) ~= nil
end

local function compile_try(code)
  local chunk, err = load_with_env(code, "REPL")
  if chunk then
    return chunk
  elseif is_incomplete(err) then
    return nil, err, true
  end
  return chunk, err, false
end

local function compile(code)
  local chunk, err, incomp = compile_try(code)
  if incomp then
    local e_chunk, e_err = compile_try("return " .. code)
    if e_chunk then
      return e_chunk, e_err
    end
    return chunk, err, true
  end
  if chunk then
    local e_chunk, e_err = compile_try("return " .. code)
    if e_chunk then
      return e_chunk, e_err
    end
    return chunk
  end
  local e_chunk, e_err, e_incomp =
    compile_try("return " .. code)
  if e_chunk or e_incomp then
    return e_chunk, e_err, e_incomp
  end
  return nil, err or e_err, false
end

function print(...)
  print_values(tostring, ...)  
end

local to_string = tostring

local PRECISION = 1e-6

local function fraction(o, i, f)
  local p = PRECISION
  while f >= p do
    i, f = math.modf(10 * f)
    table.insert(o, string.format("%d", i))
    p = 10 * p
  end
end

local function number2str(n)
  local i, f = math.modf(n)
  local o = {
    string.format("%d", i)
  }
  if f >= PRECISION then
    table.insert(o, ".")
    fraction(o, i, f)
  end
  return table.concat(o)
end

function tostring(o)
  if type(o) ~= "number" then
    return to_string(o)
  end
  return number2str(o)
end

collectgarbage("setpause", 100)
print("micro:bit\nLua 5.1 REPL")

local function execute(chunk)
  local results = { pcall(chunk) }
  if results[1] then
    if #results > 1 then
      local out = { }
      for i = 2, #results do
        table.insert(out, serialize(results[i]))
      end
      print("=> " .. table.concat(out, "\t"))
    end
  else
    print("Runtime error: " .. tostring(results[2]))
  end
end

-- A REPL session: a buffer plus the compile-driven submit loop. The
-- same engine is used for the serial console and the BLE UART service.
local function make_session(transport)
  local s = {
    transport = transport,
    buffer = "",
  }
  function s.prompt()
    write(s.buffer == "" and "> " or ">> ")
  end
  function s.submit(text)
    s.buffer = s.buffer .. text .. "\n"
    if s.transport.crlf_before_result then
      write("\r\n")
    end
    local chunk, err, incomplete = compile(s.buffer)
    if not incomplete then
      if chunk then
        execute(chunk)
      else
        print("Compile error: " .. tostring(err))
      end
      s.buffer = ""
    end
    collectgarbage("collect")
    s.prompt()
  end
  function s.run(f)
    local saved = active_session
    active_session = s
    f()
    active_session = saved
  end
  return s
end

local serial_session = make_session({
  write = serial_write,
  crlf_before_result = true,
  getChar = serial.getCharAsync,
  arm = function() serial.eventAfterAsync(1) end
})

local ble_session = make_session({
  write = ble_write,
  crlf_before_result = false,
  getChar = ble_uart and ble_uart.getCharAsync,
  arm = function() if ble_uart then ble_uart.eventAfterAsync(1) end end
})

local handler = { }

microbit.handler = handler

local function enter()
  serial_session.submit("")
end

local function backspace()
  if #serial_session.buffer > 0 then
    serial_session.buffer = serial_session.buffer:sub(1, -2)
    write("\b \b")
  end
end

local keypress = {
  ["\r"] = enter,
  ["\n"] = enter,
  ["\b"] = backspace,
  ["\127"] = backspace
}

handler[microbit.DEVICE_ID_SERIAL] = function(value)
  if value == microbit.CODAL_SERIAL_EVT_HEAD_MATCH then
    serial_session.run(function()
      local c = serial_session.transport.getChar()
      local echo = ""
      while c do
        local input = keypress[c]
        if input then
          if #echo > 0 then
            serial_write(echo)
            echo = ""
          end
          input()
        else
          serial_session.buffer = serial_session.buffer .. c
          echo = echo .. c
        end
        c = serial_session.transport.getChar()
      end
      if #echo > 0 then
        serial_write(echo)
      end
      serial_session.transport.arm()
    end)
  end
end

-- BLE UART input is framed: [2-byte big-endian length][payload bytes].
-- Payload is raw Lua source and may contain newlines. On a complete
-- frame we hand it to the shared submit loop, which uses compile
-- detection for multi-line continuation.
local ble_parser = { state = "len_hi" }
local BLE_MAX_FRAME = 1024
local ble_greeted = false

local function ble_feed(c)
  local b = string.byte(c)
  local st = ble_parser.state
  if st == "len_hi" then
    ble_parser.len_hi = b
    ble_parser.state = "len_lo"
  elseif st == "len_lo" then
    local n = ble_parser.len_hi * 256 + b
    if n == 0 then
      ble_parser.state = "len_hi"
      if not ble_greeted then
        ble_greeted = true
        write("micro:bit BLE REPL (Lua 5.1)\r\n")
      end
      ble_session.submit("")
    elseif n > BLE_MAX_FRAME then
      ble_parser.state = "len_hi"
    else
      ble_parser.remaining = n
      ble_parser.payload = ""
      ble_parser.state = "payload"
    end
  elseif st == "payload" then
    ble_parser.payload = ble_parser.payload .. c
    ble_parser.remaining = ble_parser.remaining - 1
    if ble_parser.remaining == 0 then
      ble_parser.state = "len_hi"
      ble_session.submit(ble_parser.payload)
    end
  end
end

if microbit.MICROBIT_ID_BLE_UART then
  handler[microbit.MICROBIT_ID_BLE_UART] = function(value)
    if value == microbit.MICROBIT_UART_S_EVT_HEAD_MATCH then
      ble_session.run(function()
        local c = ble_session.transport.getChar()
        while c do
          ble_feed(c)
          c = ble_session.transport.getChar()
        end
        ble_session.transport.arm()
      end)
    end
  end

  handler[microbit.MICROBIT_ID_BLE] = function(value)
    if value == microbit.MICROBIT_BLE_EVT_DISCONNECTED then
      ble_greeted = false
    end
  end
end

local function button(value, btn)
  if value == microbit.DEVICE_BUTTON_EVT_CLICK then
      uBit.display.scroll(btn)
   elseif value == microbit.DEVICE_BUTTON_EVT_LONG_CLICK then
      uBit.display.scroll(btn .. "!")
  end
end

handler[microbit.DEVICE_ID_BUTTON_A] = function(value)
  button(value, "A")
end

handler[microbit.DEVICE_ID_BUTTON_B] = function(value)
  button(value, "B")
end

handler[microbit.DEVICE_ID_BUTTON_AB] = function(value)
  button(value, "AB")
end

function on_event(source, value, timestamp)
  local handle = handler[source]
  if handle then
    handle(value, timestamp)
  end
end

-- Script-level setup (runs once before the main fiber
-- is released):
-- show prompt, initialise the serial RX buffer, and arm
-- the first per-char head-match event on both transports.
-- After this returns, release_fiber() in main() hands
-- control to the scheduler; on_event() handles all events 
-- from the bus.
serial_session.prompt()
serial.getCharAsync()
serial.eventAfterAsync(1)
if ble_uart then
  ble_uart.eventAfterAsync(1)
end
