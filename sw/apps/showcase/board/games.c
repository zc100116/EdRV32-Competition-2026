/* games.c — showcase 4.5.5; one embedded record parsed per application step.
 * List descriptors live in the application heap; ROM bytes stay in DDR, clk_sys. */
#include "../app.h"
#include "../platform.h"
#include "../ui/theme.h"
#include "games.h"
#include "ddr_map.h"
#include <stdlib.h>
extern const uint8_t __game_pack_start[], __game_pack_end[];
static uint8_t *const uploads=(uint8_t *)(uintptr_t)
    (EDRV32_DDR_UNCACHED_BASE+SHOWCASE_UPLOAD_BASE);
static uint32_t used;
static unsigned embedded, parsed, count;
static struct game_record *records;
static ui_game_t *games;
static lv_image_dsc_t **images;
static uint32_t pack_bytes(void) { return (uint32_t)(__game_pack_end-__game_pack_start); }
static void publish(struct game_record r)
{
    records = realloc(records, (count+1)*sizeof(*records));
    games = realloc(games, (count+1)*sizeof(*games));
    images = realloc(images, (count+1)*sizeof(*images));
    if (!records || !games || !images) { platform_puts("game list allocation failed\r\n");
        platform_stop(); }
    images[count]=malloc(3*sizeof(**images));
    if (!images[count]) { platform_puts("game image allocation failed\r\n"); platform_stop(); }
    records[count]=r;
    images[count][0]=(lv_image_dsc_t){.header={.magic=LV_IMAGE_HEADER_MAGIC,
        .cf=LV_COLOR_FORMAT_A8,.w=r.name_w,.h=r.name_h,.stride=r.name_w},
        .data_size=(uint32_t)r.name_w*r.name_h,.data=r.name};
    images[count][2]=images[count][0];
    unsigned first_width=20;
    if((unsigned char)r.text[0]<128) {
        lv_font_glyph_dsc_t glyph;
        lv_font_get_glyph_dsc(&sim_font_20,&glyph,(unsigned char)r.text[0],0);
        first_width=glyph.adv_w;
    }
    images[count][2].header.w=first_width<r.name_w ? first_width : r.name_w;
    images[count][1]=(lv_image_dsc_t){.header={.magic=LV_IMAGE_HEADER_MAGIC,
        .cf=LV_COLOR_FORMAT_RGB565,.w=r.cover_w,.h=r.cover_h,.stride=r.cover_w*2},
        .data_size=(uint32_t)r.cover_w*r.cover_h*2,.data=r.cover};
    games[count]=(ui_game_t){.name=r.text,.initial="",.cover=NULL};
    ++count;
    /* realloc moves the descriptors: refresh all borrowed image pointers. */
    for (unsigned i=0;i<count;++i) {
        games[i].cover=records[i].cover ? &images[i][1] : NULL;
    }
}
void board_games_init(void)
{
    if (game_pack_count(__game_pack_start,pack_bytes(),&embedded)) {
        platform_puts("invalid EDGP v2\r\n"); platform_stop(); }
}
void board_games_step(void)
{
    if (parsed == embedded) return;
    struct game_record r;
    if (game_pack_record(&r,__game_pack_start,pack_bytes(),parsed++)) {
        platform_puts("invalid embedded EDG2\r\n"); platform_stop(); }
    publish(r);
    app_wake_at(platform_ticks());
}
uint32_t board_game_destination(void) { return SHOWCASE_UPLOAD_BASE+used; }
uint32_t board_game_available(void) { return SHOWCASE_UPLOAD_BYTES-used; }
unsigned board_game_append(uint32_t bytes,uint32_t *index)
{
    struct game_record r;
    unsigned status=game_record_parse(&r,uploads+used,bytes);
    if (status) return status;
    *index=count; publish(r); used+=(bytes+3)&~3u;
    return 0;
}
const struct game_record *board_game(unsigned i) { return &records[i]; }
const ui_game_t *ui_data_games(unsigned *n) { *n=count; return games; }

const lv_image_dsc_t *ui_data_game_name(unsigned i) { return &images[i][0]; }

const lv_image_dsc_t *ui_data_game_initial(unsigned i) { return &images[i][2]; }
