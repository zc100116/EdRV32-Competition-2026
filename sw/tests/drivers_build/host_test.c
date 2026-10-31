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

/* T-CAM30: use the final write to each sensor register, as SCCB initialization does. */
static uint8_t sensor_register(uint16_t address)
{
    size_t count;
    const struct ov5640_register *table = ov5640_table(&count);
    while (count != 0u) {
        --count;
        if (table[count].address == address) {
            return table[count].value;
        }
    }
    fprintf(stderr, "FAIL OV5640 register 0x%04x missing from table\n", address);
    exit(1);
}

static uint32_t sensor_register16(uint16_t address)
{
    return ((uint32_t)sensor_register(address) << 8) | sensor_register(address + 1u);
}

/* T-CAM30: geometry/format and datasheet + Linux DVP clock equations; no sensor MMIO. */
static void test_sensor(void)
{
    size_t count;
    const struct ov5640_register *table = ov5640_table(&count);
    equal("OV5640 table length", (uint32_t)count, 252u);
    equal("sensor software reset address", table[0].address, 0x3008u);
    equal("sensor software reset value", table[0].value, 0x82u);
    equal("RGB565 format/byte order", sensor_register(0x4300u), 0x61u);
    equal("RGB format selector", sensor_register(0x501fu), 1u);
    equal("720p width", sensor_register16(0x3808u), 1280u);
    equal("720p height", sensor_register16(0x380au), 720u);
    equal("crop left", sensor_register16(0x3800u), 0u);
    equal("crop top", sensor_register16(0x3802u), 250u);
    equal("crop right", sensor_register16(0x3804u), 2623u);
    equal("crop bottom", sensor_register16(0x3806u), 1705u);
    equal("horizontal subsampling", sensor_register(0x3814u), 0x31u);
    equal("vertical subsampling", sensor_register(0x3815u), 0x31u);
    equal("scaler bypass", sensor_register(0x5001u), 0x83u);
    equal("DVP auto PCLK divider", sensor_register(0x460cu), 0x20u);
    equal("sensor test pattern off", sensor_register(0x503du), 0u);
    equal("last register", table[count - 1].address, 0x3019u);
    equal("last value", table[count - 1].value, 0u);

    uint32_t pll0 = sensor_register(0x3034u);
    uint32_t pll1 = sensor_register(0x3035u);
    uint32_t pll3 = sensor_register(0x3037u);
    uint32_t roots = sensor_register(0x3108u);
    uint32_t sysdiv = pll1 >> 4;
    uint32_t p_div = pll1 & 0x0fu;
    double vco = 24000000.0 / (pll3 & 0x0fu) * sensor_register(0x3036u);
    double pll_clock = vco / (sysdiv == 0u ? 16u : sysdiv)
        / (((pll3 >> 4) & 1u) + 1u) / ((pll0 & 0x0fu) / 4.0);
    double sclk = pll_clock / (1u << (roots & 3u));
    double pclk = pll_clock / (1u << ((roots >> 4) & 3u))
        / (p_div == 0u ? 1u : p_div);
    uint32_t hts = sensor_register16(0x380cu);
    uint32_t vts = sensor_register16(0x380eu);
    double fps = sclk / hts / vts;
    if (!(pclk <= 100000000.0 && fps >= 29.5 && fps <= 30.5)) {
        fprintf(stderr, "FAIL OV5640: PCLK %.0f Hz (max 100000000), "
                "fps %.6f (expected 29.5..30.5)\n", pclk, fps);
        exit(1);
    }
    equal("60Hz exposure ceiling", sensor_register16(0x3a02u), vts);
    equal("50Hz exposure ceiling", sensor_register16(0x3a14u), vts);
    equal("50Hz band step", sensor_register16(0x3a08u), (uint32_t)(sclk / hts / 100));
    equal("60Hz band step", sensor_register16(0x3a0au), (uint32_t)(sclk / hts / 120));
    equal("50Hz max bands", sensor_register(0x3a0eu),
          (vts - 4u) / sensor_register16(0x3a08u));
    equal("60Hz max bands", sensor_register(0x3a0du),
          (vts - 4u) / sensor_register16(0x3a0au));
    printf("OV5640: VCO %.0f Hz, PCLK %.0f Hz, SCLK %.0f Hz, "
           "HTS %u x VTS %u, %.6f fps\n", vco, pclk, sclk, hts, vts, fps);
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
