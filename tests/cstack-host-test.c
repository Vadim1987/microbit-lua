// -*- mode: c; indent-tabs-mode: nil; -*-
//
// Host test for source/lua-cstack.c: Lua may go deeper while the C stack
// in use leaves LUAI_CSTACK_MARGIN of the region free, and stops past
// that. A stand-in region gives the stack pointer for a size and the stack
// in use. luai_cstack_at's first test is luaconf.h's luai_cstackroom, the
// comparison luai_cstack makes inline, so this tests both.
//
// Usage: cstack-host-test

#include <stdint.h>
#include <stdio.h>

int luai_cstack_at(uintptr_t sp);

// A stand-in for the linker's region, the stack growing down from its top.
char stand_in[16384] __asm__("__StackLimit");

static uint32_t used, region;

static int full_at(void) {
  return luai_cstack_at((uintptr_t)stand_in + region - used);
}

static int failures, checks;

static const char *const said[] = {"room", "full", "past the last line"};

static void check(uint32_t size, uint32_t in_use, int full) {
  region = size;
  used = in_use;
  checks++;
  if (full_at() != full)
    failures++;
  printf("%s %u bytes in use of %u: %s\n",
         full_at() == full ? "ok  " : "FAIL", (unsigned)in_use,
         (unsigned)size, said[full]);
}

int main(void) {
  // the board's 8 KB region: 5,888 bytes in use is the most that goes on,
  // and past 6,912 luaD_call throws "error in error handling"
  check(8192, 5888, 0);
  check(8192, 5889, 1);
  check(8192, 6912, 1);
  check(8192, 6913, 2);
  printf("%d stack checks, %d failed\n", checks, failures);
  return failures != 0;
}
