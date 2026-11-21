/* track.c — T-HELMET-STABLE: IoU association and five-observation class vote.
 * Confirm after two consecutive hits, retire on the fourth consecutive miss.
 * GUI domain; positions remain at the last observation while missing.
 */
#include "track.h"
#include <string.h>
unsigned helmet_revision;
helmet_state_t helmet_stable;
static unsigned overlap(const ui_detection_t *a, const ui_detection_t *b)
{
    int left = a->x > b->x ? a->x : b->x;
    int top = a->y > b->y ? a->y : b->y;
    int right = a->x+a->width < b->x+b->width ? a->x+a->width : b->x+b->width;
    int bottom = a->y+a->height < b->y+b->height ? a->y+a->height : b->y+b->height;
    if (right <= left || bottom <= top) return 0;
    unsigned intersection = (unsigned)((right-left)*(bottom-top));
    unsigned total = (unsigned)(a->width*a->height+b->width*b->height)-intersection;
    return intersection*1000/total;
}
static void observe(helmet_track_t *t, const ui_detection_t *box)
{
    unsigned cls = t->box.class_id;
    t->box = *box;
    t->history = ((t->history << 1) | box->class_id) & 31;
    if (t->samples < HELMET_HISTORY) ++t->samples;
    unsigned heads = 0;
    for (unsigned i = 0; i < t->samples; ++i) heads += (t->history >> i) & 1;
    if (heads*2 != t->samples) cls = heads*2 > t->samples;
    t->box.class_id = cls;
    t->box.category = cls ? "未戴" : "安全帽";
    t->lost = 0;
    if (t->seen < 2) ++t->seen;
    if (t->seen == 2) t->visible = true;
}
void helmet_step(helmet_state_t *s, const ui_detection_t *boxes, unsigned count)
{
    bool matched[HELMET_TRACKS] = {false};
    int assigned[100];
    /* Associate only with tracks from the previous frame, independent of class. */
    for (unsigned i = 0; i < count; ++i) {
        assigned[i] = -2;
        /* User-selected helmet-only floor; raw head detections remain unchanged. */
        if (boxes[i].class_id == 0 && boxes[i].confidence < 60) continue;
        unsigned best = 299;
        assigned[i] = -1;
        for (unsigned j = 0; j < HELMET_TRACKS; ++j) {
            if (!s->tracks[j].active || matched[j]) continue;
            unsigned score = overlap(&s->tracks[j].box, &boxes[i]);
            if (score > best) { best = score; assigned[i] = (int)j; }
        }
        if (assigned[i] >= 0) matched[assigned[i]] = true;
    }
    for (unsigned j = 0; j < HELMET_TRACKS; ++j) {
        helmet_track_t *t = &s->tracks[j];
        if (!t->active || matched[j]) continue;
        t->seen = 0;
        if (!t->visible || ++t->lost == 4) memset(t, 0, sizeof *t);
    }
    for (unsigned i = 0; i < count; ++i) {
        if (assigned[i] == -2) continue;
        int slot = assigned[i];
        if (slot < 0) {
            for (unsigned j = 0; j < HELMET_TRACKS; ++j)
                if (!s->tracks[j].active) { slot = (int)j; break; }
            /* Keep the existing 100-object UI capacity when retained tracks fill it. */
            if (slot < 0) continue;
            s->tracks[slot].active = true;
            s->tracks[slot].box.class_id = boxes[i].class_id;
        }
        observe(&s->tracks[slot], &boxes[i]);
    }
    s->helmet = s->head = 0;
    for (unsigned j = 0; j < HELMET_TRACKS; ++j) {
        const helmet_track_t *t = &s->tracks[j];
        if (t->visible) {
            if (t->box.class_id) ++s->head; else ++s->helmet;
        }
    }
}
bool helmet_warning(helmet_state_t *s, unsigned now)
{
    bool has_head = s->head != 0;
    if (has_head != s->has_head) {
        s->has_head = has_head;
        s->warning_since = now;
    }
    if (now-s->warning_since >= (has_head ? 300u : 500u)) s->warning = has_head;
    return s->warning;
}
