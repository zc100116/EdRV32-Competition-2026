/* test_bridge.c — gpu-spec 8: private selftest adapter, never linked into clients.
 * Exposes internal operations to replay Python model unit scenarios; host, no clock.
 */
#include "gpu_emu.c"
void *test_buffer(struct gpu_emu *e, int kind)
{
    if (kind == 3 || kind == 4) e->texel_dirty = 1;
    switch (kind) {
    case 0: return e->color;
    case 1: return e->depth;
    case 2: return e->stencil;
    case 3: return e->ram;
    case 4: return e->palettes;
    default: return e->regs;
    }
}
void test_size(struct gpu_emu *e, int width, int height)
{
    free(e->color); free(e->depth); free(e->stencil);
    e->color = calloc((size_t)width*height,sizeof *e->color);
    e->depth = calloc((size_t)width*height,sizeof *e->depth);
    e->stencil = calloc((size_t)width*height,1);
    if (!e->color || !e->depth || !e->stencil) abort();
    e->width = width; e->height = height;
}
void test_matrix(struct gpu_emu *e, const int32_t *m) { memcpy(e->matrix,m,64); }
/* Operations return the same GPU error code as GPU.run; direct helpers use valid inputs. */
int test_op(struct gpu_emu *e, int op, uint8_t *data, int64_t *v)
{
    int code = setjmp(e->fault);
    if (code) return code;
    switch (op) {
    case 0: command(e,data); break;
    case 1: quad(e,decode_quad(data)); break;
    case 2: {
        struct vec a[3]; memcpy(a,v,sizeof a); triangle(e,a[0],a[1],a[2]); break;
    }
    case 3: draw_triangle(e,data); break;
    case 4: objects(e,decode_cmd_obj_step(data)); break;
    case 5: resolve(e,decode_cmd_resolve(data)); break;
    case 6: {
        struct rgba rgba;
        for (int i = 0; i < 4; ++i) rgba.c[i] = v[i+3];
        pixel_at(e,address(e,v[0],v[1]),v[2],rgba,v[7]); break;
    }
    case 7: stencil_op(e,v[0],v[1]); break;
    case 8: { struct vec a = transform(e,decode_vertex(data)); memcpy(v,&a,sizeof a); break; }
    case 9: { struct vec a; memcpy(&a,v,sizeof a); a = project(e,a); memcpy(v,&a,sizeof a); break; }
    default: abort();
    }
    return 0;
}
void test_sample(struct gpu_emu *e, int64_t u, int64_t v, int lod, int group,
                 int nearest, int64_t *out)
{
    prepare_texture(e,group);
    struct rgba a = sample(e,u,v,lod,group,nearest);
    for (int i = 0; i < 4; ++i) out[i] = a.c[i];
}
void *test_planes(const int64_t *v, int64_t area)
{
    struct planes *p = malloc(sizeof *p);
    if (!p) abort();
    struct vec a[3]; memcpy(a,v,sizeof a); setup(p,a,area);
    return p;
}
void test_at(const struct planes *p, int x, int y, wide *out)
{
    for (int i = 0; i < 7; ++i)
        out[i] = p->coeff[i][0]+(x-p->x)*p->coeff[i][1]+(y-p->y)*p->coeff[i][2];
}
void test_free(void *p) { free(p); }
void test_number(int op, int64_t am, int ae, int64_t bm, int be, int64_t *out)
{
    struct number a = {am,ae}, b = {bm,be}, c;
    switch (op) {
    case 0: c = normal(am,ae); break;
    case 1: c = multiply(a,b); break;
    case 2: c = subtract(a,b); break;
    default: c = inverse(a); break;
    }
    out[0] = c.m; out[1] = c.e;
}
int test_clip(int64_t *v, int count)
{
    struct vec polygon[16]; memcpy(polygon,v,(size_t)count*sizeof *polygon);
    count = clip(polygon,count); memcpy(v,polygon,(size_t)count*sizeof *polygon);
    return count;
}
