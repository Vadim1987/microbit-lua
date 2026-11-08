// -*- mode: c; indent-tabs-mode: nil; -*-
//
// Host test for source/lua-format.c, run by lua-format-tests.sh: an %f item
// against the host's printf, and %e, %g and the other %f items against the
// sign and lua_float2str.

#include <math.h>
#include <stdio.h>
#include <string.h>

int luai_numformat(char *s, const char *form, double n);
void lua_float2str(char *s, float n);

static int failures = 0;
static int checks = 0;

// Lua's numbers here are floats; string.format hands them over as double.
static const float values[] = {
    0,        -0.0f,    1,       -7,      12,       100,      0.5f,
    1.5f,     2.5f,     3.5f,    -2.5f,   0.125f,   0.1f,     0.25f,
    -0.75f,   1.0f / 3, 2.0f / 3, 3.14159f, 9.95f,  0.96f,    99.5f,
    0.05f,    0.0005f,  1e-5f,   123456,  16777216, 3.9e9f,
    3999999744.0f, 4e9f, -4e9f,  4.5e9f,  1e10f,    3.4e38f,  INFINITY,
    -INFINITY, NAN,     -NAN,
};

// The shapes lessons use, then the flags and precisions this file keeps.
static const char *forms[] = {
    "%.1f", "%.2f", "%5.1f", "%f", "%.0f", "%.3f", "%-8.2f", "%+.1f",
    "% .2f", "%+ .1f", "%#.1f", "%.9f",
};

static void check(const char *form, double x, const char *want) {
    char got[512];
    luai_numformat(got, form, x);
    checks++;
    if (strcmp(got, want) != 0) {
        failures++;
        printf("FAIL %s of %.9g: got \"%s\", want \"%s\"\n", form, x, got,
               want);
    }
}

int main(void) {
    char want[512];
    for (size_t i = 0; i < sizeof values / sizeof values[0]; i++) {
        float x = values[i];
        char print[64];
        print[0] = '-';
        lua_float2str(print + 1, fabsf(x));
        const char *as_print = signbit(x) ? print : print + 1;
        check("%e", x, as_print);
        check("%g", x, as_print);
        check("%.3g", x, as_print);
        check("%E", x, as_print);
        check("%G", x, as_print);
        snprintf(want, sizeof want, "%10s", as_print);
        check("%10g", x, want);
        if (isfinite(x)) {
            check("%.10f", x, as_print);
            if (!(fabsf(x) < 4e9f)) {
                check("%.2f", x, as_print);
                continue;
            }
        }
        for (size_t j = 0; j < sizeof forms / sizeof forms[0]; j++) {
            snprintf(want, sizeof want, forms[j], x);
            check(forms[j], x, want);
        }
    }
    printf("%d checks, %d failures\n", checks, failures);
    return failures != 0;
}
