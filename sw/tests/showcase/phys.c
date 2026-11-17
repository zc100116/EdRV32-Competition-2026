/* phys.c — T-TOWER-PHYS acceptance and RV32IM instruction benchmark.
 * Standalone deterministic scenarios; no LVGL or device dependencies.
 * Clock domain: host / Spike instruction clock.
 */
#include "phys.h"
#include <string.h>
#define Q(n) ((phys_q)((n)*65536))
static phys_world world;
static phys_material wood = {64,52429,3277};
static phys_shape box(int width, int height)
{
    phys_shape s = {.type=PHYS_POLYGON,.count=4};
    s.vertices[0] = (phys_vec){-Q(width)/2,-Q(height)/2};
    s.vertices[1] = (phys_vec){Q(width)/2,-Q(height)/2};
    s.vertices[2] = (phys_vec){Q(width)/2,Q(height)/2};
    s.vertices[3] = (phys_vec){-Q(width)/2,Q(height)/2};
    return s;
}
static int block(phys_type type, int x, int y, int width, int height, phys_q angle,
                 phys_material material)
{
    phys_body_def d = {.type=type,.position={Q(x),Q(y)},.angle=angle,
        .material=material,.part_count=1};
    d.parts[0] = box(width,height);
    return phys_body_add(&world,&d);
}
static void begin(void)
{
    phys_world_init(&world,(phys_vec){0,Q(600)});
}
static int floor_body(phys_type type)
{
    /* Static mass scale is immaterial; keep its geometric moment representable. */
    return block(type,0,310,1000,20,0,(phys_material){1,52429,0});
}
#ifndef PHYS_PERF
static void steps(int n) { for (int i=0; i<n; ++i) phys_step(&world); }
#endif
#ifdef PHYS_PERF
#include "edrv32.h"
static uint32_t instructions(void)
{
    uint32_t value;
    __asm__ volatile (".insn i 0x73, 2, %0, x0, -1022" : "=r"(value) :: "memory");
    return value;
}
static void number(uint32_t n)
{
    char digits[10];
    int count = 0;
    do { digits[count++] = (char)('0'+n%10); n /= 10; } while (n);
    while (count) edrv32_putchar(digits[--count]);
}
static void text_out(const char *s) { while (*s) edrv32_putchar(*s++); }
int main(void)
{
    begin();
    floor_body(PHYS_STATIC);
    /* 23 blocks plus platform = maximum 24 live rigid bodies. */
    for (int i=0; i<23; ++i) block(PHYS_DYNAMIC,0,290-i*20,20,20,0,wood);
    uint64_t total = 0;
    uint32_t peak = 0;
    uint32_t active_peak = 0;
    uint64_t active_total = 0;
    for (int i=0; i<600; ++i) {
        uint32_t start = instructions();
        phys_step(&world);
        uint32_t elapsed = instructions()-start;
        total += elapsed;
        if (elapsed > peak) peak = elapsed;
        if (i < 60) {
            active_total += elapsed;
            if (elapsed > active_peak) active_peak = elapsed;
        }
    }
    text_out("phys-perf 24 bodies, 600 steps: average=");
    number((uint32_t)(total/600));
    text_out(" max="); number(peak);
    text_out(" instructions/step; first60 average=");
    number((uint32_t)(active_total/60));
    text_out(" max="); number(active_peak); text_out("\n");
    edrv32_exit(total/600 > 250000);
}
#else
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define F(n) ((phys_q)((n)*65536.0))
static double real(phys_q q) { return q/65536.0; }
static void require(int condition, const char *name, double actual, double limit)
{
    if (!condition) {
        fprintf(stderr,"FAIL %s: actual=%.6f limit=%.6f\n",name,actual,limit);
        exit(1);
    }
}
static void rest_test(void)
{
    begin(); floor_body(PHYS_STATIC);
    int id = block(PHYS_DYNAMIC,0,290,20,20,0,wood);
    phys_body *b = &world.bodies[id];
    int asleep = 0;
    double drift = 0;
    for (int i=0; i<600; ++i) {
        phys_step(&world);
        if (!b->awake && !asleep) asleep = i+1;
        drift = fmax(drift,hypot(real(b->position.x),real(b->position.y)-290));
    }
    printf("rest drift=%.4f sleep=%.3fs\n",drift,asleep/60.0);
    require(drift<0.5,"rest drift",drift,0.5);
    require(asleep && asleep<=120,"rest sleep",asleep,120);
    require(!b->moved,"sleep redraw",b->moved,0);
    require(!b->max_normal_impulse,"sleep impact",real(b->max_normal_impulse),0);
    phys_grab_create(&world,id,b->position);
    require(b->awake,"grab wakes sleeping body",b->awake,1);
    phys_grab_release(&world);
    steps(60);
    block(PHYS_DYNAMIC,0,240,20,20,0,wood);
    int woke = 0;
    for (int i=0; i<60; ++i) { phys_step(&world); if (b->awake) woke = 1; }
    require(woke,"collision wakes sleeping body",woke,1);
}
static void stack_test(void)
{
    begin(); floor_body(PHYS_STATIC);
    int ids[10];
    for (int i=0; i<10; ++i) ids[i]=block(PHYS_DYNAMIC,0,290-i*20,20,20,0,wood);
    double drift = 0;
    for (int i=0; i<600; ++i) {
        phys_step(&world);
        phys_body *b=&world.bodies[ids[9]];
        drift=fmax(drift,hypot(real(b->position.x),real(b->position.y)-110));
        for (int j=0; j<10; ++j) {
            if (fabs(real(world.bodies[ids[j]].angle))>=0.1)
                fprintf(stderr,"step=%d block=%d x=%.4f y=%.4f\n",i,j,
                    real(world.bodies[ids[j]].position.x),real(world.bodies[ids[j]].position.y));
            require(fabs(real(world.bodies[ids[j]].angle))<0.1,"stack angle",
                real(world.bodies[ids[j]].angle),0.1);
        }
    }
    printf("stack top drift=%.4f\n",drift);
    require(drift<2,"stack drift",drift,2);
}
static void plank_test(void)
{
    begin(); floor_body(PHYS_STATIC);
    int id=block(PHYS_DYNAMIC,0,257,100,12,F(1.0),wood);
    steps(600);
    double angle=real(world.bodies[id].angle);
    double error=fmin(fabs(angle),fabs(fabs(angle)-3.141592653589793));
    printf("plank final angle=%.3fdeg\n",angle*180/3.141592653589793);
    require(error<3.141592653589793/180,"plank flat",error,0.017454);
}
static void slope_test(void)
{
    double movement[2];
    for (int ice=0; ice<2; ++ice) {
        begin();
        phys_q angle=F(20*3.141592653589793/180);
        block(PHYS_STATIC,0,250,600,20,angle,(phys_material){1,52429,0});
        phys_material material=wood;
        if (ice) material.friction=F(0.01);
        int id=block(PHYS_DYNAMIC,7,231,20,20,angle,material);
        double start=real(world.bodies[id].position.x);
        steps(180);
        movement[ice]=real(world.bodies[id].position.x)-start;
    }
    printf("slope wood=%.3f ice=%.3fpx\n",movement[0],movement[1]);
    require(fabs(movement[0])<1,"wood slope",movement[0],1);
    require(movement[1]>30,"ice slope",movement[1],30);
}
static double drop(int height, phys_material material, double *impact)
{
    begin(); floor_body(PHYS_STATIC);
    int id=block(PHYS_DYNAMIC,0,290-height,20,20,0,material);
    phys_body *b=&world.bodies[id];
    int hit=0;
    double bounce=0;
    *impact=0;
    for (int i=0; i<300; ++i) {
        phys_step(&world);
        *impact=fmax(*impact,real(b->max_normal_impulse));
        if (real(b->max_normal_impulse)>1) hit=1;
        if (hit) bounce=fmax(bounce,290-real(b->position.y));
    }
    return bounce;
}
static void drop_test(void)
{
    double iw, ir, low, high;
    double wooden=drop(100,wood,&iw);
    phys_material rubber=wood; rubber.restitution=F(0.85);
    double bouncing=drop(100,rubber,&ir);
    drop(50,wood,&low); drop(500,wood,&high);
    printf("bounce wood=%.3f rubber=%.3f; impact 5cm=%.3f 50cm=%.3f\n",
        wooden,bouncing,low,high);
    require(bouncing>3*wooden,"rubber bounce",bouncing,3*wooden);
    require(high>2*low,"height impulse distinction",high,2*low);
}
static void grab_test(void)
{
    begin();
    int id=block(PHYS_DYNAMIC,0,0,20,20,0,wood);
    phys_grab_create(&world,id,(phys_vec){Q(6),0});
    phys_grab_move(&world,(phys_vec){Q(106),Q(50)});
    steps(60);
    phys_body *b=&world.bodies[id];
    double distance=hypot(real(b->position.x)+6-106,real(b->position.y)-50);
    printf("grab target error=%.3fpx\n",distance);
    require(distance<5,"grab target",distance,5);
    phys_grab_rotate(&world,PHYS_PI/2);
    steps(30);
    double angle_error=fabs(real(b->angle)-3.141592653589793/2)*180/3.141592653589793;
    printf("grab angle error=%.3fdeg\n",angle_error);
    require(angle_error<2,"grab rotation",angle_error,2);
    phys_grab_release(&world);
}
static void earthquake_test(void)
{
    double displacement[2];
    for (int wide=0; wide<2; ++wide) {
        begin(); int platform=floor_body(PHYS_KINEMATIC);
        world.bodies[platform].material.friction=F(0.1);
        int columns=wide ? 4 : 1;
        int rows=wide ? 2 : 8;
        int ids[8];
        for (int row=0; row<rows; ++row) for (int col=0; col<columns; ++col)
            ids[row*columns+col]=block(PHYS_DYNAMIC,(2*col-columns+1)*10,
                290-row*20,20,20,0,wood);
        steps(120);
        require(!world.bodies[ids[0]].awake,"platform tower sleeping",1,0);
        for (int i=0; i<300; ++i) {
            /* Exact samples of ±20px, 2Hz sine; prescribed interval velocity. */
            double next=20*sin(2*3.141592653589793*2*(i+1)/60);
            double current=20*sin(2*3.141592653589793*2*i/60);
            world.bodies[platform].velocity.x=F((next-current)*60);
            phys_step(&world);
            if (i==0) require(world.bodies[ids[0]].awake,"platform wake",0,1);
        }
        world.bodies[platform].velocity.x=0;
        steps(120);
        displacement[wide]=real(world.bodies[ids[7]].position.y)-(290-(rows-1)*20);
        if (wide) for (int j=0; j<8; ++j) {
            double angle=fabs(real(world.bodies[ids[j]].angle));
            require(angle<0.15,"wide tower upright",angle,0.15);
        }
    }
    printf("earthquake top fall tall=%.3f wide=%.3fpx\n",displacement[0],displacement[1]);
    require(displacement[0]>60,"tall tower collapse",displacement[0],60);
    require(fabs(displacement[1])<2,"wide tower stable",displacement[1],2);
}
static void arch_test(void)
{
    begin(); floor_body(PHYS_STATIC);
    block(PHYS_DYNAMIC,-40,270,20,60,0,wood);
    block(PHYS_DYNAMIC,40,270,20,60,0,wood);
    phys_body_def d={.type=PHYS_DYNAMIC,.position={0,Q(240)},.material=wood,.part_count=4};
    /* Four annular sectors, outer radius 50, inner radius 35, upper semicircle. */
    for (int i=0; i<4; ++i) {
        double a=3.141592653589793+i*3.141592653589793/4;
        double b=a+3.141592653589793/4;
        d.parts[i]=(phys_shape){.type=PHYS_POLYGON,.count=4};
        d.parts[i].vertices[0]=(phys_vec){F(50*cos(a)),F(50*sin(a))};
        d.parts[i].vertices[1]=(phys_vec){F(50*cos(b)),F(50*sin(b))};
        d.parts[i].vertices[2]=(phys_vec){F(35*cos(b)),F(35*sin(b))};
        d.parts[i].vertices[3]=(phys_vec){F(35*cos(a)),F(35*sin(a))};
    }
    int id=phys_body_add(&world,&d);
    phys_vec start=world.bodies[id].position;
    steps(600);
    phys_body *b=&world.bodies[id];
    double drift=hypot(real(b->position.x-start.x),real(b->position.y-start.y));
    printf("arch drift=%.4f angle=%.4fdeg\n",drift,real(b->angle)*180/3.141592653589793);
    require(drift<1,"arch stable",drift,1);
    require(fabs(real(b->angle))<0.02,"arch upright",real(b->angle),0.02);
    /* Both arch feet contact one platform: reduce contacts across all parts. */
    begin(); floor_body(PHYS_STATIC);
    d.position.y=Q(300);
    id=phys_body_add(&world,&d);
    start=world.bodies[id].position;
    steps(600);
    b=&world.bodies[id];
    drift=hypot(real(b->position.x-start.x),real(b->position.y-start.y));
    require(drift<1,"compound platform support",drift,1);
    require(fabs(real(b->angle))<0.02,"compound platform angle",real(b->angle),0.02);
}
static phys_world repeat;
static void determinism_test(void)
{
    for (int run=0; run<2; ++run) {
        begin(); floor_body(PHYS_STATIC);
        for (int i=0; i<8; ++i)
            block(PHYS_DYNAMIC,(i%2)*3,270-23*i,20,20,F(i*0.07),wood);
        steps(600);
        if (!run) repeat=world;
        else require(!memcmp(&repeat,&world,sizeof(world)),"determinism",1,0);
    }
    puts("determinism: all world state bytes identical");
}
static void circle_test(void)
{
    begin(); floor_body(PHYS_STATIC);
    phys_body_def d={.type=PHYS_DYNAMIC,.position={0,Q(250)},.material=wood,.part_count=1};
    d.parts[0]=(phys_shape){.type=PHYS_CIRCLE,.radius=Q(10)};
    int lower=phys_body_add(&world,&d);
    d.position.y=Q(220);
    int upper=phys_body_add(&world,&d);
    steps(180);
    require(fabs(real(world.bodies[lower].position.y)-290)<0.5,"circle floor",
        real(world.bodies[lower].position.y),290);
    require(fabs(real(world.bodies[upper].position.y)-270)<0.5,"circle contact",
        real(world.bodies[upper].position.y),270);
    phys_body_remove(&world,upper);
    require(!world.bodies[upper].used,"remove",1,0);
    phys_world_clear(&world);
    require(!world.bodies[lower].used,"clear",1,0);
}
int main(void)
{
    rest_test(); stack_test(); plank_test(); slope_test(); drop_test(); grab_test();
    earthquake_test(); arch_test(); circle_test(); determinism_test();
    puts("PASS phys: all acceptance scenarios");
    return 0;
}
#endif
