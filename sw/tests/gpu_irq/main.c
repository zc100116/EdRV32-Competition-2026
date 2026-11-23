/* File: main.c
 * Spec: gpu-soc-testplan ST-11; GPU 2.9, 5; visual SoC 7.4.
 * Description: Exercise DONE/PLIC and cached object, hit and release list handoff.
 * Clock domain: clk_sys software; GPU command execution clk_gpu.
 */
#include "../gpu_drivers/test.h"
static volatile uint32_t completed;
static struct gpu_event last;

static void complete(const struct gpu_event *event, void *context)
{
    (void)context;
    last = *event;
    completed = 1u;
}

static void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    unsigned int source = plic_claim();
    test_equal("GPU PLIC source", EDRV32_PLIC_SOURCE_GPU, source);
    gpu_irq_handle();
    plic_complete(source);
}

int main(void)
{
    test_init();
    struct gpu_object *objects = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x10000u);
    uint32_t *hits = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x11000u);
    uint32_t *released = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x12000u);
    struct gpu_command *commands = (void *)(uintptr_t)(EDRV32_DDR_BASE + 0x20000u);
    gpu_object(&objects[0], &(struct gpu_object_args){
        .alive = 1u, .px = 10u * 256u, .py = 10u * 256u, .vx = 256u,
        .col_hw = 2u, .col_hh = 2u, .tgt_mask = 1u
    });
    gpu_object(&objects[1], &(struct gpu_object_args){.alive = 1u, .life = 1u});
    gpu_live_rect(0, 0, 640, 360);
    gpu_collision_target(0, 8, 8, 16, 16);
    gpu_object_lists(hits, 8u, released, 8u);
    gpu_obj_step(commands, &(struct gpu_obj_step_args){
        .addr = gpu_physical(objects), .count = 2u, .step = 1u
    });
    struct gpu_range source = {(uintptr_t)objects, 64u};
    struct gpu_range results[] = {
        {(uintptr_t)objects, 64u}, {(uintptr_t)hits, 32u}, {(uintptr_t)released, 32u}
    };
    struct gpu_batch batch = {commands, 1u, &source, 1u, results, 3u};
    uint32_t before = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_DONE_COUNT_OFFSET);
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap_handler));
    gpu_irq_register(1u, complete, 0);
    plic_set_threshold(0u);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11));
    __asm__ volatile ("csrsi mstatus, 8");
    gpu_submit(&batch);
    while (completed == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8");
    test_equal("GPU error", 0u, last.error);
    test_equal("DONE", EDRV32_GPU_IRQ_STAT_DONE_MASK, last.irq);
    test_equal("DONE_COUNT", before + 1u, last.done_count);
    test_equal("hits", 1u, last.hit_count);
    test_equal("released", 1u, last.free_count);
    test_equal("alive", 1u, last.alive_count);
    test_equal("object status", 0u, last.object_status);
    test_equal("hit object", 0u, gpu_hit_object(hits[0]));
    test_equal("hit target", 0u, gpu_hit_target(hits[0]));
    test_equal("free object", 1u, gpu_free_object(released[0]));
    test_equal("position writeback", 11u * 256u,
               objects[0].word[EDRV32_GPU_OBJ_PX_OFFSET / 4u] & EDRV32_GPU_OBJ_PX_MASK);
    test_equal("expired object", 0u,
               objects[1].word[EDRV32_GPU_OBJ_ALIVE_OFFSET / 4u] & EDRV32_GPU_OBJ_ALIVE_MASK);
    uart_puts("PASS ST-11 GPU IRQ cache\r\n");
    test_finish(0u);
}
