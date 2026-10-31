/* File: main.c
 * Spec: SoC 7.5; design 2026-10-29-b2-software 3.1/3.4/3.5.
 * Description: SRAM B2 application, UART/KEY controls and interrupt dispatch.
 * Clock domain: clk_sys.
 */
#include "runtime.h"
#include "parameters.h"
#include "i2c.h"

struct demo_state demo;
static volatile uint8_t uart_queue[128];
static volatile uint32_t uart_written;
static volatile uint32_t uart_read;
static char line[192];
static unsigned int line_length;
static unsigned int line_invalid;
static unsigned int previous_cr;

_Noreturn void demo_fail(const char *reason, enum engine_id engine)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    struct engine_event event = engine_poll(engine);
    info_text("DEMO ERROR", reason);
    info_number("engine", (unsigned int)engine);
    info_hex("IRQ_STAT", event.irq);
    info_hex("STATUS", event.status);
    info_hex("ERR_CODE", event.error);
    info_hex("DONE_COUNT", event.done_count);
    info_text("DEMO stopped", "reset to restart this scene");
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

void demo_wait_idle(enum engine_id engine)
{
    for (;;) {
        struct engine_event event = engine_poll(engine);
        if (event.error || (event.status & EDRV32_VIN_STATUS_ERROR_MASK)) {
            demo_fail("waiting for engine IDLE", engine);
        }
        if (event.status & EDRV32_VIN_STATUS_IDLE_MASK) {
            return;
        }
    }
}

static void uart_event(void)
{
    uint32_t irq = mmio_read32(EDRV32_UART0_BASE + UART_IRQ_STAT);
    if (irq & (UART_IRQ_RX_OVERRUN | UART_IRQ_FRAME_ERR)) {
        info_hex("UART IRQ_STAT", irq);
        info_hex("UART STATUS", mmio_read32(EDRV32_UART0_BASE + UART_STATUS));
        demo_fail("UART receive", ENGINE_VIN);
    }
    while (!(mmio_read32(EDRV32_UART0_BASE + UART_STATUS) & UART_STATUS_RX_EMPTY)) {
        uint8_t byte = uart_getc();
        uart_queue[uart_written % sizeof uart_queue] = byte;
        ++uart_written;
    }
    mmio_write32(EDRV32_UART0_BASE + UART_IRQ_STAT, irq);
}

static void __attribute__((interrupt("machine"), aligned(4))) demo_interrupt(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    if (demo.sleeping) {
        demo.idle_cycles += (uint32_t)(clint_time() - demo.sleep_start);
        demo.sleeping = 0;
    }
    if (cause == 0x80000007u) {
        demo_monitor_tick();
    } else if (cause == 0x8000000bu) {
        unsigned int source = plic_claim();
        if (source == EDRV32_PLIC_SOURCE_UART0) {
            uart_event();
        } else if (source == EDRV32_PLIC_SOURCE_GPIO0) {
            uint16_t keys = gpio_irq_status();
            demo.keys |= keys & 0x0eu;
            gpio_irq_clear(keys);
        } else if (source != EDRV32_PLIC_SOURCE_NONE) {
            engine_irq_handle(source);
        }
        if (source != EDRV32_PLIC_SOURCE_NONE) {
            plic_complete(source);
        }
    } else {
        uint32_t pc;
        uint32_t value;
        __asm__ volatile ("csrr %0, mepc" : "=r"(pc));
        __asm__ volatile ("csrr %0, mtval" : "=r"(value));
        info_hex("mcause", cause);
        info_hex("mepc", pc);
        info_hex("mtval", value);
        demo_fail("CPU trap", ENGINE_VIN);
    }
}

static void menu(void)
{
    info_text("Demo commands", demo_scene_allowed(1) ?
              "s1 | s2 | status | help" : "s2 | status | help");
    info_text("PIX", "pix bypass | pix brightness | pix gamma | pix gaussian | pix sobel");
    info_text("PIX parameters", "pix set BC CONTRAST BRIGHT GAMMA_EN GAMMA S1 S2 GRAY BIN THRESH INV");
    info_text("GEO parameters", "geo set EN ANGLE SX SY TX TY MX MY (0.1 deg / per mille / px)");
    info_text("GEO", "geo off | geo rotate | geo scale");
    info_text("Output", "output hdmi | output eth | output both | fps 1..60");
    info_text("Monitor", "sample 10..1000 (Hz), default 100");
    info_text("KEY", demo_scene_allowed(1) ?
              "KEY2 scene; KEY3 PIX; KEY4 GEO (PIX/GEO require S2)" :
              "KEY2 requires s2; KEY3 PIX; KEY4 GEO");
}

