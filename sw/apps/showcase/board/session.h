/* session.h — P5 3.1/3.2/8.1; hardware-free exclusive media lifecycle.
 * Callbacks run cooperatively on clk_sys or in host tests. */
#ifndef SHOWCASE_SESSION_H
#define SHOWCASE_SESSION_H
#include "../ui/ui_data.h"
struct session_ops {
    void (*start)(ui_app_t app, unsigned arg);
    void (*stop)(ui_app_t app);
    void (*pause)(ui_app_t app, bool paused);
    bool (*ready)(ui_app_t app, ui_state_t target);
};
struct session {
    struct session_ops ops;
    ui_app_t app, requested;
    ui_state_t state;
    unsigned arg, requested_arg, error;
    bool pending, pausing;
};
void session_open(struct session *s, ui_app_t app, unsigned arg);
void session_pause(struct session *s, bool paused);
void session_retry(struct session *s);
void session_fail(struct session *s, unsigned error);
void session_complete(struct session *s);
void session_step(struct session *s);
#endif
