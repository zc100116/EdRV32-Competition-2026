/* File: pc.c
 * Spec: PC design 4.3-4.4; sys-subsys 2.5.
 * Description: Host game services and the board-compatible claim/complete loop.
 * Clock domain: host main loop.
 */
#include "plat.h"
#include "pc_soc.h"
#include "plic.h"
#include <stdarg.h>
#include <stdio.h>
static plat_irq_handler handlers[16];
static void *contexts[16];
void plat_irq_register(unsigned source, plat_irq_handler handler, void *context)
{
    handlers[source] = handler;
    contexts[source] = context;
}
void plat_irq_dispatch(void)
{
    unsigned source;
    while ((source = plic_claim()) != 0) {
        handlers[source](contexts[source]);
        plic_complete(source);
    }
}
void plat_init(void)
{
    pc_soc_init();
    pc_soc_interrupt(plat_irq_dispatch);
    plic_set_threshold(0);
}
void plat_wait_vsync(void) { pc_soc_vsync(pc_frontend_wait()); }
uint32_t plat_keys(void) { return pc_frontend_keys(); }
uint32_t plat_game_keys(void) { return pc_soc_game_keys(); }
struct plat_pointer_state plat_pointer(void) { return pc_soc_pointer(); }
uint32_t plat_millis(void) { return pc_frontend_millis(); }
void *plat_dma_alloc(size_t bytes, size_t alignment) { return pc_soc_alloc(bytes, alignment); }
int plat_printf(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    int result = vprintf(format, args);
    va_end(args);
    return result;
}