void demo_status(void)
{
    info_number("Scene", demo.scene);
    info_number("PIX mode", demo.pix);
    info_number("GEO mode", demo.geo);
    info_number("Output mode", demo.output);
    info_number("Requested video fps", demo.fps);
    info_number("Video divisor", demo_frame_divisor(DEMO_CAMERA_FPS, demo.fps));
    info_number("Monitor Hz", demo.sample_hz);
    info_number("VIN camera0 frames", engine_perf(ENGINE_VIN, 0));
    info_number("VIN camera1 frames", engine_perf(ENGINE_VIN, 1));
    info_number("VIN CH0 frames", engine_perf(ENGINE_VIN, 3));
    info_number("VIN CH2 frames", engine_perf(ENGINE_VIN, 5));
    info_number("VIN CH0 overflow", engine_perf(ENGINE_VIN, 6));
    info_number("VIN CH2 overflow", engine_perf(ENGINE_VIN, 8));
    demo_scene_status();
    demo_overlay_status();
    info_hex("ETH peer IP", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_IP_OFFSET));
    info_number("ETH peer port", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_PEER_PORT_OFFSET));
    info_hex("ETH STATUS", engine_poll(ENGINE_ETH).status);
    info_number("Video skips (current window)", demo.video_skips);
    info_number("Monitor sequence", demo.monitor_sequence);
    info_number("Monitor dropped records", demo.monitor_dropped);
    info_number("mtime", clint_time());
}

void demo_command_apply(struct demo_command command)
{
    if (command.kind == DEMO_HELP) {
        menu();
    } else if (command.kind == DEMO_STATUS) {
        demo_status();
    } else if (command.kind == DEMO_SCENE && !demo_scene_allowed(command.value)) {
        info_text("Input error", "this board requires s2");
        return;
    } else if ((command.kind == DEMO_PIX || command.kind == DEMO_GEO) && demo.scene != 2u) {
        info_text("Input error", "PIX/GEO controls require s2");
        return;
    } else if (command.kind == DEMO_SAMPLE) {
        uint32_t lock = demo_irq_lock();
        /* Close the old sampling window before changing its duration. */
        demo_monitor_tick();
        demo.sample_hz = command.value;
        demo.deadline = clint_time() + demo.clock_hz / demo.sample_hz;
        clint_set_compare(demo.deadline);
        demo_irq_unlock(lock);
    } else if (command.kind == DEMO_FPS) {
        demo.fps = command.value;
        /* P6 rate units are beat/cycle / 256; 60 fps video needs >111 MB/s payload. */
        mem_xbar_rate(6, demo.fps == 60u ? 32u : EDRV32_MEM_XBAR_RATE_RESET_6);
    } else {
        demo_switch_begin(command);
        demo_switch_wait();
    }
    info_text("Demo command", "OK");
    if (command.kind == DEMO_SCENE || command.kind == DEMO_PIX ||
        command.kind == DEMO_GEO || command.kind == DEMO_OUTPUT) {
        demo_switch_report();
    }
}

static void uart_service(void)
{
    while (uart_read != uart_written) {
        uint8_t byte = uart_queue[uart_read % sizeof uart_queue];
        ++uart_read;
        if (byte == '\n' && previous_cr) {
            previous_cr = 0;
            continue;
        }
        previous_cr = byte == '\r';
        if (byte == '\r' || byte == '\n') {
            line[line_length] = 0;
            struct demo_parameters parameters;
            int parsed = demo_parameters_parse(line, &parameters);
            struct demo_command command;
            if (!line_invalid && parsed == 0) {
                demo_parameters_apply(&parameters);
            } else if (line_invalid || parsed < 0 || demo_parse(line, &command) != 0) {
                info_text("Input error", "unknown command or value; help lists commands");
            } else {
                demo_command_apply(command);
            }
            line_length = 0;
            line_invalid = 0;
        } else if (line_length + 1u < sizeof line) {
            line[line_length++] = (char)byte;
        } else {
            line_invalid = 1;
        }
    }
}

static void keys_service(void)
{
    uint32_t lock = demo_irq_lock();
    uint32_t keys = demo.keys;
    demo.keys = 0;
    demo_irq_unlock(lock);
    if (keys & 2u) {
        demo_command_apply((struct demo_command){DEMO_SCENE, demo.scene == 1u ? 2u : 1u});
    }
    if (keys & 4u) {
        demo_command_apply((struct demo_command){DEMO_PIX, (demo.pix + 1u) % 5u});
    }
    if (keys & 8u) {
        demo_command_apply((struct demo_command){DEMO_GEO, (demo.geo + 1u) % 3u});
    }
}

