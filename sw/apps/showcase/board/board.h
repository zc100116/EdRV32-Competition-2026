/* board.h — showcase 4.5; board service and exclusive-action dispatch. */
#ifndef SHOWCASE_BOARD_H
#define SHOWCASE_BOARD_H
#include "../app.h"
#include "../ui/ui_data.h"
void board_request(const struct app *app);
void board_init(void);
void board_step(void);
int board_uart_active(void);
void board_uart_byte(unsigned byte);
void board_serial_character(int byte);
void board_bulk_complete(unsigned kind);
void board_bulk_cancel(void);
unsigned board_peer(void);
unsigned board_session_error(void);
ui_app_t board_session_target(void);
void board_session_fail(unsigned error);
uint32_t board_image_request(void);
void board_coremark_begin(void);
void board_coremark_stop(void);
void board_graphics_stop(void);
bool board_nes_ready(ui_state_t target);
int board_eth_send(uint32_t descriptors,uint32_t count);
uint64_t board_rnd_cycles(void);
uint64_t board_npu_cycles(void);
void board_network_init(void);
void board_network_step(void);
void board_prof_sample(uint32_t pc);
uint64_t board_prof_deadline(uint64_t deadline);
void board_benchmark_result(unsigned scene,uint64_t ticks,unsigned frames);
void board_benchmark_end(void);
#endif
