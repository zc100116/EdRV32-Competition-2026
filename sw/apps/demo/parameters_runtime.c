/* File: parameters_runtime.c
 * Spec: pix-spec 2.3/2.6; geo-spec 2.4; SoC 7.3; Task T-UI1.
 * Description: Commit complete custom controls while VIN is paused at frame boundary.
 * Clock domain: clk_sys; parameter computation precedes any pipeline change.
 */
#include "runtime.h"
#include "parameters.h"

void demo_parameters_apply(const struct demo_parameters *parameters)
{
    const int *v = parameters->value;
    int32_t matrix[6];
    uint8_t gamma[256];
    if (parameters->geo) {
        const char *error = demo_parameters_matrix(parameters, matrix);
        if (error) {
            info_text("Input error", error);
            return;
        }
    } else {
        demo_parameters_gamma(gamma, v[4]);
    }
    demo_pipeline_pause();
    if (parameters->geo) {
        for (unsigned int i = 0; i < 6; ++i) {
            demo.geo_matrix[i] = matrix[i];
        }
        demo.geo_custom = 1;
        demo.geo = (unsigned int)v[0];
    } else {
        unsigned int bank = 1u - demo.gamma_bank;
        pix_gamma_load(bank, gamma);
        demo.gamma_bank = bank;
        demo.pix_config = (struct pix_config){
            (v[0] ? EDRV32_PIX_CFG_BC_EN_MASK : 0u) |
            (v[3] ? EDRV32_PIX_CFG_GAMMA_EN_MASK : 0u) |
            (v[7] ? EDRV32_PIX_CFG_GRAY_EN_MASK : 0u) |
            (v[8] ? EDRV32_PIX_CFG_BIN_EN_MASK : 0u) |
            (v[10] ? EDRV32_PIX_CFG_INV_EN_MASK : 0u),
            (enum pix_operation)v[5], (enum pix_operation)v[6], bank,
            (uint16_t)v[1], (int16_t)v[2], (uint8_t)v[9]};
        demo.pix_custom = 1;
    }
    demo_pipeline_configure(VIN_CAM0);
    info_text("Demo command", "OK");
}
