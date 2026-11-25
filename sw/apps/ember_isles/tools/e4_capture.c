/* File: e4_capture.c; tech 6 E4 screenshot and thirty-second content recording.
 * Uses the shared game/GPU path, eight independent deterministic character fixtures.
 * Clock domain: virtual 60 Hz; uncompressed 640x360 AVI records every fourth frame.
 */
#define main ember_existing_headless_main
#include "../src/headless.c"
#undef main
static FILE *video;
static long movi_start;
static uint32_t offsets[450];
static void u32(uint32_t n)
{
    unsigned char bytes[4] = {(unsigned char)n, (unsigned char)(n >> 8),
        (unsigned char)(n >> 16), (unsigned char)(n >> 24)};
    if (fwrite(bytes, 1, 4, video) != 4) { perror("write E4 AVI"); exit(1); }
}
static void fourcc(const char *s)
{
    if (fwrite(s, 1, 4, video) != 4) { perror("write E4 AVI tag"); exit(1); }
}
static void patch(long start, uint32_t size)
{
    long current = ftell(video);
    if (fseek(video, start, SEEK_SET)) { perror("seek E4 AVI"); exit(1); }
    u32(size);
    if (fseek(video, current, SEEK_SET)) { perror("seek E4 AVI end"); exit(1); }
}
static void avi_begin(void)
{
    video = fopen("outputs/ember_isles/e4/content.avi", "wb");
    if (!video) { perror("open E4 AVI"); exit(1); }
    fourcc("RIFF"); u32(0); fourcc("AVI ");
    fourcc("LIST"); long hdrl = ftell(video); u32(0); fourcc("hdrl");
    fourcc("avih"); u32(56);
    const uint32_t avih[14] = {66667,10368000,0,16,450,0,1,691200,640,360,0,0,0,0};
    for (unsigned i = 0; i < 14; ++i) u32(avih[i]);
    fourcc("LIST"); long strl = ftell(video); u32(0); fourcc("strl");
    fourcc("strh"); u32(56); fourcc("vids"); fourcc("DIB ");
    const uint32_t strh[12] = {0,0,0,1,15,0,450,691200,UINT32_MAX,0,0,(360u<<16)|640};
    for (unsigned i = 0; i < 12; ++i) u32(strh[i]);
    fourcc("strf"); u32(40);
    const uint32_t strf[10] = {40,640,360,(24u<<16)|1,0,691200,0,0,0,0};
    for (unsigned i = 0; i < 10; ++i) u32(strf[i]);
    patch(strl, (uint32_t)(ftell(video) - strl - 4));
    patch(hdrl, (uint32_t)(ftell(video) - hdrl - 4));
    fourcc("LIST"); movi_start = ftell(video); u32(0); fourcc("movi");
}
static void avi_frame(unsigned index)
{
    const uint32_t *pixels = pc_soc_pixels();
    offsets[index] = (uint32_t)(ftell(video) - movi_start - 4);
    fourcc("00db"); u32(691200);
    unsigned char row[640 * 3];
    for (int y = 359; y >= 0; --y) {
        for (unsigned x = 0; x < 640; ++x) {
            uint32_t rgb = pixels[(unsigned)y * 2 * 1280 + x * 2];
            row[x * 3] = (unsigned char)rgb;
            row[x * 3 + 1] = (unsigned char)(rgb >> 8);
            row[x * 3 + 2] = (unsigned char)(rgb >> 16);
        }
        if (fwrite(row, 1, sizeof(row), video) != sizeof(row)) {
            perror("write E4 frame"); exit(1);
        }
    }
}
static void avi_end(void)
{
    patch(movi_start, (uint32_t)(ftell(video) - movi_start - 4));
    fourcc("idx1"); u32(450 * 16);
    for (unsigned i = 0; i < 450; ++i) {
        fourcc("00db"); u32(16); u32(offsets[i]); u32(691200);
    }
    patch(4, (uint32_t)(ftell(video) - 8));
    if (fclose(video)) { perror("close E4 AVI"); exit(1); }
}
int main(void)
{
    static struct ember_replay replay;
    replay.seed = 20261124;
    ember_run_config_default(&replay.config);
    replay.config.sub_weapon = 1;
    ember_game_init(); ember_game_replay(&replay);
    avi_begin();
    for (frame = 1; frame <= 1800; ++frame) {
        unsigned local = (frame - 1) % 225;
        if (!local) {
            struct ember_sim *s = (struct ember_sim *)(uintptr_t)ember_game_state();
            ember_sim_init(s, 20261124 + frame);
            ember_sim_character(s, (frame - 1) / 225);
            s->phase = EMBER_PLAY; s->wave = 1; s->rest = 60000;
            s->player.charge = 100;
            ember_sim_pet(s, ((frame - 1) / 225) % 6, ((frame - 1) / 225) % 12);
            for (unsigned n = 0; n < 6; ++n)
                ember_sim_spawn(s, ((frame - 1) / 225 * 2 + n) % 15,
                    n == 0 ? 1 + ((frame - 1) / 225) % 8 : 0,
                    s->player.x + (50 + (int)n * 15) * EMBER_Q,
                    s->player.y + ((int)n - 3) * 20 * EMBER_Q);
        }
        keys = local % 90 < 70 ? EMBER_J : 0;
        keys |= local < 60 ? EMBER_DOWN : local < 120 ? EMBER_RIGHT :
            local < 180 ? EMBER_UP : EMBER_LEFT;
        if (local == 1) keys |= EMBER_K;
        if (local == 30) keys |= EMBER_L;
        if (local == 60) keys |= EMBER_U;
        pc_soc_game_input(keys, (struct plat_pointer_state){0});
        ember_game_frame(frame); plat_wait_vsync();
        if (frame % 4 == 0) avi_frame(frame / 4 - 1);
        if (frame == 120 || frame == 570 || frame == 1020 || frame == 1695) {
            char path[160];
            snprintf(path, sizeof(path), "outputs/ember_isles/e4/frame%05u.png", frame);
            pc_png_write(path, pc_soc_pixels());
        }
    }
    avi_end(); pc_soc_destroy();
    puts("E4 capture: 1800 ticks, 450 AVI frames, 15 fps, 30 seconds, four screenshots");
    return 0;
}
