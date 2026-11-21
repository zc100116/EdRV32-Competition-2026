/* workshop.c — block workshop task §§2–6; grid connectivity, tools and scenes.
 * Fixed 60 Hz application clock; no LVGL, floating point or hardware access.
 */
#include "workshop.h"
#include <string.h>
const char *const ws_names[WS_ITEMS] = {
    "空手","稿子","草地","泥土","石头","碎石","沙子","木板","原木","石砖",
    "砖块","金属","冰","玻璃","树叶","灯","窗户","门","木梁","石柱",
    "木斜坡","砖斜坡"};
const char *const ws_scene_names[3] = {"空地","小屋","城堡"};
/* Alpha-weighted RGB means of the original day sprites; tools have no debris. */
const uint32_t ws_colors[WS_ITEMS] = {
    0,0,0xa28561,0xab8262,0x959ca4,0x979591,0xd7c28f,0xbe9769,0xab835d,
    0xa3a9ab,0xc7947e,0xa3b4b4,0xadd3d7,0xb0cfc6,0x87a478,0x94998c,0x95998b,
    0x9e8362,0xbf9767,0xa3aaad,0xb09068,0xb88c7a};
static bool loose(unsigned item) { return item==WS_SAND || item==WS_GRAVEL; }
void workshop_shape(unsigned item,unsigned orientation,int *w,int *h)
{
    *w=*h=1;
    if (item==WS_DOOR) *h=2;
    if (item==WS_BEAM || item==WS_PILLAR) {
        if (orientation) *h=2; else *w=2;
    }
}
unsigned workshop_rotate(unsigned item,unsigned orientation)
{
    if (item==WS_BEAM || item==WS_PILLAR) return orientation^1;
    if (item==WS_WOOD_SLOPE || item==WS_BRICK_SLOPE) return (orientation+1)%4;
    return 0;
}
unsigned workshop_hardness(unsigned item)
{
    if (item==WS_DIRT || item==WS_SAND || item==WS_GRAVEL || item==WS_LEAVES) return 24;
    if (item==WS_METAL) return 120;
    if (item==WS_STONE || item==WS_STONEBRICK || item==WS_BRICK || item==WS_PILLAR ||
        item==WS_BRICK_SLOPE || item==WS_LAMP || item==WS_WINDOW) return 72;
    return 48;
}
static uint32_t random_next(workshop_state *s)
{
    s->random=s->random*1664525u+1013904223u;
    return s->random;
}
static void grid(workshop_state *s)
{
    memset(s->grid,0xff,sizeof s->grid);
    for (int i=0;i<WS_BLOCKS;++i) {
        ws_block *b=&s->blocks[i];
        if (!b->used || b->group || i==s->held) continue;
        int w,h;
        workshop_shape(b->item,b->orientation,&w,&h);
        for (int y=b->y-h+1;y<=b->y;++y)
            for (int x=b->x;x<b->x+w;++x) s->grid[y][x]=(int16_t)i;
    }
}
static int cell(const workshop_state *s,int x,int y)
{
    if (x<0 || x>=WS_COLS || y<0 || y>=WS_ROWS) return -1;
    return s->grid[y][x];
}
bool workshop_fits(const workshop_state *s,unsigned item,unsigned orientation,int x,int y)
{
    int w,h;
    workshop_shape(item,orientation,&w,&h);
    if (x<0 || x+w>WS_COLS || y-h+1<0 || y>=WS_ROWS) return false;
    for (int j=0;j<WS_BLOCKS;++j) {
        const ws_block *b=&s->blocks[j];
        if (!b->used || j==s->held) continue;
        int bw,bh;
        workshop_shape(b->item,b->orientation,&bw,&bh);
        int top=(b->y-bh+1)*96, bottom=(b->y+1)*96;
        if (b->group) { top+=s->falls[b->group-1].offset;
                       bottom+=s->falls[b->group-1].offset; }
        if (x<b->x+bw && x+w>b->x && (y-h+1)*96<bottom && (y+1)*96>top)
            return false;
    }
    return true;
}
static int insert(workshop_state *s,unsigned item,unsigned orientation,int x,int y)
{
    int id=0;
    while (s->blocks[id].used) ++id;
    s->blocks[id]=(ws_block){true,(uint8_t)item,(uint8_t)orientation,
                            (int16_t)x,(int16_t)y,0};
    return id;
}
/* Ground flood excludes sideways support for granular blocks. Each disconnected
 * rigid component gets one motion accumulator, preserving all internal distances.
 */
