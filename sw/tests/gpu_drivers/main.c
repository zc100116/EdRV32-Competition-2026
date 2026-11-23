/* File: main.c
 * Spec: gpu-soc-testplan BSP build; GPU 2.3, 2.9.
 * Description: Link GPU/AUD/ES8156 and check representative command/record encodings.
 * Clock domain: clk_sys software; no engine command submission.
 */
#include "test.h"
int main(void)
{
    test_init();
    struct gpu_command command;
    gpu_set_target(&command, &(struct gpu_set_target_args){
        .tgt_y0 = 180u, .sc_y0 = 180u, .sc_x1 = 640u, .sc_y1 = 360u,
        .vp_w = 640u, .vp_h = 360u
    });
    test_equal("SET_TARGET opcode", 5u, command.word[0]);
    test_equal("SET_TARGET stripe", 0x00b40000u, command.word[1]);
    test_equal("SET_TARGET bounds", 0x01680280u, command.word[3]);
    test_equal("SET_TARGET viewport", 0x01680280u, command.word[5]);
    gpu_clear(&command, &(struct gpu_clear_args){
        .color = 0xf800u, .depth = 65535u, .stencil = 0x5au,
        .en_color = 1u, .en_depth = 1u, .en_stencil = 1u
    });
    test_equal("CLEAR color/depth", 0xfffff800u, command.word[1]);
    test_equal("CLEAR enables", 0x0000075au, command.word[2]);
    test_equal("CLEAR reserved", 0u, command.word[7]);
    uart_puts("PASS GPU BSP encoding\r\n");
    test_finish(0u);
}
