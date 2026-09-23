# RAM usage and how to lower it

Numbers are for the nRF52833 micro:bit v2 build in this repo. Static sizes come
from `build/MICROBIT.map`; Lua-heap figures are on-device `LUA_MEM_DEBUG`
readings (see *Method*).

## Part 1 — where the RAM goes

Total RAM is 128 KB (`0x20000000`–`0x20020000`).

### Fixed / static

| region | size | notes |
|---|---:|---|
| SoftDevice (BLE blob) | ~8 KB | `0x20000000`–`0x20002040`, outside the app linker region |
| `.data` | 0.7 KB | initialized C/C++ data, copied from flash |
| `.bss` | 8.1 KB | zero-initialized C/C++ data |
| `.stack` | 8 KB | one shared execution stack for all fibers (raised from 2 KB after stack-guard panics) |
| heap | ~103 KB | everything else; grows up to the stack floor |

The embedded Lua script is **not** in RAM: `source/lua-script.lua` is
`objcopy`'d into the read-only `.lua_script` flash section and read in place via
`__lua_meta.start` (`source/main.cpp`). The cost is the parsed `Proto`, not the
text.

### Lua heap (the tunable part)

On-device `LUA_MEM_DEBUG` deltas between the boot markers:

| item | size | marker delta |
|---|---:|---|
| Lua state (empty) | 2.6 KB | `state − boot` |
| base/table/string/math libraries | 9.6 KB | `stdlib − state` |
| `microbit.*` API namespace tables | 16.2 KB | `api − stdlib` |
| embedded script `Proto` (with debug info) | 19.2 KB | `loaded − api` |
| ↳ debug info freed by S2 | −7.6 KB | `stripped − loaded` |
| embedded script `Proto` (stripped) | 11.6 KB | `stripped − api` |
| script runtime state (`handler`, `env`, sessions, `prettyprint`) | 1.4 KB | `ran − stripped` |

The API tables are the single largest identified consumer — larger than the
entire stripped script `Proto`.

#### `microbit.*` table breakdown

LP32 sizes (identical to the ARM target): `TValue`=16, `Node`=32, `CClosure`=32,
`TString`=16, `Table`=36.

| item | count | bytes |
|---|---:|---:|
| hash nodes | 215 | 6,880 |
| C closures (one per registered function) | 138 | 4,416 |
| interned names (115 functions + 41 constants + 11 fields) | 167 | ~5,584 |
| table headers | 11 | 396 |
| **total** | | **~16.9 KB** |

Per-table node counts: `microbit` 64, `display` 32, `serial` 32, `io` 32,
`compass` 16, `ble.uart` 16, `accelerometer` 8, `radio` 8, `audio` 4, `i2c` 2,
`ble` 1. (`microbit` has 58 fields — 8 functions + 9 subtables + 41 constants —
which forces a 64-node table.) On device this matches: `api − stdlib` = 16,575 B.

#### Embedded script `Proto` breakdown

On-device deltas, with the stripped bytecode dump as a cross-check (39 protos,
1015 instructions, 215 numeric constants, 184 string constants):

| portion | size |
|---|---:|
| loaded `Proto` with debug info (`loaded − api`) | 19,640 B |
| debug info (`lineinfo`, `locvars`, upvalue names), freed by S2 | 7,740 B |
| stripped `Proto` (`stripped − api`) | 11,900 B |
| raw `code` arrays (dump) | 4,060 B |

The text parser always generates the debug info; S2 frees it after load, which
lowers the steady-state heap by 5,919 B (`ran` 48,249 B → 42,330 B).

## Part 2 — strategies to lower RAM

### S1. Lazy API namespace dispatch — ~8–12 KB, moderate risk

Create each `microbit.*` table with a metatable `__index` C function backed by
the existing static `luaL_Reg` arrays, and cache a method in the table only when
it is first touched. The built-in REPL uses ~30–40 of the 138 methods, so most
of the C closures (4.4 KB), hash nodes (up to 6.9 KB), and interned names
(up to 5.6 KB) are never allocated.

Trade-offs:

- methods no longer appear in `pairs()` / `rawget()` on the API tables;
- a cache miss costs a short linear scan of the static array;
- touching every method (unusual) returns to today's footprint.

### S2. Strip debug info from the embedded chunk — implemented, 7.6 KB

Implemented in `source/lua-strip-debug.c` and called from `source/main.cpp`
right after `luaL_loadbuffer` succeeds. `lua_strip_debug()` walks the loaded
`Proto` recursively and frees `lineinfo`, `locvars`, and `upvalues` with
`luaM_freearray`, zeroing the counts. The `debug` library is not opened, so the
only loss is line numbers in errors raised by the embedded functions. REPL
chunks compiled later keep their debug info.

