/* grab.c — T-GRAB-TEST §4; four grasp rules and independent gravity animation.
 * CPU domain; model class debounce belongs to the existing gesture decoder.
 */
#include "grab.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
grab_state_t ui_grab = {.mirror = true};
static float distance(float ax, float ay, float bx, float by)
{
    return hypotf(ax - bx, ay - by);
}
static float point_distance(const ui_pose_point_t *p, unsigned a, unsigned b)
{
    return distance(p[a].x, p[a].y, p[b].x, p[b].y);
}
void grab_reset_objects(grab_state_t *s)
{
    for (unsigned i = 0; i < GRAB_OBJECTS; ++i)
        s->objects[i] = (grab_object_t){290 + 140 * i, GRAB_GROUND - GRAB_RADIUS, 0, false};
    s->held = -1;
}
void grab_init(grab_state_t *s)
{
    bool mirror = s->mirror;
    memset(s, 0, sizeof *s);
    s->mirror = mirror;
    s->thresholds[0] = 25;
    s->thresholds[1] = 35;
    s->thresholds[3] = 25;
    s->cls = -1;
    s->candidate_object = -1;
    s->x = 640;
    s->y = 360;
    grab_reset_objects(s);
}
static void transition(grab_state_t *s, bool closed, int object)
{
    s->closed = closed;
    s->event_object = closed ? object : s->held;
    s->pending_frames = 0;
    if (closed) {
        s->held = object;
        if (object >= 0) {
            grab_object_t *o = &s->objects[object];
            o->falling = false;
            o->velocity = 0;
            s->offset_x = o->x - s->x;
            s->offset_y = o->y - s->y;
            ++s->picks;
        }
    } else if (s->held >= 0) {
        s->objects[s->held].falling = true;
        s->objects[s->held].velocity = 0;
        s->held = -1;
        ++s->drops;
    }
}
bool grab_frame(grab_state_t *s, const ui_pose_point_t *p, int cls)
{
    if (!p) {
        s->pending_frames = 0;
        if (++s->lost == 15 && s->held >= 0) {
            transition(s, false, -1);
            return true;
        }
        return false;
    }
    s->lost = 0;
    static const unsigned required[4][10] = {
        {0,5,9,13,17,4,8}, {0,5,9,13,17,4,8,12,16,20}, {0,5,9,13,17}, {4,8}
    };
    static const unsigned count[] = {7,10,5,2};
    for (unsigned i = 0; i < count[s->mode]; ++i)
        if (p[required[s->mode][i]].visibility < .5f) {
            s->pending_frames = 0;
            return false;
        }
    static const unsigned tips[] = {4,8,12,16,20};
    static const unsigned palm[] = {0,5,9,13,17};
    const unsigned *cursor = s->mode == 2 ? palm : tips;
    unsigned n = s->mode == 1 || s->mode == 2 ? 5 : 2;
    float x = 0;
    float y = 0;
    for (unsigned i = 0; i < n; ++i) { x += p[cursor[i]].x; y += p[cursor[i]].y; }
    x /= n;
    y /= n;
    bool smooth = s->smooth;
    s->x = s->smooth ? .5f * (s->x + x) : x;
    s->y = s->smooth ? .5f * (s->y + y) : y;
    s->smooth = true;
    s->cls = cls;
    bool close = false;
    bool release = false;
    int object = -1;
    if (s->mode <= 1) {
        float d = point_distance(p,4,8);
        if (s->mode == 1) {
            for (unsigned i = 2; i < 5; ++i) d += point_distance(p,4,tips[i]);
            d /= 4;
        }
        float scale = 0;
        for (unsigned i = 1; i < 5; ++i) scale += point_distance(p,0,palm[i]);
        d /= scale / 4;
        s->d = smooth ? .5f * (s->d + d) : d;
        float threshold = s->thresholds[s->mode] / 100.f;
        close = s->d < threshold;
        release = s->d > threshold + (s->mode == 0 ? .15f : .20f);
    } else if (s->mode == 2) {
        close = cls == 1 || cls == 5;
        release = cls == 0 || cls == 11;
    } else {
        float d = point_distance(p,4,8);
        s->d = smooth ? .5f * (s->d + d) : d;
        float reach = GRAB_RADIUS + s->thresholds[3];
        release = s->d > 2 * reach + 40;
        for (unsigned i = 0; i < GRAB_OBJECTS; ++i) {
            const grab_object_t *o = &s->objects[i];
            float ax = p[4].x - o->x;
            float ay = p[4].y - o->y;
            float bx = p[8].x - o->x;
            float by = p[8].y - o->y;
            if (distance(p[4].x,p[4].y,o->x,o->y) <= reach &&
                distance(p[8].x,p[8].y,o->x,o->y) <= reach && ax*bx + ay*by < 0) {
                object = (int)i;
                close = true;
                break;
            }
        }
    }
    if (s->held >= 0) {
        s->objects[s->held].x = s->x + s->offset_x;
        s->objects[s->held].y = s->y + s->offset_y;
    }
    bool change = s->closed ? release : close;
    /* D's consecutive frames must refer to the same object. */
    if (s->mode == 3 && !s->closed && object != s->candidate_object)
        s->pending_frames = 0;
    s->candidate_object = object;
    s->pending_frames = change ? s->pending_frames + 1 : 0;
    bool changed = change && (s->mode == 2 || s->pending_frames >= (s->closed ? 4u : 2u));
    if (changed) {
        if (!s->closed && s->mode != 3) {
            float nearest = GRAB_RADIUS + 40;
            for (unsigned i = 0; i < GRAB_OBJECTS; ++i) {
                const grab_object_t *o = &s->objects[i];
                float d = distance(s->x,s->y,o->x,o->y);
                if (d <= nearest) { nearest = d; object = (int)i; }
            }
        }
        transition(s, !s->closed, object);
    }
    return changed;
}
void grab_animate(grab_state_t *s, float seconds)
{
    for (unsigned i = 0; i < GRAB_OBJECTS; ++i) {
        grab_object_t *o = &s->objects[i];
        if (!o->falling) continue;
        o->y += o->velocity * seconds + 1500 * seconds * seconds;
        o->velocity += 3000 * seconds;
        if (o->y >= GRAB_GROUND - GRAB_RADIUS) {
            o->y = GRAB_GROUND - GRAB_RADIUS;
            o->velocity = 0;
            o->falling = false;
        }
    }
}
void grab_value(const grab_state_t *s, char *text, unsigned size)
{
    if (s->mode == 2) snprintf(text,size,"%s",s->cls < 0 ? "none" : ui_gesture_ids[s->cls]);
    else if (s->mode == 3) snprintf(text,size,"%d",(int)(s->d + .5f));
    else {
        int d = (int)(s->d * 100 + .5f);
        snprintf(text,size,"%d.%02d",d/100,d%100);
    }
}
