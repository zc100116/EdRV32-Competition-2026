/* session.c — P5 8.1; six-app switch matrix and deferred resource ownership. */
#include "session.h"
#include <assert.h>
#include <stdio.h>
static ui_app_t owner;
static bool available;
static unsigned starts, stops;
static void start(ui_app_t app, unsigned arg)
{ (void)arg; assert(owner==UI_APP_NONE); owner=app; ++starts; }
static void stop(ui_app_t app) { assert(owner==app); ++stops; }
static void pause_app(ui_app_t app, bool paused) { assert(owner==app); (void)paused; }
static bool ready(ui_app_t app, ui_state_t target)
{
    assert(owner==app);
    if(available && target==UI_STATE_IDLE) owner=UI_APP_NONE;
    return available;
}
static struct session fresh(ui_app_t app)
{
    owner=UI_APP_NONE; available=true;
    struct session s={.ops={start,stop,pause_app,ready}};
    session_open(&s,app,0); session_step(&s);
    assert(s.app==app && s.state==UI_STATE_RUNNING);
    return s;
}
int main(void)
{
    for(ui_app_t a=1;a<=6;++a) for(ui_app_t b=1;b<=6;++b) {
        for(unsigned paused=0;paused<2;++paused) {
            struct session s=fresh(a);
            if(paused) {
                session_pause(&s,true); session_step(&s); assert(s.state==UI_STATE_PAUSED);
            }
            available=false;
            session_open(&s,b,1); assert(s.state==UI_STATE_STOPPING);
            unsigned count=starts; session_step(&s); assert(starts==count && owner==a);
            /* Another request while stopping replaces the target without a second stop. */
            unsigned count_stop=stops;
            session_open(&s,b,2); session_step(&s);
            assert(stops==count_stop && starts==count && owner==a);
            available=true; session_step(&s);
            assert(s.app==b && s.arg==2 && s.state==UI_STATE_RUNNING && owner==b);
        }
    }
    struct session s=fresh(UI_APP_PIPELINE);
    session_pause(&s,true); session_step(&s); assert(s.state==UI_STATE_PAUSED);
    session_pause(&s,false); session_step(&s); assert(s.state==UI_STATE_RUNNING);
    session_fail(&s,2); assert(s.state==UI_STATE_FAILED && s.error==2);
    session_retry(&s); session_step(&s); assert(s.state==UI_STATE_RUNNING && !s.error);
    session_open(&s,UI_APP_NONE,0); session_step(&s);
    assert(s.state==UI_STATE_IDLE && s.app==UI_APP_NONE && owner==UI_APP_NONE);
    for(ui_app_t app=UI_APP_GAME;app<=UI_APP_COREMARK;++app) {
        s=fresh(app); session_complete(&s); assert(s.state==UI_STATE_IDLE && s.app==app);
    }
    puts("PASS six-by-six RUNNING/PAUSED/STOPPING switch matrix, resume, retry, completion");
}
