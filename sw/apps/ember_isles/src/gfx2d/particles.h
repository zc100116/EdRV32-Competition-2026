/* File: particles.h; art-plan 6.1/tech 2. GPU object-owned effects, CPU clock. */
#ifndef EMBER_GFX_PARTICLES_H
#define EMBER_GFX_PARTICLES_H
#include "gpu.h"
struct ember_sim;
typedef void (*ember_particle_draw)(int id,int x,int y,unsigned scale,unsigned alpha,unsigned additive,unsigned element);
void ember_particles_init(void);
void ember_particles_prepare(const struct ember_sim *sim,unsigned advance,unsigned consume,ember_particle_draw draw);
unsigned ember_particles_commands(struct gpu_command *commands,unsigned advance);
unsigned ember_particles_numbers(struct gpu_command *commands,unsigned stripe);
struct gpu_range ember_particles_source(void);
struct gpu_range ember_particles_result(void);
struct gpu_range ember_numbers_source(void);
unsigned ember_particles_alive(void);
unsigned ember_numbers_alive(void);
#endif
