/* File: main.c
 * Spec: S-0b board example.
 * Description: Run the shared GPU example on the board display clock.
 * Clock domain: clk_sys.
 */
#include "hello.h"
#include "plat.h"
int main(void)
{
    hello_init();
    for (unsigned frame = 1;; ++frame) {
        hello_frame(frame);
        plat_wait_vsync();
    }
}
