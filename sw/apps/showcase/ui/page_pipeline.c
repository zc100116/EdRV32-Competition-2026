/* page_pipeline.c — vision pipeline design 4 / 7.1–7.2; editable DDR block chain.
 * LVGL thread owns selection and menus; backend owns images and chain acceptance.
 */
#include "theme.h"
#include <string.h>
static unsigned selected;
static unsigned menu;
static bool parameter_mode;
static bool insert_at_source;
static lv_timer_t *thumbnail_timer;
static ui_pipe_stats_t last_stats;
static bool have_stats;
static bool grouped[UI_BLOCK_MAX];
static char rejection[200];
static ui_chain_t shown;
static lv_obj_t *root, *parameters, *path_rows, *metrics, *bandwidth, *band_fill;
static lv_obj_t *view_title, *notice, *file_info;
static lv_obj_t *card_details[UI_BLOCK_MAX];
static lv_obj_t *previous_image, *next_image, *source_card;
static lv_obj_t *cards[UI_BLOCK_MAX], *thumbs[UI_BLOCK_MAX+2], *first_parameter;
static lv_obj_t *parameter_values[5];
static const char *names[]={"", "亮度 / 对比度", "伽马", "滤波", "灰度", "二值化",
    "反色", "几何", "检测", "叠加"};
static const char *icons[]={"", LV_SYMBOL_TINT, LV_SYMBOL_SETTINGS, LV_SYMBOL_SETTINGS,
    LV_SYMBOL_IMAGE, LV_SYMBOL_SETTINGS, LV_SYMBOL_REFRESH, LV_SYMBOL_LOOP,
    LV_SYMBOL_EYE_OPEN, LV_SYMBOL_COPY};
static const char *presets[]={"标准识别", "边缘识别", "旋转识别", "局部放大", "整屏旋转",
    "夜视增强", "多级滤波", "PC 图片"};
