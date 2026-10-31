/* File: network_npu.c
 * Spec: Task T-NETN-R; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: Shared EDNM validation/loading and NPU receive-window allocation.
 * Clock domain: clk_sys; CPU-built DDR objects use the uncached alias.
 */
#include "runtime.h"

const uint32_t demo_network_rx_mask = EDRV32_ETH_IRQ_EN_RX_NOTIFY0_MASK |
    EDRV32_ETH_IRQ_EN_RX_NOTIFY1_MASK | EDRV32_ETH_IRQ_EN_RX_NOTIFY2_MASK |
    EDRV32_ETH_IRQ_EN_RX_NOTIFY3_MASK;

void demo_network_windows_init(void)
{
    eth_window_configure(0, DEMO_WINDOW_BASE, DEMO_WINDOW_SIZE);
    eth_window_configure(1, DEMO_WINDOW_BASE + DEMO_WINDOW_SIZE, DEMO_WINDOW_SIZE);
    eth_window_configure(2, DEMO_MODEL_WINDOW, DEMO_MODEL_WINDOW_SIZE);
    eth_window_configure(3, DEMO_COMMAND_WINDOW, DEMO_COMMAND_WINDOW_SIZE);
}

static void copy_bytes(uint32_t destination, uint32_t source, uint32_t bytes)
{
    uint32_t *out = demo_uncached(destination);
    const uint32_t *in = demo_uncached(source);
    for (uint32_t i = 0; i < bytes / 4u; ++i) {
        out[i] = in[i];
    }
    uint8_t *tail = (uint8_t *)out;
    const uint8_t *source_tail = (const uint8_t *)in;
    for (uint32_t i = bytes & ~3u; i < bytes; ++i) {
        tail[i] = source_tail[i];
    }
}

const uint8_t *demo_network_model_header(void)
{
    const uint8_t *header = demo_uncached(DEMO_MODEL_WINDOW);
    uint32_t bytes = eth_window_bytes(2);
    info_number("WIN2_BYTES", bytes);
    const char *error = demo_model_header(header, bytes);
    if (error) {
        for (unsigned int i = 0; i < 8; ++i) {
            info_hex("EDNM word", demo_read32(header + i * 4));
        }
        demo_fail(error, ENGINE_ETH);
    }
    return header;
}

void demo_network_model_load(const uint8_t *header)
{
    copy_bytes(DEMO_DESC_BASE, DEMO_MODEL_WINDOW + 0x1000u, demo_read32(header + 12));
    copy_bytes(DEMO_MODEL_BASE, DEMO_MODEL_WINDOW + 0x100000u, demo_read32(header + 16));
    struct npu_config config = {DEMO_MODEL_BASE, DEMO_WORK_BASE, DEMO_INPUT_BASE,
        DEMO_OUTPUT_BASE, DEMO_DESC_BASE, demo_read32(header + 8)};
    npu_configure(&config);
    eth_window_configure(2, DEMO_MODEL_WINDOW, DEMO_MODEL_WINDOW_SIZE);
    info_text("EDNM", "loaded");
}
