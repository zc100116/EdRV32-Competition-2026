/* serial.c — P5b 9.3; commit complete lines, drain through one UART writer.
 * Coordinator decision: on overflow synchronously make room, never drop a line.
 * Clock domain: clk_sys; producers never yield while assembling a line.
 */
#include "serial.h"
#include "../platform.h"
#include <string.h>
enum { CAPACITY = 16 * 1024 };
static char queue[CAPACITY];
static char line[CAPACITY];
static unsigned head, count, length;

static void drain_byte(void)
{
    while (!platform_serial_ready()) {}
    platform_serial_byte((unsigned char)queue[head]);
    head = (head + 1) % CAPACITY;
    --count;
}
void board_serial_drain(bool wait)
{
    while (count && (wait || platform_serial_ready())) drain_byte();
}
void board_serial_finish(void)
{
    board_serial_drain(true);
    for (unsigned i = 0; i < length; ++i) {
        while (!platform_serial_ready()) {}
        platform_serial_byte((unsigned char)line[i]);
    }
    length = 0;
}
void board_serial_write(const char *text)
{
    while (*text) {
        if (length == CAPACITY) {
            board_serial_drain(true);
            const char *error = "UART line exceeds 16 KiB\r\n";
            while (*error) {
                while (!platform_serial_ready()) {}
                platform_serial_byte((unsigned char)*error++);
            }
            platform_stop();
        }
        line[length++] = *text++;
        if (line[length - 1] != '\n') continue;
        while (CAPACITY - count < length) drain_byte();
        for (unsigned i = 0; i < length; ++i) {
            queue[(head + count) % CAPACITY] = line[i];
            ++count;
        }
        length = 0;
    }
}
