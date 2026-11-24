/* profile.c — gpu-spec 7: repeat the exported stress scene for gprof sampling.
 * Host-only driver; binary DDR and little-endian APB writes come from stress.py.
 */
#include "gpu_emu.h"
#include "../../../sw/bsp/include/regs/gpu_regs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char *read_file(const char *path, size_t *size)
{
    FILE *f = fopen(path,"rb");
    if (!f) { perror(path); exit(1); }
    if (fseek(f,0,SEEK_END)) { perror(path); exit(1); }
    long length = ftell(f);
    if (length < 0 || fseek(f,0,SEEK_SET)) { perror(path); exit(1); }
    *size = (size_t)length;
    unsigned char *data = malloc(*size);
    if (!data) { fputs("profile allocation failed\n",stderr); exit(1); }
    if (fread(data,1,*size,f) != *size) { fputs("profile read failed\n",stderr); exit(1); }
    if (fclose(f)) { perror(path); exit(1); }
    return data;
}
static uint32_t word(const unsigned char *p)
{
    return p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
int main(int argc, char **argv)
{
    if (argc != 3) {
        fputs("profile stress.bin writes.bin\n",stderr);
        return 1;
    }
    size_t bytes, write_bytes;
    unsigned char *raw = read_file(argv[1],&bytes);
    unsigned char *writes = read_file(argv[2],&write_bytes);
    unsigned char *ddr = malloc(bytes);
    if (!ddr) { fputs("profile DDR allocation failed\n",stderr); return 1; }
    struct gpu_emu *e = gpu_emu_create(ddr,(uint32_t)bytes);
    if (!e) { fputs("profile emulator allocation failed\n",stderr); return 1; }
    for (int repeat = 0; repeat < 100; ++repeat) {
        memcpy(ddr,raw,bytes);
        gpu_emu_write(e,EDRV32_GPU_CTRL_OFFSET,EDRV32_GPU_CTRL_SOFT_RST_MASK);
        for (size_t i = 0; i < write_bytes; i += 8)
            gpu_emu_write(e,word(writes+i),word(writes+i+4));
    }
    gpu_emu_destroy(e);
    free(ddr); free(raw); free(writes);
    return 0;
}
