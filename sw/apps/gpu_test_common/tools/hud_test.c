/* hud_test.c — gpu-spec 2.7–2.8; batch alignment and complete HUD glyph regression.
 * Host frame thread, actual application lists and PC GPU reference renderer.
 */
#define main capture_main
#include "../../gpu_test/headless.c"
#undef main
#include "font8x16.h"

static void text_pixels(int x, int y, const char *text, uint16_t color)
{
    const uint16_t *surface = test.surface[test.frame & 1];
    for (; *text; ++text, x += 8) {
        unsigned glyph = (unsigned char)*text - 32;
        for (unsigned row = 0; row < 16; ++row)
            for (unsigned col = 0; col < 8; ++col) {
                uint16_t expected = font8x16[glyph][row] & (128u >> col) ? color : 0x1085;
                uint16_t actual = surface[(y + row) * 640 + x + col];
                if (actual != expected) {
                    fprintf(stderr, "HUD '%c' (%u,%u): expected %04x, actual %04x\n",
                            *text, x + col, y + row, expected, actual);
                    exit(1);
                }
            }
    }
}
static void diagnostic_ink(unsigned scene,unsigned mode)
{
    char number[16];
    snprintf(number,sizeof(number),"%u",scene==1?test.alive_count:test.triangles/3);
    unsigned mode_width=mode<2?24:scene==1?56:48;
    unsigned x0=14+mode_width+8+(scene==1?24:36)+8+(unsigned)strlen(number)*8+8;
    const uint16_t *surface=test.surface[test.frame&1];
    const char *label="FPS";
    for(unsigned i=0;i<3;++i)for(unsigned y=0;y<16;++y)for(unsigned x=0;x<8;++x)
        if(font8x16[(unsigned char)label[i]-32][y]&(128u>>x)){
            unsigned actual=surface[(340+y)*640+x0+i*8+x];
            if(actual!=0xffff){
                fprintf(stderr,"Diagnostic FPS ink (%u,%u): expected ffff, actual %04x\n",
                        x0+i*8+x,340+y,actual);
                exit(1);
            }
        }
}
int main(void)
{
    test_init();
    test.aa = 0; /* Exact font comparison; AA screenshots are inspected separately. */
    /* Smallest offending layout: one quad followed by another quad batch.
     * The second batch must start at byte 32, with COUNT still equal to one. */
    test_quad(0, 0, 8, 16, 0, 128, 1, 255);
    test_draw(0, 0, 1, 0, 1, 0);
    unsigned first = test.quads_count;
    test_quad(8, 0, 8, 16, 8, 128, 1, 255);
    test_draw(0, first, 1, 0, 1, 0);
    if (first != 2 || test.draws[1].count != 1) {
        fprintf(stderr, "Second quad batch: expected first=2 count=1, actual first=%u count=%u\n",
                first, test.draws[1].count);
        return 1;
    }
    for (unsigned scene = 1; scene <= 2; ++scene)
        for (unsigned mode = 0; mode < 3; ++mode)
            for (unsigned filter = 0; filter < (scene == 2 && mode == 2 ? 3u : 1u);
                 ++filter) {
                test_select(scene, mode, 6, filter);
                for (unsigned tick = 0; tick < 2; ++tick) {
                    test_frame();
                    for (unsigned i = 0; i < test.draws_count; ++i) {
                        const struct test_draw *draw = &test.draws[i];
                        if (draw->kind == 0 && (draw->first & 1)) {
                            fprintf(stderr, "Unaligned quad batch %u starts at %u\n",
                                    i, draw->first);
                            return 1;
                        }
                    }
                    diagnostic_ink(scene,mode);
                    char score[16];
                    snprintf(score, sizeof(score), "%07u", test.score);
                    text_pixels(50, 26, score, 0xffff);
                    if (test.quads_count > TEST_QUAD_MAX ||
                        test.triangles > TEST_TRI_MAX*3 || test.draws_count > 128) {
                        fprintf(stderr, "Scene list exceeds allocated buffers\n");
                        return 1;
                    }
                    if (scene == 2 && mode == 2) {
                        static const char *filters[] = {"NEAREST", "BILINEAR", "TRILINEAR"};
                        text_pixels(444, 12, filters[filter], 0xffff);
                    }
                }
            }
    pc_soc_destroy();
    puts("PASS aligned batches, list budgets and HUD pixels in all modes");
    return 0;
}
