/* File: parameters.c
 * Spec: pix-spec 2.2–2.6; geo-spec 2.1/2.4; Task T-UI1.
 * Description: Parse integer UART parameters; build gamma tables and inverse matrices.
 * Clock domain: none (pure software).
 */
#include "parameters.h"
#include "affine.h"
#include <limits.h>

static int starts(const char *line, const char *key)
{
    while (*key) {
        if (*line++ != *key++) {
            return 0;
        }
    }
    return 1;
}

int demo_parameters_parse(const char *line, struct demo_parameters *parameters)
{
    if (starts(line, "pix set ")) {
        parameters->geo = 0;
    } else if (starts(line, "geo set ")) {
        parameters->geo = 1;
    } else {
        return 1;
    }
    line += 8;
    unsigned int count = parameters->geo ? 8 : 11;
    for (unsigned int i = 0; i < count; ++i) {
        int negative = *line == '-';
        line += negative;
        if (*line < '0' || *line > '9') {
            return -1;
        }
        int64_t value = 0;
        while (*line >= '0' && *line <= '9') {
            value = value * 10 + (*line++ - '0');
            if (value > INT_MAX) {
                return -1;
            }
        }
        parameters->value[i] = (int)(negative ? -value : value);
        if (*line != (i + 1 == count ? 0 : ' ')) {
            return -1;
        }
        if (*line) {
            ++line;
        }
    }
    const int *v = parameters->value;
    if (parameters->geo) {
        return (v[0] < 0 || v[0] > 1 || v[2] <= 0 || v[3] <= 0 ||
                v[6] < 0 || v[6] > 1 || v[7] < 0 || v[7] > 1) ? -1 : 0;
    }
    return (v[0] < 0 || v[0] > 1 || v[1] < 0 || v[1] > 511 ||
            v[2] < -256 || v[2] > 255 || v[3] < 0 || v[3] > 1 || v[4] <= 0 ||
            v[5] < 0 || v[5] > 6 || v[6] < 0 || v[6] > 6 ||
            v[7] < 0 || v[7] > 1 || v[8] < 0 || v[8] > 1 ||
            v[9] < 0 || v[9] > 255 || v[10] < 0 || v[10] > 1) ? -1 : 0;
}

const char *demo_parameters_matrix(const struct demo_parameters *parameters, int32_t matrix[6])
{
    const int *v = parameters->value;
    return affine_inverse(matrix, v[1], v[2], v[3], v[4], v[5], v[6], v[7], 1280, 720);
}

/* Small software-only logarithm/exponential avoids pulling a full libc into SRAM.
 * Mantissa reduction keeps |z| <= 1/3; 20 log terms give <1e-20 series error.
 */
static double logarithm(double value)
{
    int exponent = 0;
    while (value < 1) {
        value *= 2;
        --exponent;
    }
    double z = (value - 1) / (value + 1);
    double term = z;
    double sum = 0;
    for (int n = 1; n < 40; n += 2) {
        sum += term / n;
        term *= z * z;
    }
    return 2 * sum + exponent * 0.69314718055994530942;
}

void demo_parameters_gamma(uint8_t table[256], int gamma)
{
    table[0] = 0;
    for (unsigned int i = 1; i < 256; ++i) {
        double power = logarithm(i / 255.0) * (1000.0 / gamma);
        /* Values below half an output LSB round to zero. */
        if (power < -6.234410725718371) {
            table[i] = 0;
            continue;
        }
        double factor = 1;
        while (power < -0.69314718055994530942) {
            power += 0.69314718055994530942;
            factor *= 0.5;
        }
        double term = 1;
        double sum = 1;
        for (int n = 1; n <= 20; ++n) {
            term *= power / n;
            sum += term;
        }
        table[i] = (uint8_t)(255 * factor * sum + 0.5);
    }
}
