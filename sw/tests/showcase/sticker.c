/* sticker.c — T-FACE-STICKER-R2 host acceptance; synthetic 27 fps landmarks. */
#include "sticker.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static sticker_detection_t face(int x, int y, int d, int dy)
{
    sticker_detection_t a = {{{x-d/2,y-dy/2},{x+d/2,y+dy/2},
                              {x,y+30},{x-20,y+60},{x+20,y+60}}};
    return a;
}
int main(void)
{
    sticker_state_t s = {0};
    sticker_detection_t f = face(400,300,80,0);
    sticker_step(&s,&f,1,37); assert(!sticker_opacity(&s.tracks[0]));
    sticker_step(&s,&f,1,37); assert(sticker_opacity(&s.tracks[0])==255);
    unsigned random = 23;
    int lo=1000000, hi=-1000000;
    int ly=1000000, hy=-1000000;
    for (unsigned i=0;i<600;++i) {
        f=face(400,300,80,0);
        for (unsigned k=0;k<5;++k) {
            random=random*1664525u+1013904223u;
            f.points[k].x+=(int)((random>>16)%7)-3;
            random=random*1664525u+1013904223u;
            f.points[k].y+=(int)((random>>16)%7)-3;
        }
        sticker_step(&s,&f,1,37);
        if (i>100) {
            int x=s.tracks[0].filter[0].value;
            if(x<lo)lo=x;
            if(x>hi)hi=x;
            int y=s.tracks[0].filter[1].value;
            if(y<ly)ly=y;
            if(y>hy)hy=y;
        }
    }
    printf("static eye anchor peak-to-peak x/y = %d/%d Q8 px\n",hi-lo,hy-ly);
    assert(hi-lo<=384 && hy-ly<=384);
    memset(&s,0,sizeof s);
    int lag=0;
    for(int i=0;i<100;++i) {
        f=face(100+i*600*37/1000,300,80,0); sticker_step(&s,&f,1,37);
        int error=(100+i*600*37/1000)*256-s.tracks[0].filter[0].value;
        if(error>lag)lag=error;
    }
    printf("600 px/s lag = %d/256 px (%d/100 frames)\n",lag,lag*100000/(600*37*256));
    assert(lag<=600*37*256/1000);
    for(unsigned i=1;i<=6;++i) {
        sticker_step(&s,NULL,0,37); assert(sticker_opacity(&s.tracks[0])==255);
    }
    for(unsigned i=7;i<=10;++i) {
        sticker_step(&s,NULL,0,37); assert(sticker_opacity(&s.tracks[0])==(10-i)*255/4);
    }
    memset(&s,0,sizeof s);
    for(int i=0;i<20;++i) {
        sticker_detection_t pair[]={face(200+i*10,300,80,0),face(390-i*10,300,80,0)};
        if(i&1) { sticker_detection_t tmp=pair[0];pair[0]=pair[1];pair[1]=tmp; }
        sticker_step(&s,pair,2,37);
        assert(s.tracks[0].raw_x==(200+i*10)*256);
        assert(s.tracks[1].raw_x==(390-i*10)*256);
    }
    unsigned angle=2;
    for(int i=0;i<50;++i) { angle=sticker_angle(angle,(i&1?5:7)*256);assert(angle==2); }
    assert(sticker_angle(2,10*256)==3);
    assert(sticker_angle(3,4*256)==3);
    assert(sticker_angle(3,2*256)==2);
    memset(&s,0,sizeof s); f=face(400,300,80,0); sticker_step(&s,&f,1,37);
    sticker_placement_t p; sticker_place(&s.tracks[0],0,&p);
    assert(abs(p.x-400)<=1 && abs(p.y-220)<=1 && p.width==200);
    s.tracks[0].filter[3].value=24*256;
    sticker_place(&s.tracks[0],0,&p);
    assert(abs(p.x-432)<=1 && abs(p.y-227)<=1 && p.width==200);
    assert(abs(sticker_tilt(80,36)-24*256)<256);
    s.tracks[0].filter[2].value=160*256;
    sticker_place(&s.tracks[0],0,&p); assert(p.width==400);
    memset(&s,0,sizeof s);
    sticker_step(&s,&f,1,37); sticker_step(&s,NULL,0,37);
    sticker_step(&s,&f,1,37); assert(!sticker_opacity(&s.tracks[0]));
    sticker_step(&s,&f,1,37); assert(sticker_opacity(&s.tracks[0])==255);
    sticker_detection_t four[]={face(100,100,80,0),face(300,100,80,0),
                               face(500,100,80,0),face(700,100,80,0)};
    memset(&s,0,sizeof s); sticker_step(&s,four,4,37); sticker_step(&s,four,4,37);
    for(unsigned i=0;i<3;++i)assert(sticker_opacity(&s.tracks[i])==255);
    memset(&s,0,sizeof s); f=face(400,300,80,0); sticker_step(&s,&f,1,37);
    sticker_place(&s.tracks[0],6,&p);
    assert(p.x==400 && p.y==300 && p.width==187);
    sticker_place(&s.tracks[0],9,&p);
    assert(p.x==400 && p.y==330 && p.width==50);
    sticker_place(&s.tracks[0],12,&p);
    assert(p.x==400 && p.y==360 && p.width==70);
    sticker_place_part(&s.tracks[0],15,0,&p);
    assert(p.x==370 && p.y==330 && p.width==45);
    sticker_place_part(&s.tracks[0],15,1,&p);
    assert(p.x==430 && p.y==330 && p.width==45);
    f=face(400,300,80,36); memset(&s,0,sizeof s); sticker_step(&s,&f,1,37);
    sticker_place_part(&s.tracks[0],16,0,&p);
    assert(p.x==370 && p.y==321 && s.tracks[0].angle==4);
    for (unsigned part=0;part<STICKER_PARTS;++part) {
        int style=-1; unsigned options=0;
        while ((style=sticker_next(part,style))>=0) {
            assert(sticker_styles[style].part==part); ++options;
        }
        assert(options==(part==STICKER_HEAD?5u:part==STICKER_EYES?4u:
                         part==STICKER_CHEEKS?2u:3u));
    }
    puts("PASS sticker: confirmation, hold/fade, crossing, hysteresis, anchor geometry");
}
