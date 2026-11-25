/* File: ui.c
 * Spec: ember_isles gdd 3-5 and tech 2, E1/E2; GPU 2.8.
 * Description: Fusion Pixel UTF-8 HUD, weapon selection, volume and economy panels.
 * Clock domain: CPU frame; builders perform no MMIO or platform calls.
 */
#include "ui/ui.h"
#include "ui/font.h"
#include "data.h"
#include <stdio.h>
#include <string.h>

static void rect(struct ember_ui_canvas *out, int x, int y, unsigned w, unsigned h,
                 unsigned color, unsigned alpha)
{
    /* GPU quad width is nine bits; a full-width overlay is two rectangles. */
    while (w) {
        unsigned part = w > 511 ? 511 : w;
        gpu_quad(&out->rects[out->rect_count++], &(struct gpu_quad_args){
            .x = (uint32_t)x, .y = (uint32_t)y, .w = part, .h = h,
            .pal_group = color, .alpha = alpha
        });
        x += (int)part;
        w -= part;
    }
}

void ember_ui_text(struct ember_ui_canvas *out, int x, int y, const char *text, unsigned big)
{
    int origin = x;
    (void)big;
    while (*text) {
        uint32_t cp = ember_utf8_next(&text);
        if (cp == '\n') { x = origin; y += 16; continue; }
        unsigned width;
        ember_font_rows(cp, &width);
        if (cp != ' ') {
            unsigned i = out->glyph_count++;
            out->codepoints[i] = cp;
            gpu_quad(&out->glyphs[i], &(struct gpu_quad_args){
                .x = (uint32_t)x, .y = (uint32_t)y, .w = width, .h = 12,
                .alpha = 255, .pal_group = 15
            });
        }
        x += (int)width;
    }
}
static void center(struct ember_ui_canvas *out, int y, const char *text, unsigned big)
{
    ember_ui_text(out, 320 - (int)ember_text_width(text) / 2, y, text, big);
}
static int wrap(struct ember_ui_canvas *out, int x, int y, unsigned width, const char *text)
{
    int cursor = x;
    while (*text) {
        const char *begin = text;
        uint32_t cp = ember_utf8_next(&text);
        if (cp == '\n') { cursor=x;y+=16;continue; }
        unsigned advance;
        ember_font_rows(cp, &advance);
        if (cursor + (int)advance > x + (int)width) {
            cursor = x; y += 16;
        }
        char glyph[5] = {0};
        memcpy(glyph, begin, (size_t)(text - begin));
        ember_ui_text(out, cursor, y, glyph, 0);
        cursor += (int)advance;
    }
    return y + 16;
}

static void panel(struct ember_ui_canvas *out, int x, int y, unsigned w, unsigned h,
                  unsigned active)
{
    rect(out, x, y, w, h, active ? EMBER_FIRE : EMBER_EDGE, 255);
    rect(out, x + 1, y + 1, w - 2, h - 2, EMBER_PANEL, 249);
}

static void bar(struct ember_ui_canvas *out, int x, int y, unsigned w, unsigned h,
                unsigned value, unsigned maximum, unsigned color)
{
    rect(out, x, y, w, h, EMBER_TRACK, 255);
    /* Banked XP can fund several upgrades; the gauge stays full above its threshold. */
    unsigned fill = value >= maximum ? w : w * value / maximum;
    if (fill) rect(out, x, y, fill, h, color, 255);
}

