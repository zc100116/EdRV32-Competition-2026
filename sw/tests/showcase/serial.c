/* serial.c — P5b 9.3; partial FIFO drains preserve complete producer lines; host clock. */
#include "serial.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
static char output[40000];
static unsigned used, credit;
bool platform_serial_ready(void) { return credit != 0; }
void platform_serial_byte(unsigned char byte)
{
    assert(credit);
    --credit;
    output[used++] = byte;
}
_Noreturn void platform_stop(void) { abort(); }
int main(void)
{
    board_serial_write("LVGL split scene=\"");
    board_serial_write("Empty screen\" frames=1\r\n");
    credit = 7;
    board_serial_drain(false);
    board_serial_write("CPU%/max_us 1/2\r\nvision fps=3\r\nimage request=4\r\n");
    while (credit = 3, used < strlen("LVGL split scene=\"Empty screen\" frames=1\r\n"
            "CPU%/max_us 1/2\r\nvision fps=3\r\nimage request=4\r\n"))
        board_serial_drain(false);
    assert(!strcmp(output, "LVGL split scene=\"Empty screen\" frames=1\r\n"
        "CPU%/max_us 1/2\r\nvision fps=3\r\nimage request=4\r\n"));
    /* Queue wrap plus the approved synchronous full-queue drain. */
    char line[8193];
    memset(line, 'a', sizeof line - 2);
    line[8191] = '\n'; line[8192] = 0;
    credit = 40000;
    unsigned before = used;
    board_serial_write(line); board_serial_write(line); board_serial_write(line);
    board_serial_drain(true);
    assert(used == before + 3 * 8192);
    for (unsigned i = 0; i < 3; ++i) assert(!memcmp(output + before + i * 8192, line, 8192));
    board_serial_write("fatal detail without newline");
    before = used;
    board_serial_finish();
    assert(!memcmp(output + before, "fatal detail without newline", 28));
    puts("PASS whole-line FIFO partial drain, queue wrap, synchronous overflow drain");
}
