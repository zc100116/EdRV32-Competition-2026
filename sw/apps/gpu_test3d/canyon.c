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
static unsigned hit_flash;
static unsigned gate_flash;
static int gate_x;
static int gate_y;
static unsigned collect_flash;
void test3d_capture(unsigned event)
{
    if (event == 3) {
        gate_flash = 30;
        gate_x = camera_x;
        gate_y = camera_y;
        test.score += 100;
        ++ring_passed;
    }
    if (event == 4) {
        hit_flash = 18;
        test.health -= 8;
    }
    if (event == 5) test.tick = 40;
}
static int lane_x(unsigned seed)
{
    return (seed&1024 ? -1 : 1)*(100+(int)((seed>>12)%350));
}
static int drone_x(unsigned i)
{
    return test_sine[(test.tick+i*85)&255]*90/16384;
}
static int gem_x(unsigned index)
{
    return (index&1 ? 1 : -1)*(34+test_sine[(index*37)&255]*10/16384);
}
static unsigned blend_color(unsigned color, unsigned distance)
{
    if (distance > 1400) distance = 1400;
    unsigned r = ((color>>11)&31)*8;
    unsigned g = ((color>>5)&63)*4;
    unsigned b = (color&31)*8;
    return test_color((r*(1800-distance)+140*distance)/1800,
                      (g*(1800-distance)+140*distance)/1800,
                      (b*(1800-distance)+205*distance)/1800);
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
    hit_flash = 0;
    gate_flash = 0;
    collect_flash = 0;
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
    camera_x = test.player_x+(hit_flash ? ((test.tick&1) ? 3 : -3) : 0);
    camera_y = test.player_y;
    if (hit_flash) --hit_flash;
    if (gate_flash) --gate_flash;
    if (collect_flash) --collect_flash;
    if (test.mode != 2 && test.tick%60 == 0) {
        unsigned gem = test.tick/60-1;
        int x = gem_x(gem);
        int dx = test.player_x-x;
        int dy = test.player_y;
        if (dx*dx+dy*dy < 24*24) {
            test.score += 25;
            collect_flash = 20;
            test_sound(3);
        }
    }
    if (test.mode == 2) return;
    for (unsigned i = 0; i < 3; ++i) {
        unsigned age = (test.tick+i*40)%120;
        int dx = test.player_x-test_sine[((test.tick-age)+i*85)&255]*90/16384;
        int dy = test.player_y-15;
        if (age == 105 && dx*dx+dy*dy < 24*24) {
            test.health = test.health > 8 ? test.health-8 : 100;
            hit_flash = 18;
            test_sound(1);
        }
    }
    if (test.tick%90 == 0) {
        unsigned gate = test.tick/90-1;
        int gx = test_sine[(gate*53)&255]*60/16384;
        int gy = 10+test_sine[(gate*79)&255]*24/16384;
        int dx = test.player_x-gx;
        int dy = test.player_y-gy;
        if (dx*dx+dy*dy < 34*34) {
            test.score += 100;
            ++ring_passed;
            gate_flash = 30;
            gate_x = gx;
            gate_y = gy;
            test_sound(3);
        } else {
            if (test.health > 5) test.health -= 5;
            hit_flash = 18;
            test_sound(1);
        }
    }
}
static int terrain_height(int x, unsigned row)
{
    int a = x < 0 ? -x : x;
    int ridge = (test_sine[(row*13)&255]+16384)*22/32768;
    return -82+(a > 140 ? (a-140)*6/5+ridge : 0);
}
static void terrain(int texture_test)
{
    static const unsigned order[6] = {0,1,2,0,2,3};
    unsigned scroll = (test.tick*3)%24;
    for (unsigned material = 0; material < (texture_test ? 1u : 3u); ++material) {
        unsigned first = test.triangles;
        for (unsigned row = 0; row < 48; ++row) {
            int z0 = 24+(int)row*24-(int)scroll;
            for (unsigned col = 0; col < 16; ++col) {
                unsigned surface = col > 5 && col < 10 ? 2 : col < 4 || col > 11 ? 1 : 0;
                if (!texture_test && surface != material) continue;
                int x0 = ((int)col-8)*64;
                int p[4][3] = {{x0,0,z0},{x0+64,0,z0},
                               {x0+64,0,z0+24},{x0,0,z0+24}};
                for (unsigned k = 0; k < 4; ++k) {
                    if (!texture_test)
                        p[k][0] += test_sine[((row+(k > 1))*5+test.tick/8)&255]*32/16384;
                    p[k][1] = texture_test ? -58 : terrain_height(p[k][0], row+(k > 1));
                }
                for (unsigned j = 0; j < 6; ++j) {
                    unsigned k = order[j];
                    unsigned u = (unsigned)(material == 1 ? p[k][2]/4 :
                                            (p[k][0]+512)/4);
                    unsigned v = (unsigned)(material == 1 ? (p[k][1]+128)/4 :
                                            p[k][2]/4);
                    vertex(p[k][0], p[k][1], p[k][2], 0xffff, u*256, v*256,
                           material == 1 ? 65+(int)(col%2)*15+(int)(row/4%2)*10 : 100);
                }
            }
        }
        test_draw(1, first, (test.triangles-first)/3,
                   texture_test ? (test.checker ? 4 : 1) : material == 1 ? 2 : 1, 0, 1);
    }
}
static void rock(int x, int y, int z, unsigned seed)
{
    unsigned angle = (test.tick+seed*17)&255;
    int s = test_sine[angle];
    int c = test_sine[(angle+64)&255];
    int size = 3+(int)(seed%4);
    int crystal[12][3];
    if (seed&1) {
        crystal[0][0] = 0; crystal[0][1] = 28; crystal[0][2] = 0;
        crystal[1][0] = 0; crystal[1][1] = -28; crystal[1][2] = 0;
        for (unsigned i = 0; i < 5; ++i) {
            unsigned a = i*256/5;
            for (unsigned row = 0; row < 2; ++row) {
                unsigned k = 2+i+row*5;
                crystal[k][0] = test_sine[(a+64)&255]*11/16384;
                crystal[k][1] = row ? -9 : 9;
                crystal[k][2] = test_sine[a]*11/16384;
            }
        }
    }
    for (unsigned f = 0; f < 20; ++f) {
        unsigned base = seed&1 ? 0x7fff : 0xffff;
        unsigned color = f%3 == 0 ? 0xffff : f%3 == 1 ? base :
                         seed&1 ? 0x3dba : 0xd5b0;
        unsigned sector = f/4;
        unsigned a = 2+sector;
        unsigned b = 2+(sector+1)%5;
        unsigned crystal_face[4][3] = {{0,a,b},{a,a+5,b+5},{a,b+5,b},{1,b+5,a+5}};
        for (unsigned j = 0; j < 3; ++j) {
            const int8_t *iv = ico[faces[f][j]];
            const int *cv = crystal[crystal_face[f%4][j]];
            int vx = seed&1 ? cv[0] : iv[0];
            int vy = seed&1 ? cv[1] : iv[1];
            int vz = seed&1 ? cv[2] : iv[2];
            if (!(seed&1)) {
                int facet = 80+(int)((seed*17+faces[f][j]*23)%45);
                vx = vx*facet/100;
                vy = vy*facet/100;
                vz = vz*facet/100;
            }
            int rx = (vx*c-vz*s)*size/65536;
            int rz = (vx*s+vz*c)*size/65536;
            vertex(x+rx, y+vy*size/4, z+rz, color,
                   (j == 1 ? (seed&1 ? 31 : 63) : 0)*256, (j == 2 ? 63 : 0)*256,
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
/* Original 176-triangle spacecraft: lofted body, twin engine pods, swept wings,
 * canopy and vertical fins. Geometry stays in world units; skin is a 64px mipmap. */
static void ship_vertex(int x, int y, int z, unsigned color, unsigned u, unsigned v)
{
    test_vertex(x+test.player_x/20, y-17, z, color, u*256, v*256, 100);
}
static void pod(int cx, int cy, int rear, unsigned sides, unsigned rings, int radius)
{
    static const unsigned order[6] = {0,1,2,0,2,3};
    for (unsigned r = 0; r < rings-1; ++r) for (unsigned side = 0; side < sides; ++side) {
        for (unsigned j = 0; j < 6; ++j) {
            unsigned k = order[j];
            unsigned a = ((side+(k == 1 || k == 2))*256/sides)&255;
            unsigned ring_id = r+(k > 1);
            int width = ring_id == rings-1 ? 1 : ring_id == 0 ? radius*3/4 : radius;
            int x = cx+test_sine[(a+64)&255]*width/16384;
            int y = cy+test_sine[a]*width/16384;
            unsigned color = side < sides/2 ? 0xffff : 0x4b37;
            ship_vertex(x, y, rear+(int)ring_id*7, color,
                        side < sides/2 ? 1+(side%2)*14 : 33, ring_id*16);
        }
    }
    for (unsigned cap = 0; cap < 2; ++cap) for (unsigned side = 0; side < sides; ++side) {
        int r = cap ? 1 : radius*3/4;
        int z = rear+(cap ? (int)(rings-1)*7 : 0);
        ship_vertex(cx, cy, z, cap ? 0x3fff : cx ? 0xffa5 : 0x1170, 1, 1);
        for (unsigned j = 0; j < 2; ++j) {
            unsigned a = ((side+j)*256/sides)&255;
            ship_vertex(cx+test_sine[(a+64)&255]*r/16384,
                        cy+test_sine[a]*r/16384, z,
                        cap ? 0x3fff : cx ? 0xfd29 : 0x1170, 1, 1);
        }
    }
}
static void aircraft(void)
{
    pod(0, 0, 44, 8, 4, 4);
    pod(-6, -1, 40, 6, 3, 3);
    pod(6, -1, 40, 6, 3, 3);
    static const int wing[8][3] = {
        {3,0,59},{18,-1,44},{17,-1,40},{4,-1,46},
        {3,-2,59},{18,-3,44},{17,-3,40},{4,-3,46}
    };
    static const unsigned faces_wing[12][3] = {
        {0,1,2},{0,2,3},{4,6,5},{4,7,6},{0,4,5},{0,5,1},
        {1,5,6},{1,6,2},{2,6,7},{2,7,3},{3,7,4},{3,4,0}
    };
    for (int side = -1; side <= 1; side += 2)
        for (unsigned f = 0; f < 12; ++f) for (unsigned j = 0; j < 3; ++j) {
            const int *p = wing[faces_wing[f][j]];
            ship_vertex(p[0]*side, p[1], p[2], f < 2 ? 0xffff : 0x2370,
                        p[0] > 12 ? 24 : 2, f < 2 ? 8 : 40);
        }
    /* Cyan canopy rises above the fuselage and has a clean navy base. */
    static const int canopy[6][3] = {
        {-2,3,51},{2,3,51},{-2,3,61},{2,3,61},{-1,6,55},{1,6,55}
    };
    static const unsigned cf[8][3] = {
        {0,1,5},{0,5,4},{2,4,5},{2,5,3},{0,4,2},{1,3,5},{0,2,3},{0,3,1}
    };
    for (unsigned f = 0; f < 8; ++f) for (unsigned j = 0; j < 3; ++j) {
        const int *p = canopy[cf[f][j]];
        ship_vertex(p[0], p[1], p[2], f < 4 ? 0x3fff : 0x1170, 24, 10);
    }
    for (int side = -1; side <= 1; side += 2) {
        static const int fin[4][3] = {{14,-1,42},{14,5,40},{14,3,49},{13,-1,47}};
        static const unsigned ff[4][3] = {{0,1,2},{0,2,3},{2,1,0},{3,2,0}};
        for (unsigned f = 0; f < 4; ++f) for (unsigned j = 0; j < 3; ++j) {
            const int *p = fin[ff[f][j]];
            ship_vertex(p[0]*side, p[1], p[2], f%2 ? 0xffff : 0x3fff, 24, 8);
        }
    }
}
static void billboard(int x, int y, int z, int size, unsigned color)
{
    static const unsigned order[6] = {0,1,2,0,2,3};
    for (unsigned j = 0; j < 6; ++j) {
        unsigned k = order[j];
        vertex(x+(k == 1 || k == 2 ? size : -size), y+(k > 1 ? -size : size), z,
               color, (k == 1 || k == 2 ? 15 : 0)*256, (k > 1 ? 47 : 32)*256, 100);
    }
}
static void drone(unsigned id)
{
    static const int p[6][3] = {{0,3,-14},{-24,0,1},{24,0,1},
                               {0,7,6},{0,-4,6},{0,0,13}};
    static const unsigned f[8][3] = {{0,1,3},{0,3,2},{0,4,1},{0,2,4},
                                    {1,5,3},{2,3,5},{1,4,5},{2,5,4}};
    int x = drone_x(id);
    int y = 15+test_sine[(test.tick*2+id*70)&255]*12/16384;
    int z = 170+(int)id*95;
    for (unsigned i = 0; i < 8; ++i) for (unsigned j = 0; j < 3; ++j) {
        const int *v = p[f[i][j]];
        vertex(x+v[0], y+v[1], z+v[2], i%2 ? 0xfdbb : 0xffff,
               (j == 1 ? 63 : 32)*256, (j == 2 ? 63 : 0)*256, 100);
    }
    for (int side = -1; side <= 1; side += 2)
        for (unsigned f = 0; f < 20; ++f) for (unsigned j = 0; j < 3; ++j) {
            const int8_t *p = ico[faces[f][j]];
            vertex(x+side*17+p[0]/4, y+p[1]/4, z+3+p[2]/3,
                   f%3 ? 0xffff : 0xfb8f, 40*256, 12*256, 100);
        }
}
void test3d_scene(void)
{
    unsigned first = test.quads_count;
    for (unsigned band = 0; band < 18; ++band)
        test_rect(0, (int)band*20, 640, 20, 10+band*4/17);
    test_draw(0, first, test.quads_count-first, 0, 0, 0);
    first = test.quads_count;
    for (unsigned i = 0; i < 7; ++i)
        test_quad((int)((i*133+test.tick/3)%780)-128, 65+(int)(i%3)*22,
                  96, 32, 160, 96, 0, 95);
    test_draw(0, first, test.quads_count-first, 6, 1, 0);
    terrain(test.mode == 2);
    if (test.mode != 2) {
        unsigned count = test.mode == 1 ? rocks[test.level] : 64;
        for (unsigned material = 0; material < 2; ++material) {
            unsigned start = test.triangles;
            for (unsigned i = material; i < count; i += 2) {
                unsigned seed = i*2654435761u;
                int z = 80+(int)((seed/17-test.tick*3)%1120);
                int x = lane_x(seed);
                int y = terrain_height(x, (unsigned)z/24)+12;
                rock(x, y, z, i);
            }
            test_draw(1, start, (test.triangles-start)/3, material ? 5 : 3, 0, 1);
        }
        unsigned gem_start = test.triangles;
        for (unsigned i = 0; i < 3; ++i) {
            unsigned gem = test.tick/60+i;
            rock(gem_x(gem), 0,
                 210+(int)i*180-(int)(test.tick%60)*3, 101+i*2);
        }
        test_draw(1, gem_start, (test.triangles-gem_start)/3, 5, 0, 1);
        unsigned start = test.triangles;
        for (unsigned i = 0; i < 6; ++i) {
            unsigned gate = test.tick/90+i;
            int z = 300+(int)i*270-(int)(test.tick%90)*3;
            if (z > 8)
                ring(test_sine[(gate*53)&255]*60/16384,
                     10+test_sine[(gate*79)&255]*24/16384, z);
        }
        test_draw(1, start, (test.triangles-start)/3, 0, 0, 1);
        start = test.triangles;
        aircraft();
        for (unsigned i = 0; i < 3; ++i) drone(i);
        test_draw(1, start, (test.triangles-start)/3, 5, 0, 1);
        /* Glowing ammunition and engine particles use alpha-shaped textures. */
        start = test.triangles;
        for (unsigned i = 0; i < 3; ++i) {
            unsigned age = (test.tick+i*40)%120;
            int x = test_sine[((test.tick-age)+i*85)&255]*90/16384;
            billboard(x, 15, 350-(int)age*3, 6, 0xfb8e);
            billboard(drone_x(i), 15, 184+(int)i*95, 9, 0xfbcf);
        }
        for (unsigned i = 0; i < 8; ++i) {
            unsigned age = (test.tick+i*3)%24;
            for (int side = -1; side <= 1; side += 2)
                billboard(camera_x+side*6+(int)(i%3)-1,
                          camera_y-18-(int)(age/18), 39-(int)age/9,
                          1, i%3 ? 0xfdc5 : 0xffff);
        }
        for (unsigned i = 0; i < 6; ++i) {
            unsigned gate = test.tick/90+i;
            int z = 300+(int)i*270-(int)(test.tick%90)*3;
            if (z <= 8) continue;
            int x = test_sine[(gate*53)&255]*60/16384;
            int y = 10+test_sine[(gate*79)&255]*24/16384;
            for (unsigned j = 0; j < 32; ++j) {
                unsigned a = j*8;
                billboard(x+test_sine[(a+64)&255]*35/16384,
                          y+test_sine[a]*35/16384, z-4, 5, 0xffa5);
            }
        }
        for (unsigned i = 0; i < 3; ++i) {
            unsigned gem = test.tick/60+i;
            int x = gem_x(gem);
            int z = 210+(int)i*180-(int)(test.tick%60)*3;
            billboard(x, 0, z-12, 10+(int)(test.tick%12)/2, 0x7fff);
        }
        if (collect_flash) for (unsigned i = 0; i < 16; ++i) {
            unsigned a = (i*16+test.tick*3)&255;
            int r = (20-(int)collect_flash)*2;
            billboard(camera_x+test_sine[(a+64)&255]*r/16384,
                      camera_y+test_sine[a]*r/16384, 60, 2, 0x7fff);
        }
        /* Crystal sparkle uses the same positions as the textured crystal meshes. */
        for (unsigned i = 1; i < count; i += 12) {
            unsigned seed = i*2654435761u;
            int z = 80+(int)((seed/17-test.tick*3)%1120);
            int x = lane_x(seed);
            billboard(x, terrain_height(x, (unsigned)z/24)+12, z,
                      7+(int)(test.tick+i)%4, 0x7fff);
        }
        if (gate_flash) for (unsigned i = 0; i < 48; ++i) {
            unsigned a = (i*41)&255;
            int r = (30-(int)gate_flash)*3;
            billboard(gate_x+test_sine[(a+64)&255]*r/16384,
                      gate_y+test_sine[a]*r/16384, 65+(int)i*2, 2, i%2 ? 0xffa5 : 0x7fff);
        }
        test_draw(1, start, (test.triangles-start)/3, 0, 2, 1);
    }
    if (test.mode != 2) {
        unsigned start = test.triangles;
        static const unsigned order[6] = {0,1,2,0,2,3};
        for (unsigned i = 0; i < 18; ++i) {
            unsigned a = (i*41)&255;
            int radius = 95+(int)((test.tick*4+i*13)%110);
            int dx = test_sine[(a+64)&255];
            int dy = test_sine[a];
            int x = 320+dx*radius*2/16384;
            int y = 180+dy*radius/16384;
            for (unsigned j = 0; j < 6; ++j) {
                unsigned k = order[j];
                int far = k == 1 || k == 2;
                int side = k > 1 ? 1 : -1;
                test_vertex(x+(far ? dx*22/16384 : 0)+dy*side/16384,
                            y+(far ? dy*14/16384 : 0)-dx*side/16384, 0, 0x3fff,
                            (far ? 6 : 1)*256, (k > 1 ? 5 : 2)*256, 0);
            }
        }
        test_draw(1, start, (test.triangles-start)/3, 0, 2, 0);
        if (hit_flash) {
            start = test.triangles;
            test_sprite(0, 48, 640, 288, 19, 0, 0, 0);
            for (unsigned i = start; i < test.triangles; ++i)
                test.vertices[i].word[2] = (test.vertices[i].word[2]&0xffff) | (0xf800u << 16);
            test_draw(1, start, 2, 0, 1, 0);
        }
    }
    first = test.quads_count;
    if (test.mode != 2) {
        if (hit_flash) for (unsigned y = 48; y < 336; y += 8) {
            test_quad((test.tick&1) ? 0 : 3, (int)y, 8, 8, 0, 0, 3, hit_flash*10);
            test_quad(630, (int)y, 8, 8, 0, 0, 3, hit_flash*10);
        }
    }
    test_draw(0, first, test.quads_count-first, 0, 2, 0);
}
void test3d_hud(void)
{
    if (test.mode == 2) {
        static const char *filters[3] = {"NEAREST", "BILINEAR", "TRILINEAR"};
        test_panel(436, 8, 192, 40, 2);
        test_text(444, 12, filters[test.filter], 1);
        test_text(444, 30, test.checker ? "棋盘 / 7 MIP" : "纹理 / 7 MIP", 2);
    } else {
        test_panel(10, 50, 216, 40, 7);
        test_quad(18, 58, 12, 12, 68, 112, 0, 255);
        test_text(38, 56, "任务 穿过下一个光环", 1);
        char text[64];
        snprintf(text, sizeof(text), "距离 %u 米  速度 180", 300-(test.tick%90)*3);
        test_text(20, 74, text, 7);
        test_panel(540, 8, 88, 66, 2);
        test_text(552, 12, "方向", 2);
        unsigned gate = test.tick/90;
        int dx = test_sine[(gate*53)&255]*60/16384-test.player_x;
        int dy = 10+test_sine[(gate*79)&255]*24/16384-test.player_y;
        test_rect(580, 48, 3, 3, 1);
        test_rect(580+dx/4, 48-dy/3, 5, 5, 7);
        test_rect(317, 177, 6, 2, 1);
        test_rect(319, 175, 2, 6, 1);
        if (gate_flash) test_text(260, 110, "得分 +100", 7);
        else if (collect_flash) test_text(260, 110, "得分 +25", 2);
        if (hit_flash) test_text(272+(test.tick&1 ? 3 : -3), 130, "敌机警告", 3);
    }
}
