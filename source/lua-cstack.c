// -*- mode: c; indent-tabs-mode: nil; -*-
//
// How full the C stack is, for Lua's luai_cstack (luaconf.h).
//
// All fibers share one 8 KB stack, and nothing stops a call that runs past
// its bottom: it overwrites the heap, and the board panics with 045.
// LUAI_MAXCCALLS allows 200 nested C calls, but one costs 140 to 430 bytes
// here. So luaD_call, lua_resume and each parser level raise "C stack
// overflow" when less than LUAI_CSTACK_MARGIN is left. lua_resume is
// checked because coroutines run on the same stack.
//
// The margin, 2,304 bytes, is what may run between two checks, estimated
// from the ARM build's frame sizes at about 2,300: one Lua call (216
// bytes), the deepest C function below it (string.format raising an error,
// about 1,600) and an interrupt (about 500). The deepest case measured on
// the board, nested coroutines each building a 1,200-character string,
// peaked at 7,072 of 8,192 bytes. The build has no BLE (DEVICE_BLE 0); with
// BLE, the SoftDevice's interrupts would need a larger margin.
//
// Not covered: pattern matching, long assignment lists, string.dump and
// loading bytecode recurse with no C stack check of their own.
//
// Under xpcall, calling the error handler fails the same check again and
// again. LUA_CSTACK_LAST, 1,024 bytes further down, ends this: luai_cstack
// returns 2, and luaD_call throws "error in error handling".

#include <stdint.h>

#include "luaconf.h"

#define LUA_CSTACK_LAST 1280

// luai_stackbottom, declared in luaconf.h, is the linker's __StackLimit,
// the bottom of the shared stack region; CODAL's stack_limit() returns its
// address.

// How full the stack is for a stack pointer at sp: 0 with room, 1 past the
// margin, 2 past the last line. The first test is luaconf.h's
// luai_cstackroom, the one luai_cstack makes inline.
int luai_cstack_at(uintptr_t sp) {
  if (luai_cstackroom(sp))
    return 0;
  return sp < (uintptr_t)luai_stackbottom + LUA_CSTACK_LAST ? 2 : 1;
}

// luaconf.h's luai_cstack calls this only within the margin.
int luai_cstackcheck(void) {
  return luai_cstack_at((uintptr_t)luai_sp());
}
