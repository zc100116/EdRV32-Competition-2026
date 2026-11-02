/* File: input.c
 * Design: showcase 4.1/4.2; regression for overwritten input event payload.
 * Description: Duplicate service wakeups must preserve an edge until dispatch;
 * the framework and application read the same snapshot without consuming it.
 * Clock domain: deterministic host call sequence.
 */
#include "platform.h"
#include "runtime.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    showcase_input_sample(0);
    showcase_input_sample(PLATFORM_ENTER);
    /* A repeated service wake can run at priority 0 before the app at 1. */
    showcase_input_sample(PLATFORM_ENTER);
    showcase_input_dispatch();
    assert(platform_keys() == PLATFORM_ENTER);
    assert(platform_pressed() == PLATFORM_ENTER);
    assert(platform_pressed() == PLATFORM_ENTER);
    showcase_input_dispatch();
    assert(platform_pressed() == 0);
    showcase_input_sample(0);
    showcase_input_sample(PLATFORM_LEFT);
    showcase_input_sample(PLATFORM_LEFT);
    showcase_input_sample(0);
    showcase_input_sample(PLATFORM_BACK);
    showcase_input_dispatch();
    assert(platform_keys() == PLATFORM_BACK);
    assert(platform_pressed() == (PLATFORM_LEFT | PLATFORM_BACK));
    puts("PASS input duplicate sampling, pending edges and shared dispatch snapshot");
    return 0;
}
