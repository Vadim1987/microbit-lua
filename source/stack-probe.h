#ifndef STACK_PROBE_H
#define STACK_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Fill the free part of the shared fiber stack region with a pattern so that
// the deepest address later overwritten identifies the high-water mark.
void     stack_probe_paint(void);

// Peak stack usage in bytes since the last paint, measured from the region top.
uint32_t stack_probe_peak(void);

// Current stack usage in bytes (region top - current SP).
uint32_t stack_probe_current(void);

// Total size of the shared stack region in bytes.
uint32_t stack_probe_region(void);

#ifdef __cplusplus
}
#endif

#endif
