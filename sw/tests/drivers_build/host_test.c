/* File: host_test.c
 * Spec: Task B2-3b; GEO 2.1/2.6; ETH 2.1/2.3/2.6; SoC 7.3; PIX 4.2.
 * Description: Pure packing/math acceptance vectors with explicit expected values.
 * Clock domain: none (host CPU); no MMIO calls and no hardware simulation.
 */
#include <stdio.h>
#include <stdlib.h>
#include "geo.h"
#include "eth.h"
#include "vin.h"
#include "pix.h"
#include "ov5640.h"

/* Task B2-3b: print both sides of a failed comparison and terminate immediately. */
static void equal(const char *field, uint32_t actual, uint32_t expected)
{
    if (actual != expected) {
        fprintf(stderr, "FAIL %s: actual 0x%08x expected 0x%08x\n", field, actual, expected);
        exit(1);
    }
}

/* Task B2-3b: deterministic identity/translation matrix and RGB565 Surface descriptor. */
static void test_geo(void)
{
    struct geo_config config = {
        .src_base = 0x06000000u, .src_stride = 2560u,
        .src_width = 1280u, .src_height = 720u,
        .dst_base = 0x07000000u, .dst_stride = 2560u,
        .rect_x = 16u, .rect_y = 7u, .rect_width = 1264u, .rect_height = 700u,
        .background = 0xf81fu,
        .matrix = {65536, 0, -98304, 0, 65536, 163840}
    };
    const uint32_t expected[16] = {
        0x06000000, 0x00000a00, 0x02d00500, 0x07000000,
        0x00000a00, 0x00070010, 0x02bc04f0, 0x0000f81f,
        0x00010000, 0, 0xfffe8000, 0, 0x00010000, 0x00028000, 0, 0
    };
    struct geo_descriptor descriptor;
    geo_descriptor_pack(&descriptor, &config);
    for (unsigned int i = 0; i < 16u; ++i) {
        equal("GEO descriptor word", descriptor.word[i], expected[i]);
    }
    equal("Q16 identity", (uint32_t)geo_q16(1, 1), 0x00010000);
    equal("Q16 negative half", (uint32_t)geo_q16(-1, 2), 0xffff8000);
    equal("Q16 three halves", (uint32_t)geo_q16(3, 2), 0x00018000);
    equal("Q16 rational truncation", (uint32_t)geo_q16(-1, 3), 0xffffaaab);
}

/* Task B2-3b: ETH descriptors are little-endian words; app OFFSET is network order. */
static void test_eth(void)
{
    struct eth_tx_descriptor descriptor;
    const uint8_t ip[4] = {192, 168, 1, 10};
    const uint8_t expected[8] = {2, 1, 0, 0, 0x12, 0x34, 0x56, 0x78};
    uint8_t header[8];
    eth_tx_descriptor_pack(&descriptor, 0x0a100000u, 1843200u, 2u, 1u, 32u);
    equal("TX source", descriptor.word[0], 0x0a100000u);
    equal("TX length", descriptor.word[1], 0x001c2000u);
    equal("TX flags", descriptor.word[2], 0x00000102u);
    equal("TX block offset", descriptor.word[3], 32u);
    for (unsigned int i = 4; i < 8u; ++i) {
        equal("TX reserved", descriptor.word[i], 0u);
    }
    eth_header_pack(header, 2u, 1u, 0x12345678u);
    for (unsigned int i = 0; i < 8u; ++i) {
        equal("application header byte", header[i], expected[i]);
    }
    eth_header_pack(header, 0u, 0u, 1024u);
    equal("nonterminal NOTIFY", header[1], 0u);
    equal("packet offset high byte", header[6], 4u);
    equal("IPv4 register", eth_ipv4_pack(ip), 0xc0a8010au);
}

/* Task B2-3b: accepted 244-entry vendor table, with literal format and geometry values. */
static void test_sensor(void)
{
    size_t count;
    const struct ov5640_register *table = ov5640_table(&count);
    equal("OV5640 table length", (uint32_t)count, 244u);
    equal("sensor software reset address", table[0].address, 0x3008u);
    equal("sensor software reset value", table[0].value, 0x82u);
    equal("RGB565 format address", table[52].address, 0x4300u);
    equal("RGB565 format value", table[52].value, 0x61u);
    equal("RGB format selector", table[53].value, 1u);
    equal("720p width high", table[217].value, 5u);
    equal("720p width low", table[218].value, 0u);
    equal("720p height high", table[219].value, 2u);
    equal("720p height low", table[220].value, 0xd0u);
    equal("last register", table[count - 1].address, 0x3019u);
    equal("last value", table[count - 1].value, 0u);
}

/* Task B2-3b: exercise design-record ring spacing and PIX Gaussian/Sobel configuration. */
int main(void)
{
    test_geo();
    test_eth();
    test_sensor();
    for (unsigned int slot = 0; slot < 4u; ++slot) {
        equal("CH0 ring slot", surface_ring_slot(0x06000000u + slot * 0x200000u,
                                                0x06000000u, 0x200000u), slot);
    }
    for (unsigned int slot = 0; slot < 3u; ++slot) {
        equal("CH2 ring slot", surface_ring_slot(0x04000000u + slot * 0x100000u,
                                                0x04000000u, 0x100000u), slot);
    }
    equal("VIN DONE_INFO slot", vin_frame_slot(0x36u), 2u);
    struct pix_config config = {
        .flags = EDRV32_PIX_CFG_BC_EN_MASK | EDRV32_PIX_CFG_GAMMA_EN_MASK,
        .stage1 = PIX_GAUSSIAN, .stage2 = PIX_SOBEL, .gamma_bank = 1u
    };
    equal("PIX config", pix_config_word(&config), 0x00000427u);
    puts("PASS: GEO/Q16, ETH descriptor/header/IP, Surface rings, VIN, PIX, OV5640");
    return 0;
}
