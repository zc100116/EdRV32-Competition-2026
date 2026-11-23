/* File: runtime.c
 * Spec: S-0b standalone RISC-V C library support.
 * Description: Bind newlib's console and heap requests to UART and static DDR.
 * Clock domain: clk_sys.
 */
#include "uart.h"
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
static uint8_t heap[65536] __attribute__((aligned(16)));
static ptrdiff_t heap_end;
void *_sbrk(ptrdiff_t increment)
{
    ptrdiff_t next = heap_end + increment;
    if (next < 0 || (size_t)next > sizeof(heap)) { errno = ENOMEM; return (void *)-1; }
    void *result = heap + heap_end;
    heap_end = next;
    return result;
}
int _write(int file, const void *buffer, size_t size)
{
    (void)file;
    const uint8_t *bytes = buffer;
    for (size_t i = 0; i < size; ++i) uart_putc(bytes[i]);
    return (int)size;
}
int _read(int file, void *buffer, size_t size)
{
    (void)file;
    uint8_t *bytes = buffer;
    for (size_t i = 0; i < size; ++i) bytes[i] = uart_getc();
    return (int)size;
}
int _fstat(int file, struct stat *status)
{
    (void)file;
    memset(status, 0, sizeof(*status));
    status->st_mode = S_IFCHR;
    return 0;
}
int _isatty(int file) { (void)file; return 1; }
int _close(int file) { (void)file; return 0; }
off_t _lseek(int file, off_t offset, int origin)
{
    (void)file; (void)offset; (void)origin;
    errno = ESPIPE;
    return -1;
}
int _getpid(void) { return 1; }
int _kill(int pid, int signal)
{
    (void)pid; (void)signal;
    errno = EINVAL;
    return -1;
}
