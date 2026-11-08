// -*- mode: c; indent-tabs-mode: nil; -*-
//
// string.format's %e, %f and %g, for a C library that cannot print floats.
// Lua's numbers here are floats (LUA_NUMBER_IS_FLOAT). %f rounds a number
// whose magnitude is below 4e9 to at most 9 decimals, halfway to even as
// printf does, and writes the whole part and the decimals with integer
// printf. %e, %E, %g, %G and any other %f write the magnitude as print does
// (lua_float2str), in lowercase. The sign, the width and the -, + and space
// flags follow C for all of them; the 0 and # flags are ignored.

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "lua.h"

void lua_float2str(char *s, float n);

int luai_numformat(char *s, const char *form, double x) {
    char text[48];
    char *t = text;
    const char *f = form + 1;
    int left = 0, plus = 0, space = 0, p = 6;
    for (;; f++) {
        if (*f == '-')
            left = 1;
        else if (*f == '+')
            plus = 1;
        else if (*f == ' ')
            space = 1;
        else if (*f != '0' && *f != '#')
            break;
    }
    int width = (int)strtol(f, (char **)&f, 10);
    if (*f == '.')
        p = (int)strtol(f + 1, (char **)&f, 10);
    if (signbit(x))
        *t++ = '-';
    else if (plus || space)
        *t++ = plus ? '+' : ' ';
    double a = fabs(x);
    if (*f == 'f' && p <= 9 && a < 4e9) {
        // whole and decimals, each exact in double for a float number
        uint32_t whole = (uint32_t)a, q = 1;
        for (int i = 0; i < p; i++)
            q *= 10;
        double m = (a - whole) * q;
        uint32_t r = (uint32_t)m;
        double rest = m - r;
        uint32_t last = p ? r : whole;
        if (rest > 0.5 || (rest == 0.5 && (last & 1)))
            r++;
        if (r == q) {  // 0.96 to 1 decimal is 1.0
            whole++;
            r = 0;
        }
        if (p)
            sprintf(t, "%lu.%0*lu", (unsigned long)whole, p, (unsigned long)r);
        else
            sprintf(t, "%lu", (unsigned long)whole);
    } else {
        lua_float2str(t, (float)a);
    }
    return sprintf(s, left ? "%-*s" : "%*s", width, text);
}
