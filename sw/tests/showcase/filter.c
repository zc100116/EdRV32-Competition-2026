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
    assert(out.count==4 && out.category_used==3);
    assert(out.category_id[0]==2 && out.category_count[0]==2);
    ui_data_detection_threshold(70); ui_detection_filter(&out,raw,6);
    assert(out.count==3 && out.category_id[0]==1 && out.category_id[1]==2);
    ui_data_detection_class(2,false); ui_detection_filter(&out,raw,6);
    assert(out.count==2 && out.category_used==2 && out.category_id[1]==79);
    ui_data_detection_all(false); ui_detection_filter(&out,raw,6);
    assert(!out.count && !out.category_used && !out.category_count[0]);
    ui_data_detection_class(79,true); ui_detection_filter(&out,raw,6);
    assert(out.count==1 && out.targets[0].class_id==79);
    ui_data_detection_all(true); ui_data_detection_threshold(25);
    ui_detection_filter(&out,raw,6);
    assert(out.count==6 && out.category_id[0]==2 && out.category_count[0]==2);
    assert(out.category_id[1]==0 && out.category_id[2]==1 && out.category_id[3]==5);
    assert(out.category_id[4]==79 && out.category_used==5);
    assert(out.targets[4].class_id==79 && !memcmp(raw,original,sizeof(raw)));
    const unsigned ids[]={7,2,5,1,0,79,12,7,2,5,1,7,2};
    ui_detection_t many[13]={0};
    for(unsigned i=0;i<13;++i) {
        many[i].class_id=ids[i]; many[i].confidence=90;
    }
    ui_detection_filter(&out,many,13);
    const unsigned expected_ids[]={2,7,1,5,0}, expected_counts[]={3,3,2,2,1};
    assert(out.count==13 && out.category_used==5);
    assert(!memcmp(out.category_id,expected_ids,sizeof expected_ids));
    assert(!memcmp(out.category_count,expected_counts,sizeof expected_counts));
    puts("PASS display threshold, 80-class mask, total/category counts, unchanged raw data");
}