static void engine_ids(void)
{
    info_hex("VIN ID", mmio_read32(EDRV32_VIN_BASE + EDRV32_VIN_ID_OFFSET));
    info_hex("PIX ID", mmio_read32(EDRV32_PIX_BASE + EDRV32_PIX_ID_OFFSET));
    info_hex("GEO ID", mmio_read32(EDRV32_GEO_BASE + EDRV32_GEO_ID_OFFSET));
    info_hex("DISP ID", mmio_read32(EDRV32_DISP_BASE + EDRV32_DISP_ID_OFFSET));
    demo_scene_ids();
    demo_overlay_ids();
    info_hex("ETH ID", mmio_read32(EDRV32_ETH_BASE + EDRV32_ETH_ID_OFFSET));
    info_hex("MEM_XBAR ID", mmio_read32(EDRV32_MEM_XBAR_BASE + EDRV32_MEM_XBAR_ID_OFFSET));
}

int main(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    demo.clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    demo.scene = 2;
    demo.output = DEMO_HDMI;
    demo.fps = 30;
    demo.sample_hz = 100;
    demo.pair_image = -1;
    demo.pair_input = -1;
    demo.ready_surface = -1;
    demo.active_npu = -1;
    demo.active_geo = -1;
    demo.display_current = -1;
    demo.display_next = -1;
    demo.display_queue = -1;
    demo.tx_surface = -1;
    demo.tx_check_buffer = -1;
    uart_init();
    uart_set_baud(demo.clock_hz, 115200);
    info_text("Demo", demo_version);
    system_info();
    engine_ids();
    for (unsigned int camera = 0; camera < 2; ++camera) {
        uint16_t chip_id;
        if (ov5640_init(camera, demo.clock_hz) ||
            ov5640_chip_id(camera, demo.clock_hz, &chip_id)) {
            info_number("Camera SCCB error", camera);
            info_hex("I2C STATUS", mmio_read32(EDRV32_I2C0_BASE + I2C_STATUS));
            demo_fail("camera initialization/read ID", ENGINE_VIN);
        }
        info_number("Camera", camera);
        info_hex("Camera chip ID", chip_id);
    }
    uintptr_t handler = (uintptr_t)demo_interrupt;
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler) : "memory");
    plic_set_enable(0);
    plic_set_threshold(0);
    demo_pipeline_init();
    demo_network_init();
    demo_model_init();
    gpio_set_debounce(demo.clock_hz / 50u);
    gpio_set_edges(0, 0x0e);
    gpio_irq_clear(0x0e);
    plic_set_priority(EDRV32_PLIC_SOURCE_GPIO0, 1);
    plic_set_priority(EDRV32_PLIC_SOURCE_UART0, 2);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
        (1u << EDRV32_PLIC_SOURCE_GPIO0) | (1u << EDRV32_PLIC_SOURCE_UART0));
    mmio_write32(EDRV32_UART0_BASE + UART_RX_THRESH, 1);
    mmio_write32(EDRV32_UART0_BASE + UART_IRQ_EN,
                  UART_IRQ_RX_THRESH | UART_IRQ_RX_OVERRUN | UART_IRQ_FRAME_ERR);
    struct mem_xbar_stats initial;
    mem_xbar_snapshot(&initial);
    demo.deadline = clint_time() + demo.clock_hz / demo.sample_hz;
    clint_set_compare(demo.deadline);
    __asm__ volatile ("csrw mie, %0" :: "r"((1u << 7) | (1u << 11)) : "memory");
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    demo_pipeline_configure(VIN_CAM0);
    menu();
    for (;;) {
        demo_network_service();
        demo_pipeline_service();
        demo_network_receive();
        uart_service();
        keys_service();
        demo_monitor_send();
        uint32_t lock = demo_irq_lock();
        if (uart_read == uart_written && !demo.keys && !demo.received &&
            demo.ready_surface < 0 && demo.inference[0].state != BUFFER_READY &&
            demo.inference[1].state != BUFFER_READY) {
            demo.sleep_start = clint_time();
            demo.sleeping = 1;
            __asm__ volatile ("wfi" ::: "memory");
        }
        demo_irq_unlock(lock);
    }
}
