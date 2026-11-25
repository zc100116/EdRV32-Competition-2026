/* File: ui_test.c; tech 5b/7. Exercise real UTF-8 canvases on the normal coast
 * input recording; no GPU timing or rendering claims are made by this test. */
#include "core/core.h"
#include "ui/ui.h"
#include "data.h"
#include <assert.h>
#include <stdio.h>
#include <stdarg.h>
int plat_printf(const char *format,...)
{
    va_list args;va_start(args,format);int result=vprintf(format,args);va_end(args);return result;
}
static struct ember_sim simulation;
static struct ember_replay replay;
static struct gpu_quad rects[EMBER_UI_RECTS],glyphs[EMBER_UI_GLYPHS];
static unsigned non_digits(const struct ember_ui_canvas *canvas)
{
    unsigned count=0;
    for (unsigned g=0;g<canvas->glyph_count;++g) {
        if (canvas->codepoints[g]>='0' && canvas->codepoints[g]<='9') continue;
        unsigned prior=0;
        while (prior<g && canvas->codepoints[prior]!=canvas->codepoints[g]) ++prior;
        count+=prior==g;
    }
    return count;
}
int main(int argc,char **argv)
{
    assert(argc==2);
    ember_replay_load(&replay,argv[1]);
    ember_sim_begin(&simulation,replay.seed,&replay.config);
    struct ember_ui_canvas canvas={.rects=rects,.glyphs=glyphs};
    struct ember_ui_state ui={.tick_rate=60,.volume=100};
    unsigned peak=0,frame=0,first_clear=0;
    for (unsigned i=0;i<replay.count;++i) {
        ember_sim_step(&simulation,replay.input[i]);
        if (simulation.wave>=2 && !first_clear) {
            unsigned alive=0;
            for (unsigned e=0;e<EMBER_ENEMIES;++e) alive+=simulation.enemies[e].alive && simulation.enemies[e].wave==1;
            if (!alive) first_clear=i+1;
        }
        ember_ui_build(&canvas,&simulation,&ui,60,(uint32_t[16]){0},0);
        unsigned unique=0;
        for (unsigned g=0;g<canvas.glyph_count;++g) {
            unsigned prior=0;
            while (prior<g && canvas.codepoints[prior]!=canvas.codepoints[g]) ++prior;
            unique+=prior==g;
        }
        if (unique>peak) { peak=unique;frame=i+1; }
    }
    assert(simulation.phase==EMBER_WON);
    printf("PASS native Chinese canvases: frames=%u unique-visible-glyph-peak=%u at=%u first-wave-cleared=%u\n",replay.count,peak,frame,first_clear);
    struct ember_choice choices[128];unsigned count=0,card_peak=0,combinations=0;
    for (unsigned i=0;i<EMBER_COAST_POOL_COUNT;++i)
        choices[count++]=(struct ember_choice){(uint8_t)ember_coast_pool[i].kind,(uint8_t)ember_coast_pool[i].item_index,0};
    for (unsigned w=0;w<=2;w+=2) for (unsigned branch=1;branch<=2;++branch)
        choices[count++]=(struct ember_choice){EMBER_ITEM_EVOLUTION,(uint8_t)branch,(uint8_t)w};
    for (unsigned i=0;i<EMBER_UPGRADE_FILLERS_COUNT;++i)
        choices[count++]=(struct ember_choice){EMBER_ITEM_RESOURCE,(uint8_t)i,0};
    for (unsigned i=0;i<EMBER_BLESSINGS_COUNT;++i)
        choices[count++]=(struct ember_choice){EMBER_ITEM_BLESSING,(uint8_t)i,0};
    simulation.phase=EMBER_UPGRADE;simulation.panel=0;
    for (unsigned a=0;a<count;++a) for (unsigned b=a+1;b<count;++b) for (unsigned c=b+1;c<count;++c) {
        simulation.choices[0]=choices[a];simulation.choices[1]=choices[b];simulation.choices[2]=choices[c];
        ember_ui_build(&canvas,&simulation,&ui,60,(uint32_t[16]){0},0);
        unsigned needed=non_digits(&canvas);
        assert(needed<=140);
        if (needed>card_peak) card_peak=needed;
        ++combinations;
    }
    printf("PASS Chinese card cache: combinations=%u non-digit-glyph-peak=%u capacity=140 plus ten digits\n",combinations,card_peak);
    return 0;
}
