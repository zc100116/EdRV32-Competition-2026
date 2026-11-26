/* world.c — G-4; seeded island chunks, CPU frustum culling, three LODs and exploration.
 * CPU/host frame thread; GPU transforms camera-space vertices and rasterizes terrain.
 */
#include "demo.h"
#include "world_assets.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct chunk { int x,z,lod; };
struct height_block { int x,z; int16_t h[289]; };
static struct height_block cache[81];
static unsigned cache_lookup[1024];
static struct chunk visible[1024];
static unsigned visible_count, collected, discovered, toast, stopped;
static unsigned generated, replacing, yaw, heading, press_time, burst_tick;
static uint32_t previous;
static int player_x,player_z,camera_x,camera_z,camera_y;
static int fog_r,fog_g,fog_b,light;
static unsigned craft_transform;
static unsigned picked[24];
unsigned world_lod,world_time;
int world_light_y,world_light_z;
unsigned world_light_dir,world_light_ambient;
static const int landmark[3][2]={{1180,930},{650,1100},{1420,1370}};
static const char *names[3]={"发现：风页塔","发现：折光庭","发现：云轮风车"};
static int sn(unsigned a){return test_sine[a&255];}
static int cs(unsigned a){return sn(a+64);}
static unsigned random_at(unsigned x,unsigned z)
{
    unsigned n=x*374761393u+z*668265263u+0x264b42u;
    n=(n^(n>>13))*1274126177u;return n^(n>>16);
}
static int noise(int x,int z,int step)
{
    unsigned gx=(unsigned)x/(unsigned)step,gz=(unsigned)z/(unsigned)step;
    int fx=x%step,fz=z%step;
    int a=(int)(random_at(gx,gz)&255),b=(int)(random_at(gx+1,gz)&255);
    int c=(int)(random_at(gx,gz+1)&255),d=(int)(random_at(gx+1,gz+1)&255);
    return ((a*(step-fx)+b*fx)*(step-fz)+(c*(step-fx)+d*fx)*fz)/(step*step);
}
static int height(int x,int z)
{
    int dx=x-1024,dz=z-1024;
    int radius=(dx*dx+dz*dz)/4096;
    int h=60+noise(x,z,256)/2+noise(x,z,64)/8-radius;
    return h<0?0:h;
}
static void generate(struct height_block *b,int x,int z)
{
    b->x=x;b->z=z;
    for(int j=0;j<=16;++j)for(int i=0;i<=16;++i)
        b->h[j*17+i]=(int16_t)height(x*64+i*4,z*64+j*4);
}
static int sample(int x,int z)
{
    if(x==2048||z==2048)return height(x,z);
    unsigned slot=cache_lookup[(unsigned)(z/64)*32+(unsigned)(x/64)];
    if(slot)return cache[slot-1].h[(z%64)/4*17+(x%64)/4];
    return height(x,z);
}
static void view(int x,int y,int z,int *vx,int *vy,int *vz)
{
    int dx=x-camera_x,dz=z-camera_z,dy=y-camera_y;
    int tx=(dx*cs(yaw)-dz*sn(yaw))/16384;
    int tz=(dx*sn(yaw)+dz*cs(yaw))/16384;
    *vx=tx;*vy=(dy*15872+tz*4096)/16384;*vz=(tz*15872-dy*4096)/16384;
}
static unsigned color(unsigned rgb,int distance)
{
    int f=distance*256/(test.mode?384+(int)(test.level%3)*192:512);
    if(f<0)f=0;
    if(f>256)f=256;
    int r=(int)((rgb>>11)&31)*255/31*light/256;
    int g=(int)((rgb>>5)&63)*255/63*light/256;
    int b=(int)(rgb&31)*255/31*light/256;
    return test_color((unsigned)(r*(256-f)+fog_r*f)/256,
                      (unsigned)(g*(256-f)+fog_g*f)/256,
                      (unsigned)(b*(256-f)+fog_b*f)/256);
}
static void vertex(int x,int y,int z,unsigned rgb,unsigned u,unsigned v)
{
    if(craft_transform){
        int dx=x-player_x/256,dz=z-player_z/256;
        x=player_x/256+(dx*cs(heading)+dz*sn(heading))/16384;
        z=player_z/256+(dz*cs(heading)-dx*sn(heading))/16384;
    }
    int vx,vy,vz;view(x,y,z,&vx,&vy,&vz);
    test_vertex(vx,vy,vz,color(rgb,vz),u,v,100);
}
static void triangle(int ax,int ay,int az,int bx,int by,int bz,int cx,int cy,int cz,
                     unsigned rgb,unsigned step)
{
    vertex(ax,ay,az,rgb,0,0);vertex(bx,by,bz,rgb,step*128,0);
    vertex(cx,cy,cz,rgb,step*128,step*128);
}
static void flat_triangle(int ax,int ay,int az,int bx,int by,int bz,int cx,int cy,int cz,
                          unsigned rgb)
{
    vertex(ax,ay,az,rgb,256,256);vertex(bx,by,bz,rgb,256,256);vertex(cx,cy,cz,rgb,256,256);
}
static void box(int x,int y,int z,int w,int h,int d,unsigned rgb)
{
    const int p[8][3]={{-1,0,-1},{1,0,-1},{1,0,1},{-1,0,1},
                        {-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1}};
    static const unsigned faces[12][3]={{0,1,5},{0,5,4},{1,2,6},{1,6,5},
        {2,3,7},{2,7,6},{3,0,4},{3,4,7},{4,5,6},{4,6,7},{0,3,2},{0,2,1}};
    for(unsigned i=0;i<12;++i)for(unsigned j=0;j<3;++j) {
        unsigned k=faces[i][j];
        vertex(x+p[k][0]*w,y+p[k][1]*h,z+p[k][2]*d,
            i<8?(i%4<2?rgb:(rgb&0xf7de)>>1):rgb,256,256);
    }
}
static void gem(int x,int y,int z,int radius,unsigned rgb)
{
    for(unsigned a=0;a<4;++a) {
        int x0=x+cs(a*64)*radius/16384,z0=z+sn(a*64)*radius/16384;
        int x1=x+cs((a+1)*64)*radius/16384,z1=z+sn((a+1)*64)*radius/16384;
        flat_triangle(x0,y,z0,x1,y,z1,x,y+radius*2,z,rgb);
        flat_triangle(x1,y,z1,x0,y,z0,x,y-radius,z,(rgb&0xf7de)>>1);
    }
}
static void sky(void)
{
    unsigned first=test.triangles;
    for(int y=0;y<360;y+=24) {
        unsigned rgb=test_color((unsigned)(fog_r+y/12),(unsigned)(fog_g+y/16),(unsigned)fog_b);
        test_vertex(0,y,0,rgb,256,256,0);test_vertex(640,y,0,rgb,256,256,0);
        test_vertex(640,y+24,0,rgb,256,256,0);test_vertex(0,y,0,rgb,256,256,0);
        test_vertex(640,y+24,0,rgb,256,256,0);test_vertex(0,y+24,0,rgb,256,256,0);
    }
    for(unsigned i=0;i<7;++i) {
        int x=(int)((i*123+test.tick/9)%800)-100,y=35+(int)(i%3)*23;
        unsigned rgb=test_color((unsigned)(fog_r+40),(unsigned)(fog_g+30),220);
        test_vertex(x,y,0,rgb,256,256,0);test_vertex(x+85,y+8,0,rgb,256,256,0);
        test_vertex(x+120,y+20,0,rgb,256,256,0);test_vertex(x,y,0,rgb,256,256,0);
        test_vertex(x+120,y+20,0,rgb,256,256,0);test_vertex(x-20,y+20,0,rgb,256,256,0);
    }
    test_draw(1,first,(test.triangles-first)/3,0,0,0);
}
static void cull(void)
{
    visible_count=0;
    int distance=test.mode?384+(int)(test.level%3)*192:512;
    for(int z=0;z<32;++z)for(int x=0;x<32;++x) {
        int dx=x*64+32-camera_x,dz=z*64+32-camera_z;
        int d=dx*dx+dz*dz;
        if(d>(distance+46)*(distance+46))continue;
        int vx,vy,vz;view(x*64+32,height(x*64+32,z*64+32)/2,z*64+32,&vx,&vy,&vz);
        /* Conservative AABB sphere against near, left, right, top and bottom planes. */
        if(vz < -100 || abs(vx)*3> (vz+160)*4 || abs(vy)*4>(vz+200)*3)continue;
        int lod=d<128*128?0:d<320*320?1:2;
        visible[visible_count++]=(struct chunk){x,z,lod};
    }
}
static unsigned material(int h0,int h1,int h2,int h3)
{
    int h=(h0+h1+h2+h3)/4;
    if(h<27)return 1;
    if(h>146)return 3;
    if(abs(h0-h1)+abs(h0-h2)>20)return 2;
    return 0;
}
static void terrain(void)
{
    static const unsigned lodcolor[3]={0x3fff,0xffa5,0xbb5f};
    for(unsigned mat=0;mat<4;++mat) {
        unsigned first=test.triangles;
        for(unsigned k=0;k<visible_count;++k) {
            struct chunk *c=&visible[k];int step=4<<c->lod;
            for(int j=0;j<64;j+=step)for(int i=0;i<64;i+=step) {
                int x=c->x*64+i,z=c->z*64+j;
                int a=sample(x,z),b=sample(x+step,z),d=sample(x,z+step),e=sample(x+step,z+step);
                if(material(a,b,d,e)!=mat)continue;
                unsigned rgb=world_lod?lodcolor[c->lod]:0xffff;
                triangle(x,a,z,x+step,b,z,x+step,e,z+step,rgb,(unsigned)step);
                triangle(x,a,z,x+step,e,z+step,x,d,z+step,rgb,(unsigned)step);
                if(i==0) {
                    triangle(x,a,z,x,d,z+step,x,d-8,z+step,rgb,(unsigned)step);
                    triangle(x,a,z,x,d-8,z+step,x,a-8,z,rgb,(unsigned)step);
                }
                if(j==0) {
                    triangle(x,a,z,x+step,b,z,x+step,b-8,z,rgb,(unsigned)step);
                    triangle(x,a,z,x+step,b-8,z,x,a-8,z,rgb,(unsigned)step);
                }
                if(i+step==64) {
                    triangle(x+step,b,z,x+step,b-8,z,x+step,e-8,z+step,rgb,(unsigned)step);
                    triangle(x+step,b,z,x+step,e-8,z+step,x+step,e,z+step,rgb,(unsigned)step);
                }
                if(j+step==64) {
                    triangle(x,d,z+step,x+step,e,z+step,x+step,e-8,z+step,rgb,(unsigned)step);
                    triangle(x,d,z+step,x+step,e-8,z+step,x,d-8,z+step,rgb,(unsigned)step);
                }
            }
        }
        test_draw(1,first,(test.triangles-first)/3,world_lod?0:mat+1,0,1);
    }
}
static void objects(void)
{
    unsigned first=test.triangles;
    for(unsigned k=0;k<visible_count;++k) {
        struct chunk *c=&visible[k];
        unsigned n=test.mode?2+(test.level%3)*2:2;
        if(c->lod==2)n/=2;
        for(unsigned j=0;j<n;++j) {
            unsigned r=random_at((unsigned)c->x*17+j,(unsigned)c->z*13+j);
            int x=c->x*64+(int)(r%56)+4,z=c->z*64+(int)((r>>8)%56)+4,y=height(x,z);
            if(y<30||y>165)continue;
            if(r&1) {
                box(x,y,z,1,9,1,0x6248);
                if(r%3==0)box(x,y+7,z,5,8,5,0x3dc9);
                else if(r%3==1)gem(x,y+10,z,5,0x2633);
                else {gem(x,y+9,z,5,0x3dc9);gem(x,y+14,z,3,0x2633);}
            } else gem(x,y+2,z,3+(int)(r%4),0x83b5);
        }
    }
    for(unsigned i=0;i<3;++i) {
        int x=landmark[i][0],z=landmark[i][1],y=height(x,z);
        if(i==0) {
            box(x,y,z,10,6,10,0x73b1);box(x,y+6,z,5,42,5,0xdba9);
            gem(x,y+50,z,9,0x3fff);
            box(x,y+39,z,15,4,4,0xfda6);
        } else if(i==1) {
            box(x-12,y,z,4,22,4,0x9497);box(x+12,y,z,4,22,4,0x9497);
            box(x,y+22,z,16,5,4,0xd594);box(x,y,z+10,20,2,15,0x9497);
        } else {
            box(x,y,z,5,26,5,0xe634);
            for(unsigned j=0;j<4;++j) {
                unsigned a=test.tick/3+j*64;
                flat_triangle(x,y+25,z-6,x+cs(a)*22/16384,y+25+sn(a)*22/16384,z-6,
                              x+cs(a+8)*19/16384,y+25+sn(a+8)*19/16384,z-6,0xffac);
            }
        }
    }
    for(unsigned i=0;i<24;++i)if(!picked[i]) {
        int x=700+(int)(random_at(i,7)%700),z=680+(int)(random_at(i,9)%700);
        gem(x,height(x,z)+7+sn(test.tick+i*21)/8192,z,3,0x3fff);
    }
    /* Craft geometry faces travel heading; camera yaw follows it. */
    int x=player_x/256,z=player_z/256,y=height(x,z)+5;
    craft_transform=1;
    box(x,y-1,z,5,3,6,0x1085);box(x,y,z,4,3,5,0xffff);
    box(x,y+3,z,3,3,3,0x1085);box(x,y+4,z,2,3,2,0x3fff);
    flat_triangle(x-4,y+1,z+3,x-10,y,z-5,x-3,y,z-4,0x3fff);
    flat_triangle(x+4,y+1,z+3,x+10,y,z-5,x+3,y,z-4,0x3fff);
    gem(x-3,y,z-6,1,0xfd29);gem(x+3,y,z-6,1,0xfd29);
    if(burst_tick)for(unsigned j=0;j<12;++j)
        gem(x+cs(j*21)*((int)(25-burst_tick))/16384,y+4,
            z+sn(j*21)*((int)(25-burst_tick))/16384,1,0xffa5);
    craft_transform=0;
    test_draw(1,first,(test.triangles-first)/3,0,0,1);
    first=test.triangles;
    /* Transparent water is drawn last, with depth test on and depth writes off. */
    for(int z=0;z<32;++z)for(int x=0;x<32;++x) {
        int wx=x*64,wz=z*64;
        int dx=wx-camera_x,dz=wz-camera_z;
        if(dx*dx+dz*dz>600*600||height(wx,wz)>26)continue;
        unsigned rgb=height(wx,wz)<12?0x2f7d:0x7fff;
        int v[6][2]={{0,0},{64,0},{64,64},{0,0},{64,64},{0,64}};
        for(unsigned j=0;j<6;++j)vertex(wx+v[j][0],16,wz+v[j][1],rgb,4*256,100*256);
    }
    test_draw(1,first,(test.triangles-first)/3,6,1,1);
}
void world_init(void)
{
    memcpy(test.textures+TEST_MIP_BASE,world_materials,sizeof(world_materials));
    player_x=1000*256;player_z=740*256;yaw=heading=0;
    stopped=collected=discovered=toast=press_time=burst_tick=0;
    world_lod=world_time=0;previous=0;generated=81;replacing=0;
    memset(picked,0,sizeof(picked));test.objects_count=0;test.health=100;
    memset(cache_lookup,0,sizeof(cache_lookup));
    for(int j=0;j<9;++j)for(int i=0;i<9;++i){
        generate(&cache[j*9+i],11+i,7+j);cache_lookup[(7+j)*32+11+i]=(unsigned)(j*9+i+1);
    }
}
void world_update(uint32_t keys)
{
    uint32_t pressed=keys&~previous;previous=keys;
    if(keys&PLAT_LEFT)heading=(heading+254)&255;
    if(keys&PLAT_RIGHT)heading=(heading+2)&255;
    if(keys&PLAT_A)++press_time;
    else {if(press_time&&press_time<30)stopped^=1;press_time=0;}
    if(pressed&PLAT_B)world_lod^=1;
    int speed=keys&PLAT_DOWN?-78:keys&PLAT_UP?115:stopped?0:78;
    player_x+=sn(heading)*speed/16384;player_z+=cs(heading)*speed/16384;
    if(player_x<32*256)player_x=32*256;
    if(player_x>2016*256)player_x=2016*256;
    if(player_z<32*256)player_z=32*256;
    if(player_z>2016*256)player_z=2016*256;
    int diff=((int)heading-(int)yaw+384)%256-128;
    yaw=(unsigned)((int)yaw+diff/4)&255;
    camera_x=player_x/256-sn(yaw)*65/16384;
    camera_z=player_z/256-cs(yaw)*65/16384;
    camera_y=height(player_x/256,player_z/256)+42;
    unsigned time=(world_time?world_time==1?0:world_time==2?80:150:test.tick*256/10800)&255;
    int sun=cs(time);light=160+sun/200;if(light<80)light=80;
    fog_r=85+sun/800;fog_g=112+sun/600;fog_b=205+sun/800;
    if(time>55&&time<115){fog_r+=70;fog_g-=15;}
    world_light_y=cs(time);world_light_z=sn(time);
    world_light_dir=0x303030;world_light_ambient=0xe0e0e0;
    if(toast)--toast;
    if(burst_tick)--burst_tick;
    for(unsigned i=0;i<24;++i)if(!picked[i]) {
        int x=700+(int)(random_at(i,7)%700),z=680+(int)(random_at(i,9)%700);
        int dx=x-player_x/256,dz=z-player_z/256;
        if(dx*dx+dz*dz<12*12){picked[i]=1;++collected;burst_tick=24;test_sound(3);}
    }
    for(unsigned i=0;i<3;++i) {
        int dx=landmark[i][0]-player_x/256,dz=landmark[i][1]-player_z/256;
        if(dx*dx+dz*dz<55*55&&!(discovered&(1u<<i))) {
            discovered|=1u<<i;toast=180;test.score=i;test_sound(3);
        }
        if(dx*dx+dz*dz<14*14){player_x-=sn(heading)*speed/16384;player_z-=cs(heading)*speed/16384;}
    }
    unsigned made=0;
    int bx=player_x/(64*256),bz=player_z/(64*256);
    for(int j=-4;j<=4&&made<2;++j)for(int i=-4;i<=4&&made<2;++i) {
        int x=bx+i,z=bz+j;if(x<0||z<0||x>=32||z>=32)continue;
        unsigned found=0;
        for(unsigned k=0;k<81;++k)found|=cache[k].x==x&&cache[k].z==z;
        if(!found) {
            while(abs(cache[replacing].x-bx)<=4&&abs(cache[replacing].z-bz)<=4)
                replacing=(replacing+1)%81;
            cache_lookup[cache[replacing].z*32+cache[replacing].x]=0;
            generate(&cache[replacing],x,z);cache_lookup[z*32+x]=replacing+1;
            replacing=(replacing+1)%81;++made;++generated;
        }
    }
    cull();
}
void world_scene(void)
{
    sky();terrain();objects();
    unsigned first=test.quads_count;
    char s[96];test_panel(8,8,210,38,2);demo_text(16,10,"云脊漫游",1);
    snprintf(s,sizeof(s),"光种 %02u/24",collected);demo_text(16,28,s,2);
    if(toast){test_panel(8,54,210,28,7);demo_text(18,61,names[test.score],7);}
    if(collected>=12&&discovered==7){test_panel(224,8,178,28,7);demo_text(251,16,"探索完成",7);}
    test_panel(520,8,112,100,2);demo_text(569,12,"N",2);
    for(unsigned i=0;i<3;++i)test_rect(530+(unsigned)landmark[i][0]/24,
                                      22+(unsigned)landmark[i][1]/25,4,4,7);
    test_rect(530+player_x/(256*24),22+player_z/(256*25),4,4,2);
    snprintf(s,sizeof(s),"%u BLK",visible_count);demo_text(534,88,s,1);
    if(world_lod){test_panel(8,90,210,26,2);demo_text(16,96,"LOD0 LOD1 LOD2",2);}
    test_draw(0,first,test.quads_count-first,0,1,0);demo_diagnostics(visible_count);
}
void world_capture(unsigned event)
{
    if(event==1){world_time=1;player_x=850*256;player_z=620*256;heading=yaw=160;}
    if(event==2){world_time=2;player_x=850*256;player_z=620*256;heading=yaw=160;}
    if(event==3){player_x=600*256;player_z=620*256;heading=160;yaw=160;}
    if(event==4){player_x=1180*256;player_z=885*256;heading=yaw=0;}
    if(event==5)world_lod=1;
    stopped=1;
}