static const char *filters[]={"均值", "高斯", "锐化", "Sobel", "腐蚀", "膨胀"};
static ui_block_t default_block(unsigned type)
{
    ui_block_t b={.type=(uint8_t)type};
    if(type==UI_BLOCK_LEVEL) b.p[1]=256;
    if(type==UI_BLOCK_GAMMA) b.p[0]=10;
    if(type==UI_BLOCK_FILTER) b.p[0]=2;
    if(type==UI_BLOCK_BINARY) b.p[0]=128;
    if(type==UI_BLOCK_GEO) b.p[1]=100;
    if(type==UI_BLOCK_OVERLAY) b.flags=1;
    return b;
}
static const char *invalid_reason(const ui_chain_t *c, unsigned error)
{
    if(error==1) return "链长度不符：需要完整的积木链。";
    if(c->count>UI_BLOCK_MAX) return "积木最多 8 块，请先删除一块。";
    unsigned detects=0;
    for(unsigned i=0;i<c->count;++i) {
        const ui_block_t *b=&c->block[i];
        if(b->type==UI_BLOCK_DETECT && ++detects>1) return "检测最多 1 块：NPU 只有一个。";
        if(b->type==UI_BLOCK_OVERLAY && (b->flags&1) && !detects)
            return "叠加检测框之前必须先放置检测积木。";
        if(b->type==UI_BLOCK_OVERLAY && !b->flags) return "叠加必须选择检测框或界面。";
    }
    if(c->view!=UI_VIEW_FINAL && c->view!=UI_VIEW_SOURCE && c->view>=c->count)
        return "查看的积木已不存在，请选择最终输出。";
    return "格式或参数范围不符；未使用的字段必须为零。";
}
static bool submit(ui_chain_t *c)
{
    unsigned error=ui_data_chain_set(c);
    if(error) {
        lv_snprintf(rejection,sizeof rejection,"未应用 · %s",invalid_reason(c,error));
        ui_text(notice,rejection);
        lv_obj_set_style_bg_opa(notice,LV_OPA_90,0);
        return false;
    }
    rejection[0]=0;
    ui_text(notice,"");
    lv_obj_set_style_bg_opa(notice,LV_OPA_TRANSP,0);
    return true;
}
static void describe(const ui_block_t *b, char *s, unsigned size)
{
    switch(b->type) {
        case UI_BLOCK_LEVEL: lv_snprintf(s,size,"亮度 %+d · 对比 %d",b->p[0],b->p[1]); break;
        case UI_BLOCK_GAMMA: lv_snprintf(s,size,"γ %d.%d",b->p[0]/10,b->p[0]%10); break;
        case UI_BLOCK_FILTER: lv_snprintf(s,size,"%s",filters[b->p[0]-1]); break;
        case UI_BLOCK_BINARY: lv_snprintf(s,size,"阈值 %d",b->p[0]); break;
        case UI_BLOCK_GEO: lv_snprintf(s,size,"%d° · %d%%",b->p[0],b->p[1]); break;
        case UI_BLOCK_DETECT: lv_snprintf(s,size,"门槛 %u%% · 异步取样",
            ui_data_detection_config().threshold); break;
        case UI_BLOCK_OVERLAY: lv_snprintf(s,size,"%s%s",b->flags&1 ? "检测框" : "",
            b->flags&2 ? " + 界面" : ""); break;
        default: lv_snprintf(s,size,"1280 × 720 · RGB565"); break;
    }
}
static void build_parameters(void);
static void block_focused(lv_event_t *e)
{
    unsigned index=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    if(index==selected) return;
    selected=index;
    for(unsigned i=0;i<shown.count;++i)
        lv_obj_set_style_bg_color(cards[i],
            lv_color_hex(i==selected ? SELECTED : grouped[i] ? 0xf0faf7 : PANEL),0);
    build_parameters();
}
static void parameter_changed(lv_event_t *e)
{
    unsigned field=(unsigned)(uintptr_t)lv_event_get_user_data(e);
    ui_chain_t c=ui_data_chain();
    ui_block_t *b=&c.block[selected];
    lv_obj_t *o=lv_event_get_target_obj(e);
    if(field>=5) {
        unsigned mask=1u<<(field-5);
        if(lv_obj_has_state(o,LV_STATE_CHECKED)) b->flags|=mask;
        else b->flags&=(uint8_t)~mask;
    } else {
        int n=lv_obj_check_type(o,&lv_dropdown_class) ? (int)lv_dropdown_get_selected(o)+1 :
            lv_slider_get_value(o);
        b->p[field]=(int16_t)n;
        if(parameter_values[field]) {
            char s[24]; lv_snprintf(s,sizeof s,"%d",n); ui_text(parameter_values[field],s);
        }
    }
    if(submit(&c)) {
        shown=ui_data_chain();
        ui_pipeline_update();
    } else if(field>=5) {
        lv_obj_set_state(o,LV_STATE_CHECKED,(shown.block[selected].flags&(1u<<(field-5)))!=0);
    }
}
static void add_parameter(const char *name, unsigned field, int low, int high, int y)
{
    ui_label(parameters,name,16,y,&sim_font_14,MUTED);
    char s[24]; lv_snprintf(s,sizeof s,"%d",shown.block[selected].p[field]);
    parameter_values[field]=ui_label(parameters,s,304,y,&sim_font_14,ACCENT);
    lv_obj_t *o=ui_slider(parameters,24,y+24,336,low,high);
    lv_slider_set_value(o,shown.block[selected].p[field],LV_ANIM_OFF);
    lv_obj_add_event_cb(o,parameter_changed,LV_EVENT_VALUE_CHANGED,(void *)(uintptr_t)field);
    if(!first_parameter) first_parameter=o;
}
static void add_flag(const char *name, unsigned bit, int y)
{
    ui_label(parameters,name,16,y,&sim_font_14,MUTED);
    lv_obj_t *o=ui_switch(parameters,322,y);
    lv_obj_set_state(o,LV_STATE_CHECKED,(shown.block[selected].flags&(1u<<bit))!=0);
    lv_obj_add_event_cb(o,parameter_changed,LV_EVENT_VALUE_CHANGED,(void *)(uintptr_t)(bit+5));
    if(!first_parameter) first_parameter=o;
}
static void build_parameters(void)
{
    lv_obj_clean(parameters); first_parameter=NULL;
    memset(parameter_values,0,sizeof parameter_values);
    char s[80];
    if(!shown.count) { ui_label(parameters,"空链 · 在来源后插入积木",16,12,&sim_font_16,TEXT); return; }
    const ui_block_t *b=&shown.block[selected];
    lv_snprintf(s,sizeof s,"%02u  %s",selected+1,names[b->type]);
    ui_label(parameters,s,16,10,&sim_font_20,TEXT);
    switch(b->type) {
        case UI_BLOCK_LEVEL:
            add_parameter("亮度",0,-256,255,36); add_parameter("对比度 Q8",1,0,512,80); break;
        case UI_BLOCK_GAMMA: add_parameter("伽马 × 0.1",0,3,30,36); break;
        case UI_BLOCK_FILTER: {
            first_parameter=ui_dropdown(parameters,16,50,356,"均值\n高斯\n锐化\nSobel\n腐蚀\n膨胀");
            lv_dropdown_set_selected(first_parameter,(unsigned)b->p[0]-1);
            lv_obj_add_event_cb(first_parameter,parameter_changed,LV_EVENT_VALUE_CHANGED,NULL);
            break;
        }
        case UI_BLOCK_BINARY: add_parameter("二值化阈值",0,0,255,36); break;
        case UI_BLOCK_GEO:
            add_parameter("角度 °",0,-180,180,36); add_parameter("缩放 %",1,50,400,80);
            add_parameter("平移 X",2,-1280,1280,128); add_parameter("平移 Y",3,-720,720,176);
            add_flag("水平镜像",0,228); add_flag("垂直镜像",1,268); break;
        case UI_BLOCK_DETECT:
            ui_button(parameters,"门槛与类别设置",16,48,356,2050);
            first_parameter=lv_obj_get_child(parameters,-1); break;
        case UI_BLOCK_OVERLAY:
            add_flag("叠加检测框",0,48); add_flag("叠加界面",1,88);
            for(unsigned i=0;i<selected;++i)
                if(shown.block[i].type==UI_BLOCK_GEO && shown.block[i].p[0]%90) {
                    lv_obj_t *note=ui_label(parameters,"任意角度：检测框以外接矩形显示",
                        16,128,&sim_font_14,MUTED);
                    lv_obj_set_width(note,356); break;
                }
            break;
        default: ui_label(parameters,"此积木无需参数",16,54,&sim_font_16,MUTED); break;
    }
    lv_obj_set_style_pad_bottom(parameters,18,0);
}
static void compact_button(lv_obj_t *p,const char *s,int x,int y,int w,unsigned action)
{
    ui_button(p,s,x,y,w,action);
    lv_obj_t *o=lv_obj_get_child(p,-1); lv_obj_set_height(o,34);
    lv_obj_set_y(lv_obj_get_child(o,0),7);
}
static void build_menu(void)
{
    lv_obj_t *shade=ui_box(root,0,0,1280,632,0x14243b);
    lv_obj_set_style_bg_opa(shade,LV_OPA_60,0);
    lv_obj_set_clickable(shade,true);
    lv_group_remove_all_objs(lv_group_get_default());
    lv_obj_t *box=ui_box(shade,390,98,500,414,PANEL);
    const char *title=menu==1 ? "积木操作" : menu==2 ? "换功能" : menu==3 ? "在后面插入" : "选择来源";
    ui_label(box,title,24,20,&sim_font_28,TEXT);
    ui_label(box,"← → 选择 · Enter 确认 · Esc 返回",24,60,&sim_font_14,MUTED);
    if(menu==1) {
        const char *choices[]={"换功能", "参数", "在后面插入", "删除", "看此级"};
        for(unsigned i=0;i<5;++i) ui_button(box,choices[i],24,98+(int)i*54,452,2010+i);
    } else if(menu==4) {
        const char *sources[]={"摄像头", "PC 图片", "测试图"};
        for(unsigned i=0;i<3;++i) ui_button(box,sources[i],24,98+(int)i*60,452,2040+i);
        ui_button(box,"在来源后插入",24,278,452,2060);
        ui_button(box,"看此级 · 来源原图",24,338,452,2061);
    } else {
        for(unsigned i=1;i<=9;++i)
            ui_button(box,names[i],24+(int)((i-1)%2)*232,98+(int)((i-1)/2)*58,220,2020+i);
    }
    lv_group_focus_obj(lv_group_get_obj_by_index(lv_group_get_default(),0));
}
void ui_pipeline_action(unsigned action)
{
    ui_chain_t c=ui_data_chain();
    unsigned before_selection=selected;
    if(action>=2101 && action<=2108) {
        ui_data_chain_preset(action-2100); selected=0; menu=0; parameter_mode=false;
        rejection[0]=0; ui_open(1); return;
    }
    if(action>=2200 && action<2208) {
        selected=action-2200; menu=1; parameter_mode=false; ui_open(1); return;
    }
    if(action==2000) { menu=4; parameter_mode=false; ui_open(1); return; }
    if(action==2001 || action==2061) {
        c.view=action==2061 ? UI_VIEW_SOURCE : UI_VIEW_FINAL;
        if(submit(&c)) { menu=0; parameter_mode=false; ui_open(1); }
        return;
    }
    if(action==2002 || action==2003) { ui_data_image_step(action==2002 ? -1 : 1); return; }
    if(action==2050 || (action==2011 && c.block[selected].type==UI_BLOCK_DETECT)) {
        menu=0; ui_detection_settings=true; ui_open(1); return;
    }
    if(action==2060) { insert_at_source=true; menu=3; ui_open(1); return; }
    if(action==2010 || action==2012) {
        insert_at_source=false; menu=action==2010 ? 2 : 3; ui_open(1); return;
    }
    if(action==2011) {
        menu=0; parameter_mode=true; ui_open(1);
        if(first_parameter) lv_group_focus_obj(first_parameter);
        return;
    }
    if(action==2013) {
        for(unsigned i=selected;i+1<c.count;++i) c.block[i]=c.block[i+1];
        memset(&c.block[--c.count],0,sizeof c.block[0]);
        if(c.view==selected) c.view=UI_VIEW_FINAL;
        else if(c.view!=UI_VIEW_FINAL && c.view!=UI_VIEW_SOURCE && c.view>selected) --c.view;
    } else if(action==2014) c.view=(uint8_t)selected;
    else if(action>=2021 && action<=2029) {
        unsigned type=action-2020;
        if(menu==3) {
            if(c.count==UI_BLOCK_MAX) {
                ui_text(notice,"未应用 · 积木最多 8 块，请先删除一块。");
                lv_snprintf(rejection,sizeof rejection,"未应用 · 积木最多 8 块，请先删除一块。");
                menu=0; ui_open(1); return;
            }
            unsigned at=c.count && !insert_at_source ? selected+1 : 0;
            for(unsigned i=c.count;i>at;--i) c.block[i]=c.block[i-1];
            c.block[at]=default_block(type); ++c.count;
            if(c.view!=UI_VIEW_FINAL && c.view!=UI_VIEW_SOURCE && c.view>=at) ++c.view;
            selected=at;
        } else c.block[selected]=default_block(type);
    } else if(action>=2040 && action<=2042) c.source=(uint8_t)(action-2040);
    else return;
    bool accepted=submit(&c);
    if(!accepted) selected=before_selection;
    menu=0; ui_open(1);
}
bool ui_pipeline_back(void)
{
    if(menu) {
        if(menu==2) menu=1;
        else if(menu==3) menu=insert_at_source ? 4 : 1;
        else menu=0;
        ui_open(1); return true;
    }
    if(parameter_mode) { parameter_mode=false; ui_open(1); return true; }
    return false;
}
void ui_pipeline_update(void)
{
    ui_chain_t c=ui_data_chain();
    if(memcmp(&c,&shown,sizeof c)) { ui_open(1); return; }
    ui_vision_t v=ui_data_vision();
    for(unsigned i=0;i<shown.count+2u;++i) {
        unsigned block=i==shown.count+1u ?
            (shown.count ? (unsigned)shown.count-1 : UI_VIEW_FINAL) : i ? i-1 : UI_VIEW_FINAL;
        lv_image_set_src(thumbs[i],ui_data_thumb(block));
        lv_obj_invalidate(thumbs[i]);
    }
    ui_pipe_stats_t stats=ui_data_pipe_stats();
    char s[200];
    if(shown.view==UI_VIEW_SOURCE) lv_snprintf(s,sizeof s,"来源原图");
    else if(shown.view==UI_VIEW_FINAL) lv_snprintf(s,sizeof s,"最终输出 / HDMI");
    else {
        lv_snprintf(s,sizeof s,"看此级 · %s",names[shown.block[shown.view].type]);
        for(unsigned i=0;i<stats.hop_count;++i) {
            ui_hop_t h=stats.hop[i];
            if((h.engine==UI_HOP_CAM_PIX || h.engine==UI_HOP_MEM_PIX) &&
                shown.view>=h.first && shown.view<=h.last) {
                lv_snprintf(s,sizeof s,"看此级 · %s · 显示本次 PIX 处理的输出",
                    names[shown.block[shown.view].type]);
                break;
            }
        }
    }
    ui_text(view_title,s);
    for(unsigned i=0;i<shown.count;++i) {
        describe(&shown.block[i],s,sizeof s); ui_text(card_details[i],s);
    }
    if(shown.source==UI_SOURCE_PC_IMAGE) {
        bool busy=v.image_status==UI_IMAGE_RECEIVING || v.image_status==UI_IMAGE_DETECTING;
        lv_obj_set_state(previous_image,LV_STATE_DISABLED,busy);
        lv_obj_set_state(next_image,LV_STATE_DISABLED,busy);
        lv_snprintf(s,sizeof s,"%s   %u / %u",v.image_name,v.image_index,v.image_total);
        ui_text(file_info,s);
    }
    if(have_stats && !memcmp(&stats,&last_stats,sizeof stats)) return;
    last_stats=stats; have_stats=true;
    lv_obj_clean(path_rows);
    const char *engines[]={"CAM → CH0 · PIX 融合", "CAM → CH1", "MEM → CH0 · PIX",
        "MEM → CH2 · NPU", "GEO 几何", "RND 叠加"};
    for(unsigned i=0;i<stats.hop_count;++i) {
        ui_hop_t h=stats.hop[i];
        lv_snprintf(s,sizeof s,"%s",engines[h.engine]);
        ui_label(path_rows,s,0,(int)i*22,&sim_font_14,TEXT);
        if(h.engine==UI_HOP_CAM_RAW) lv_snprintf(s,sizeof s,"来源 · 随摄像头帧");
        else if(h.engine==UI_HOP_CAM_PIX)
            lv_snprintf(s,sizeof s,"%u–%u · 随摄像头帧",h.first+1,h.last+1);
        else lv_snprintf(s,sizeof s,"%u–%u  %u.%u ms",h.first+1,h.last+1,h.us/1000,h.us/100%10);
        ui_label(path_rows,s,222,(int)i*22,&sim_font_14,MUTED);
    }
    // Box lag only exists when the chain samples frames for detection.
    bool detect=false;
    for(unsigned i=0;i<c.count;++i) detect=detect || c.block[i].type==UI_BLOCK_DETECT;
    if(detect)
        lv_snprintf(s,sizeof s,"端到端 %u.%u ms   ·   %u fps   ·   框滞后 %u ms",
            stats.e2e_us/1000,stats.e2e_us/100%10,stats.fps,stats.box_lag_us/1000);
    else
        lv_snprintf(s,sizeof s,"端到端 %u.%u ms   ·   %u fps",
            stats.e2e_us/1000,stats.e2e_us/100%10,stats.fps);
    ui_text(metrics,s);
    lv_snprintf(s,sizeof s,"DDR  %u.%02u / %u.%02u GB/s",stats.ddr_mbps/1000,
        stats.ddr_mbps/10%100,stats.ddr_limit_mbps/1000,stats.ddr_limit_mbps/10%100);
    ui_text(bandwidth,s);
    unsigned fill=stats.ddr_mbps*356/stats.ddr_limit_mbps;
    lv_obj_set_width(band_fill,(int)(fill>356 ? 356 : fill));
    lv_obj_set_style_bg_color(band_fill,lv_color_hex(fill>356 ? 0xc45131 : TEAL),0);
}
static void refresh_thumbnails(lv_timer_t *timer)
{
    (void)timer;
    if(ui_page==1 && !ui_detection_settings) ui_pipeline_update();
}
void ui_page_pipeline(lv_obj_t *p)
{
    root=p; shown=ui_data_chain(); have_stats=false;
    if(!thumbnail_timer) thumbnail_timer=lv_timer_create(refresh_thumbnails,200,NULL);
    ui_video_surface(p);
    if(selected>=shown.count) selected=shown.count ? shown.count-1 : 0;
    ui_label(p,"预设",16,18,&sim_font_16,MUTED);
    for(unsigned i=0;i<8;++i) {
        compact_button(p,presets[i],76+(int)i*148,10,138,2101+i);
        if(shown.preset==i+1) lv_obj_add_state(lv_obj_get_child(p,-1),LV_STATE_CHECKED);
    }
    lv_obj_t *strip=ui_box(p,16,56,1248,202,PANEL);
    lv_obj_set_style_border_width(strip,0,0);
    lv_obj_set_style_bg_opa(strip,LV_OPA_90,0);
    lv_obj_set_scrollable(strip,true); lv_obj_set_scroll_dir(strip,LV_DIR_HOR);
    lv_obj_set_style_pad_all(strip,8,0);
    memset(grouped,0,sizeof grouped);
    ui_pipe_stats_t stats=ui_data_pipe_stats();
    for(unsigned i=0;i<stats.hop_count;++i) {
        ui_hop_t h=stats.hop[i];
        if(h.engine!=UI_HOP_CAM_PIX && h.engine!=UI_HOP_MEM_PIX) continue;
        unsigned first=h.engine==UI_HOP_CAM_PIX ? 0 : h.first+1u;
        unsigned last=h.last+1u;
        lv_obj_t *band=ui_box(strip,(int)first*204,0,(int)(last-first)*204+180,184,0xdaf0e9);
        lv_obj_set_style_border_width(band,0,0);
        ui_label(band,h.engine==UI_HOP_CAM_PIX ? "一次 PIX 处理 · 与摄像头融合" :
            "一次 PIX 处理",10,164,&sim_font_14,TEAL);
        for(unsigned k=h.first;k<=h.last;++k) grouped[k]=true;
    }
    const char *sources[]={"摄像头", "PC 图片", "测试图"};
    for(unsigned i=0;i<shown.count+2u;++i) {
        unsigned k=i-1;
        bool source=i==0, hdmi=i==shown.count+1u;
        const char *name=source ? sources[shown.source] : hdmi ? "HDMI" :
            names[shown.block[k].type];
        unsigned action=source ? 2000 : hdmi ? 2001 : 2200+k;
        ui_button(strip,"",(int)i*204,2,180,action);
        lv_obj_t *card=lv_obj_get_child(strip,-1); lv_obj_set_height(card,156);
        char s[80];
        if(source || hdmi) lv_snprintf(s,sizeof s,"%s  %s",
            source ? LV_SYMBOL_VIDEO : LV_SYMBOL_PLAY,name);
        else lv_snprintf(s,sizeof s,"%s %02u %s",icons[shown.block[k].type],k+1,name);
        ui_label(card,s,10,7,&sim_font_16,source || hdmi ? TEAL : TEXT);
        if(source) source_card=card;
        if(!source && !hdmi) {
            cards[k]=card;
            lv_obj_add_event_cb(card,block_focused,LV_EVENT_FOCUSED,(void *)(uintptr_t)k);
            lv_obj_set_style_bg_color(card,
                lv_color_hex(k==selected ? SELECTED : grouped[k] ? 0xf0faf7 : PANEL),0);
            describe(&shown.block[k],s,sizeof s);
        } else lv_snprintf(s,sizeof s,"%s",source ? "输入 · 1280 × 720" : "最终输出 · RGB565");
        lv_obj_t *detail=ui_label(card,s,10,32,&sim_font_14,MUTED);
        if(!source && !hdmi) card_details[k]=detail;
        ui_picture(card,ui_data_thumb(source ? UI_VIEW_FINAL : hdmi ?
            (shown.count ? (unsigned)shown.count-1 : UI_VIEW_FINAL) : k),10,56,160,90);
        thumbs[i]=lv_obj_get_child(card,-1);
        if(i<shown.count+1u) ui_label(strip,"→",188+(int)i*204,70,&sim_font_16,MUTED);
    }
    lv_obj_t *main=ui_box(p,16,286,820,330,PANEL);
    lv_obj_set_style_bg_opa(main,LV_OPA_TRANSP,0);
    lv_obj_set_style_border_width(main,0,0);
    view_title=ui_label(main,"",16,10,&sim_font_16,0xffffff);
    lv_obj_set_style_bg_color(view_title,lv_color_hex(0x10233a),0);
    lv_obj_set_style_bg_opa(view_title,LV_OPA_80,0);
    if(shown.source==UI_SOURCE_PC_IMAGE) {
        file_info=ui_label(main,"",16,44,&sim_font_14,0xffffff);
        compact_button(main,"上一张",16,82,100,2002);
        previous_image=lv_obj_get_child(main,-1);
        compact_button(main,"下一张",16,126,100,2003);
        next_image=lv_obj_get_child(main,-1);
    }
    parameters=ui_box(p,852,280,412,120,PANEL);
    lv_obj_set_scrollable(parameters,true); lv_obj_set_scroll_dir(parameters,LV_DIR_VER);
    lv_obj_set_style_bg_opa(parameters,LV_OPA_90,0);
    build_parameters();
    lv_obj_t *hardware=ui_box(p,852,410,412,206,PANEL);
    lv_obj_set_style_bg_opa(hardware,LV_OPA_90,0);
    ui_label(hardware,"硬件路径",16,10,&sim_font_20,TEXT);
    ui_label(hardware,"积木 / 耗时",284,14,&sim_font_14,MUTED);
    path_rows=ui_box(hardware,16,42,380,86,PANEL);
    lv_obj_set_style_border_width(path_rows,0,0);
    lv_obj_set_scrollable(path_rows,true); lv_obj_set_scroll_dir(path_rows,LV_DIR_VER);
    metrics=ui_label(hardware,"",16,134,&sim_font_14,TEXT);
    bandwidth=ui_label(hardware,"",16,158,&sim_font_14,MUTED);
    ui_bar(hardware,16,186,356,1,TEAL); band_fill=lv_obj_get_child(hardware,-1);
    notice=ui_label(p,rejection,20,260,&sim_font_14,0xb4482f);
    lv_obj_set_style_bg_color(notice,lv_color_hex(PANEL),0);
    lv_obj_set_style_bg_opa(notice,rejection[0] ? LV_OPA_90 : LV_OPA_TRANSP,0);
    ui_hint("← → 选择积木或预设 · Enter 打开菜单 · Esc 返回 · 长链可横向滚动");
    ui_pipeline_update();
}
void ui_pipeline_ready(void)
{
    lv_group_focus_obj(shown.count ? cards[selected] : source_card);
    if(menu) build_menu();
}
