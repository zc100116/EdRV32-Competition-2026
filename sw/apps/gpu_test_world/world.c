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
static int player_x,player_z,camera_x,camera_z,camera_y,camera_pitch;
static int fog_r,fog_g,fog_b,light;
static unsigned craft_transform,terrain_plain,crown_sides=6;
static unsigned picked[24];
unsigned world_lod,world_time;
int world_light_y,world_light_z;
unsigned world_light_dir,world_light_ambient;
static const int landmark[3][2]={{1000,1070},{865,1150},{720,980}};
static const char *names[3]={"发现：风页塔","发现：折光庭","发现：云轮风车"};
static int sn(unsigned a){return test_sine[a&255];}
static int cs(unsigned a){return sn(a+64);}
static unsigned random_at(unsigned x,unsigned z)
{
    unsigned n=x*374761393u+z*668265263u+0x264b42u;
    n=(n^(n>>13))*1274126177u;return n^(n>>16);
}
static int seed_x(unsigned i){return 850+(int)i*8+sn(i*13)*55/16384;}
static int seed_z(unsigned i){return 840+(int)i*15;}
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
    int ridge=120-abs(x-1140)/3-abs(z-1310)/2;
    if(ridge<0)ridge=0;
    int h=60+noise(x,z,256)/2+noise(x,z,64)/8-radius+ridge;
    int bay=150-abs(x-560)/3-abs(z-1080)/3;
    if(bay>0)h-=bay;
    return h<0?0:h;
}
static int altitude(int x,int z)
{
    int h=height(x,z);
    return h<16?16:h;
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
    *vx=tx;*vy=(dy*cs((unsigned)camera_pitch)+tz*sn((unsigned)camera_pitch))/16384;
    *vz=(tz*cs((unsigned)camera_pitch)-dy*sn((unsigned)camera_pitch))/16384;
}
static unsigned color(unsigned rgb,int distance)
{
    int f=(distance-140)*256/((test.mode?384+(int)(test.level%3)*192:512)-140);
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
                     unsigned rgb)
{
    /* CPU directional facet light uses the actual height gradients. */
    int nx=(by-ay)*(cz-az)-(bz-az)*(cy-ay);
    int ny=(bz-az)*(cx-ax)-(bx-ax)*(cz-az);
    int nz=(bx-ax)*(cy-ay)-(by-ay)*(cx-ax);
    if(ny<0){nx=-nx;ny=-ny;nz=-nz;}
    int shade=175+(ny*70-nx*55-nz*40)/(abs(nx)+abs(ny)+abs(nz));
    if(!world_lod)rgb=test_color(((rgb>>11)&31)*8*(unsigned)shade/255,
        ((rgb>>5)&63)*4*(unsigned)shade/255,(rgb&31)*8*(unsigned)shade/255);
    int ox=ax<bx?ax:bx,oz=az<bz?az:bz;
    if(cx<ox)ox=cx;
    if(cz<oz)oz=cz;
    ox=ox/16*16;oz=oz/16*16;
    vertex(ax,ay,az,rgb,terrain_plain?256:(unsigned)(ax-ox)*1024,
           terrain_plain?256:(unsigned)(az-oz)*1024);
    vertex(bx,by,bz,rgb,terrain_plain?256:(unsigned)(bx-ox)*1024,
           terrain_plain?256:(unsigned)(bz-oz)*1024);
    vertex(cx,cy,cz,rgb,terrain_plain?256:(unsigned)(cx-ox)*1024,
           terrain_plain?256:(unsigned)(cz-oz)*1024);
}
static void flat_triangle(int ax,int ay,int az,int bx,int by,int bz,int cx,int cy,int cz,
                          unsigned rgb)
{
    vertex(ax,ay,az,rgb,((unsigned)(ax+az)*512)&16383,((unsigned)ay*512)&16383);
    vertex(bx,by,bz,rgb,((unsigned)(bx+bz)*512)&16383,((unsigned)by*512)&16383);
    vertex(cx,cy,cz,rgb,((unsigned)(cx+cz)*512)&16383,((unsigned)cy*512)&16383);
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
            i<8?(i%4<2?rgb:(rgb&0xf7de)>>1):rgb,
            (unsigned)(p[k][0]+p[k][2]+2)*12*256,(unsigned)(p[k][1]*36+4)*256);
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
/* Six-sided bevelled polyhedron: broad top and fractured sides, no cone apex. */
static unsigned shade_rgb(unsigned rgb,unsigned n,unsigned d)
{
    return test_color(((rgb>>11)&31)*8*n/d,((rgb>>5)&63)*4*n/d,(rgb&31)*8*n/d);
}
static void boulder(int x,int y,int z,int r,int h,unsigned rgb)
{
    for(unsigned a=0;a<6;++a){
        unsigned a0=a*256/6,a1=(a+1)*256/6;
        int x0=x+cs(a0)*r/16384,z0=z+sn(a0)*r/16384;
        int x1=x+cs(a1)*r/16384,z1=z+sn(a1)*r/16384;
        int tx0=x+(x0-x)*2/3,tz0=z+(z0-z)*2/3;
        int tx1=x+(x1-x)*2/3,tz1=z+(z1-z)*2/3;
        unsigned face=a<3?rgb:shade_rgb(rgb,3,4);
        flat_triangle(x0,y,z0,x1,y,z1,tx1,y+h,tz1,face);
        flat_triangle(x0,y,z0,tx1,y+h,tz1,tx0,y+h,tz0,face);
        flat_triangle(tx0,y+h,tz0,tx1,y+h,tz1,x,y+h+1,z,rgb);
    }
}
static void crown(int x,int y,int z,int r,int h,unsigned rgb)
{
    for(unsigned a=0;a<crown_sides;++a){
        unsigned a0=a*256/crown_sides,a1=(a+1)*256/crown_sides;
        int x0=cs(a0)*r/16384,z0=sn(a0)*r/16384;
        int x1=cs(a1)*r/16384,z1=sn(a1)*r/16384;
        unsigned face=a<2?rgb:a<4?shade_rgb(rgb,3,4):(rgb&0xf7de)>>1;
        flat_triangle(x+x0*2/3,y,z+z0*2/3,x+x1*2/3,y,z+z1*2/3,
                      x+x1,y+h/2,z+z1,face);
        flat_triangle(x+x0*2/3,y,z+z0*2/3,x+x1,y+h/2,z+z1,
                      x+x0,y+h/2,z+z0,face);
        flat_triangle(x+x0,y+h/2,z+z0,x+x1,y+h/2,z+z1,
                      x+x1/3,y+h,z+z1/3,rgb);
        flat_triangle(x+x0,y+h/2,z+z0,x+x1/3,y+h,z+z1/3,
                      x+x0/3,y+h,z+z0/3,rgb);
        flat_triangle(x+x0/3,y+h,z+z0/3,x+x1/3,y+h,z+z1/3,x,y+h,z,rgb);
    }
    /* Close the underside; 6*N-2 triangles also keeps DRAW_TRI batches 32B aligned. */
    for(unsigned a=1;a+1<crown_sides;++a){
        unsigned a0=a*256/crown_sides,a1=(a+1)*256/crown_sides;
        flat_triangle(x+r*2/3,y,z,x+cs(a0)*r*2/(16384*3),y,
            z+sn(a0)*r*2/(16384*3),x+cs(a1)*r*2/(16384*3),y,
            z+sn(a1)*r*2/(16384*3),(rgb&0xf7de)>>1);
    }

}
static void sky_triangle(int x0,int y0,int x1,int y1,int x2,int y2,unsigned rgb)
{
    test_vertex(x0,y0,0,rgb,256,256,0);test_vertex(x1,y1,0,rgb,256,256,0);
    test_vertex(x2,y2,0,rgb,256,256,0);
}
static void sky(void)
{
    unsigned first=test.triangles;
    for(int y=0;y<360;y+=12) {
        unsigned rgb=test_color((unsigned)(fog_r+y/10),(unsigned)(fog_g+y/9),(unsigned)fog_b);
        sky_triangle(0,y,640,y,640,y+12,rgb);
        sky_triangle(0,y,640,y+12,0,y+12,rgb);
    }
    /* Layered distant snowy ridges turn with camera yaw, immersed in sky fog. */
    for(unsigned layer=0;layer<2;++layer)for(int i=-1;i<10;++i){
        int x=i*91-(int)(yaw*2%91),base=172+(int)layer*15;
        int peak=base-35-(int)(random_at((unsigned)(i+2),layer)&31);
        unsigned rgb=test_color((unsigned)(fog_r+20-layer*8),
            (unsigned)(fog_g+13-layer*10),(unsigned)(fog_b+8-layer*14));
        sky_triangle(x-15,base,x+47,peak,x+110,base,rgb);
        unsigned snow=test_color((unsigned)(fog_r+72),(unsigned)(fog_g+61),235);
        sky_triangle(x+28,peak+17,x+47,peak,x+67,peak+19,snow);
        sky_triangle(x+47,peak,x+110,base,x+64,base,
                     test_color((unsigned)(fog_r+3),(unsigned)fog_g,(unsigned)(fog_b+4)));
    }
    test_draw(1,first,(test.triangles-first)/3,0,0,0);
    first=test.triangles;
    for(unsigned i=0;i<7;++i){
        int x=(int)((i*123+test.tick/12)%820)-100,y=28+(int)(i%3)*26;
        test_sprite(x,y,122,35,0,160,96,32);
    }
    test_draw(1,first,(test.triangles-first)/3,6,1,0);
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
        int lod=d<112*112?0:d<300*300?1:2;
        visible[visible_count++]=(struct chunk){x,z,lod};
    }
}
static unsigned material(int h0,int h1,int h2,int h3,int step)
{
    int h=(h0+h1+h2+h3)/4;
    if(h<27)return 1;
    if(h>165)return 3;
    if(abs(h0-h1)+abs(h0-h2)>step || h>130)return 2;
    return 0;
}
static void terrain(void)
{
    static const unsigned lodcolor[3]={0x3fff,0xffa5,0xbb5f};
    for(unsigned pass=0;pass<8;++pass) {
        unsigned mat=pass%4,far=pass>=4;
        terrain_plain=world_lod||far;
        static const unsigned distant[4]={0x4530,0xe62d,0x9499,0xe75e};
        unsigned first=test.triangles;
        for(unsigned k=0;k<visible_count;++k) {
            struct chunk *c=&visible[k];int step=4<<c->lod;
            if((c->lod==2)!=(far!=0))continue;
            for(int j=0;j<64;j+=step)for(int i=0;i<64;i+=step) {
                int x=c->x*64+i,z=c->z*64+j;
                int a=sample(x,z),b=sample(x+step,z),d=sample(x,z+step),e=sample(x+step,z+step);
                if(material(a,b,d,e,step)!=mat)continue;
                unsigned rgb=world_lod?lodcolor[c->lod]:far?distant[mat]:0xffff;
                triangle(x,a,z,x+step,b,z,x+step,e,z+step,rgb);
                triangle(x,a,z,x+step,e,z+step,x,d,z+step,rgb);
                if(i==0) {
                    triangle(x,a,z,x,d,z+step,x,d-8,z+step,rgb);
                    triangle(x,a,z,x,d-8,z+step,x,a-8,z,rgb);
                }
                if(j==0) {
                    triangle(x,a,z,x+step,b,z,x+step,b-8,z,rgb);
                    triangle(x,a,z,x+step,b-8,z,x,a-8,z,rgb);
                }
                if(i+step==64) {
                    triangle(x+step,b,z,x+step,b-8,z,x+step,e-8,z+step,rgb);
                    triangle(x+step,b,z,x+step,e-8,z+step,x+step,e,z+step,rgb);
                }
                if(j+step==64) {
                    triangle(x,d,z+step,x+step,e,z+step,x+step,e-8,z+step,rgb);
                    triangle(x,d,z+step,x+step,e-8,z+step,x,d-8,z+step,rgb);
                }
            }
        }
        test_draw(1,first,(test.triangles-first)/3,world_lod||far?0:mat+1,0,1);
    }
}
static void shore_edge(int ax,int az,int ah,int bx,int bz,int bh,int cx,int cz,int ch)
{
    int x[3]={ax,bx,cx},z[3]={az,bz,cz},h[3]={ah,bh,ch},ex[2],ez[2];
    unsigned n=0;
    for(unsigned i=0;i<3;++i){
        unsigned j=(i+1)%3;
        if((h[i]<16)==(h[j]<16))continue;
        ex[n]=x[i]+(x[j]-x[i])*(16-h[i])/(h[j]-h[i]);
        ez[n]=z[i]+(z[j]-z[i])*(16-h[i])/(h[j]-h[i]);++n;
    }
    if(n!=2)return;
    int dx=ex[1]-ex[0],dz=ez[1]-ez[0];
    int ox=dz>0?1:dz<0?-1:0,oz=dx>0?-1:dx<0?1:0;
    const unsigned order[6]={0,1,2,0,2,3};
    int xx[4]={ex[0]-ox,ex[1]-ox,ex[1]+ox,ex[0]+ox};
    int zz[4]={ez[0]-oz,ez[1]-oz,ez[1]+oz,ez[0]+oz};
    for(unsigned j=0;j<6;++j)vertex(xx[order[j]],17,zz[order[j]],0xdfff,236*256,100*256);
}
static void objects(void)
{
    unsigned first=test.triangles;
    for(unsigned k=0;k<visible_count;++k) {
        struct chunk *c=&visible[k];
        unsigned n=test.mode?2+(test.level%3)*2:2;
        if(c->lod==2)n=1;
        crown_sides=c->lod==0?6:c->lod==1?4:3;
        for(unsigned j=0;j<n;++j) {
            unsigned r=random_at((unsigned)c->x*17+j,(unsigned)c->z*13+j);
            int x=c->x*64+(int)(r%56)+4,z=c->z*64+(int)((r>>8)%56)+4,y=height(x,z);
            if(y<30||y>165)continue;
            /* Leave the winding seed promenade and launch clearing open. */
            if(z>=800&&z<1200&&abs(x-seed_x((unsigned)(z-800)/15))<22)continue;
            if(abs(x-850)+abs(z-820)<32)continue;
            if(r&1) {
                box(x,y,z,1,9,1,0x6248);
                if(r%3==0)crown(x,y+7,z,7,10,0x76ce);
                else if(r%3==1)crown(x,y+7,z,6,15,0x3594);
                else {crown(x-2,y+7,z,6,8,0x56d0);crown(x+2,y+12,z,4,7,0x86d0);}
            } else boulder(x,y,z,4+(int)(r%4),3+(int)(r%5),0xb51b);
        }
    }
    crown_sides=6;
    for(unsigned i=0;i<3;++i) {
        int x=landmark[i][0],z=landmark[i][1],y=height(x,z);
        if(i==0) {
            box(x,y,z,13,4,13,0x73b1);box(x,y+4,z,10,3,10,0xb51b);
            box(x-7,y+7,z,2,67,2,0xfbae);box(x+7,y+7,z,2,67,2,0xfbae);
            box(x,y+7,z,2,87,2,0xfda6);
            for(int j=0;j<4;++j){
                int yy=y+15+j*14,dir=j&1?1:-1;
                flat_triangle(x-9,yy,z-3,x+9,yy+12,z-3,x+9,yy+17,z-3,0xfda6);
                flat_triangle(x-9,yy,z-3,x+9,yy+17,z-3,x-9,yy+5,z-3,0xfda6);
                box(x+dir*18,yy+16,z,13,9,1,0xff2b);
                box(x+dir*18,yy+18,z-2,10,2,1,0xffd7);
            }
            gem(x,y+63,z-5,5,0x3fff);
        } else if(i==1) {
            for(int j=0;j<3;++j){
                box(x-14,y+j*8,z,4,7,5,0x9497);
                box(x+14,y+j*8,z,4,7,5,0xb51b);
            }
            box(x-10,y+24,z,5,6,5,0xd594);box(x+10,y+24,z,5,6,5,0xb51b);
            box(x,y+28,z,7,5,5,0xd594);box(x,y,z+10,23,2,17,0x9497);
            boulder(x+24,y,z-8,6,5,0xb51b);
        } else {
            box(x,y,z,10,16,10,0x9497);y+=16;
            box(x,y,z,8,4,8,0xd594);box(x,y+4,z,5,48,5,0xffd7);
            crown(x,y+50,z,8,9,0xe3ad);
            for(unsigned j=0;j<4;++j) {
                unsigned a=test.tick+j*64;
                int ax=cs(a)*29/16384,ay=sn(a)*29/16384;
                int bx=cs(a+12)*26/16384,by=sn(a+12)*26/16384;
                flat_triangle(x,y+49,z-7,x+ax,y+49+ay,z-7,
                              x+bx,y+49+by,z-7,0xffac);
                flat_triangle(x+cs(a)*7/16384,y+49+sn(a)*7/16384,z-7,
                              x+bx,y+49+by,z-7,x,y+49,z-7,0xffd7);
            }
            gem(x,y+49,z-8,3,0xfbae);
        }
    }
    test_draw(1,first,(test.triangles-first)/3,5,0,1);
    first=test.triangles;
    for(unsigned i=0;i<24;++i)if(!picked[i]) {
        int x=seed_x(i),z=seed_z(i);
        gem(x,height(x,z)+7+sn(test.tick+i*21)/8192,z,3,0x3fff);
    }
    /* Craft geometry faces travel heading; camera yaw follows it. */
    int x=player_x/256,z=player_z/256,y=altitude(x,z)+5;
    craft_transform=1;
    /* 184 triangles: framed hull, canopy, wings, skids and dual engines. */
    box(x,y-2,z,7,3,9,0x1085);box(x,y,z,6,3,8,0xffff);
    box(x,y+3,z+2,4,4,5,0x1085);box(x,y+4,z+2,3,4,4,0x6f7f);
    box(x,y+3,z-4,1,1,5,0x3fff);
    for(int side=-1;side<=1;side+=2){
        box(x+side*7,y-1,z-1,2,2,7,0x1085);
        box(x+side*7,y+1,z-1,2,1,6,0x3fff);
        box(x+side*5,y-2,z-8,2,4,2,0x1085);
        box(x+side*5,y-1,z-10,1,2,1,0xfd29);
        flat_triangle(x+side*6,y+2,z+5,x+side*12,y,z-5,x+side*6,y,z-7,0x3fff);
        flat_triangle(x+side*6,y+2,z+5,x+side*6,y,z-7,x+side*6,y-1,z+5,0xffff);
    }
    box(x+4,y+6,z+3,1,5,1,0x1085);box(x+4,y+10,z+3,1,2,1,0x3fff);
    if(burst_tick)for(unsigned j=0;j<12;++j)
        gem(x+cs(j*21)*((int)(25-burst_tick))/16384,y+4,
            z+sn(j*21)*((int)(25-burst_tick))/16384,1,0xffa5);
    craft_transform=0;
    test_draw(1,first,(test.triangles-first)/3,5,0,1);
    first=test.triangles;
    /* Small water cells follow the shore; colour and alpha come from I8 samples. */
    for(unsigned k=0;k<visible_count;++k){
        struct chunk *c=&visible[k];
        for(int j=0;j<64;j+=16)for(int i=0;i<64;i+=16){
            int wx=c->x*64+i,wz=c->z*64+j;
            int h=height(wx+8,wz+8);
            if(h>20)continue;
            unsigned rgb=h<10?test_color(28,148,158):test_color(64,185,175);
            const int v[6][2]={{0,0},{16,0},{16,16},{0,0},{16,16},{0,16}};
            for(unsigned n=0;n<6;++n)
                vertex(wx+v[n][0],16,wz+v[n][1],rgb,244*256,100*256);
        }
    }
    for(unsigned k=0;k<visible_count;++k){
        struct chunk *c=&visible[k];
        if(c->lod==2)continue;
        for(int j=0;j<64;j+=8)for(int i=0;i<64;i+=8){
            int x=c->x*64+i,z=c->z*64+j;
            int a=height(x,z),b=height(x+8,z),d=height(x,z+8),e=height(x+8,z+8);
            shore_edge(x,z,a,x+8,z,b,x+8,z+8,e);
            shore_edge(x,z,a,x+8,z+8,e,x,z+8,d);
        }
    }
    test_draw(1,first,(test.triangles-first)/3,6,1,1);
}
static void glow(int x,int y,int z,int r,unsigned rgb)
{
    static const int corners[6][2]={{-1,-1},{1,-1},{1,1},{-1,-1},{1,1},{-1,1}};
    for(unsigned j=0;j<6;++j){
        int side=corners[j][0],up=corners[j][1];
        vertex(x+side*cs(yaw)*r/16384,y+up*r,z-side*sn(yaw)*r/16384,
               rgb,(unsigned)(side>0?48:16)*256,(unsigned)(up>0?96:128)*256);
    }
}
static void glows(void)
{
    unsigned first=test.triangles;
    for(unsigned i=0;i<24;++i)if(!picked[i]){
        int x=seed_x(i),z=seed_z(i);
        int y=height(x,z)+8+sn(test.tick+i*21)/8192;
        glow(x,y,z,6,0x3db4);
    }
    int x=player_x/256,z=player_z/256,y=altitude(x,z)+5;
    craft_transform=1;
    for(int side=-1;side<=1;side+=2)glow(x+side*5,y-1,z-11,5,0xfd29);
    craft_transform=0;
    test_draw(1,first,(test.triangles-first)/3,6,2,1);
}
void world_init(void)
{
    memcpy(test.textures+TEST_MIP_BASE,world_materials,sizeof(world_materials));
    memcpy(test.textures+65536,world_effects,sizeof(world_effects));
    test.palettes[105]=0xaffff;test.palettes[106]=0xdffff;
    player_x=850*256;player_z=820*256;yaw=heading=0;
    stopped=collected=discovered=toast=press_time=burst_tick=0;
    world_lod=world_time=0;previous=0;generated=81;replacing=0;
    memset(picked,0,sizeof(picked));test.objects_count=0;test.health=100;
    memset(cache_lookup,0,sizeof(cache_lookup));
    for(int j=0;j<9;++j)for(int i=0;i<9;++i){
        generate(&cache[j*9+i],9+i,8+j);cache_lookup[(8+j)*32+9+i]=(unsigned)(j*9+i+1);
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
    camera_x=player_x/256-sn(yaw)*42/16384;
    camera_z=player_z/256-cs(yaw)*42/16384;
    int base_y=altitude(player_x/256,player_z/256)+28;
    camera_y=altitude(camera_x,camera_z)+12;
    if(camera_y<base_y)camera_y=base_y;
    camera_pitch=10+(camera_y-base_y)*256/(6*42);
    unsigned time=(world_time?world_time==1?0:world_time==2?80:150:test.tick*256/10800)&255;
    int sun=cs(time);light=160+sun/200;if(light<80)light=80;
    fog_r=85+sun/800;fog_g=112+sun/600;fog_b=205+sun/800;
    if(time>55&&time<115){fog_r+=70;fog_g-=15;}
    world_light_y=cs(time);world_light_z=sn(time);
    world_light_dir=0x181818;world_light_ambient=0xe7e7e7;
    if(toast)--toast;
    if(burst_tick)--burst_tick;
    for(unsigned i=0;i<24;++i)if(!picked[i]) {
        int x=seed_x(i),z=seed_z(i);
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
    sky();terrain();objects();glows();
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
    if(event==1){world_time=1;player_x=850*256;player_z=820*256;heading=yaw=0;}
    if(event==2){world_time=2;player_x=850*256;player_z=820*256;heading=yaw=0;}
    if(event==3){world_time=1;player_x=580*256;player_z=850*256;heading=yaw=0;}
    if(event==4){world_time=1;player_x=950*256;player_z=920*256;heading=yaw=0;}
    if(event==5)world_lod=1;
    stopped=1;
}
