/* process.c — PIX 2.1–2.5 / GEO 2.1–2.2; simulator-only L0 software model.
 * Recomputed only after parameter changes, independent of LVGL's L1 draw buffer.
 */
#include "sim_data.h"
#include "theme.h"
#include "geo_matrix.h"
#include <string.h>
#include <stdlib.h>
extern const lv_image_dsc_t sim_indoor;
static uint32_t rgb[2][1280 * 720];
static uint16_t output[1280 * 720];
static lv_image_dsc_t image = {.header = {.magic = LV_IMAGE_HEADER_MAGIC,
    .cf = LV_COLOR_FORMAT_RGB565, .w = 1280, .h = 720, .stride = 2560},
    .data_size = sizeof(output), .data = (const uint8_t *)output};
static ui_process_config_t previous;
static bool valid;
static int clamp(int x) { return x < 0 ? 0 : x > 255 ? 255 : x; }
static uint32_t expand(uint16_t p)
{
    unsigned r = p >> 11, g = (p >> 5) & 63, b = p & 31;
    return (((r << 3) | (r >> 2)) << 16) | (((g << 2) | (g >> 4)) << 8) |
           ((b << 3) | (b >> 2));
}
static uint16_t pack(uint32_t p)
{
    return (uint16_t)(((p >> 8) & 0xf800) | ((p >> 5) & 0x07e0) | ((p >> 3) & 31));
}
static int gray(uint32_t p)
{
    return (77 * (p >> 16) + 150 * ((p >> 8) & 255) + 29 * (p & 255) + 128) >> 8;
}
static void stage(uint32_t *dst, const uint32_t *src, int op)
{
    for (int y = 0; y < 720; ++y) for (int x = 0; x < 1280; ++x) {
        uint32_t p[9];
        for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx)
            p[(dy+1)*3+dx+1] = x+dx < 0 || x+dx >= 1280 || y+dy < 0 || y+dy >= 720 ?
                               0 : src[(y+dy)*1280+x+dx];
        uint32_t result = 0;
        for (int shift = 0; shift <= 16; shift += 8) {
            int c[9];
            for (unsigned k = 0; k < 9; ++k)
                c[k] = op >= 4 ? gray(p[k]) : (int)((p[k] >> shift) & 255);
            int value = c[4];
            if (op == 1) {
                int sum = 0;
                for (unsigned k = 0; k < 9; ++k) sum += c[k];
                value = (sum + 4) / 9;
            } else if (op == 2)
                value = (c[0]+2*c[1]+c[2]+2*c[3]+4*c[4]+2*c[5]+c[6]+2*c[7]+c[8]+8)>>4;
            else if (op == 3) value = clamp(5*c[4]-c[1]-c[3]-c[5]-c[7]);
            else if (op == 4) value = clamp(abs(-c[0]+c[2]-2*c[3]+2*c[5]-c[6]+c[8]) +
                                           abs(-c[0]-2*c[1]-c[2]+c[6]+2*c[7]+c[8]));
            else if (op >= 5) for (unsigned k = 0; k < 9; ++k)
                if ((op == 5 && c[k] < value) || (op == 6 && c[k] > value)) value = c[k];
            result |= (uint32_t)value << shift;
        }
        dst[y*1280+x] = result;
    }
}
const lv_image_dsc_t *sim_process_image(const ui_process_config_t *config)
{
    if (valid && memcmp(&previous, config, sizeof previous) == 0) return &image;
    previous = *config;
    valid = true;
    uint8_t gamma[256];
    pix_gamma_table(gamma, (unsigned)config->gamma_tenths);
    const uint16_t *source = (const uint16_t *)sim_indoor.data;
    for (unsigned y = 0; y < 720; ++y) for (unsigned x = 0; x < 1280; ++x) {
        uint32_t p = expand(source[(y*sim_indoor.header.h/720)*sim_indoor.header.w +
                                  x*sim_indoor.header.w/1280]);
        uint32_t value = 0;
        for (unsigned shift = 0; shift <= 16; shift += 8) {
            int c = (p >> shift) & 255;
            c = clamp(((c-128)*config->contrast >> 8) + 128 + config->brightness);
            value |= (uint32_t)gamma[c] << shift;
        }
        rgb[0][y*1280+x] = config->original ? p : value;
    }
    unsigned bank = 0;
    if (!config->original) {
        if (config->stage1) { stage(rgb[1], rgb[0], config->stage1); bank = 1; }
        if (config->stage2) { stage(rgb[bank^1], rgb[bank], config->stage2); bank ^= 1; }
        for (unsigned i = 0; i < 1280*720; ++i) {
            uint32_t p = rgb[bank][i];
            if (config->gray) p = (uint32_t)gray(p) * 0x010101;
            if (config->binary) p = gray(p) >= config->threshold ? 0xffffff : 0;
            if (config->invert) p ^= 0xffffff;
            rgb[bank][i] = expand(pack(p));
        }
    }
    int32_t m[6];
    geo_matrix(m, config->original ? 0 : config->angle,
        config->original ? 100 : config->scale_percent,
        config->original ? 0 : config->translate_x, config->original ? 0 : config->translate_y,
        !config->original && config->mirror_x, !config->original && config->mirror_y, 1280, 720);
    for (unsigned y = 0; y < 720; ++y) for (unsigned x = 0; x < 1280; ++x) {
        int32_t sx = (int32_t)((int64_t)m[0]*x + (int64_t)m[1]*y + m[2]);
        int32_t sy = (int32_t)((int64_t)m[3]*x + (int64_t)m[4]*y + m[5]);
        int ix = sx >> 16, iy = sy >> 16;
        unsigned fx = (sx >> 8) & 255, fy = (sy >> 8) & 255;
        uint32_t p[4];
        for (int dy = 0; dy < 2; ++dy) for (int dx = 0; dx < 2; ++dx)
            p[dy*2+dx] = ix+dx < 0 || ix+dx >= 1280 || iy+dy < 0 || iy+dy >= 720 ?
                         0 : rgb[bank][(iy+dy)*1280+ix+dx];
        uint32_t result = 0;
        for (unsigned shift = 0; shift <= 16; shift += 8) {
            unsigned a = (p[0] >> shift)&255, b = (p[1] >> shift)&255;
            unsigned c = (p[2] >> shift)&255, d = (p[3] >> shift)&255;
            unsigned value = (a*(256-fx)*(256-fy)+b*fx*(256-fy)+c*(256-fx)*fy+d*fx*fy+32768)>>16;
            result |= value << shift;
        }
        output[y*1280+x] = pack(result);
    }
    return &image;
}
const lv_image_dsc_t *sim_l0_image(void)
{
    if (ui_page == 1) return ui_data_vision(false).image;
    if (ui_page == 2) return ui_data_vision(true).image;
    if (ui_page == 3) return ui_data_process(0);
    return NULL;
}
uint32_t sim_composite(const lv_image_dsc_t *l0, uint32_t foreground, unsigned x, unsigned y)
{
    uint32_t back = 0;
    if (l0) {
        const uint16_t *pixels = (const uint16_t *)l0->data;
        back = expand(pixels[(y*l0->header.h/720)*l0->header.w+x*l0->header.w/1280]);
    }
    unsigned alpha = foreground >> 24;
    uint32_t result = 0xff000000;
    for (unsigned shift = 0; shift <= 16; shift += 8) {
        unsigned value = alpha*((foreground >> shift)&255) +
                         (255-alpha)*((back >> shift)&255) + 128;
        result |= ((value + (value >> 8)) >> 8) << shift;
    }
    return result;
}
