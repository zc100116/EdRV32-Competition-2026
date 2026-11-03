/* input.c — P5 R4/8.5; held Esc must be consumed once, transport expiry releases all. */
#include "input.h"
#include <assert.h>
#include <stdio.h>
uint32_t platform_pressed(void);
int main(void)
{
    struct virtual_input_state v={.keys=VI_ESC,.mouse=7,.active=1,.x=123,.y=456};
    showcase_input_virtual(v,0); showcase_input_sample(8);
    showcase_input_owner(INPUT_APP);
    assert(!showcase_input_keys(INPUT_APP) && !showcase_input_view(INPUT_APP).keys);
    v.keys=v.mouse=0; showcase_input_virtual(v,10); showcase_input_sample(0);
    v.keys=VI_ESC; v.mouse=7; showcase_input_virtual(v,20); showcase_input_sample(8);
    showcase_input_dispatch(); assert(platform_pressed()==8);
    assert(showcase_input_keys(INPUT_APP)==8 && !showcase_input_keys(INPUT_GUI));
    showcase_input_owner(INPUT_GUI); showcase_input_sample(8); showcase_input_dispatch();
    assert(!platform_pressed() && !showcase_input_keys(INPUT_GUI));
    assert(!showcase_input_view(INPUT_GUI).keys && !showcase_input_view(INPUT_GUI).mouse);
    v.keys=v.mouse=0; showcase_input_virtual(v,30); showcase_input_sample(0);
    v.keys=VI_ESC; v.mouse=7; showcase_input_virtual(v,40); showcase_input_sample(8);
    assert(showcase_input_keys(INPUT_GUI)==8 && showcase_input_view(INPUT_GUI).mouse==7);
    showcase_input_expire(339,300); assert(showcase_input_view(INPUT_GUI).keys==VI_ESC);
    showcase_input_expire(340,300); v=showcase_input_view(INPUT_GUI);
    assert(!v.keys && !v.mouse && !v.active && v.x==123 && v.y==456);
    showcase_input_sample(0);
    assert(!showcase_input_keys(INPUT_GUI));
    puts("PASS game Esc once, ownership suppression, 300 ms virtual release");
}
