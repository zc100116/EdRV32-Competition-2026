/* File: main.c
 * Spec: rnd-spec 2.6/5.4; DISP 5.3; Task B3-3a board acceptance.
 * Description: Draw the shared scenes, print target CRCs, then display both layers.
 * Clock domain: clk_sys CPU; rendering/display engines in clk_mem.
 */
#include "scenes.h"
#include "cache.h"
#include "disp.h"
#include "uart.h"

_Alignas(4096) static uint8_t arena[BOARD_ARENA_BYTES];
_Alignas(64) static struct rnd_command commands[BOARD_MAX_COMMANDS];

static uint32_t crc32(const uint8_t *data, uint32_t bytes)
{
    uint32_t crc = 0xffffffffu;
    for (uint32_t i = 0; i < bytes; ++i) {
        crc ^= data[i];
        for (unsigned int bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
        }
    }
    return ~crc;
}

static void hex32(uint32_t value)
{
    const char *digits = "0123456789abcdef";
    uart_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc((uint8_t)digits[(value >> shift) & 15u]);
    }
}

static void error_print(uint32_t error, uint32_t descriptor)
{
    uart_puts("RND ERR_CODE=");
    hex32(error);
    uart_puts(" CUR_DESC=");
    hex32(descriptor);
    uart_puts("\r\n");
}

int main(void)
{
    uart_init();
    /* BIOS may have left a display active; R3 requires stopped IDLE before writing. */
    engine_control(ENGINE_DISP, 0);
    while (!(engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK)) {
    }
    for (unsigned int i = 0; i < BOARD_DATA_BYTES; ++i) {
        arena[BOARD_DATA_OFFSET + i] = board_data[i];
    }
    /* BSS supplies the initially transparent/black surfaces. They are RND inputs. */
    cache_clean((uintptr_t)arena, sizeof(arena));
    uint32_t base = rnd_physical(arena);
    for (unsigned int group = 0; group < BOARD_GROUP_COUNT; ++group) {
        unsigned int fmt = board_formats[group];
        struct rnd_range source = {arena + BOARD_DATA_OFFSET, BOARD_DATA_BYTES};
        struct rnd_range target = {arena + board_bases[fmt], board_sizes[fmt]};
        struct rnd_batch batch = {commands, (uint16_t)board_commands(group, base, commands),
                                  &source, 1, &target, 1};
        rnd_submit(&batch);
        struct rnd_result result = rnd_wait();
        error_print(result.error, result.cur_desc);
        if (result.error) {
            for (;;) {
                __asm__ volatile ("wfi");
            }
        }
        /* rnd_wait has invalidated exactly the target before this CPU read. */
        uart_puts("RND ");
        uart_puts(board_names[group]);
        uart_puts(" crc=");
        hex32(crc32(target.address, target.bytes));
        uart_puts("\r\n");
    }
    disp_l0_scroll(0, 0);
    disp_l1_geometry(0, 0, 1280, 720, 255);
    for (unsigned int layer = 0; layer < 2; ++layer) {
        disp_submit((enum disp_layer)layer, base + board_bases[layer], board_strides[layer]);
        disp_layer_enable((enum disp_layer)layer, 1);
    }
    engine_control(ENGINE_DISP, EDRV32_DISP_CTRL_ENABLE_MASK);
    uart_puts("RND display ready\r\n");
    for (;;) {
        __asm__ volatile ("wfi");
    }
}
