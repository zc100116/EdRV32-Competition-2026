/* File: png.h
 * Spec: S-0b headless frontend.
 * Description: Standalone RGB PNG output interface.
 * Clock domain: host.
 */
#ifndef GPU_PC_PNG_H
#define GPU_PC_PNG_H
#include <stdint.h>
void pc_png_write(const char *path, const uint32_t *pixels);
#endif
