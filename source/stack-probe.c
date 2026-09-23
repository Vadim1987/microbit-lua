// -*- mode: c; indent-tabs-mode: nil; -*-
//
// Stack high-water measurement for the shared fiber stack region
// [stack_limit(), fiber_initial_stack_base()). The scheduler pages every fiber
// through that one region and the context switch copies only the used range
// [SP, stack_base), so bytes below the deepest stack pointer ever reached stay
// painted. Painting the free region and scanning for the lowest overwritten
// word therefore reports the peak usage.

#include <stdint.h>

#include "stack-probe.h"

// Provided by codal (declared in codal_target_hal.h, extern "C").
extern uint32_t stack_limit(void);
extern uint32_t fiber_initial_stack_base(void);
extern uint32_t get_current_sp(void);
extern void target_disable_irq(void);
extern void target_enable_irq(void);

#define STACK_PAINT 0xC0DEFACEu

void stack_probe_paint(void) {
    // Leave the first word alone: the stack guard stores its canary there.
    volatile uint32_t *bottom =
        (volatile uint32_t *)(stack_limit() + sizeof(uint32_t));
    volatile uint32_t *sp = (volatile uint32_t *)get_current_sp();

    // Mask interrupts so an exception can't push a frame into the region
    // while it is being filled.
    target_disable_irq();
    for (volatile uint32_t *p = bottom; p < sp; p++)
        *p = STACK_PAINT;
    target_enable_irq();
}

uint32_t stack_probe_peak(void) {
    uint32_t top = fiber_initial_stack_base();
    volatile uint32_t *bottom =
        (volatile uint32_t *)(stack_limit() + sizeof(uint32_t));
    volatile uint32_t *end = (volatile uint32_t *)top;
    int run = 0;

    // The first overwritten word from the bottom is the deepest touch. Require
    // two consecutive overwritten words so a value that happens to equal the
    // pattern is not mistaken for untouched.
    for (volatile uint32_t *p = bottom; p < end; p++) {
        if (*p != STACK_PAINT) {
            if (++run >= 2)
                return top - (uint32_t)(p - 1);
        } else {
            run = 0;
        }
    }
    return 0;
}

uint32_t stack_probe_current(void) {
    return fiber_initial_stack_base() - get_current_sp();
}

uint32_t stack_probe_region(void) {
    return fiber_initial_stack_base() - stack_limit();
}
