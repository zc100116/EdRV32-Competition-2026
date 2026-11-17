/* workshop_view.c — block workshop task §7; shared snapshot bounds and damage.
 * CPU-only geometry; GUI clips repainting to these old/new object rectangles.
 */
#include "workshop.h"
#include <string.h>
ws_rect workshop_block_rect(const workshop_snapshot *s,int id)
{
    const ws_block *b=&s->blocks[id];
    int w,h;
    workshop_shape(b->item,b->orientation,&w,&h);
    if (s->held==id) return (ws_rect){s->held_x,s->held_y-(h-1)*48,w*48,h*48};
    return (ws_rect){WS_X+b->x*48,WS_Y+(b->y-h+1)*48+s->offset[id]/2,w*48,h*48};
}
static ws_rect join(ws_rect a,ws_rect b)
{
    int right=a.x+a.w>b.x+b.w ? a.x+a.w : b.x+b.w;
    int bottom=a.y+a.h>b.y+b.h ? a.y+a.h : b.y+b.h;
    int x=a.x<b.x ? a.x : b.x,y=a.y<b.y ? a.y : b.y;
    return (ws_rect){x,y,right-x,bottom-y};
}
static ws_rect preview(const workshop_snapshot *s)
{
    unsigned item=s->held>=0 ? s->blocks[s->held].item : s->selected;
    unsigned orientation=s->held>=0 ? s->blocks[s->held].orientation : s->orientation;
    int w,h;
    workshop_shape(item,orientation,&w,&h);
    return (ws_rect){WS_X+s->preview_x*48,WS_Y+(s->preview_y-h+1)*48,w*48,h*48};
}
void workshop_dirty(const workshop_snapshot *a,const workshop_snapshot *b,
                    void (*emit)(ws_rect,void *),void *context)
{
    if (a->menu!=b->menu || a->sky!=b->sky || a->scene!=b->scene) {
        emit((ws_rect){0,0,1280,720},context);
        return;
    }
    if (a->inventory!=b->inventory || (b->inventory && a->hover!=b->hover))
        emit((ws_rect){280,130,720,478},context);
    for (int i=0;i<WS_BLOCKS;++i) {
        const ws_block *p=&a->blocks[i],*q=&b->blocks[i];
        if (!p->used && !q->used) continue;
        ws_rect r=workshop_block_rect(a,i),t=workshop_block_rect(b,i);
        if (memcmp(p,q,sizeof *p)==0 && memcmp(&r,&t,sizeof r)==0) continue;
        if (!p->used) r=t;
        if (!q->used) t=r;
        if ((p->used && (p->item==WS_LAMP || p->item==WS_WINDOW)) ||
            (q->used && (q->item==WS_LAMP || q->item==WS_WINDOW))) {
            r=(ws_rect){r.x-48,r.y-48,r.w+96,r.h+96};
            t=(ws_rect){t.x-48,t.y-48,t.w+96,t.h+96};
        }
        emit(join(r,t),context);
    }
    for (unsigned i=0;i<b->animal_count;++i) {
        const ws_animal *p=&a->animals[i],*q=&b->animals[i];
        if (p->x!=q->x || p->y!=q->y || p->frame!=q->frame ||
            p->direction!=q->direction || p->action!=q->action)
            emit(join((ws_rect){p->x/2-32,p->y/2-52,64,56},
                      (ws_rect){q->x/2-32,q->y/2-52,64,56}),context);
    }
    for (unsigned i=0;i<WS_PARTICLES;++i) {
        const ws_particle *p=&a->particles[i],*q=&b->particles[i];
        if (p->life || q->life) {
            ws_rect r={p->x/2-16,p->y/2-16,32,32},t={q->x/2-16,q->y/2-16,32,32};
            if (!p->life) r=t;
            if (!q->life) t=r;
            emit(join(r,t),context);
        }
    }
    if (a->mining!=b->mining || a->crack!=b->crack) {
        if (a->mining>=0) emit(workshop_block_rect(a,a->mining),context);
        if (b->mining>=0) emit(workshop_block_rect(b,b->mining),context);
    }
    if (a->hand.x!=b->hand.x || a->hand.y!=b->hand.y ||
        a->hand.closed!=b->hand.closed || a->selected!=b->selected ||
        (b->selected==WS_PICK && b->hand.closed && a->ticks/10!=b->ticks/10)) {
        emit(join((ws_rect){a->hand.x-32,a->hand.y-32,64,64},
                  (ws_rect){b->hand.x-32,b->hand.y-32,64,64}),context);
    }
    if (a->preview_x!=b->preview_x || a->preview_y!=b->preview_y ||
        a->preview!=b->preview || a->held!=b->held || a->selected!=b->selected ||
        a->orientation!=b->orientation || a->inventory!=b->inventory ||
        (a->held>=0 && b->held>=0 &&
         a->blocks[a->held].orientation!=b->blocks[b->held].orientation)) {
        if (a->selected>=WS_GRASS || a->held>=0) emit(preview(a),context);
        if (b->selected>=WS_GRASS || b->held>=0) emit(preview(b),context);
    }
}
