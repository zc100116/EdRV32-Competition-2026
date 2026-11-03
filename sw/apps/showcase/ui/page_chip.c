/* page_chip.c — showcase design §4.3; SoC topology and CoreMark card.
 * Rectangles and orthogonal connectors only; UI thread, LVGL tick clock.
 */
#include "theme.h"
#include "coremark.h"
static lv_obj_t *score;
static lv_obj_t *per_mhz;
static lv_obj_t *progress;
static void wire(lv_obj_t *p, int x, int y, int w, int h)
{
    lv_obj_t *o = ui_box(p, x, y, w, h, LINE);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_radius(o, 0, 0);
}
static void module(lv_obj_t *p, const char *name, int x, int y, int w, int h,
                   unsigned mask)
{
    bool present = (ui_data_hardware() & mask) == mask;
    lv_obj_t *o = ui_box(p, x, y, w, h, present ? SELECTED : DISABLED);
    lv_obj_t *label = ui_label(o, name, 0, 0, &sim_font_14, present ? ACCENT : MUTED);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(label);
}
static void counters(lv_obj_t *p)
{
    ui_coremark_t d=ui_data_coremark();
    char s[256];
    ui_title(p,"CoreMark 性能计数器");
    for(unsigned round=0;round<2;++round) {
        lv_obj_t *card=ui_box(p,40+(int)round*612,104,588,376,PANEL);
        lv_snprintf(s,sizeof(s),"第 %u 轮   mcycle %llu   minstret %llu",round+1,
            (unsigned long long)d.cycles[round],(unsigned long long)d.instructions[round]);
        ui_label(card,s,14,12,&sim_font_14,ACCENT);
        for(unsigned slot=0;slot<8;++slot) {
            unsigned event=ui_hpm_event(round,slot)-1;
            lv_obj_t *name=ui_label(card,ui_hpm_names[event],14,47+(int)slot*39,
                &sim_font_14,TEXT);
            lv_obj_set_width(name,405);
            lv_label_set_long_mode(name,LV_LABEL_LONG_WRAP);
            lv_snprintf(s,sizeof(s),"%llu",(unsigned long long)d.events[event]);
            ui_label(card,s,436,47+(int)slot*39,&sim_font_14,ACCENT);
        }
        uint64_t ipc=d.cycles[round] ? d.instructions[round]*1000/d.cycles[round] : 0;
        lv_snprintf(s,sizeof(s),"IPC %llu.%03llu",(unsigned long long)(ipc/1000),
            (unsigned long long)(ipc%1000));
        ui_label(card,s,14,355,&sim_font_14,TEAL);
    }
    uint64_t ins=d.instructions[1];
    unsigned ic=ins ? (unsigned)(d.events[12]*1000000/ins) : 0;
    unsigned dc=ins ? (unsigned)(d.events[13]*1000000/ins) : 0;
    lv_snprintf(s,sizeof(s),"每千条指令：I$ 缺失 %u.%03u    D$ 缺失 %u.%03u",
        ic/1000,ic%1000,dc/1000,dc%1000);
    ui_label(p,s,42,495,&sim_font_16,TEAL);
    lv_obj_t *flags=ui_label(p,d.compiler_flags ? d.compiler_flags :
        "g15-tuned · SRAM · 尚未运行",42,531,&sim_font_14,MUTED);
    lv_obj_set_width(flags,1196); lv_label_set_long_mode(flags,LV_LABEL_LONG_WRAP);
}
void ui_page_chip(lv_obj_t *p)
{
    if(ui_tab==1) { counters(p); return; }
    ui_title(p, "芯片信息");
    lv_obj_t *diagram = ui_box(p, 40, 124, 710, 484, PANEL);
    ui_label(diagram, "clk_sys", 20, 14, &sim_font_14, MUTED);
    wire(diagram, 310, 68, 2, 18);
    wire(diagram, 398, 68, 2, 18);
    module(diagram, "EdRV32 CPU · I$ / D$", 240, 18, 230, 50, 0);
    module(diagram, "sys_xbar", 20, 86, 670, 30, 0);
    const char *slaves[] = {"ROM", "SRAM", "ddr_gateway", "CLINT", "PLIC",
        "sys_apb", "media_\napb_brg"};
    for(unsigned i = 0; i < 7; ++i) {
        int x = 20 + (int)i * 96;
        wire(diagram, x + 43, 116, 2, 19);
        module(diagram, slaves[i], x, 135, 88, 44, 0);
    }
    wire(diagram, 543, 179, 2, 14);
    module(diagram, "UART · GPIO · I2C\nCACHE_CTRL · SYSCTRL", 320, 193, 275, 42, 0);
    for(int x = 20; x < 684; x += 16) wire(diagram, x, 246, 8, 1);
    ui_label(diagram, "clk_mem", 20, 256, &sim_font_14, MUTED);
    ui_label(diagram, "NPU：clk_npu", 310, 272, &sim_font_14, MUTED);
    wire(diagram, 639, 179, 2, 85);
    module(diagram, "media_apb", 590, 264, 100, 28, 0);
    wire(diagram, 255, 179, 2, 200);
    const char *masters[] = {"DISP", "VIN + PIX", "", "NPU", "RND", "GEO", "ETH"};
    unsigned masks[] = {UI_DISP, UI_VIN | UI_PIX, 0, UI_NPU, UI_RND, UI_GEO, UI_ETH};
    for(unsigned i = 0; i < 7; ++i) {
        int x = 20 + (int)i * 96;
        wire(diagram, x + 43, 346, 2, 33);
        if(i == 1) {
            wire(diagram, x + 20, 346, 2, 5);
            wire(diagram, x + 66, 346, 2, 5);
            wire(diagram, x + 20, 350, 48, 2);
            module(diagram, "VIN", x, 310, 42, 36, UI_VIN);
            module(diagram, "PIX", x + 46, 310, 42, 36, UI_PIX);
        } else if(i != 2) module(diagram, masters[i], x, 310, 88, 36, masks[i]);
        char port[8];
        lv_snprintf(port, sizeof(port), "P%u", i);
        lv_obj_t *label = ui_label(diagram, port, x + 49, 353, &sim_font_14, MUTED);
        lv_obj_set_style_bg_color(label, lv_color_hex(PANEL), 0);
        lv_obj_set_style_bg_opa(label, LV_OPA_COVER, 0);
    }
    module(diagram, "mem_xbar · 7 主 × 1 从", 20, 379, 670, 32, 0);
    wire(diagram, 354, 411, 2, 18);
    module(diagram, "DDR3", 290, 429, 130, 32, 0);
    ui_label(diagram, "PG2L200H FPGA", 20, 466, &sim_font_14, MUTED);
    lv_obj_t *params = ui_box(p, 774, 124, 466, 262, PANEL);
    ui_label(params, "芯片参数", 24, 18, &sim_font_20, TEXT);
    char parameters[256];
    lv_snprintf(parameters,sizeof(parameters),"CPU    顺序双发射 RV32 · %u MHz\n\n"
        "I$ / D$    各 32 KiB    SRAM 64 KiB\n\n"
        "NPU    每拍 512 次乘加 @150 MHz\n\n"
        "DDR3    32 位 · 1000 MT/s\n\n显示    1280×720 @60 Hz",
        ui_data_system().clock_hz/1000000);
    ui_label(params,parameters,24,60,&sim_font_16,TEXT);
    lv_obj_t *card = ui_box(p, 774, 406, 466, 202, PANEL);
    ui_label(card, "CoreMark · Iterations/Sec", 24, 18, &sim_font_20, TEXT);
    score = ui_label(card, "", 24, 54, &sim_digits_40, ACCENT);
    per_mhz = ui_label(card, "", 216, 70, &sim_font_16, MUTED);
    progress = ui_label(card, "", 24, 115, &sim_font_14, MUTED);
    ui_button(card, "运行 CoreMark", 24, 148, 210, 0);
    ui_button(card, "性能计数器", 246, 148, 196, 1);
}
void ui_chip_update(void)
{
    if(ui_tab) return;
    ui_coremark_t d = ui_data_coremark();
    char s[100];
    if(d.score_tenths) lv_snprintf(s, sizeof(s), "%u.%u", d.score_tenths / 10,
        d.score_tenths % 10);
    else lv_snprintf(s, sizeof(s), "--");
    ui_text(score, s);
    if(d.score_tenths) lv_snprintf(s, sizeof(s), "%u.%03u\nCoreMark/MHz",
        d.per_mhz_thousandths / 1000, d.per_mhz_thousandths % 1000);
    else lv_snprintf(s, sizeof(s), "CoreMark/MHz");
    ui_text(per_mhz, s);
    if(d.running) lv_snprintf(s, sizeof(s), "正在运行 · %u%%", d.progress);
    else lv_snprintf(s, sizeof(s), "%s", d.score_tenths ? "运行完成" : "按确认开始跑分");
    ui_text(progress, s);
}
