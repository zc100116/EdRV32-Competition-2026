/* File: common.c
 * Spec: soc-testplan 2, 4; SoC 6.1, 7.3-7.4; module specs 4.
 * Description: Configure engines with generated register definitions and service PLIC.
 *              The DDR mailbox synchronizes external stimuli and reference checks.
 * Clock domain: clk_sys software, media registers through the APB bridge.
 */
#include "common.h"
volatile uint32_t interrupts[16];
volatile uint32_t events[16];

uint32_t read_reg(uintptr_t base, uint32_t offset)
{
    return *(volatile uint32_t *)(base + offset);
}
void write_reg(uintptr_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(base + offset) = value;
}
volatile uint32_t *ddr(uint32_t physical)
{
    return (volatile uint32_t *)(EDRV32_DDR_UNCACHED_BASE + physical);
}
_Noreturn void finish(uint32_t code)
{
    uart_drain();
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
    sysctrl_write(SYSCTRL_SIM_EXIT, code);
    for (;;) {
        __asm__ volatile ("wfi");
    }
}
void print_hex(uint32_t value)
{
    for (int digit = 7; digit >= 0; digit--) {
        uart_putc("0123456789abcdef"[(value >> (digit * 4)) & 15u]);
    }
}
void equal(const char *position, uint32_t expected, uint32_t actual)
{
    if (expected != actual) {
        uart_puts("FAIL position=");
        uart_puts(position);
        uart_puts(" expected=");
        print_hex(expected);
        uart_puts(" actual=");
        print_hex(actual);
        uart_puts(" mtime=");
        print_hex((uint32_t)clint_time());
        uart_puts("\r\n");
        finish(1u);
    }
}

