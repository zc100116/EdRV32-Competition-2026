/* File: input.c
 * Design: showcase 4.1/4.2; one input snapshot for each application step.
 * Description: Preserve pressed edges across repeated service samples until
 * the application task dispatches them; all readers share that dispatch.
 * Clock domain: clk_sys, cooperative foreground tasks only.
 */
#include "platform.h"
#include "runtime.h"
static uint32_t input_snapshot;
static uint32_t pending_pressed;
static uint32_t input_pressed;
void showcase_input_sample(uint32_t keys)
{
    pending_pressed |= keys & ~input_snapshot;
    input_snapshot = keys;
}
void showcase_input_dispatch(void)
{
    input_pressed = pending_pressed;
    pending_pressed = 0;
}
uint32_t platform_keys(void) { return input_snapshot; }
uint32_t platform_pressed(void) { return input_pressed; }
