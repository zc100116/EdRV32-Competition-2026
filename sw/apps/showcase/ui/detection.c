/* detection.c — showcase 4.5.10; RAM-only configuration filters display copies.
 * Raw YOLO results and wire records remain owned by the inference backend. */
#include "detection.h"
#include <string.h>
static ui_detection_config_t config={50,{UINT32_MAX,UINT32_MAX,0xffff}};
ui_detection_config_t ui_data_detection_config(void) { return config; }
void ui_data_detection_threshold(unsigned percent) { config.threshold=percent; }
void ui_data_detection_class(unsigned id,bool enabled)
{
    uint32_t bit=1u<<(id%32);
    if(enabled) config.classes[id/32]|=bit;
    else config.classes[id/32]&=~bit;
}
void ui_data_detection_all(bool enabled)
{
    config.classes[0]=config.classes[1]=enabled ? UINT32_MAX : 0;
    config.classes[2]=enabled ? 0xffff : 0;
}
void ui_detection_filter(ui_vision_t *out,const ui_detection_t *raw,unsigned count)
{
    out->count=0;
    memset(out->category_count,0,sizeof(out->category_count));
    unsigned counts[80]={0};
    out->category_used=0;
    memset(out->category_id,0,sizeof(out->category_id));
    for(unsigned i=0;i<count;++i) {
        const ui_detection_t *d=&raw[i];
        if(d->confidence<config.threshold ||
           !(config.classes[d->class_id/32]&(1u<<(d->class_id%32)))) continue;
        ++counts[d->class_id];
        if(out->count<5) out->targets[out->count]=*d;
        ++out->count;
    }
    /* Ascending IDs make equal-count ties deterministic without a second sort. */
    for(unsigned id=0;id<80;++id) {
        if(!counts[id]) continue;
        unsigned rank=0;
        while(rank<out->category_used && out->category_count[rank]>=counts[id]) ++rank;
        if(rank==5) continue;
        if(out->category_used<5) ++out->category_used;
        for(unsigned j=out->category_used-1;j>rank;--j) {
            out->category_count[j]=out->category_count[j-1];
            out->category_id[j]=out->category_id[j-1];
        }
        out->category_count[rank]=counts[id]; out->category_id[rank]=id;
    }
}
const char *const ui_coco_names[80]={
    "行人","自行车","汽车","摩托车","飞机","公交车","火车","卡车","船","交通灯",
    "消防栓","停车标志","停车计时器","长椅","鸟","猫","狗","马","羊","牛",
    "大象","熊","斑马","长颈鹿","背包","雨伞","手提包","领带","行李箱","飞盘",
    "滑雪板","单板滑雪","运动球","风筝","棒球棒","棒球手套","滑板","冲浪板","网球拍","瓶子",
    "酒杯","杯子","叉子","刀","勺子","碗","香蕉","苹果","三明治","橙子",
    "西兰花","胡萝卜","热狗","披萨","甜甜圈","蛋糕","椅子","沙发","盆栽","床",
    "餐桌","马桶","电视","笔记本电脑","鼠标","遥控器","键盘","手机","微波炉","烤箱",
    "烤面包机","水槽","冰箱","书","时钟","花瓶","剪刀","泰迪熊","吹风机","牙刷"
};