### S3. Build-time stripped bytecode — ~same RAM as S2, plus no boot parse

Compile `lua-script.lua` with `luac -s` and embed the bytecode instead of the
text (`f_parser` auto-detects the `\033Lua` signature). Same RAM win as S2, a
slightly smaller flash payload (9.1 KB vs 10.4 KB), and no parse at boot.

Blocker: the bytecode header encodes `sizeof(size_t)`. A native 64-bit host
`luac` emits 8 and is rejected by `LoadHeader` on the 32-bit ARM target. Requires
a 32-bit `luac` (`gcc -m32`, so `gcc-multilib` in the Docker/CI image) or a
cross-build under qemu. Also changes the `hextract embed` workflow to require
compatible bytecode.

### S4. Resolve constants through `__index` — ~1–2 KB

The 41 constants occupy 41 of `microbit`'s 58 fields and 41 interned strings.
Serving them from an `__index` metamethod would shrink the table toward 32 nodes
and drop those names, at the cost of constants not being enumerable via `pairs`.

### S5. Flash-resident (read-only) strings — ~2 KB, invasive

Lua's string value is a `TString*`, not bytes: `Proto.k` holds `TValue`s whose
string constants are pointers (`lobject.h:233`), and the bytes live inline right
after the header (`getstr(ts) = (char*)(ts+1)`, `lobject.h:210`). On load,
`LoadString` calls `luaS_newlstr` (`lundump.c:76`), which allocates
`16 + len + 1` bytes, **copies the bytes**, and interns the result in
`G(L)->strt` (`lstring.c:56-67`). Table and global lookups then rely on the
interned object's cached `hash` and on pointer identity (`ltable.c:52,455`). The
chunk format has no "reference a flash string" opcode, so the dump must echo the
bytes (once per occurrence — 184 here, deduped to 109 unique at load; the
repeats cost flash only).

Keeping the bytes in flash would therefore require:

- a `TString` variant with an external data pointer, changing `getstr` to an
  indirection — an extra dereference on **every** string access in the VM;
- a real, mutable GC header (`next`, `marked`, cached `hash`) still allocated in
  RAM, since interning and table lookup need it;
- a reworked interning/lookup path that accepts the external representation
  (e.g. a static, compile-time string table) instead of `luaS_newlstr`.

| strings | unique | payload | current RAM (`TString` hdr + inline bytes) | best case after stub |
|---|---:|---:|---:|---:|
| script string constants | 109 | 936 B | ~3.0 KB | save ~2.0 KB |
| API namespace names | 167 | ~2.4 KB | ~5.6 KB | save ~4–5 KB |

The script-only win is ~2 KB; the larger API-name win is better obtained with
S1/S4, which need no VM changes. This is the eLua "LTR" / LuatOS class of change.

### Rejected: true flash-resident `Proto`

Aliasing the dumped `code` arrays into flash would avoid only the ~4 KB of
instructions; string constants, numeric constants, `Proto` headers, and nested
proto arrays must remain on the heap. It needs invasive changes to
`luaF_newproto` / `luaF_freeproto` / GC traversal with a new `Proto` flag. Poor
cost/benefit.

### Method and caveats

- Static sizes: `build/MICROBIT.map` and `build/nrf52833-patched.ld`.
- Namespace sizes: computed from the `luaL_Reg` registration in
  `source/codal-lua.cpp` using LP32 struct sizes (identical to the ARM target).
- Lua-heap sizes are on-device `LUA_MEM_DEBUG` readings on the micro:bit v2,
  computed as deltas of the boot markers (last bullet). The per-table node/name
  breakdown remains an analytical cross-check.
- On-device instrumentation is built into `source/main.cpp`: define
  `LUA_MEM_DEBUG` (e.g. `"LUA_MEM_DEBUG": 1` in `codal.json` config) to emit a
  `LUA_MEM <tag>: lua=<bytes>` line via `DMESG` at boot, after `luaL_newstate`,
  after the standard libraries, after the API registration, after loading the
  script, and after running it; the deltas isolate each component. Output also
  needs `"DMESG_SERIAL_DEBUG": 1`. If `CODAL_DEBUG >= 2` as well, each tag also
  calls `device_heap_print()` (CODAL allocator `mb_total_used`/`mb_total_free`).
  Config changes require `./build.py --clean`.
