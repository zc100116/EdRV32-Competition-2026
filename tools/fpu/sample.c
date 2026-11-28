// File: sample.c
// Spec: fpu-testplan FT01; coordinator F05 sampling clarification 2026-11-28.
// Description: Reservoir-sample the entire TestFloat text stream with a fixed seed.
// Clock: host only.
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t state;
static uint64_t random64(void)
{
    uint64_t z = (state += UINT64_C(0x9e3779b97f4a7c15));
    z = (z ^ (z >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94d049bb133111eb);
    return z ^ (z >> 31);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: sample count seed\n");
        return 1;
    }
    size_t count = strtoul(argv[1], NULL, 10);
    state = strtoull(argv[2], NULL, 10);
    // F/D TestFloat records contain at most four 16-digit values plus flags.
    char (*sample)[96] = calloc(count, sizeof(*sample));
    if (!sample) {
        perror("sample allocation");
        return 1;
    }
    char line[96];
    uint64_t seen = 0;
    while (fgets(line, sizeof(line), stdin)) {
        ++seen;
        uint64_t slot = seen <= count ? seen - 1 : random64() % seen;
        if (slot < count) strcpy(sample[slot], line);
    }
    if (ferror(stdin) || seen < count) {
        fprintf(stderr, "sample: stream has %" PRIu64 " rows, need %zu\n", seen, count);
        free(sample);
        return 1;
    }
    for (size_t i = 0; i < count; ++i) fputs(sample[i], stdout);
    free(sample);
    return 0;
}
