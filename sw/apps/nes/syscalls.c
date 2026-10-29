/* File: syscalls.c
 * Spec: Task B3-4b; CLAUDE.md 12.1 fail loudly; SoC 7.5.
 * Description: newlib heap and console in the DDR application, with no filesystem.
 * Clock domain: clk_sys.
 */
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include "edrv32.h"
#ifndef NES_SPIKE
#include "uart.h"
#endif

static unsigned char heap[2 * 1024 * 1024] __attribute__((aligned(16)));
static ptrdiff_t heap_used;

void *_sbrk(ptrdiff_t increment)
{
    if (heap_used + increment < 0 || heap_used + increment > (ptrdiff_t)sizeof(heap)) {
        errno = ENOMEM;
        return (void *)-1;
    }
    void *previous = heap + heap_used;
    heap_used += increment;
    return previous;
}

int _write(int fd, const void *data, size_t length)
{
    (void)fd;
    const unsigned char *text = data;
    for (size_t i = 0; i < length; ++i) {
#ifdef NES_SPIKE
        edrv32_putchar((char)text[i]);
#else
        uart_putc(text[i]);
#endif
    }
    return (int)length;
}

_Noreturn void _exit(int status)
{
#ifndef NES_SPIKE
    uart_drain();
#endif
    edrv32_exit(status);
}

int _close(int fd) { (void)fd; errno = EBADF; return -1; }
int _fstat(int fd, struct stat *status)
{
    (void)fd;
    status->st_mode = 0020000; /* newlib character device */
    return 0;
}
int _isatty(int fd) { (void)fd; return 1; }
int _lseek(int fd, int offset, int whence)
{
    (void)fd; (void)offset; (void)whence;
    errno = ESPIPE;
    return -1;
}
int _read(int fd, void *data, size_t length)
{
    (void)fd; (void)data; (void)length;
    errno = ENOSYS;
    return -1;
}
int _open(const char *path, int flags, ...)
{
    (void)path; (void)flags;
    errno = ENOSYS;
    return -1;
}
int _getpid(void) { return 1; }
int _kill(int pid, int signal)
{
    (void)pid; (void)signal;
    errno = ENOSYS;
    return -1;
}
