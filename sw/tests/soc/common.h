/* File: common.h
 * Spec: soc-testplan 2, 4; SoC 7.3-7.4.
 * Description: Shared test diagnostics, PLIC service and model mailbox.
 * Clock domain: clk_sys software.
 */
#ifndef SOC_TEST_COMMON_H
#define SOC_TEST_COMMON_H
#include <stdint.h>
#include "soc_map.h"
#include "sysctrl.h"
#include "uart.h"
#include "plic.h"
#include "clint.h"
#include "cache.h"
#include "i2c.h"
#include "gpio.h"
#include "regs/vin_regs.h"
#include "regs/pix_regs.h"
#include "regs/geo_regs.h"
#include "regs/disp_regs.h"
#include "regs/npu_regs.h"
#include "regs/eth_regs.h"
#include "regs/mem_xbar_regs.h"
#include "regs/perf_mon_regs.h"

#define SURFACE_BASE 0x06000000u
#define SURFACE_STEP 0x00200000u
#define CH2_BASE 0x04000000u
#define GEO_BASE 0x07000000u
#define IMAGE_BASE 0x08000000u
#define MAILBOX_BASE 0x0a3ff000u
#define TX_BASE 0x0a100000u
#define TX_DESC 0x0a110000u
#define GEO_DESC 0x0a120000u
#define RX_BASE 0x09000000u
#define NPU_DESC 0x00080000u
#define NPU_MODEL 0x00100000u
#define NPU_WORK 0x01000000u
#define NPU_OUTPUT 0x05000000u
#define WIDTH 1280u
#define HEIGHT 720u
#define STRIDE (WIDTH * 2u)
#define FRAME_BYTES (STRIDE * HEIGHT)

uint32_t read_reg(uintptr_t base, uint32_t offset);
void write_reg(uintptr_t base, uint32_t offset, uint32_t value);
volatile uint32_t *ddr(uint32_t physical);
_Noreturn void finish(uint32_t code);
void equal(const char *position, uint32_t expected, uint32_t actual);
void print_hex(uint32_t value);
void init(void);
void command(uint32_t operation, uint32_t argument);
void wait_irq(unsigned int source, uint32_t count);
void configure_vin(unsigned int memory, unsigned int ch2);
void configure_camera(void);
void display(uint32_t base);
void run_geo(uint32_t source);
void configure_npu(uint32_t input);
void configure_eth(void);
void eth_send(uint32_t descriptor, uint32_t count);
void snapshot(uint32_t clear);
void video_descriptors(void);
extern volatile uint32_t interrupts[16];
extern volatile uint32_t events[16];
#endif