static void __attribute__((interrupt("machine"), aligned(4))) trap_handler(void)
{
    uint32_t cause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    equal("mcause", 0x8000000bu, cause);
    unsigned int source = plic_claim();
    uint32_t base = 0u;
    uint32_t offset = 0u;
    switch (source) {
    case EDRV32_PLIC_SOURCE_VIN:
        base = EDRV32_VIN_BASE;
        offset = EDRV32_VIN_IRQ_STAT_OFFSET;
        break;
    case EDRV32_PLIC_SOURCE_PIX:
        base = EDRV32_PIX_BASE;
        offset = EDRV32_PIX_IRQ_STAT_OFFSET;
        break;
    case EDRV32_PLIC_SOURCE_GEO:
        base = EDRV32_GEO_BASE;
        offset = EDRV32_GEO_IRQ_STAT_OFFSET;
        break;
    case EDRV32_PLIC_SOURCE_DISP:
        base = EDRV32_DISP_BASE;
        offset = EDRV32_DISP_IRQ_STAT_OFFSET;
        break;
    case EDRV32_PLIC_SOURCE_NPU:
        base = EDRV32_NPU_BASE;
        offset = EDRV32_NPU_IRQ_STAT_OFFSET;
        break;
    case EDRV32_PLIC_SOURCE_ETH:
        base = EDRV32_ETH_BASE;
        offset = EDRV32_ETH_IRQ_STAT_OFFSET;
        break;
    case EDRV32_PLIC_SOURCE_MEM_XBAR:
        base = EDRV32_MEM_XBAR_BASE;
        offset = EDRV32_MEM_XBAR_IRQ_STAT_OFFSET;
        break;
    default:
        equal("PLIC source 8-15 excluding RND", 8u, source);
        break;
    }
    uint32_t status = read_reg(base, offset);
    events[source] |= status;
    write_reg(base, offset, status);
    /* Deassert before complete; the APB round trip also crosses the IRQ synchronizer. */
    (void)read_reg(base, offset);
    plic_complete(source);
    interrupts[source]++;
}
void init(void)
{
    uart_init();
    uart_set_baud(EDRV32_CLK_SYS_HZ, 115200u);
    uart_puts("SoC test software ready\r\n");
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uintptr_t)trap_handler));
    for (unsigned int source = 8u; source < 16u; source++) {
        plic_set_priority(source, 1u);
    }
    plic_set_threshold(0u);
    plic_set_enable(0xf700u);
    __asm__ volatile ("csrs mie, %0" :: "r"(1u << 11));
    __asm__ volatile ("csrsi mstatus, 8");
}
void command(uint32_t operation, uint32_t argument)
{
    volatile uint32_t *mail = ddr(MAILBOX_BASE);
    mail[1] = argument;
    mail[2] = 0u;
    mail[0] = operation;
    while (mail[2] == 0u) {
    }
}
void wait_irq(unsigned int source, uint32_t count)
{
    while (interrupts[source] < count) {
    }
}
void configure_camera(void)
{
    gpio_write((1u << 13) | (1u << 15));
    gpio_set_output_enable(0xf000u);
    /* SCCB selects RGB565, 1280x720, matching the external model's supplied frame. */
    for (unsigned int port = 0; port < 2; port++) {
        i2c_init(port, EDRV32_CLK_SYS_HZ, 400000u);
        equal("SCCB 4300 RGB565", 0u, (uint32_t)i2c_sccb_write(0x3cu, 0x4300u, 0x61u));
        equal("SCCB 3808 width hi", 0u, (uint32_t)i2c_sccb_write(0x3cu, 0x3808u, 5u));
        equal("SCCB 3809 width lo", 0u, (uint32_t)i2c_sccb_write(0x3cu, 0x3809u, 0u));
        equal("SCCB 380a height hi", 0u, (uint32_t)i2c_sccb_write(0x3cu, 0x380au, 2u));
        equal("SCCB 380b height lo", 0u, (uint32_t)i2c_sccb_write(0x3cu, 0x380bu, 0xd0u));
    }
}
void configure_vin(unsigned int memory, unsigned int ch2)
{
    for (unsigned int slot = 0; slot < 4; slot++) {
        write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SURF_BASE_OFFSET(0, slot),
                  SURFACE_BASE + slot * SURFACE_STEP);
        write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_SURF_BASE_OFFSET(2, slot),
                  CH2_BASE + slot * 0x100000u);
    }
    uint32_t control = 1u | (memory << EDRV32_VIN_CH_CTRL_SRC_POS) |
                       (3u << EDRV32_VIN_CH_CTRL_RING_N_POS);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_CTRL_OFFSET(0), control);
    if (ch2 != 0u) {
        write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CH_CTRL_OFFSET(2), control);
    }
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_IRQ_EN_OFFSET,
              EDRV32_VIN_IRQ_EN_FRAME_MASK |
              (ch2 ? EDRV32_VIN_IRQ_EN_CH2_FRAME_MASK : 0u));
    write_reg(EDRV32_PIX_BASE, EDRV32_PIX_CTRL_OFFSET, EDRV32_PIX_CTRL_ENABLE_MASK);
    write_reg(EDRV32_VIN_BASE, EDRV32_VIN_CTRL_OFFSET, EDRV32_VIN_CTRL_ENABLE_MASK);
}
void display(uint32_t base)
{
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_NEXT_BASE_OFFSET, base);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_STRIDE_OFFSET, STRIDE);
    write_reg(EDRV32_DISP_BASE, EDRV32_DISP_CTRL_OFFSET, EDRV32_DISP_CTRL_ENABLE_MASK);
    while (read_reg(EDRV32_DISP_BASE, EDRV32_DISP_CUR_BASE_OFFSET) != base) {
    }
}
void run_geo(uint32_t source)
{
    volatile uint32_t *descriptor = ddr(GEO_DESC);
    for (unsigned int i = 0; i < 16; i++) descriptor[i] = 0u;
    descriptor[0] = source;
    descriptor[1] = STRIDE;
    descriptor[2] = (HEIGHT << 16) | WIDTH;
    descriptor[3] = GEO_BASE;
    descriptor[4] = STRIDE;
    descriptor[6] = (HEIGHT << 16) | WIDTH;
    descriptor[8] = 46341u;
    descriptor[9] = 46341u;
    descriptor[10] = 640u * 65536u - 46341u * 1000u;
    descriptor[11] = (uint32_t)-46341;
    descriptor[12] = 46341u;
    descriptor[13] = 360u * 65536u + 46341u * 280u;
    write_reg(EDRV32_GEO_BASE, EDRV32_GEO_DESC_BASE_OFFSET, GEO_DESC);
    write_reg(EDRV32_GEO_BASE, EDRV32_GEO_DESC_COUNT_OFFSET, 1u);
    write_reg(EDRV32_GEO_BASE, EDRV32_GEO_IRQ_EN_OFFSET, EDRV32_GEO_IRQ_EN_DONE_MASK);
    write_reg(EDRV32_GEO_BASE, EDRV32_GEO_DOORBELL_OFFSET, 1u);
}
void configure_npu(uint32_t input)
{
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_MODEL_BASE_OFFSET, NPU_MODEL);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_WORK_BASE_OFFSET, NPU_WORK);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_INPUT_BASE_OFFSET, input);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_OUTPUT_BASE_OFFSET, NPU_OUTPUT);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_DESC_BASE_OFFSET, NPU_DESC);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_DESC_COUNT_OFFSET, 3u);
    write_reg(EDRV32_NPU_BASE, EDRV32_NPU_IRQ_EN_OFFSET, EDRV32_NPU_IRQ_EN_DONE_MASK);
}
void configure_eth(void)
{
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_MAC_LO_OFFSET, 0x00000001u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_MAC_HI_OFFSET, 0x0200u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_IP_ADDR_OFFSET, 0xc0a80164u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_RX_PORT_OFFSET, 9000u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_TX_DST_MAC_LO_OFFSET, 0x00000002u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_TX_DST_MAC_HI_OFFSET, 0x0200u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_TX_DST_IP_OFFSET, 0xc0a80101u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_TX_PORT_OFFSET, (9000u << 16) | 9001u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_WIN_BASE_OFFSET(2), RX_BASE);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_WIN_SIZE_OFFSET(2), 65536u);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_IRQ_EN_OFFSET,
              EDRV32_ETH_IRQ_EN_RX_NOTIFY2_MASK);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_CTRL_OFFSET, EDRV32_ETH_CTRL_ENABLE_MASK);
}
void eth_send(uint32_t descriptor, uint32_t count)
{
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_DESC_BASE_OFFSET, descriptor);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_DESC_COUNT_OFFSET, count);
    write_reg(EDRV32_ETH_BASE, EDRV32_ETH_DOORBELL_OFFSET, 1u);
}
void snapshot(uint32_t clear)
{
    write_reg(EDRV32_MEM_XBAR_BASE, EDRV32_MEM_XBAR_STAT_CTRL_OFFSET,
              EDRV32_MEM_XBAR_STAT_CTRL_SNAPSHOT_MASK |
              (clear ? EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_MASK : 0u));
    for (unsigned int port = 0; port < 7; port++) {
        uart_puts("PORT ");
        print_hex(port);
        uint32_t offsets[] = {
            EDRV32_MEM_XBAR_RD_TXN_OFFSET(port), EDRV32_MEM_XBAR_RD_BEAT_OFFSET(port),
            EDRV32_MEM_XBAR_WR_TXN_OFFSET(port), EDRV32_MEM_XBAR_WR_BEAT_OFFSET(port),
            EDRV32_MEM_XBAR_WAIT_SUM_OFFSET(port), EDRV32_MEM_XBAR_WAIT_MAX_OFFSET(port),
            EDRV32_MEM_XBAR_URG_CNT_OFFSET(port)
        };
        for (unsigned int field = 0; field < 7; field++) {
            uart_putc(' ');
            print_hex(read_reg(EDRV32_MEM_XBAR_BASE, offsets[field]));
        }
        uart_puts("\r\n");
    }
}

