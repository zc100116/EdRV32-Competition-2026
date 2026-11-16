/* page_chip.c — showcase §4.3; chip parameters and CoreMark native tables.
 * The GUI thread owns score, progress and the running spinner.
 */
#include "widgets.h"
#include "coremark.h"
static lv_obj_t *score, *per_mhz, *progress, *spinner;
static void counters(lv_obj_t *p)
{
    ui_coremark_t d=ui_data_coremark();
    ui_page_layout(p,"CoreMark 性能计数器",false);
    lv_obj_t *row=ui_stack(p,LV_FLEX_FLOW_ROW,UI_SPACE_LG);
    for(unsigned round=0;round<2;++round) {
        lv_obj_t *card=ui_panel(row,LV_PCT(48)); char text[256];
        lv_snprintf(text,sizeof text,"第 %u 轮 · mcycle %llu · minstret %llu",round+1,
            (unsigned long long)d.cycles[round],(unsigned long long)d.instructions[round]);
        ui_text_label(card,text,&sim_font_14,ACCENT);
        lv_obj_t *table=ui_data_table(card,2,8);
        lv_table_set_column_width(table,0,398); lv_table_set_column_width(table,1,150);
        for(unsigned slot=0;slot<8;++slot) {
            unsigned event=ui_hpm_event(round,slot)-1;
            lv_table_set_cell_value(table,slot,0,ui_hpm_names[event]);
            lv_snprintf(text,sizeof text,"%llu",(unsigned long long)d.events[event]);
            lv_table_set_cell_value(table,slot,1,text);
        }
        uint64_t ipc=d.cycles[round] ? d.instructions[round]*1000/d.cycles[round] : 0;
        lv_snprintf(text,sizeof text,"IPC %llu.%03llu",(unsigned long long)(ipc/1000),
            (unsigned long long)(ipc%1000));
        ui_text_label(card,text,&sim_font_14,TEAL);
    }
    uint64_t ins=d.instructions[1]; char text[192];
    unsigned ic=ins ? (unsigned)(d.events[12]*1000000/ins) : 0;
    unsigned dc=ins ? (unsigned)(d.events[13]*1000000/ins) : 0;
    lv_snprintf(text,sizeof text,"每千条指令：I$ 缺失 %u.%03u · D$ 缺失 %u.%03u",
        ic/1000,ic%1000,dc/1000,dc%1000);
    ui_text_label(p,text,&sim_font_16,TEAL);
    lv_obj_t *flags=ui_text_label(p,d.compiler_flags ? d.compiler_flags :
        "g15-tuned · SRAM · 尚未运行",&sim_font_14,MUTED);
    lv_obj_set_width(flags,LV_PCT(100));
}
void ui_page_chip(lv_obj_t *p)
{
    if(ui_tab==1) { counters(p); return; }
    ui_page_layout(p,"芯片信息",false);
    lv_obj_t *row=ui_stack(p,LV_FLEX_FLOW_ROW,UI_SPACE_LG);
    lv_obj_t *params=ui_panel(row,LV_PCT(60));
    lv_obj_set_height(params,500); lv_obj_set_scrollable(params,true);
    lv_obj_t *table=ui_data_table(params,2,16);
    lv_table_set_column_width(table,0,150); lv_table_set_column_width(table,1,540);
    const char *names[]={"器件","CPU","片上存储","NPU","DDR3","显示","系统互连",
        "外设","内存互连"};
    char cpu[96]; lv_snprintf(cpu,sizeof cpu,"顺序双发射 RV32 · %u MHz",
                             ui_data_system().clock_hz/1000000);
    const char *values[]={"PG2L200H FPGA",cpu,"I$ / D$ 各 32 KiB · SRAM 64 KiB",
        "每拍 512 次乘加 @180 MHz","32 位 · 1000 MT/s","1280×720 @60 Hz",
        "CPU → sys_xbar → ROM / SRAM / DDR / CLINT / PLIC",
        "UART · GPIO · I2C · CACHE_CTRL · SYSCTRL · media_apb",
        "DISP / VIN+PIX / CPU / NPU / RND / GEO / ETH → mem_xbar → DDR3"};
    for(unsigned i=0;i<9;++i) {
        lv_table_set_cell_value(table,i,0,names[i]); lv_table_set_cell_value(table,i,1,values[i]);
    }
    const char *blocks[]={"DISP","VIN + PIX","CPU","NPU","RND","GEO","ETH"};
    const unsigned masks[]={UI_DISP,UI_VIN|UI_PIX,0,UI_NPU,UI_RND,UI_GEO,UI_ETH};
    for(unsigned i=0;i<7;++i) {
        lv_table_set_cell_value(table,9+i,0,blocks[i]);
        lv_table_set_cell_value(table,9+i,1,(ui_data_hardware()&masks[i])==masks[i] ?
                                "已连接" : "当前硬件无此模块");
    }
    lv_obj_t *card=ui_panel(row,LV_PCT(38));
    ui_text_label(card,"CoreMark · Iterations/Sec",&sim_font_20,TEXT);
    score=ui_number(card,"",false);
    per_mhz=ui_text_label(card,"",&sim_font_20,MUTED);
    lv_obj_t *state=ui_stack(card,LV_FLEX_FLOW_ROW,UI_SPACE_SM);
    spinner=lv_spinner_create(state); lv_obj_set_size(spinner,32,32);
    progress=ui_text_label(state,"",&sim_font_16,MUTED);
    ui_action_button(card,"运行 CoreMark",0); ui_action_button(card,"性能计数器",1);
}
void ui_chip_update(void)
{
    if(ui_tab) return;
    ui_coremark_t d=ui_data_coremark(); char text[100];
    if(d.score_tenths) lv_snprintf(text,sizeof text,"%u.%u",d.score_tenths/10,d.score_tenths%10);
    else lv_snprintf(text,sizeof text,"--");
    ui_text(score,text);
    lv_snprintf(text,sizeof text,"%u.%03u CoreMark/MHz",d.per_mhz_thousandths/1000,
                d.per_mhz_thousandths%1000); ui_text(per_mhz,text);
    if(d.running) lv_snprintf(text,sizeof text,"正在运行 · %u%%",d.progress);
    else lv_snprintf(text,sizeof text,"%s",d.score_tenths ? "运行完成" : "按确认开始跑分");
    ui_text(progress,text); lv_obj_set_hidden(spinner,!d.running);
}