void workshop_reconnect(workshop_state *s)
{
    grid(s);
    bool fixed[WS_BLOCKS]={false};
    bool changed=true;
    while (changed) {
        changed=false;
        for (int i=0;i<WS_BLOCKS;++i) {
            ws_block *b=&s->blocks[i];
            if (!b->used || b->group || i==s->held || fixed[i]) continue;
            int w,h;
            workshop_shape(b->item,b->orientation,&w,&h);
            bool support=b->y==WS_ROWS-1;
            for (int x=b->x;x<b->x+w;++x) {
                int below=cell(s,x,b->y+1);
                if (below>=0 && fixed[below]) support=true;
                if (!loose(b->item)) {
                    int above=cell(s,x,b->y-h);
                    if (above>=0 && fixed[above]) support=true;
                }
            }
            if (!loose(b->item))
                for (int y=b->y-h+1;y<=b->y;++y) {
                    int l=cell(s,b->x-1,y),r=cell(s,b->x+w,y);
                    if ((l>=0 && fixed[l]) || (r>=0 && fixed[r])) support=true;
                }
            if (support) { fixed[i]=true; changed=true; }
        }
    }
    int queue[WS_BLOCKS];
    for (int i=0;i<WS_BLOCKS;++i) {
        ws_block *first=&s->blocks[i];
        if (!first->used || first->group || i==s->held || fixed[i]) continue;
        int n=1,head=0;
        queue[0]=i;
        first->group=(int16_t)(i+1);
        s->falls[i]=(ws_fall){0,0};
        while (head<n) {
            ws_block *b=&s->blocks[queue[head++]];
            if (loose(b->item)) continue;
            int w,h;
            workshop_shape(b->item,b->orientation,&w,&h);
            for (int y=b->y-h;y<=b->y+1;++y)
                for (int x=b->x-1;x<=b->x+w;++x) {
                    bool edge=(x>=b->x && x<b->x+w) ||
                              (y>=b->y-h+1 && y<=b->y);
                    int id=cell(s,x,y);
                    if (!edge || id<0 || fixed[id] || s->blocks[id].group ||
                        loose(s->blocks[id].item)) continue;
                    s->blocks[id].group=(int16_t)(i+1);
                    queue[n++]=id;
                }
        }
    }
    grid(s);
}
int workshop_add(workshop_state *s,unsigned item,unsigned orientation,int x,int y)
{
    if (!workshop_fits(s,item,orientation,x,y)) return -1;
    int id=insert(s,item,orientation,x,y);
    workshop_reconnect(s);
    return id;
}
void workshop_remove(workshop_state *s,int id)
{
    s->blocks[id].used=false;
    workshop_reconnect(s);
}
static void particle(workshop_state *s,int x,int y,int vx,int vy,int life,
                     unsigned kind,uint32_t color)
{
    unsigned i=0;
    while (s->particles[i].life) ++i;
    s->particles[i]=(ws_particle){x*2,y*2,vx,vy,life,color,(uint8_t)kind};
}
static void frightened(workshop_state *s,int x,int y)
{
    for (unsigned i=0;i<s->animal_count;++i) {
        ws_animal *a=&s->animals[i];
        if (a->action==WS_LIFT) continue;
        if (a->x/2>=x-28 && a->x/2<=x+76 && a->y/2>=y && a->y/2<=y+104) {
            int dir=a->x/2<x+24 ? -1 : 1;
            int nx=a->x/2;
            int cy=(a->y/2-WS_Y-1)/48;
            for (int distance=1;distance<WS_COLS;++distance) {
                bool found=false;
                for (int side=0;side<2;++side) {
                    int candidate=a->x/2+(side ? -dir : dir)*48*distance;
                    int cx=(candidate-WS_X)/48;
                    if (candidate>=WS_X+28 && candidate<=WS_X+WS_COLS*48-28 &&
                        cell(s,cx,cy)<0) {
                        nx=candidate;
                        dir=side ? -dir : dir;
                        found=true;
                        break;
                    }
                }
                if (found) break;
            }
            a->x=nx*2;
            a->direction=dir;
            a->action=WS_RUN;
            a->timer=180;
            a->velocity=-8;
        }
    }
}
static void falling(workshop_state *s)
{
    for (int g=1;g<=WS_BLOCKS;++g) {
        bool used=false,stationary_contact=true;
        int gap=WS_ROWS*96;
        ws_fall *f=&s->falls[g-1];
        for (int i=0;i<WS_BLOCKS;++i) {
            ws_block *b=&s->blocks[i];
            if (!b->used || b->group!=g) continue;
            used=true;
            int w,h;
            workshop_shape(b->item,b->orientation,&w,&h);
            int bottom=(b->y+1)*96+f->offset;
            if (WS_ROWS*96-bottom<gap) { gap=WS_ROWS*96-bottom; stationary_contact=true; }
            for (int j=0;j<WS_BLOCKS;++j) {
                ws_block *other=&s->blocks[j];
                if (!other->used || other->group==g || j==s->held) continue;
                int ow,oh;
                workshop_shape(other->item,other->orientation,&ow,&oh);
                if (b->x>=other->x+ow || b->x+w<=other->x) continue;
                int top=(other->y-oh+1)*96;
                if (other->group) top+=s->falls[other->group-1].offset;
                if (top>=bottom && top-bottom<gap) {
                    gap=top-bottom;
                    stationary_contact=other->group==0;
                }
            }
        }
        if (!used) continue;
        if (f->velocity<32) ++f->velocity;
        int distance=f->velocity<gap ? f->velocity : gap;
        f->offset+=distance;
        if (distance==gap && stationary_contact) {
            int rows=f->offset/96;
            bool landed[WS_BLOCKS]={false};
            for (int i=0;i<WS_BLOCKS;++i) if (s->blocks[i].used && s->blocks[i].group==g) {
                ws_block *b=&s->blocks[i];
                b->y+=(int16_t)rows;
                b->group=0;
                landed[i]=true;
                particle(s,WS_X+b->x*48+24,WS_Y+(b->y+1)*48,-2,-3,18,0,0);
            }
            workshop_reconnect(s);
            for (int i=0;i<WS_BLOCKS;++i) if (landed[i])
                frightened(s,WS_X+s->blocks[i].x*48,WS_Y+s->blocks[i].y*48);
        }
    }
}
static void terrain(workshop_state *s,unsigned item)
{
    for (int x=0;x<WS_COLS;++x) {
        insert(s,WS_DIRT,0,x,10);
        insert(s,item,0,x,9);
    }
}
void workshop_init(workshop_state *s)
{
    memset(s,0,sizeof *s);
    s->random=0x1742u;
    s->held=s->lifted=s->mining=s->last_cell=-1;
    s->menu_hover=s->inventory_hover=-1;
    s->menu=true;
    s->selected=WS_HAND;
    grid(s);
}
void workshop_scene(workshop_state *s,unsigned scene)
{
    workshop_init(s);
    s->menu=false;
    s->scene=scene;
    terrain(s,scene==2 ? WS_STONE : WS_GRASS);
    if (scene==1) {
        for (int x=5;x<=11;++x)
            for (int y=6;y<=8;++y) {
                if ((x==8 && y>=7) || (x==10 && y==7)) continue;
                insert(s,x==5 || x==11 ? WS_LOG : WS_PLANK,0,x,y);
            }
        insert(s,WS_DOOR,0,8,8);
        insert(s,WS_WINDOW,0,10,7);
        for (int x=4;x<=12;++x) insert(s,WS_BRICK,0,x,5);
        insert(s,WS_BRICK_SLOPE,1,4,4);
        for (int x=5;x<=11;++x) insert(s,WS_BRICK,0,x,4);
        insert(s,WS_BRICK_SLOPE,0,12,4);
        /* Lamp replaces an interior wall cell rather than overlapping it. */
        for (int i=0;i<WS_BLOCKS;++i)
            if (s->blocks[i].used && s->blocks[i].x==7 && s->blocks[i].y==6)
                s->blocks[i].item=WS_LAMP;
        for (int y=5;y<=8;++y) insert(s,WS_LOG,0,16,y);
        for (int x=14;x<=18;++x) insert(s,WS_LEAVES,0,x,4);
        for (int x=15;x<=17;++x) insert(s,WS_LEAVES,0,x,3);
        insert(s,WS_LEAVES,0,16,2);
    }
    if (scene==2) {
        for (int x=3;x<=16;++x)
            for (int y=6;y<=8;++y) {
                if ((x==9 && y>=7) || (x==5 && y==6) || (x==14 && y==6)) continue;
                insert(s,WS_STONEBRICK,0,x,y);
            }
        insert(s,WS_DOOR,0,9,8);
        insert(s,WS_WINDOW,0,5,6);
        insert(s,WS_WINDOW,0,14,6);
        for (int x=3;x<=6;++x)
            for (int y=3;y<=5;++y) insert(s,WS_STONEBRICK,0,x,y);
        for (int x=13;x<=16;++x)
            for (int y=3;y<=5;++y) insert(s,WS_STONEBRICK,0,x,y);
        for (int x=3;x<=16;++x)
            if (x==3 || x==5 || x==14 || x==16) insert(s,WS_STONEBRICK,0,x,2);
        for (int i=0;i<WS_BLOCKS;++i)
            if (s->blocks[i].used && s->blocks[i].y==7 &&
                (s->blocks[i].x==7 || s->blocks[i].x==11)) s->blocks[i].item=WS_LAMP;
    }
    workshop_reconnect(s);
    s->animal_count=scene ? 3 : 2;
    for (unsigned i=0;i<s->animal_count;++i) {
        ws_animal *a=&s->animals[i];
        a->species=(uint8_t)(i%2);
        a->x=(WS_X+72+(int)i*112)*2;
        a->direction=i%2 ? -1 : 1;
        int col=(a->x/2-WS_X)/48, row=0;
        while (cell(s,col,row)<0) ++row;
        a->y=(WS_Y+row*48)*2;
        a->action=WS_IDLE;
        a->timer=60+(int)(random_next(s)%121);
    }
}
static bool animal_solid(const workshop_state *s,int col,int row)
{
    int id=cell(s,col,row);
    return id>=0 && s->blocks[id].item!=WS_DOOR;
}
static int floor_below(const workshop_state *s,int x,int y)
{
    int col=(x/2-WS_X)/48;
    if (col<0 || col>=WS_COLS) return WS_BOTTOM*2;
    for (int row=0;row<WS_ROWS;++row)
        if ((WS_Y+row*48)*2>=y && animal_solid(s,col,row)) return (WS_Y+row*48)*2;
    return WS_BOTTOM*2;
}
static void animals(workshop_state *s)
{
    /* assets/workshop/README.md: displacement advances exactly with walk frames. */
    static const int strides[2]={24,16};
    for (unsigned i=0;i<s->animal_count;++i) {
        ws_animal *a=&s->animals[i];
        if (a->action==WS_LIFT) {
            a->x=s->hand.x*2;
            a->y=(s->hand.y+20)*2;
            a->frame=(int)(s->ticks/30%2);
            continue;
        }
        if (a->action==WS_JUMP) {
            int t=19-a->timer;
            a->x=a->jump_x+a->direction*96*t/18;
            a->y=a->jump_y-96*t/18-160*t*(18-t)/(18*18);
            if (--a->timer==0) { a->action=WS_WALK; a->timer=120; }
            continue;
        }
        int floor=floor_below(s,a->x,a->y);
        if (a->y<floor || a->velocity<0) {
            if (a->velocity<32) ++a->velocity;
            a->y+=a->velocity;
            if (a->y>=floor && a->velocity>=0) {
                a->y=floor;
                a->velocity=0;
                if (a->action==WS_FALL) {
                    a->action=WS_IDLE;
                    a->timer=60+(int)(random_next(s)%121);
                }
            }
        }
        if (a->action==WS_FALL) continue;
        if (a->action==WS_STUN) {
            a->frame=(int)(s->ticks/30%2);
            if (--a->timer==0) { a->action=WS_RUN; a->timer=180; a->phase=0; }
            continue;
        }
        if (--a->timer<=0) {
            bool walking=a->action==WS_IDLE || a->action==WS_RUN;
            a->action=walking ? WS_WALK : WS_IDLE;
            a->timer=walking ? 120+(int)(random_next(s)%181) :
                              60+(int)(random_next(s)%121);
            a->phase=0;
        }
        if (a->action==WS_IDLE) { a->frame=(int)(s->ticks/30%2); continue; }
        a->phase+=a->action==WS_RUN ? 24 : 10;
        if (a->phase<60) continue;
        a->phase-=60;
        a->frame=(a->frame+1)%8;
        if (a->y<floor || a->velocity) continue;
        int ahead=a->x/2+a->direction*28;
        if (ahead<WS_X+2 || ahead>=WS_X+WS_COLS*48-2) {
            a->direction=-a->direction;
            continue;
        }
        int col=(ahead-WS_X)/48;
        int row=(a->y/2-WS_Y-1)/48;
        if (animal_solid(s,col,row)) {
            if (!animal_solid(s,col,row-1) && !animal_solid(s,col,row-2)) {
                a->jump_x=a->x;
                a->jump_y=a->y;
                a->action=WS_JUMP;
                a->timer=18;
            } else a->direction=-a->direction;
            continue;
        }
        int next_floor=floor_below(s,ahead*2,a->y);
        if (next_floor-a->y>192) { a->direction=-a->direction; continue; }
        a->x+=a->direction*strides[a->species]*2/8;
    }
}
static int inventory_hit(int x,int y)
{
    x-=300;
    y-=150;
    if (x<0 || x>=680 || y<0 || y>=450 || x%136>=128 || y%90>=84) return -1;
    return y/90*5+x/136;
}
static void inventory_select(workshop_state *s,int index)
{
    if (index>=2 && index<=4) s->sky=(unsigned)(index-2);
    else {
        s->selected=(unsigned)(index<2 ? index : index-3);
        s->orientation=s->selected==WS_PILLAR;
    }
    s->inventory=false;
    s->selection_grab=s->hand.closed;
    s->mining=-1;
    s->mine_ticks=0;
    s->last_cell=-1;
}
void workshop_key(workshop_state *s,unsigned key)
{
    if (s->menu) {
        if (key==1) s->menu_hover=(s->menu_hover+1)%3;
        if (key==2) s->menu_hover=(s->menu_hover+2+3)%3;
        if (key==3) workshop_scene(s,(unsigned)(s->menu_hover<0 ? 0 : s->menu_hover));
        return;
    }
    if (!s->inventory) {
        if (key==3) { s->inventory=true; s->inventory_hover=0; s->mining=-1; }
        return;
    }
    if (key==1) s->inventory_hover=(s->inventory_hover+1)%25;
    if (key==2) s->inventory_hover=(s->inventory_hover+24+25)%25;
    if (key==3) inventory_select(s,s->inventory_hover<0 ? 0 : s->inventory_hover);
    if (key==4) s->inventory=false;
}
static int animal_hit(const workshop_state *s)
{
    for (int i=(int)s->animal_count-1;i>=0;--i) {
        const ws_animal *a=&s->animals[i];
        if (s->hand.x>=a->x/2-28 && s->hand.x<=a->x/2+28 &&
            s->hand.y>=a->y/2-56 && s->hand.y<=a->y/2) return i;
    }
    return -1;
}
static void shatter(workshop_state *s,int id,int x,int y)
{
    ws_block *b=&s->blocks[id];
    for (unsigned i=0;i<8;++i) {
        int vx=(int)(random_next(s)%17)-8;
        int vy=-4-(int)(random_next(s)%14);
        particle(s,x,y,vx,vy,36,b->item==WS_GLASS || b->item==WS_ICE ? 2 : 1,
                 ws_colors[b->item]);
    }
    workshop_remove(s,id);
}
static void mine(workshop_state *s,int id)
{
    if (s->mining!=id) { s->mining=id; s->mine_ticks=0; }
    if (id<0) return;
    ws_block *b=&s->blocks[id];
    if (++s->mine_ticks<workshop_hardness(b->item)) return;
    shatter(s,id,WS_X+b->x*48+24,WS_Y+b->y*48+24);
    ++s->breaks;
    s->mining=-1;
    s->mine_ticks=0;
}
static void held_position(const workshop_state *s,int *x,int *y)
{
    *x=s->hand.x-24;
    *y=s->hand.y-24;
    if (s->return_ticks) {
        *x=(s->return_x*(int)s->return_ticks+(WS_X+s->origin_x*48)*
            (12-(int)s->return_ticks))/12;
        *y=(s->return_y*(int)s->return_ticks+(WS_Y+s->origin_y*48)*
            (12-(int)s->return_ticks))/12;
    }
}
static void interact(workshop_state *s,bool pressed,bool released)
{
    int x=(s->hand.x-WS_X)/48,y=(s->hand.y-WS_Y)/48;
    if (s->hand.x<WS_X) x=-1;
    if (s->hand.y<WS_Y) y=-1;
    s->preview_x=x;
    s->preview_y=y;
    unsigned item=s->held>=0 ? s->blocks[s->held].item : s->selected;
    unsigned orientation=s->held>=0 ? s->blocks[s->held].orientation : s->orientation;
    s->preview=item>=WS_GRASS && workshop_fits(s,item,orientation,x,y);
    if (s->return_ticks) {
        while (s->origin_y>=0 && !workshop_fits(s,item,orientation,
               s->origin_x,s->origin_y)) --s->origin_y;
        if (s->origin_y<0) {
            int px,py,id=s->held;
            held_position(s,&px,&py);
            s->held=-1;
            s->return_ticks=0;
            shatter(s,id,px+24,py+24);
            return;
        }
        if (--s->return_ticks==0) {
            s->blocks[s->held].x=(int16_t)s->origin_x;
            s->blocks[s->held].y=(int16_t)s->origin_y;
            s->held=-1;
            workshop_reconnect(s);
        }
        return;
    }
    if (s->lifted>=0) {
        if (released) {
            ws_animal *a=&s->animals[s->lifted];
            a->action=WS_FALL;
            a->velocity=0;
            s->lifted=-1;
        }
        return;
    }
    if (s->held>=0) {
        if (released) {
            if (s->preview) {
                s->blocks[s->held].x=(int16_t)x;
                s->blocks[s->held].y=(int16_t)y;
                s->held=-1;
                ++s->moves;
                workshop_reconnect(s);
            } else {
                held_position(s,&s->return_x,&s->return_y);
                while (s->origin_y>=0 && !workshop_fits(s,item,orientation,
                       s->origin_x,s->origin_y)) --s->origin_y;
                if (s->origin_y<0) {
                    int id=s->held;
                    s->held=-1;
                    shatter(s,id,s->hand.x,s->hand.y);
                } else s->return_ticks=12;
            }
        }
        return;
    }
    if (!s->hand.closed) { s->mining=-1; s->mine_ticks=0; s->last_cell=-1; return; }
    if (s->selected>=WS_GRASS) {
        int cx=s->hand.x-(WS_X+x*48),cy=s->hand.y-(WS_Y+y*48);
        int index=y*WS_COLS+x;
        bool center=cx>=10 && cx<=38 && cy>=10 && cy<=38;
        if ((pressed || center) && s->last_cell!=index && s->preview) {
            workshop_add(s,s->selected,s->orientation,x,y);
            s->last_cell=index;
            ++s->places;
        }
        return;
    }
    int a=animal_hit(s);
    if (a>=0 && pressed) {
        ws_animal *animal=&s->animals[a];
        if (s->selected==WS_HAND) { s->lifted=a; animal->action=WS_LIFT; }
        else {
            animal->action=WS_STUN;
            animal->timer=60;
            animal->direction=animal->x/2<s->hand.x ? -1 : 1;
        }
        s->mining=-1;
        s->mine_ticks=0;
        return;
    }
    int id=cell(s,x,y);
    if (s->selected==WS_PICK) { if (a<0) mine(s,id); return; }
    if (pressed && id>=0) {
        s->held=id;
        s->origin_x=s->blocks[id].x;
        s->origin_y=s->blocks[id].y;
        workshop_reconnect(s);
    }
}
void workshop_step(workshop_state *s,ws_input input)
{
    ++s->ticks;
    bool closed=s->hand.closed;
    if (input.lost<=200) {
        if (input.cls==1 || input.cls==5) closed=true;
        if (input.cls==0 || input.cls==11) closed=false;
    }
    if (input.lost>200) closed=false;
    input.closed=closed;
    s->hand=input;
    bool pressed=closed && !s->was_closed, released=!closed && s->was_closed;
    s->was_closed=closed;
    if (s->menu) {
        int hover=-1;
        if (input.y>=250 && input.y<480 && input.x>=190 && input.x<1090)
            hover=(input.x-190)/310;
        if (hover!=s->menu_hover || !closed) s->menu_hold=0;
        if (hover>=0) s->menu_hover=hover;
        if (hover>=0 && closed && ++s->menu_hold>=60) workshop_scene(s,(unsigned)hover);
        return;
    }
    falling(s);
    animals(s);
    for (unsigned i=0;i<WS_PARTICLES;++i) {
        ws_particle *p=&s->particles[i];
        if (!p->life) continue;
        --p->life;
        p->x+=p->vx;
        p->y+=p->vy;
        ++p->vy;
    }
    if (input.cls==7 && input.lost<=200) {
        if (!s->ok_latched && ++s->ok_ticks>=WS_INVENTORY_HOLD) {
            s->inventory=!s->inventory;
            s->ok_latched=true;
            s->mining=-1;
            s->mine_ticks=0;
        }
    } else { s->ok_ticks=0; s->ok_latched=false; }
    if (input.cls==2 && !s->scissors && !s->inventory) {
        if (s->held>=0) {
            ws_block *b=&s->blocks[s->held];
            b->orientation=(uint8_t)workshop_rotate(b->item,b->orientation);
        } else s->orientation=workshop_rotate(s->selected,s->orientation);
    }
    s->scissors=input.cls==2;
    if (s->inventory) {
        int hover=inventory_hit(input.x,input.y);
        if (hover>=0) s->inventory_hover=hover;
        if (hover>=0 && pressed) inventory_select(s,hover);
        return;
    }
    if (s->selection_grab) {
        if (!closed) s->selection_grab=false;
        else return;
    }
    interact(s,pressed,released);
}
void workshop_snapshot_copy(const workshop_state *s,workshop_snapshot *out)
{
    memset(out,0,sizeof *out);
    memcpy(out->blocks,s->blocks,sizeof out->blocks);
    for (int i=0;i<WS_BLOCKS;++i)
        if (s->blocks[i].group) out->offset[i]=(int16_t)s->falls[s->blocks[i].group-1].offset;
    memcpy(out->animals,s->animals,sizeof out->animals);
    memcpy(out->particles,s->particles,sizeof out->particles);
    out->hand=s->hand;
    out->ticks=s->ticks;
    out->animal_count=s->animal_count;
    out->scene=s->scene;
    out->sky=s->sky;
    out->selected=s->selected;
    out->orientation=s->orientation;
    out->places=s->places;
    out->breaks=s->breaks;
    out->moves=s->moves;
    out->held=s->held;
    out->lifted=s->lifted;
    out->mining=s->mining;
    out->crack=s->mining>=0 ? s->mine_ticks*8/workshop_hardness(s->blocks[s->mining].item)+1 : 0;
    if (out->crack>8) out->crack=8;
    held_position(s,&out->held_x,&out->held_y);
    out->preview_x=s->preview_x;
    out->preview_y=s->preview_y;
    out->preview=s->preview;
    out->menu=s->menu;
    out->inventory=s->inventory;
    out->returning=s->return_ticks!=0;
    out->hover=s->menu ? s->menu_hover : s->inventory_hover;
    out->hold=s->menu ? s->menu_hold : s->ok_latched ? 0 : s->ok_ticks;
}
