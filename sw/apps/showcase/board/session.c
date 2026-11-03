/* session.c — P5 3.2/Q4; newest request waits for the previous resource release.
 * No hardware access; clk_sys cooperative foreground. */
#include "session.h"
static void stop(struct session *s)
{
    s->state = UI_STATE_STOPPING;
    s->pausing = false;
    s->ops.stop(s->app);
}
void session_open(struct session *s, ui_app_t app, unsigned arg)
{
    if (!s->pending && s->app == app && s->arg == arg &&
        (s->state == UI_STATE_RUNNING || s->state == UI_STATE_STARTING)) return;
    s->requested = app;
    s->requested_arg = arg;
    s->pending = true;
    if (s->state != UI_STATE_IDLE && s->state != UI_STATE_STOPPING) stop(s);
}
void session_pause(struct session *s, bool paused)
{
    if (paused && s->state == UI_STATE_RUNNING) {
        s->pausing = true;
        s->ops.pause(s->app, true);
    } else if (!paused && s->state == UI_STATE_PAUSED) {
        s->state = UI_STATE_STARTING;
        s->ops.pause(s->app, false);
    }
}
void session_retry(struct session *s)
{
    if (s->state == UI_STATE_FAILED) session_open(s, s->app, s->arg);
}
void session_fail(struct session *s, unsigned error)
{
    s->error = error;
    s->pending = s->pausing = false;
    s->state = UI_STATE_FAILED;
}
void session_complete(struct session *s)
{
    /* Natural completion keeps the application identity (8.1). */
    s->state = UI_STATE_IDLE;
    s->error = 0;
}
void session_step(struct session *s)
{
    if (s->state == UI_STATE_STOPPING && s->ops.ready(s->app, UI_STATE_IDLE)) {
        s->state = UI_STATE_IDLE;
        s->error = 0;
    }
    if (s->state == UI_STATE_IDLE && s->pending) {
        s->app = s->requested;
        s->arg = s->requested_arg;
        s->pending = false;
        s->error = 0;
        if (s->app != UI_APP_NONE) {
            s->state = UI_STATE_STARTING;
            s->ops.start(s->app, s->arg);
        }
    }
    if (s->state == UI_STATE_STARTING && s->ops.ready(s->app, UI_STATE_RUNNING))
        s->state = UI_STATE_RUNNING;
    if (s->state == UI_STATE_RUNNING && s->pausing &&
        s->ops.ready(s->app, UI_STATE_PAUSED)) {
        s->state = UI_STATE_PAUSED;
        s->pausing = false;
    }
}
