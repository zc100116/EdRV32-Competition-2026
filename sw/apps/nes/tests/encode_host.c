/* File: encode_host.c
 * Spec: Task B3-4b step 2; rnd-spec 2.1/2.6.
 * Description: Feed RGB888 through the production palette and BLIT encoders for the oracle.
 * Clock domain: host.
 */
#include <stdio.h>
#include "display.h"

int main(void)
{
    struct nes_rgb palette[256];
    uint32_t packed[256] = {0};
    struct rnd_command command;
    if (fread(palette, sizeof(palette), 1, stdin) != 1) {
        fputs("FAIL palette input\n", stderr);
        return 1;
    }
    if (!nes_palette_update(packed, palette) || nes_palette_update(packed, palette)) {
        fputs("FAIL unchanged palette was updated\n", stderr);
        return 1;
    }
    palette[255].r ^= 1;
    if (!nes_palette_update(packed, palette)) {
        fputs("FAIL changed palette was ignored\n", stderr);
        return 1;
    }
    palette[255].r ^= 1;
    (void)nes_palette_update(packed, palette);
    nes_blit_encode(&command, 0, 0x200000, 0x210000);
    if (fwrite(&command, sizeof(command), 1, stdout) != 1 ||
        fwrite(packed, sizeof(packed), 1, stdout) != 1) {
        fputs("FAIL encoded output\n", stderr);
        return 1;
    }
    return 0;
}
