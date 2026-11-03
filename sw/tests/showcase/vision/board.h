/* board.h — showcase 4.5 test boundary; mock BOARD's sole ETH transmitter. */
#ifndef VISION_TEST_BOARD_H
#define VISION_TEST_BOARD_H
#include <stdint.h>
int board_eth_send(uint32_t descriptors, uint32_t count);
void board_bulk_complete(unsigned kind);
#endif
