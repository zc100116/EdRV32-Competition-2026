/* game_loop.h — R4 §3.3.2; reusable application-task 60 Hz simulation driver.
 * Single producer, single GUI reader, three caller-owned snapshot buffers.
 */
#ifndef SHOWCASE_GAME_LOOP_H
#define SHOWCASE_GAME_LOOP_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef struct {
    void (*step)(void *context);
    void (*snapshot)(void *context, void *destination);
    void (*report)(void *context, unsigned draws, unsigned steps,
                   unsigned late, unsigned mean_us);
    void *context;
    void *buffers[3];
    size_t bytes;
} game_loop_config;
void game_loop_start(const game_loop_config *config);
void game_loop_stop(void);
void game_loop_step(void);
bool game_loop_read(void *destination);
void game_loop_drawn(void);
#endif
