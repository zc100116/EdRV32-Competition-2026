/* debug.c — showcase 4.3/4.5.3; UART inspector owns RX while its tab is active.
 * Text/hex views share the last 256 bytes; clk_sys foreground only. */
#include "board.h"
#include "../platform.h"
#include "../runtime.h"
#include "../ui/theme.h"
#include "uart.h"
#include "eth.h"
#include "eth_monitor.h"
#include <stdio.h>
#include <string.h>
static char text[257],hex[769];
static unsigned length,rx,tx,baud=921600;
static bool hex_mode;
extern unsigned board_tx_bytes,board_tx_packets,board_echo_count;
extern unsigned board_echo_replies;
extern char board_udp_text[1001];
int board_uart_active(void) { return ui_page==8 && ui_tab==0; }
void board_uart_byte(unsigned b)
{
    ++rx;
    if(length==256) {
        memmove(text,text+1,255); memmove(hex,hex+3,765); length=255;
    }
    text[length]=(char)b; text[length+1]=0;
    static const char digits[]="0123456789ABCDEF";
    hex[length*3]=digits[b>>4]; hex[length*3+1]=digits[b&15];
    hex[length*3+2]=' '; ++length; hex[length*3]=0;
}
ui_debug_t ui_data_debug(void)
{
    static char peer[40];
    unsigned h=platform_hardware()&APP_HW_ETH;
    uint32_t ip=h ? mmio_read32(EDRV32_ETH_BASE+EDRV32_ETH_PEER_IP_OFFSET) : 0;
    unsigned port=h ? mmio_read32(EDRV32_ETH_BASE+EDRV32_ETH_PEER_PORT_OFFSET) : 0;
    snprintf(peer,sizeof(peer),"%lu.%lu.%lu.%lu:%u",(unsigned long)(ip>>24),
        (unsigned long)((ip>>16)&255),(unsigned long)((ip>>8)&255),(unsigned long)(ip&255),port);
    return (ui_debug_t){.uart_text=text,.uart_hex=hex,.udp_text=board_udp_text,.peer=peer,
        .baud=baud,.uart_rx=rx,.uart_tx=tx,.hex=hex_mode,.link=showcase_network_link()>0,
        .rx_packets=h ? engine_perf(ENGINE_ETH,1) : 0,.tx_packets=board_tx_packets,
        .rx_bytes=h ? engine_perf(ENGINE_ETH,2) : 0,.tx_bytes=board_tx_bytes,
        .echo_count=board_echo_count,.echo_replies=board_echo_replies};
}
void ui_data_debug_format(void) { hex_mode=!hex_mode; }
void ui_data_debug_clear(void) { rx=tx=length=0; text[0]=hex[0]=0; }
void ui_data_debug_baud(void)
{
    baud=baud==115200 ? 921600 : baud==921600 ? 2000000 : 115200;
    mmio_write32(EDRV32_UART0_BASE+UART_BAUD_DIV,
                 (uint32_t)((uint64_t)platform_clock_hz()*16/baud));
}
void ui_data_debug_send(void)
{
    const char *s="Hello EdRV32!\r\n";
    platform_puts(s); tx+=strlen(s);
}
