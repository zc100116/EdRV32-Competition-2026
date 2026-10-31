/* File: parameters_host_test.c
 * Spec: PIX 2.3/2.6; GEO 2.4; Task T-UI1.
 * Description: Production parameter application: inactive banks, atomic pause and errors.
 * Clock domain: none (host); MMIO and frame-boundary pause are observed stubs.
 */
#include "runtime.h"
#include "parameters.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

struct demo_state demo;
static unsigned int pauses;
static unsigned int configures;
static unsigned int writes;
static unsigned int loads[2];
static const char *error;

uint32_t mmio_read32(uintptr_t address) { (void)address; return 0; }
void mmio_write32(uintptr_t address, uint32_t value)
{
    ++writes;
    if (address == EDRV32_PIX_BASE + EDRV32_PIX_GAMMA_WR_OFFSET) {
        ++loads[(value & EDRV32_PIX_GAMMA_WR_BANK_MASK) != 0];
    }
}
void demo_pipeline_pause(void) { ++pauses; }
void demo_pipeline_configure(enum vin_source source)
{
    assert(source == VIN_CAM0);
    ++configures;
    if (demo.pix_custom) {
        pix_configure(&demo.pix_config);
    }
}
void info_text(const char *key, const char *value)
{
    if (!strcmp(key, "Input error")) {
        error = value;
    }
}

int main(void)
{
    struct demo_parameters p;
    assert(!demo_parameters_parse("pix set 1 320 24 1 2200 2 4 1 1 123 1", &p));
    demo.gamma_bank = 1;
    demo_parameters_apply(&p);
    assert(loads[0] == 256 && loads[1] == 0 && demo.gamma_bank == 0);
    assert(pauses == 1 && configures == 1);
    assert(demo.pix_config.stage1 == PIX_GAUSSIAN && demo.pix_config.stage2 == PIX_SOBEL);
    assert(demo.pix_config.flags == (EDRV32_PIX_CFG_BC_EN_MASK |
        EDRV32_PIX_CFG_GAMMA_EN_MASK | EDRV32_PIX_CFG_GRAY_EN_MASK |
        EDRV32_PIX_CFG_BIN_EN_MASK | EDRV32_PIX_CFG_INV_EN_MASK));
    demo_parameters_apply(&p);
    assert(loads[0] == 256 && loads[1] == 256 && demo.gamma_bank == 1);
    unsigned int before = writes;
    assert(!demo_parameters_parse("geo set 1 450 100 100 0 0 0 0", &p));
    demo_parameters_apply(&p);
    assert(error && strstr(error, "geo-spec 2.4"));
    assert(writes == before && pauses == 2 && configures == 2 && !demo.geo_custom);
    assert(!demo_parameters_parse("geo set 1 123 1500 700 23 -12 1 0", &p));
    demo_parameters_apply(&p);
    assert(demo.geo_custom && demo.geo && pauses == 3 && configures == 3);
    assert(!demo_parameters_parse("geo set 0 0 1000 1000 0 0 0 0", &p));
    demo_parameters_apply(&p);
    assert(!demo.geo && demo.geo_custom);
    puts("PASS parameter application: alternating gamma banks, flags, matrix, no write on error");
    return 0;
}
