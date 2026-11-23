/* File: hello.h
 * Spec: S-0b end-to-end example.
 * Description: Shared board and host demo entry points.
 * Clock domain: CPU or host.
 */
#ifndef GPU_HELLO_H
#define GPU_HELLO_H
void hello_init(void);
void hello_frame(unsigned frame);
#endif
