/* cli.c — gpu-spec 2–6 model CLI: hex DDR and JSON register writes.
 * Host C11 utility; execution timing uses the standard C clock, no GPU clock.
 */
#include "gpu_emu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <errno.h>
#include "codec.h"
static void die(const char *s) { fprintf(stderr,"%s: %s\n",s,strerror(errno)); exit(1); }
static FILE *open_file(const char *path, const char *mode)
{ FILE *f = fopen(path,mode); if (!f) die(path); return f; }
static uint32_t register_offset(const char *name)
{
    for (size_t i = 0; i < sizeof register_descs/sizeof *register_descs; ++i)
        if (!strcmp(name,register_descs[i].name)) return register_descs[i].offset;
    fprintf(stderr,"unknown register: %s\n",name); exit(1);
}
static char *space(char *p) { while (isspace((unsigned char)*p)) ++p; return p; }
static char *expect(char *p, char c)
{
    p = space(p);
    if (*p != c) { fprintf(stderr,"expected '%c' in writes JSON\n",c); exit(1); }
    return p+1;
}
static FILE *output(const char *dir, const char *name)
{
    char path[4096];
    if (snprintf(path,sizeof path,"%s/%s",dir,name) >= (int)sizeof path) {
        fprintf(stderr,"output path too long\n"); exit(1);
    }
    return open_file(path,"w");
}
int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr,"usage: %s IMAGE.hex WRITES.json OUTPUT_DIR --base ADDRESS\n",argv[0]);
        return 1;
    }
    const char *paths[3] = {NULL,NULL,NULL};
    const char *origin = NULL;
    int path_count = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i],"--base") && i+1 < argc) origin = argv[++i];
        else if (path_count < 3) paths[path_count++] = argv[i];
        else { fprintf(stderr,"unexpected argument: %s\n",argv[i]); return 1; }
    }
    if (!origin || path_count != 3) {
        fprintf(stderr,"expected --base and three paths\n"); return 1;
    }
    uint32_t base = (uint32_t)strtoul(origin,NULL,0), word;
    FILE *f = open_file(paths[0],"r");
    uint64_t count = 0;
    while (fscanf(f,"%x",&word) == 1) ++count;
    if (!feof(f)) { fprintf(stderr,"invalid DDR hex\n"); return 1; }
    rewind(f);
    uint64_t size = base+4*count;
    if (size > UINT32_MAX) { fprintf(stderr,"DDR image exceeds uint32 size\n"); return 1; }
    uint8_t *ddr = calloc((size_t)size,1);
    if (!ddr) die("DDR allocation");
    for (uint64_t i = 0; i < count; ++i) {
        if (fscanf(f,"%x",&word) != 1) die("DDR read");
        store32(ddr+base+4*i,word);
    }
    fclose(f);
    f = open_file(paths[1],"rb");
    if (fseek(f,0,SEEK_END)) die("writes seek");
    long length = ftell(f);
    if (length < 0) die("writes length");
    rewind(f);
    char *json = malloc((size_t)length+1);
    if (!json) die("writes allocation");
    if (fread(json,1,(size_t)length,f) != (size_t)length) die("writes read");
    fclose(f); json[length] = 0;
    struct gpu_emu *e = gpu_emu_create(ddr,(uint32_t)size);
    if (!e) die("GPU allocation");
    clock_t start = clock();
    char *p = expect(json,'[');
    while (*space(p) != ']') {
        p = space(expect(p,'['));
        uint32_t offset;
        if (*p == '"') {
            char *name = ++p;
            while (*p && *p != '"') ++p;
            if (!*p) { fprintf(stderr,"unterminated register name\n"); return 1; }
            *p++ = 0; offset = register_offset(name);
        } else offset = (uint32_t)strtoul(p,&p,10);
        p = space(expect(p,','));
        uint32_t value = (uint32_t)strtoll(p,&p,10);
        p = expect(p,']');
        gpu_emu_write(e,offset,value);
        p = space(p);
        if (*p == ',') ++p;
        else if (*p != ']') { fprintf(stderr,"invalid writes JSON\n"); return 1; }
    }
    double ms = 1000.0*(clock()-start)/CLOCKS_PER_SEC;
    f = output(paths[2],"ddr.hex");
    for (uint64_t i = 0; i < count; ++i) fprintf(f,"%08x\n",load32(ddr+base+4*i));
    if (fclose(f)) die("DDR output");
    f = output(paths[2],"registers.json");
    fputs("{\n",f);
    size_t n = sizeof register_descs/sizeof *register_descs;
    for (size_t i = 0; i < n; ++i)
        fprintf(f,"  \"%s\": %u%s\n",register_descs[i].name,
                gpu_emu_read(e,register_descs[i].offset),i+1 == n ? "" : ",");
    fputs("}\n",f); if (fclose(f)) die("register output");
    printf("execution_ms=%.6f\n",ms);
    gpu_emu_destroy(e); free(ddr); free(json);
    return 0;
}
