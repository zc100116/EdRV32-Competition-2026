/* File: affine.c
 * Spec: geo-spec 2.1, 2.4, 5.2; Task T-UI1-R.
 * Description: Integer inverse transform; Q30 CORDIC with fractional guard bits.
 * Clock domain: none (pure software).
 */
#include "affine.h"
#include <limits.h>

/* round(atan(2^-i) / (2*pi) * 2^60), i=0..59. */
static const int64_t atan_turns[60] = {
    INT64_C(144115188075855872), INT64_C(85076163258429568), INT64_C(44951908161305064),
    INT64_C(22818290470345124), INT64_C(11453424468330928), INT64_C(5732295643252264),
    INT64_C(2866847280169571), INT64_C(1433511120421931), INT64_C(716766496754740),
    INT64_C(358384615492276), INT64_C(179192478636968), INT64_C(89596260679883),
    INT64_C(44798133010118), INT64_C(22399066838831), INT64_C(11199533461137),
    INT64_C(5599766735784), INT64_C(2799883368544), INT64_C(1399941684353),
    INT64_C(699970842187), INT64_C(349985421095), INT64_C(174992710548),
    INT64_C(87496355274), INT64_C(43748177637), INT64_C(21874088818),
    INT64_C(10937044409), INT64_C(5468522205), INT64_C(2734261102),
    INT64_C(1367130551), INT64_C(683565276), INT64_C(341782638),
    INT64_C(170891319), INT64_C(85445659), INT64_C(42722830),
    INT64_C(21361415), INT64_C(10680707), INT64_C(5340354),
    INT64_C(2670177), INT64_C(1335088), INT64_C(667544),
    INT64_C(333772), INT64_C(166886), INT64_C(83443),
    INT64_C(41722), INT64_C(20861), INT64_C(10430),
    INT64_C(5215), INT64_C(2608), INT64_C(1304),
    INT64_C(652), INT64_C(326), INT64_C(163),
    INT64_C(81), INT64_C(41), INT64_C(20),
    INT64_C(10), INT64_C(5), INT64_C(3),
    INT64_C(1), INT64_C(1), INT64_C(0),
};

static int64_t rounded_divide(int64_t value, int64_t divisor)
{
    return value < 0 ? -((-value + divisor / 2) / divisor) :
                        (value + divisor / 2) / divisor;
}

static void sine_cosine(int angle, int64_t *sine, int64_t *cosine)
{
    angle %= 3600;
    if (angle > 1800) {
        angle -= 3600;
    } else if (angle < -1800) {
        angle += 3600;
    }
    int sign = 1;
    if (angle > 900) {
        angle -= 1800;
        sign = -1;
    } else if (angle < -900) {
        angle += 1800;
        sign = -1;
    }
    int64_t turn = INT64_C(1) << 60;
    int64_t z = (turn / 3600) * angle + rounded_divide((turn % 3600) * angle, 3600);
    /* round(product(1/sqrt(1+2^(-2*i)), i=0..59) * 2^60). */
    int64_t x = INT64_C(700114967507363456);
    int64_t y = 0;
    for (unsigned int i = 0; i < 60; ++i) {
        int64_t previous = x;
        if (z >= 0) {
            x -= y >> i;
            y += previous >> i;
            z -= atan_turns[i];
        } else {
            x += y >> i;
            y -= previous >> i;
            z += atan_turns[i];
        }
    }
    /* Keep twenty guard bits below Q30 until the final matrix quantization.
     * This avoids amplifying Q30 rounding through large pixel translations.
     */
    *sine = rounded_divide(y * sign, 1024);
    *cosine = rounded_divide(x * sign, 1024);
}

static int64_t inverse_coefficient(int64_t value, int scale, int mirror)
{
    /* Divide before multiplying by 1000 so the Q50 numerator fits int64. */
    int64_t result = (value / scale) * 1000 +
        rounded_divide((value % scale) * 1000, scale);
    return mirror ? -result : result;
}

static int64_t coordinate_product(int64_t coefficient, int64_t coordinate)
{
    int negative = (coefficient < 0) != (coordinate < 0);
    uint64_t a = (uint64_t)(coefficient < 0 ? -coefficient : coefficient);
    uint64_t b = (uint64_t)(coordinate < 0 ? -coordinate : coordinate);
    /* 96-bit product, shifted by 31 to retain four bits below Q16.16.
     * Each 32-bit limb product fits uint64; no RV32 floating/128-bit runtime.
     */
    uint64_t low = (a & UINT32_MAX) * (b & UINT32_MAX);
    uint64_t middle = (a >> 32) * (b & UINT32_MAX) +
                      (a & UINT32_MAX) * (b >> 32) + (low >> 32);
    uint64_t high = (a >> 32) * (b >> 32) + (middle >> 32);
    int64_t value = (int64_t)((high << 33) | ((middle & UINT32_MAX) << 1) |
                              ((low & UINT32_MAX) >> 31));
    return negative ? -value : value;
}

const char *affine_inverse(int32_t matrix[6], int angle_tenths, int scale_x,
                           int scale_y, int translate_x, int translate_y,
                           int mirror_x, int mirror_y, int width, int height)
{
    if (scale_x <= 0 || scale_y <= 0) {
        return "GEO scale must be positive (per mille)";
    }
    int64_t sine;
    int64_t cosine;
    sine_cosine(angle_tenths, &sine, &cosine);
    int64_t m[6] = {inverse_coefficient(cosine, scale_x, mirror_x),
        inverse_coefficient(sine, scale_x, mirror_x), 0,
        inverse_coefficient(-sine, scale_y, mirror_y),
        inverse_coefficient(cosine, scale_y, mirror_y), 0};
    for (unsigned int row = 0; row < 2; ++row) {
        unsigned int offset = row * 3;
        int64_t a = rounded_divide(m[offset], INT64_C(1) << 34);
        int64_t b = rounded_divide(m[offset + 1], INT64_C(1) << 34);
        /* 5.2: BW=32, BH=16, PW=PH=80; actual quantized coefficients. */
        if ((a < 0 ? -a : a) * 31 + (b < 0 ? -b : b) * 15 > 78 * 65536) {
            return "GEO transform exceeds geo-spec 2.4 source tile coverage";
        }
        int64_t center = (row == 0 ? width : height) - 1;
        int64_t translated = (center << 19) -
            coordinate_product(m[offset], (int64_t)width - 1 + 2 * (int64_t)translate_x) -
            coordinate_product(m[offset + 1], (int64_t)height - 1 + 2 * (int64_t)translate_y);
        int64_t translation = rounded_divide(translated, 16);
        if (translation < INT32_MIN || translation > INT32_MAX) {
            return "GEO matrix exceeds signed Q16.16 range";
        }
        matrix[offset] = (int32_t)a;
        matrix[offset + 1] = (int32_t)b;
        matrix[offset + 2] = (int32_t)translation;
    }
    return 0;
}
