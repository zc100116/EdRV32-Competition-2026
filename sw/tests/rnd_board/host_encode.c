/* File: host_encode.c
 * Spec: rnd-spec 2.5–2.6; Task B3-3a host acceptance.
 * Description: Emit descriptors encoded by the real C driver from shared scene data.
 * Clock domain: host.
 */
#include <stdio.h>
#include "scenes.h"

int main(void)
{
    struct rnd_command commands[BOARD_MAX_COMMANDS];
    (void)board_data;
    (void)board_names;
    (void)board_formats;
    (void)board_bases;
    (void)board_strides;
    (void)board_sizes;
    for (unsigned int group = 0; group < BOARD_GROUP_COUNT; ++group) {
        unsigned int count = board_commands(group, 0, commands);
        for (unsigned int i = 0; i < count; ++i) {
            for (unsigned int w = 0; w < 16; ++w) {
                uint32_t value = commands[i].word[w];
                for (unsigned int b = 0; b < 4; ++b) {
                    putchar((int)((value >> (8u * b)) & 255u));
                }
            }
        }
    }
    return 0;
}
