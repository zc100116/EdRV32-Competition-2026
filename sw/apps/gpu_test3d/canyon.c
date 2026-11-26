/* canyon.c — gpu-spec 2.4–2.7; Candy Canyon fixed-point triangle flight test.
 * Terrain, rotating icosahedra, solid rings and aircraft use real triangle meshes.
 * Clock domain: CPU/host frame thread; GPU owns emitted vertices during submission.
 */
#include "test.h"
#include <stdio.h>
static const unsigned rocks[7] = {420, 600, 900, 1200, 1600, 2100, 2600};
static const int8_t ico[12][3] = {
    {-10,16,0},{10,16,0},{-10,-16,0},{10,-16,0},
    {0,-10,16},{0,10,16},{0,-10,-16},{0,10,-16},
    {16,0,-10},{16,0,10},{-16,0,-10},{-16,0,10}
};
static const uint8_t faces[20][3] = {
    {0,11,5},{0,5,1},{0,1,7},{0,7,10},{0,10,11},
    {1,5,9},{5,11,4},{11,10,2},{10,7,6},{7,1,8},
    {3,9,4},{3,4,2},{3,2,6},{3,6,8},{3,8,9},
    {4,9,5},{2,4,11},{6,2,10},{8,6,7},{9,8,1}
};
static int camera_x;
static int camera_y;
static unsigned ring_passed;
static unsigned blend_color(unsigned color, unsigned distance)
{
    if (distance > 1400) distance = 1400;
    unsigned r = ((color>>11)&31)*8;
    unsigned g = ((color>>5)&63)*4;
    unsigned b = (color&31)*8;
    return test_color((r*(1800-distance)+100*distance)/1800,
                      (g*(1800-distance)+205*distance)/1800,
                      (b*(1800-distance)+248*distance)/1800);
}
static void vertex(int x, int y, int z, unsigned color, unsigned u, unsigned v, int ny)
{
    test_vertex(x-camera_x, y-camera_y, z, blend_color(color, (unsigned)z), u, v, ny);
}
void test3d_init(void)
{
    camera_x = 0;
    camera_y = 0;
    test.player_x = 0;
    test.player_y = 0;
    ring_passed = 0;
    test.objects_count = 0;
}
void test3d_update(uint32_t keys)
{
    if (keys & PLAT_LEFT) test.player_x -= 3;
    if (keys & PLAT_RIGHT) test.player_x += 3;
    if (keys & PLAT_UP) test.player_y += 2;
    if (keys & PLAT_DOWN) test.player_y -= 2;
    if (test.player_x < -110) test.player_x = -110;
    if (test.player_x > 110) test.player_x = 110;
    if (test.player_y < -45) test.player_y = -45;
    if (test.player_y > 65) test.player_y = 65;
    camera_x = test.player_x;
    camera_y = test.player_y;
    if (test.mode == 2) return;
    if (test.tick%90 == 0) {
        unsigned gate = test.tick/90-1;
        int gx = test_sine[(gate*53)&255]*60/16384;
        int gy = 10+test_sine[(gate*79)&255]*24/16384;
        int dx = test.player_x-gx;
        int dy = test.player_y-gy;
        if (dx*dx+dy*dy < 34*34) {
            test.score += 100;
            ++ring_passed;
            test_sound(3);
        } else {
            if (test.health > 5) test.health -= 5;
            test_sound(1);
        }
    }
}
static int terrain_height(int x, unsigned row)
{
    int a = x < 0 ? -x : x;
    int ridge = (test_sine[(row*13)&255]+16384)*22/32768;
    return -80+(a > 110 ? (a-110)/2+ridge : 0);
}
static void terrain(int checker)
{
    unsigned first = test.triangles;
    static const unsigned order[6] = {0,1,2,0,2,3};
    unsigned scroll = (test.tick*3)%24;
    for (unsigned row = 0; row < 48; ++row) {
        int z0 = 24+(int)row*24-(int)scroll;
        for (unsigned col = 0; col < 16; ++col) {
            int x0 = ((int)col-8)*64;
            int p[4][3] = {{x0,0,z0},{x0+64,0,z0},{x0+64,0,z0+24},{x0,0,z0+24}};
            for (unsigned k = 0; k < 4; ++k)
                p[k][1] = checker ? -58 : terrain_height(p[k][0], row+(k > 1));
            for (unsigned j = 0; j < 6; ++j) {
                unsigned k = order[j];
                unsigned color = checker ? 0xffff : col > 5 && col < 10 ? 0xaff8 :
                                 (row+col)%3 ? 0x7ff0 : 0xfed2;
                vertex(p[k][0], p[k][1], p[k][2], color,
                       (k == 1 || k == 2 ? 64 : 0)*256,
                       (k > 1 ? 64 : 0)*256, 100);
            }
        }
    }
    test_draw(1, first, (test.triangles-first)/3, 1, 0, 1);
}
static void rock(int x, int y, int z, unsigned seed)
{
    unsigned angle = (test.tick+seed*17)&255;
    int s = test_sine[angle];
    int c = test_sine[(angle+64)&255];
    int size = 3+(int)(seed%4);
    for (unsigned f = 0; f < 20; ++f) {
        unsigned base = seed & 1 ? 0xf49f : 0x4ff6;
        unsigned color = f%3 == 0 ? 0xffff : f%3 == 1 ? base :
                         seed & 1 ? 0x9937 : 0x1cf0;
        for (unsigned j = 0; j < 3; ++j) {
            const int8_t *v = ico[faces[f][j]];
            int rx = (v[0]*c-v[2]*s)*size/65536;
            int rz = (v[0]*s+v[2]*c)*size/65536;
            vertex(x+rx, y+v[1]*size/4, z+rz, color, 252*256, 252*256,
                   f%3 == 0 ? 120 : 35);
        }
    }
}
static void ring(int x, int y, int z)
{
    /* Sixteen segments; four sides form an actual octagonal-section solid tube. */
    static const unsigned order[6] = {0,1,2,0,2,3};
    for (unsigned i = 0; i < 16; ++i) for (unsigned side = 0; side < 4; ++side) {
        int p[4][3];
        for (unsigned k = 0; k < 4; ++k) {
            unsigned a = ((i+(k == 1 || k == 2))*16)&255;
            unsigned edge_side = (side+(k > 1))%4;
            int radius = edge_side < 2 ? 38 : 32;
            p[k][0] = x+test_sine[(a+64)&255]*radius/16384;
            p[k][1] = y+test_sine[a]*radius/16384;
            p[k][2] = z+(edge_side == 0 || edge_side == 3 ? -3 : 3);
        }
        unsigned color = side == 0 ? 0xffef : side == 1 ? 0xfd43 : 0xff00;
        for (unsigned j = 0; j < 6; ++j) {
            const int *v = p[order[j]];
            vertex(v[0], v[1], v[2], color, 252*256, 252*256, 90);
        }
    }
}
static void aircraft(void)
{
    static const int p[7][3] = {{0,-8,24},{-10,-10,15},{10,-10,15},
        {0,-6,16},{0,-12,13},{-3,-10,12},{3,-10,12}};
    static const uint8_t f[8][3] = {{0,1,3},{0,3,2},{0,4,1},{0,2,4},
        {1,4,5},{2,6,4},{3,5,6},{3,6,2}};
    for (unsigned i = 0; i < 8; ++i) for (unsigned j = 0; j < 3; ++j) {
        const int *v = p[f[i][j]];
        test_vertex(v[0]/2+test.player_x/20, v[1]-5, v[2]+18, i%3 ? 0x3fff : 0xffff,
                    252*256, 252*256, 100);
    }
}
void test3d_scene(void)
{
    unsigned first = test.quads_count;
    /* GPU quads, a stepped saturated sky gradient behind all geometry. */
    for (unsigned band = 0; band < 6; ++band)
        test_rect(0, (int)band*56, 640, 56, 9+band%5);
    test_draw(0, first, test.quads_count-first, 0, 0, 0);
    terrain(test.mode == 2);
    unsigned start = test.triangles;
    if (test.mode != 2) {
        unsigned count = test.mode == 1 ? rocks[test.level] : 240;
        for (unsigned i = 0; i < count; ++i) {
            unsigned seed = i*2654435761u;
            int z = 80+(int)((seed/17-test.tick*3)%1120);
            int x = (int)((seed>>12)%900)-450;
            int y = -20+(int)((seed>>23)%190);
            rock(x, y, z, i);
        }
        for (unsigned i = 0; i < 6; ++i) {
            unsigned gate = test.tick/90+i;
            int z = 300+(int)i*270-(int)(test.tick%90)*3;
            if (z > 8)
                ring(test_sine[(gate*53)&255]*60/16384,
                     10+test_sine[(gate*79)&255]*24/16384, z);
        }
        aircraft();
    }
    test_draw(1, start, (test.triangles-start)/3, 0, 0, 1);
    first = test.quads_count;
    if (test.mode == 2) {
        static const char *filters[3] = {"NEAREST", "BILINEAR", "TRILINEAR"};
        test_text(520, 56, filters[test.filter], 1);
        test_text(168, 288, "PERSPECTIVE / 7 MIP LEVELS", 7);
    } else {
        test_text(520, 56, "FLY THRU", 1);
        char text[32];
        snprintf(text, sizeof(text), "RINGS %u", ring_passed);
        test_text(520, 72, text, 7);
        test_rect(317, 177, 6, 2, 1);
        test_rect(319, 175, 2, 6, 1);
    }
    test_draw(0, first, test.quads_count-first, 0, 1, 0);
}
