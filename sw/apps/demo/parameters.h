/* File: parameters.h
 * Spec: pix-spec 2.2–2.6; geo-spec 2.1/2.4; Task T-UI1.
 * Description: Parameter UART boundary and complete shadow configuration.
 * Clock domain: none (parser); clk_sys (application).
 */
#ifndef EDRV32_DEMO_PARAMETERS_H
#define EDRV32_DEMO_PARAMETERS_H
#include "pix.h"
struct demo_parameters {
    int geo;
    int value[11];
};
/* 0=parsed, 1=not a parameter command, -1=invalid syntax/range. */
int demo_parameters_parse(const char *line, struct demo_parameters *parameters);
const char *demo_parameters_matrix(const struct demo_parameters *parameters, int32_t matrix[6]);
void demo_parameters_gamma(uint8_t table[256], int gamma);
void demo_parameters_apply(const struct demo_parameters *parameters);
#endif
