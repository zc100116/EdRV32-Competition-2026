/* File: main.c
 * Spec: Task B2-3b; CLAUDE.md 9.2–9.3.
 * Description: Retain all driver entry points in one compile/link acceptance image.
 * Clock domain: clk_sys CPU; this image does not exercise hardware.
 */
#include "engine.h"
#include "vin.h"
#include "pix.h"
#include "geo.h"
#include "disp.h"
#include "npu.h"
#include "eth.h"
#include "mem_xbar.h"
#include "ov5640.h"
#include "uart.h"
#include "uart_input.h"
#include "gpio.h"
#include "clint.h"
#include "plic.h"
#include "i2c.h"

static const uintptr_t driver_symbols[] = {
    (uintptr_t)&engine_control,
    (uintptr_t)&engine_poll,
    (uintptr_t)&engine_irq_clear,
    (uintptr_t)&engine_perf,
    (uintptr_t)&engine_irq_register,
    (uintptr_t)&engine_irq_handle,
    (uintptr_t)&engine_irq_dispatch,
    (uintptr_t)&surface_ring_slot,
    (uintptr_t)&engine_dma_clean,
    (uintptr_t)&engine_dma_invalidate,
    (uintptr_t)&vin_camera_size,
    (uintptr_t)&vin_channel_configure,
    (uintptr_t)&vin_channel_enable,
    (uintptr_t)&vin_slots_busy,
    (uintptr_t)&vin_frame_done,
    (uintptr_t)&vin_frame_slot,
    (uintptr_t)&vin_memory_start,
    (uintptr_t)&vin_memory_status,
    (uintptr_t)&vin_write_status,
    (uintptr_t)&pix_config_word,
    (uintptr_t)&pix_configure,
    (uintptr_t)&pix_gamma_load,
    (uintptr_t)&geo_q16,
    (uintptr_t)&geo_descriptor_pack,
    (uintptr_t)&geo_submit,
    (uintptr_t)&disp_submit,
    (uintptr_t)&disp_current,
    (uintptr_t)&disp_released,
    (uintptr_t)&npu_configure,
    (uintptr_t)&npu_start,
    (uintptr_t)&npu_current_descriptor,
    (uintptr_t)&eth_ipv4_pack,
    (uintptr_t)&eth_local_configure,
    (uintptr_t)&eth_peer_configure,
    (uintptr_t)&eth_window_configure,
    (uintptr_t)&eth_window_bytes,
    (uintptr_t)&eth_tx_descriptor_pack,
    (uintptr_t)&eth_header_pack,
    (uintptr_t)&eth_send,
    (uintptr_t)&eth_phy_reset,
    (uintptr_t)&eth_mdio_write,
    (uintptr_t)&eth_mdio_read,
    (uintptr_t)&mem_xbar_snapshot,
    (uintptr_t)&mem_xbar_rate,
    (uintptr_t)&mem_xbar_error,
    (uintptr_t)&ov5640_table,
    (uintptr_t)&ov5640_init,
    (uintptr_t)&ov5640_chip_id,
    (uintptr_t)&uart_init,
    (uintptr_t)&uart_set_baud,
    (uintptr_t)&uart_putc,
    (uintptr_t)&uart_getc,
    (uintptr_t)&uart_puts,
    (uintptr_t)&uart_drain,
    (uintptr_t)&uart_input_getc,
    (uintptr_t)&uart_read_selection,
    (uintptr_t)&uart_input_binary_begin,
    (uintptr_t)&gpio_write,
    (uintptr_t)&gpio_set_output_enable,
    (uintptr_t)&gpio_read,
    (uintptr_t)&gpio_set_edges,
    (uintptr_t)&gpio_irq_status,
    (uintptr_t)&gpio_irq_clear,
    (uintptr_t)&gpio_set_debounce,
    (uintptr_t)&clint_time,
    (uintptr_t)&clint_set_compare,
    (uintptr_t)&clint_set_software_irq,
    (uintptr_t)&plic_set_priority,
    (uintptr_t)&plic_set_enable,
    (uintptr_t)&plic_set_threshold,
    (uintptr_t)&plic_pending,
    (uintptr_t)&plic_claim,
    (uintptr_t)&plic_complete,
    (uintptr_t)&i2c_init,
    (uintptr_t)&i2c_command,
    (uintptr_t)&i2c_read_data,
    (uintptr_t)&i2c_sccb_write,
    (uintptr_t)&i2c_sccb_read,
};
static volatile uintptr_t linked_symbols;

/* Task B2-3b: references keep every driver API reachable through --gc-sections. */
int main(void)
{
    for (size_t i = 0; i < sizeof(driver_symbols) / sizeof(driver_symbols[0]); ++i) {
        linked_symbols ^= driver_symbols[i];
    }
    return 0;
}
