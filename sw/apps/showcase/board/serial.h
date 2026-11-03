/* serial.h — P5b 9.3; shared whole-line UART queue; clk_sys foreground. */
#ifndef SHOWCASE_SERIAL_H
#define SHOWCASE_SERIAL_H
#include <stdbool.h>
void board_serial_write(const char *text);
void board_serial_drain(bool wait);
void board_serial_finish(void);
/* Platform FIFO boundary; neither hook schedules other producers. */
bool platform_serial_ready(void);
void platform_serial_byte(unsigned char byte);
#endif
