/* filter.c — showcase 4.5.10; display counts, boundary classes and raw preservation. */
#include "detection.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void)
{
    ui_detection_t raw[]={
        {.class_id=0,.confidence=49},{.class_id=2,.confidence=50},
        {.class_id=2,.confidence=70},{.class_id=1,.confidence=90},
        {.class_id=79,.confidence=80},{.class_id=5,.confidence=25}
    };
    ui_detection_t original[6]; memcpy(original,raw,sizeof(raw));
    ui_vision_t out={0};
    assert(ui_data_detection_config().threshold==50);
    ui_detection_filter(&out,raw,6);
    assert(out.count==4 && out.category_count[1]==2 && out.category_count[2]==1);
    ui_data_detection_threshold(70); ui_detection_filter(&out,raw,6);
    assert(out.count==3 && out.category_count[1]==1 && out.category_count[2]==1);
    ui_data_detection_class(2,false); ui_detection_filter(&out,raw,6);
    assert(out.count==2 && out.category_count[1]==0);
    ui_data_detection_all(false); ui_detection_filter(&out,raw,6); assert(!out.count);
    ui_data_detection_class(79,true); ui_detection_filter(&out,raw,6);
    assert(out.count==1 && out.targets[0].class_id==79);
    ui_data_detection_all(true); ui_data_detection_threshold(25);
    ui_detection_filter(&out,raw,6);
    assert(out.count==6 && out.category_count[0]==1 && out.category_count[1]==2);
    assert(out.category_count[2]==1 && out.category_count[3]==1);
    assert(out.targets[4].class_id==79 && !memcmp(raw,original,sizeof(raw)));
    puts("PASS display threshold, 80-class mask, total/category counts, unchanged raw data");
}