static const char *weapon_name(const struct ember_sim *s,unsigned weapon)
{
    return s->player.evolution[weapon]==1?ember_weapons[weapon].evolution_a:
        s->player.evolution[weapon]==2?ember_weapons[weapon].evolution_b:ember_weapons[weapon].name;
}
static const char *choice_name(const struct ember_choice *c)
{
    switch (c->kind) {
    case EMBER_ITEM_WEAPON: return ember_weapons[c->id].name;
    case EMBER_ITEM_RELIC: return ember_relics[c->id].name;
    case EMBER_ITEM_INSCRIPTION: return ember_inscriptions[c->id].name;
    case EMBER_ITEM_EVOLUTION: return c->id == 1 ? ember_weapons[c->slot].evolution_a : ember_weapons[c->slot].evolution_b;
    case EMBER_ITEM_RESOURCE: return ember_upgrade_fillers[c->id].name;
    case EMBER_ITEM_BLESSING: return ember_blessings[c->id].name;
    case EMBER_ITEM_RESONANCE: return ember_resonances[c->id].name;
    case EMBER_ITEM_REFRESH: return "刷新商店";
    case EMBER_ITEM_CONTRACT: return ember_contracts[c->id].description;
    case EMBER_ITEM_CURSE: return ember_contracts[c->id].name;
    case EMBER_ITEM_CLEANSE: return ember_contracts[c->id].name;
    case EMBER_ITEM_CAP: return ember_attributes[c->id].name;
    case EMBER_ITEM_GOLD: return "金币";
    default: return "放弃";
    }
}
static const char *choice_description(const struct ember_choice *c)
{
    switch (c->kind) {
    case EMBER_ITEM_WEAPON: return ember_weapons[c->id].description;
    case EMBER_ITEM_RELIC: return ember_relics[c->id].description;
    case EMBER_ITEM_INSCRIPTION: return ember_inscriptions[c->id].description;
    case EMBER_ITEM_EVOLUTION: return ember_weapons[c->slot].description;
    case EMBER_ITEM_RESOURCE: return ember_upgrade_fillers[c->id].description;
    case EMBER_ITEM_BLESSING: return ember_blessings[c->id].description;
    case EMBER_ITEM_RESONANCE: return ember_resonances[c->id].description;
    default: return "";
    }
}
static const char *choice_tags(const struct ember_choice *c)
{
    if (c->kind == EMBER_ITEM_WEAPON) return ember_weapons[c->id].tags;
    if (c->kind == EMBER_ITEM_EVOLUTION) return ember_weapons[c->slot].tags;
    if (c->kind == EMBER_ITEM_RELIC) return ember_relics[c->id].tags;
    if (c->kind == EMBER_ITEM_INSCRIPTION) return ember_inscriptions[c->id].tags;
    if (c->kind == EMBER_ITEM_BLESSING) return ember_blessings[c->id].tags;
    return "";
}
static const char *tag_name(const char *id, size_t bytes)
{
    for (unsigned i = 0; i < EMBER_TAGS_COUNT; ++i)
        if (strlen(ember_tags[i].id) == bytes && !strncmp(ember_tags[i].id, id, bytes))
            return ember_tags[i].name;
    return NULL;
}
static void choice(struct ember_ui_canvas *out, const struct ember_sim *sim, unsigned i)
{
    const struct ember_choice *c = &sim->choices[i];
    int x = 40 + (int)i * 190;
    panel(out, x, 112, 180, 194, sim->selected == i);
    char description[512],tag_text[1024],name[128];
    snprintf(name,sizeof(name),"%s",choice_name(c));
    snprintf(description,sizeof(description),"%s",choice_description(c));
    if (c->kind==EMBER_ITEM_WEAPON) {
        const struct ember_weapons_row *w=&ember_weapons[c->id];
        unsigned level=sim->player.weapon_level[c->id];
        int old=level?w->damage*(100+((int)level-1)*w->damage_per_level)/100:0;
        int next=w->damage*(100+(int)level*w->damage_per_level)/100;
        snprintf(name,sizeof(name),"%s %u级",w->name,level+1);
        snprintf(description,sizeof(description),"升至 %u 级\n基础伤害 %d 提高到 %d",level+1,old,next);
    } else if (c->kind==EMBER_ITEM_EVOLUTION) {
        const char *full=ember_weapons[c->slot].description;
        const char *begin=c->id==1?full:strstr(full,ember_weapons[c->slot].evolution_b);
        const char *end=c->id==1?strstr(full,"；"):full+strlen(full);
        size_t bytes=(size_t)(end-begin);memcpy(description,begin,bytes);description[bytes]=0;
    }
    snprintf(tag_text,sizeof(tag_text),"%s",choice_tags(c));
    if (c->kind==EMBER_ITEM_WEAPON || c->kind==EMBER_ITEM_EVOLUTION) {
        unsigned weapon=c->kind==EMBER_ITEM_WEAPON?c->id:c->slot;
        uint32_t bits=ember_sim_weapon_tags(sim,weapon);
        if (c->kind==EMBER_ITEM_EVOLUTION && c->id==2 && sim->weapon_system[weapon].category==EMBER_STAFF)
            bits=(bits&~((1u<<EMBER_DATA_TAGS_AREA)|(1u<<EMBER_DATA_TAGS_GROUP)))|
                (1u<<EMBER_DATA_TAGS_SINGLE)|(1u<<EMBER_DATA_TAGS_CHARGE);
        unsigned written=0;
        for (unsigned t=0;t<EMBER_TAGS_COUNT;++t) if (bits&(1u<<t))
            written+=(unsigned)snprintf(tag_text+written,sizeof(tag_text)-written,"%s%s",written?"|":"",ember_tags[t].id);
        tag_text[written]=0;
    }
    ember_ui_text(out,x+48,128,name,0);
    int y=wrap(out,x+12,158,156,description);
    if (y < 258) {
        const char *text = tag_text;
        int tx = x + 12;
        while (*text) {
            const char *end = strchr(text, '|');
            const char *name = tag_name(text, end ? (size_t)(end - text) : strlen(text));
            if (name) {
                unsigned w = ember_text_width(name);
                if (tx + (int)w > x + 168) { tx = x + 12; y += 16; }
                if (y < 276) ember_ui_text(out, tx, y, name, 0);
                tx += (int)w + 6;
            }
            if (!end) break;
            text = end + 1;
        }
    }
    if (sim->selected == i) ember_ui_text(out, x + 12, 286, "J / Enter 确认", 0);
    if (sim->selected==i) ember_ui_text(out,x+12,286,"J 确认",0);
}
void ember_ui_build(struct ember_ui_canvas *out, const struct ember_sim *sim,
                    const struct ember_ui_state *state, unsigned fps, const uint32_t *perf,
                    unsigned particles)
{
    char text[256];
    out->rect_count = out->glyph_count = 0;
    if (sim->phase != EMBER_MENU) {
        panel(out, 8, 8, 212, 57, 0);
        snprintf(text, sizeof(text), "守火人  %d / %d", (int)sim->player.hp, (int)sim->player.max_hp);
        ember_ui_text(out, 16, 15, text, 0);
        bar(out, 16, 32, 196, 6, sim->player.hp > 0 ? (unsigned)sim->player.hp : 0,
            (unsigned)sim->player.max_hp, EMBER_HEALTH);
        int amounts[8]={sim->player.defense.permanent_shield,sim->player.defense.temporary[6],
            sim->player.defense.temporary[0],sim->player.defense.temporary[1],sim->player.defense.temporary[2],
            sim->player.defense.temporary[3],sim->player.defense.temporary[4],sim->player.defense.temporary[5]};
        static const unsigned shield_colors[]={EMBER_MIXED,EMBER_MIXED,EMBER_PAPER,EMBER_FIRE,EMBER_TIDE,EMBER_STAR,EMBER_SHADOW,EMBER_TRUE};
        int total=0,offset=0;
        for (unsigned i=0;i<8;++i) total+=amounts[i];
        int denominator=total>sim->player.max_hp?total:sim->player.max_hp;
        for (unsigned i=0;i<8;++i) {
            int from=offset*196/denominator;offset+=amounts[i];
            int to=offset*196/denominator;
            if (to>from) rect(out,16+from,32,(unsigned)(to-from),3,shield_colors[i],255);
        }
        bar(out,16,42,94,3,sim->player.charge,100,EMBER_STAR);
        bar(out,118,42,94,3,(unsigned)sim->oil,(unsigned)ember_lighting[0].oil_max,EMBER_FIRE);
        snprintf(text,sizeof(text),"灯油 %d%%  能量 %u%%",(int)sim->oil/100,sim->player.charge);
        ember_ui_text(out,16,50,text,0);
        panel(out,430,8,202,48,0);
        snprintf(text,sizeof(text),"海岸 第 %u / 10 波",(unsigned)sim->wave);
        ember_ui_text(out,442,15,text,0);
        snprintf(text,sizeof(text),"%02u:%02u  金币 %u",(unsigned)sim->combat_frame/3600,
                 (unsigned)sim->combat_frame/60%60,(unsigned)sim->gold);
        ember_ui_text(out,442,34,text,0);
        const struct ember_enemy *boss=NULL;
        for (unsigned i=0;i<EMBER_ENEMIES;++i) if (sim->enemies[i].alive &&
            ember_enemies[sim->enemies[i].kind].rank>=2 &&
            (!boss || ember_enemies[sim->enemies[i].kind].rank>ember_enemies[boss->kind].rank)) boss=&sim->enemies[i];
        if (boss) {
            panel(out,234,8,180,48,0);
            snprintf(text,sizeof(text),"%s %u/%u",ember_enemies[boss->kind].name,boss->stage+1,
                ember_enemies[boss->kind].rank==3?3:2);
            ember_ui_text(out,242,15,text,0);
            bar(out,242,32,164,6,(unsigned)boss->hp,(unsigned)boss->defense.max_hp,EMBER_HEALTH);
            if (boss->defense.posture_max) bar(out,242,43,164,3,(unsigned)boss->defense.posture,
                (unsigned)boss->defense.posture_max,EMBER_PAPER);
        }
        panel(out,8,296,512,56,0);
        snprintf(text,sizeof(text),"主 %s %u级",weapon_name(sim,sim->player.main_weapon),
                 sim->player.weapon_level[sim->player.main_weapon]);
        ember_ui_text(out,42,300,text,0);
        snprintf(text,sizeof(text),"副 %s %u级",sim->player.sub_weapon<50?weapon_name(sim,sim->player.sub_weapon):"无",
                 sim->player.sub_weapon<50?sim->player.weapon_level[sim->player.sub_weapon]:0);
        ember_ui_text(out,210,300,text,0);
        ember_ui_text(out,410,300,"Q 切换",0);
        snprintf(text,sizeof(text),"K %u秒",(sim->player.cooldown_k+59)/60);ember_ui_text(out,42,331,text,0);
        snprintf(text,sizeof(text),"L %u秒",(sim->player.cooldown_b+59)/60);ember_ui_text(out,194,331,text,0);
        snprintf(text,sizeof(text),"U %u%%",sim->player.charge);ember_ui_text(out,346,331,text,0);
        snprintf(text,sizeof(text),"等级 %u",(unsigned)sim->player.level);ember_ui_text(out,444,331,text,0);
        bar(out,8,355,512,4,sim->player.xp,sim->player.next_xp,EMBER_FIRE);
        panel(out,536,296,96,56,0);
        for (unsigned i=0;i<sim->pillar_count;++i)
            rect(out,540+sim->pillars[i].x/EMBER_Q*84/(sim->world_width/EMBER_Q),
                300+sim->pillars[i].y/EMBER_Q*44/(sim->world_height/EMBER_Q),
                3,3,sim->pillars[i].lit?EMBER_FIRE:EMBER_EDGE,255);
        if (sim->altars_available) rect(out,540+sim->altar.x/EMBER_Q*84/(sim->world_width/EMBER_Q),
            300+sim->altar.y/EMBER_Q*44/(sim->world_height/EMBER_Q),3,3,EMBER_STAR,255);
        if (sim->shop_available) rect(out,540+sim->merchant.x/EMBER_Q*84/(sim->world_width/EMBER_Q),
            300+sim->merchant.y/EMBER_Q*44/(sim->world_height/EMBER_Q),3,3,EMBER_TRUE,255);
        for (unsigned i=0;i<sim->rifts_count;++i) if (!(sim->rifts_used&(1u<<i)))
            rect(out,540+sim->rifts[i].x/EMBER_Q*84/(sim->world_width/EMBER_Q),
                300+sim->rifts[i].y/EMBER_Q*44/(sim->world_height/EMBER_Q),3,3,EMBER_SHADOW,255);
        rect(out,540+sim->player.x/EMBER_Q*84/(sim->world_width/EMBER_Q),
            300+sim->player.y/EMBER_Q*44/(sim->world_height/EMBER_Q),3,3,EMBER_PAPER,255);
        if (sim->rest && !sim->panel) center(out, 76, "休整：靠近商人或祭坛，F 交互", 0);
    }
    if (sim->phase == EMBER_MENU) {
        rect(out, 0, 0, 640, 360, EMBER_SHADE, 160);
        panel(out, 112, 54, 416, 250, 0);
        center(out, 79, "余烬群岛", 0);
        center(out, 109, "守住海岸最后的灯火", 0);
        if (state->menu_page == EMBER_WEAPON_MENU) {
            center(out, 146, "选择主武器，另一把作为副武器", 0);
            panel(out, 154, 179, 152, 65, state->menu_selected == 0);
            panel(out, 334, 179, 152, 65, state->menu_selected == 1);
            ember_ui_text(out, 188, 195, "余烬剑", 0);
            ember_ui_text(out, 368, 195, "余火杖", 0);
            ember_ui_text(out, 170, 220, "近战 · 挥砍", 0);
            ember_ui_text(out, 350, 220, "远程 · 弹体", 0);
            center(out, 268, "A / D 选择  J / Enter 开始  F / Esc 返回", 0);
        } else if (state->menu_page == EMBER_SETTINGS) {
            center(out, 151, "设置", 0);
            snprintf(text, sizeof(text), "音量 %u%%", state->volume);
            center(out, 194, text, 0);
            bar(out, 220, 225, 200, 8, state->volume, 100, EMBER_FIRE);
            center(out, 268, "A / D 调整音量  F / Esc 返回", 0);
        } else {
            panel(out, 218, 170, 204, 36, state->menu_selected == 0);
            center(out, 182, "开始游戏", 0);
            panel(out, 218, 222, 204, 36, state->menu_selected == 1);
            center(out, 234, "设置", 0);
            center(out, 278, "W / S 选择  J / Enter 确认", 0);
        }
        center(out, 328, "WASD 移动  J 攻击  K / L / U 技能  Q 换武器", 0);
    } else if (sim->phase == EMBER_UPGRADE) {
        rect(out, 0, 66, 640, 258, EMBER_SHADE, 230);
        center(out, 82, "余烬馈赠 · 三选一", 0);
        for (unsigned i = 0; i < 3; ++i) choice(out, sim, i);
    } else if (sim->panel) {
        rect(out, 0, 66, 640, 258, EMBER_SHADE, 225);
        panel(out, 40, 76, 560, 240, 0);
        const char *title = sim->panel == EMBER_PANEL_SHOP ? "海岸商人" :
            sim->panel == EMBER_PANEL_ALTAR ? "祭坛祝福" :
            sim->panel == EMBER_PANEL_REPLACE ? "满槽替换" : "裂隙契约";
        center(out, 88, title, 0);
        if (sim->panel == EMBER_PANEL_REPLACE) {
            snprintf(text,sizeof(text),"获得 %s，选择要替换的物品",choice_name(&sim->pending_item));
            ember_ui_text(out,56,112,text,0);
        }
        unsigned start = sim->panel_selected / 6 * 6;
        for (unsigned i = start; i < sim->option_count && i < start + 6; ++i) {
            int y = 140 + (int)(i - start) * 25;
            if (i == sim->panel_selected) rect(out,48,y-3,544,20,EMBER_EDGE,255);
            if (sim->panel == EMBER_PANEL_SHOP)
                snprintf(text,sizeof(text),"%s  %d 金币",choice_name(&sim->options[i]),(int)sim->option_prices[i]);
            else snprintf(text,sizeof(text),"%s",choice_name(&sim->options[i]));
            ember_ui_text(out,56,y,text,0);
        }
        if (sim->transaction_result) ember_ui_text(out,56,270,"金币不足",0);
        else if (sim->panel == EMBER_PANEL_REPLACE) {
            const char *explanation=sim->pending_item.kind==EMBER_ITEM_WEAPON?"旧武器落地，本关可拾回":
                sim->pending_item.kind==EMBER_ITEM_RELIC?"旧遗物返还商店价的25%金币":"旧铭文替换，无返还";
            ember_ui_text(out,56,270,explanation,0);
        } else if (sim->option_count<=4)
            wrap(out,56,234,520,choice_description(&sim->options[sim->panel_selected]));
        center(out,292,"WASD 选择  J / Enter 确认  F / Esc 离开",0);
    } else if (sim->phase == EMBER_WON || sim->phase == EMBER_LOST) {
        rect(out, 0, 0, 640, 360, EMBER_SHADE, 190);
        panel(out, 128, 86, 384, 202, sim->phase == EMBER_WON);
        center(out, 112, sim->phase == EMBER_WON ? "海岸的灯火仍在" : "灯火熄灭", 0);
        snprintf(text, sizeof(text), "击败 %u  伤害 %u", (unsigned)sim->player.kills, (unsigned)sim->damage_total);
        center(out, 160, text, 0);
        snprintf(text, sizeof(text), "存活 %02u:%02u  金币 %u", (unsigned)sim->combat_frame / 3600,
                 (unsigned)sim->combat_frame / 60 % 60, (unsigned)sim->gold);
        center(out, 192, text, 0);
        center(out, 250, "J / Enter 返回标题", 0);
    } else if (sim->paused) {
        rect(out, 0, 66, 640, 258, EMBER_SHADE, 190);
        panel(out, 192, 135, 256, 86, 0);
        center(out, 153, "暂停", 0);
        center(out, 191, "Enter 继续", 0);
    }
    if (state->show_perf) {
        snprintf(text, sizeof(text), "FPS %u T %u E %u S %u P %u GPU %u", fps, state->tick_rate,
                 (unsigned)sim->alive_count, (unsigned)sim->shot_count, particles, (unsigned)perf[0]);
        ember_ui_text(out, 10, 70, text, 0);
    }
}
