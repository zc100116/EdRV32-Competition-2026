/* uart_input.c — showcase 4.5.3/4.6.4a; virtual devices survive UART inspector.
 * MMIO is a finite host FIFO; complete ESC V frames are reserved input protocol.
 */
#include "virtual_input.h"
#include "virtual_input_uart.h"
#include "uart.h"
#include "plic.h"
#include <assert.h>
#include <stdio.h>
static const uint8_t *rx;
static unsigned size,pos,raw_count,legacy_count;
uint32_t mmio_read32(uintptr_t address)
{
    if(address==EDRV32_UART0_BASE+UART_STATUS) return pos==size ? UART_STATUS_RX_EMPTY : 0;
    assert(address==EDRV32_PLIC_BASE+PLIC_ENABLE); return 0;
}
void mmio_write32(uintptr_t address,uint32_t value) { (void)address; (void)value; }
uint8_t uart_getc(void) { assert(pos<size); return rx[pos++]; }
void plic_set_priority(unsigned source,unsigned priority) { (void)source; (void)priority; }
void plic_set_enable(uint32_t sources) { (void)sources; }
static void raw(unsigned byte) { assert(byte=='x' || byte=='y'); ++raw_count; }
static void legacy(int byte) { assert(byte=='x' || byte=='y'); ++legacy_count; }
int main(void)
{
    const uint8_t data[]={'x',27,'V',VI_A,0,10,0,20,0,1,4,'y'};
    virtual_input_uart_start(legacy);
    virtual_input_uart_set_raw(raw);
    rx=data; size=sizeof(data); virtual_input_uart_receive();
    struct virtual_input_state s=virtual_input_get();
    assert(s.keys==VI_A && s.x==10 && s.y==20 && s.mouse==1 && s.wheel==4);
    assert(raw_count==2 && legacy_count==0);
    virtual_input_uart_set_raw(NULL); pos=0; virtual_input_uart_receive();
    assert(legacy_count==2 && raw_count==2);
    puts("PASS UART inspector: virtual keyboard/mouse/wheel frames stay active; text reaches inspector");
}
