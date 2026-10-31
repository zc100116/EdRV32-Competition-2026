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

/* Q24 -log2(input/255), computed by normalized binary squaring in Q31.
 * The exp2 table samples 2^(-x) at x=j/64 in Q30; linear interpolation
 * is monotone and its maximum curve error is below 0.004 output levels.
 */
static const uint32_t exp2_q30[65] = {
    1073741824u, 1062175491u, 1050733751u, 1039415261u, 1028218693u,
    1017142735u, 1006186087u, 995347464u, 984625594u, 974019220u,
    963527098u, 953147997u, 942880699u, 932724001u, 922676710u,
    912737649u, 902905651u, 893179563u, 883558244u, 874040567u,
    864625413u, 855311680u, 846098274u, 836984114u, 827968132u,
    819049271u, 810226483u, 801498734u, 792865000u, 784324269u,
    775875538u, 767517817u, 759250125u, 751071493u, 742980960u,
    734977579u, 727060411u, 719228525u, 711481005u, 703816941u,
    696235434u, 688735596u, 681316545u, 673977412u, 666717336u,
    659535466u, 652430958u, 645402981u, 638450708u, 631573326u,
    624770026u, 618040012u, 611382493u, 604796689u, 598281827u,
    591837143u, 585461881u, 579155293u, 572916640u, 566745190u,
    560640218u, 554601009u, 548626854u, 542717053u, 536870912u,
};

static uint32_t negative_log2(unsigned int input)
{
    uint64_t value = ((uint64_t)input << 31) / 255;
    unsigned int exponent = 0;
    while (value < (UINT64_C(1) << 31)) {
        value <<= 1;
        ++exponent;
    }
    uint32_t fraction = 0;
    for (unsigned int bit = 0; bit < 24; ++bit) {
        value = (value * value) >> 31;
        if (value >= (UINT64_C(1) << 32)) {
            value >>= 1;
            fraction |= 1u << (23 - bit);
        }
    }
    return (exponent << 24) - fraction;
}

static uint8_t gamma_sample(uint32_t logarithm, int gamma)
{
    uint64_t power = (uint64_t)logarithm * 1000 / (unsigned int)gamma;
    /* 255*2^-9 < 0.5: all larger exponents quantize to zero. */
    if (power >= (9u << 24)) {
        return 0;
    }
    unsigned int whole = (unsigned int)(power >> 24);
    unsigned int index = ((unsigned int)power >> 18) & 63u;
    unsigned int fraction = (unsigned int)power & ((1u << 18) - 1);
    uint32_t value = exp2_q30[index] - (uint32_t)(
        (uint64_t)(exp2_q30[index] - exp2_q30[index + 1]) * fraction >> 18);
    return (uint8_t)(((uint64_t)value * 255 + (UINT64_C(1) << (29 + whole))) >>
                     (30 + whole));
}

void demo_parameters_gamma(uint8_t table[256], int gamma)
{
    table[0] = 0;
    for (unsigned int i = 1; i < 256; ++i) {
        table[i] = gamma_sample(negative_log2(i), gamma);
    }
}