void video_descriptors(void)
{
    volatile uint32_t *header = ddr(TX_BASE);
    header[0] = 0x46564445u;
    header[1] = 0x00010001u;
    header[2] = (HEIGHT << 16) | WIDTH;
    header[3] = STRIDE;
    header[4] = 7u;
    uint64_t time = clint_time();
    header[5] = (uint32_t)time;
    header[6] = (uint32_t)(time >> 32);
    header[7] = 1u;
    volatile uint32_t *descriptor = ddr(TX_DESC);
    for (unsigned int i = 0; i < 16; i++) descriptor[i] = 0u;
    descriptor[EDRV32_ETH_TX_DESC_SRC_ADDR_OFFSET / 4u] = TX_BASE;
    descriptor[EDRV32_ETH_TX_DESC_LEN_OFFSET / 4u] = 32u;
    descriptor[8u + EDRV32_ETH_TX_DESC_SRC_ADDR_OFFSET / 4u] = SURFACE_BASE;
    descriptor[8u + EDRV32_ETH_TX_DESC_LEN_OFFSET / 4u] = FRAME_BYTES;
    descriptor[8u + EDRV32_ETH_TX_DESC_WIN_OFFSET / 4u] = EDRV32_ETH_TX_DESC_NOTIFY_MASK;
    descriptor[8u + EDRV32_ETH_TX_DESC_OFFSET_OFFSET / 4u] = 32u;
}
