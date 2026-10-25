/* UART-driven CAM/DISP APB board test. */
#include "edrv32_cam.h"
#include "edrv32_hdmi.h"
#include "edrv32_pixel.h"
#include "edrv32_uart.h"

#ifndef EDRV32_SOC_CLOCK_HZ
#define EDRV32_SOC_CLOCK_HZ 100000000u
#endif
#ifndef EDRV32_UART_BAUD
#define EDRV32_UART_BAUD 115200u
#endif

#define UART_POLL_CYCLES 4096u
#define CAM_SCCB_TIMEOUT 1000000u
#define CAM_EXPECTED_ID  0x43414d30u
#define HDMI_EXPECTED_ID 0x44495350u
#define PIXEL_EXPECTED_ID 0x5049584cu

static unsigned int config_camera;
static int auto_exposure[2] = {1, 1};
static int auto_gain[2] = {1, 1};
static int auto_white_balance[2] = {1, 1};
static int mirror_enabled[2];
static int flip_enabled[2];
static int test_pattern_enabled[2];
static unsigned int manual_exposure[2] = {0x10000u, 0x10000u};
static unsigned int manual_gain[2] = {0x40u, 0x40u};
static unsigned int pixel_mode;
static unsigned int pixel_threshold = 128u;
static int pixel_brightness;
static unsigned int pixel_contrast = 256u;
static unsigned int spatial_mode;
static unsigned int spatial_threshold = 128u;

static void delay_cycles(unsigned int cycles)
{
    while (cycles != 0u) {
        __asm__ __volatile__("nop");
        cycles--;
    }
}

static void print_label_hex(const char *label, unsigned int value)
{
    edrv32_uart_puts(label);
    edrv32_uart_put_hex32(value);
    edrv32_uart_puts("\n");
}

static void print_enabled(const char *label, int enabled)
{
    edrv32_uart_puts(label);
    edrv32_uart_puts(enabled ? "enabled\n" : "disabled\n");
}

static void print_cam_result(const char *operation, int result)
{
    edrv32_uart_puts(operation);
    if (result == EDRV32_CAM_OK)
        edrv32_uart_puts(" applied\n");
    else if (result == EDRV32_CAM_BUSY)
        edrv32_uart_puts(" failed: SCCB busy\n");
    else if (result == EDRV32_CAM_NOT_READY)
        edrv32_uart_puts(" failed: camera initialization incomplete\n");
    else if (result == EDRV32_CAM_TIMEOUT)
        edrv32_uart_puts(" failed: SCCB timeout\n");
    else if (result == EDRV32_CAM_IO_ERROR)
        edrv32_uart_puts(" failed: SCCB bus error\n");
    else
        edrv32_uart_puts(" failed\n");
}

static void print_identity(void)
{
    print_label_hex("CAM  ID          : ", edrv32_cam_id());
    print_label_hex("CAM  version     : ", edrv32_cam_version());
    print_label_hex("CAM  capability  : ", edrv32_cam_capability());
    print_label_hex("HDMI ID          : ", edrv32_hdmi_id());
    print_label_hex("HDMI version     : ", edrv32_hdmi_version());
    print_label_hex("HDMI capability  : ", edrv32_hdmi_capability());
    print_label_hex("PIXEL ID         : ", edrv32_pixel_id());
    print_label_hex("PIXEL version    : ", edrv32_pixel_version());
    print_label_hex("PIXEL capability : ", edrv32_pixel_capability());
}

static void print_status(void)
{
    struct edrv32_cam_status cam;
    struct edrv32_hdmi_status hdmi;

    edrv32_cam_get_status(&cam);
    edrv32_hdmi_get_status(&hdmi);
    edrv32_uart_puts("\n--- Camera ---\n");
    print_enabled("CAM0             : ", (cam.control & 1u) != 0u);
    print_enabled("CAM1             : ", (cam.control & 2u) != 0u);
    print_label_hex("CAM status       : ", cam.status);
    print_label_hex("CAM0 frames      : ", cam.frame_count0);
    print_label_hex("CAM1 frames      : ", cam.frame_count1);
    print_label_hex("CAM IRQ enable   : ", cam.irq_enable);
    print_label_hex("CAM IRQ pending  : ", cam.irq_status);
    print_label_hex("CAM SCCB status  : ", cam.sccb_status);
    print_label_hex("Config target    : ", config_camera);
    edrv32_uart_puts("--- HDMI ---\n");
    print_enabled("HDMI             : ", (hdmi.control & 1u) != 0u);
    print_label_hex("HDMI status      : ", hdmi.status);
    print_label_hex("HDMI active buf  : ", (hdmi.status >> 1) & 3u);
    print_label_hex("Display frames   : ", hdmi.frame_count);
    print_label_hex("Underflows       : ", hdmi.underflow_count);
    print_label_hex("HDMI IRQ enable  : ", hdmi.irq_enable);
    print_label_hex("HDMI IRQ pending : ", hdmi.irq_status);
    print_label_hex("Scanout frames   : ", hdmi.scanout_frame_count);
    print_label_hex("HDMI debug       : ", hdmi.debug_status);
    edrv32_uart_puts("--- Pixel Pipeline ---\n");
    print_label_hex("PIXEL status     : ", edrv32_pixel_status());
    print_label_hex("PIXEL frames     : ", edrv32_pixel_frame_count());
    print_label_hex("PIXEL errors     : ", edrv32_pixel_error_count());
    print_label_hex("PIXEL mode       : ", pixel_mode);
    print_label_hex("PIXEL threshold  : ", pixel_threshold);
    print_label_hex("PIXEL brightness : ", (unsigned int)pixel_brightness);
    print_label_hex("PIXEL contrast Q8: ", pixel_contrast);
    print_label_hex("Spatial mode     : ", spatial_mode);
    print_label_hex("Spatial threshold: ", spatial_threshold);
}

static void print_buffers(void)
{
    print_label_hex("Display buffer 0 : ", edrv32_hdmi_buffer_base(0u));
    print_label_hex("Display buffer 1 : ", edrv32_hdmi_buffer_base(1u));
    print_label_hex("Display buffer 2 : ", edrv32_hdmi_buffer_base(2u));
}

static void monitor_frames(void)
{
    struct edrv32_cam_status cam0;
    struct edrv32_cam_status cam1;
    struct edrv32_hdmi_status hdmi0;
    struct edrv32_hdmi_status hdmi1;

    edrv32_cam_get_status(&cam0);
    edrv32_hdmi_get_status(&hdmi0);
    edrv32_uart_puts("Sampling counters...\n");
    delay_cycles(EDRV32_SOC_CLOCK_HZ / 2u);
    edrv32_cam_get_status(&cam1);
    edrv32_hdmi_get_status(&hdmi1);
    print_label_hex("CAM0 frame delta : ",
                    cam1.frame_count0 - cam0.frame_count0);
    print_label_hex("CAM1 frame delta : ",
                    cam1.frame_count1 - cam0.frame_count1);
    print_label_hex("DISP frame delta : ",
                    hdmi1.frame_count - hdmi0.frame_count);
    print_label_hex("Underflow delta  : ",
                    hdmi1.underflow_count - hdmi0.underflow_count);
}

static void restore_control_defaults(void)
{
    (void)edrv32_cam_set_enabled(EDRV32_CAM_CHANNEL0, 1);
    (void)edrv32_cam_set_enabled(EDRV32_CAM_CHANNEL1, 1);
    edrv32_cam_set_irq_enable(0u);
    edrv32_cam_clear_irq(EDRV32_CAM_IRQ_ALL);
    edrv32_hdmi_set_enabled(1);
    edrv32_hdmi_set_irq_enable(0u);
    edrv32_hdmi_clear_irq(EDRV32_HDMI_IRQ_ALL);
    {
        struct edrv32_pixel_config pixel = {
            .enable = 0,
            .grayscale = 0,
            .threshold_enable = 0,
            .invert = 0,
            .brightness = 0,
            .contrast_q8 = 256u,
            .threshold = 128u,
            .spatial_enable = 0,
            .spatial_mode = EDRV32_PIXEL_SPATIAL_BYPASS,
            .spatial_threshold = 128u
        };
        (void)edrv32_pixel_configure(&pixel);
        edrv32_pixel_set_irq_enable(0u);
        edrv32_pixel_clear_irq(EDRV32_PIXEL_IRQ_ALL);
        edrv32_pixel_commit();
        pixel_mode = 0u;
        pixel_threshold = 128u;
        pixel_brightness = 0;
        pixel_contrast = 256u;
        spatial_mode = EDRV32_PIXEL_SPATIAL_BYPASS;
        spatial_threshold = 128u;
    }
}

static int restore_sensor_defaults(unsigned int channel)
{
    int result;

    result = edrv32_cam_set_auto_exposure(channel, 1, CAM_SCCB_TIMEOUT);
    if (result != EDRV32_CAM_OK)
        return result;
    result = edrv32_cam_set_auto_gain(channel, 1, CAM_SCCB_TIMEOUT);
    if (result != EDRV32_CAM_OK)
        return result;
    result = edrv32_cam_set_auto_white_balance(channel, 1,
                                                CAM_SCCB_TIMEOUT);
    if (result != EDRV32_CAM_OK)
        return result;
    result = edrv32_cam_set_mirror(channel, 0, CAM_SCCB_TIMEOUT);
    if (result != EDRV32_CAM_OK)
        return result;
    result = edrv32_cam_set_flip(channel, 0, CAM_SCCB_TIMEOUT);
    if (result != EDRV32_CAM_OK)
        return result;
    return edrv32_cam_set_test_pattern(channel, 0, CAM_SCCB_TIMEOUT);
}

static void restore_defaults(void)
{
    int result0;
    int result1;

    restore_control_defaults();
    result0 = restore_sensor_defaults(EDRV32_CAM_CHANNEL0);
    result1 = restore_sensor_defaults(EDRV32_CAM_CHANNEL1);
    if (result0 == EDRV32_CAM_OK && result1 == EDRV32_CAM_OK) {
        auto_exposure[0] = 1;
        auto_exposure[1] = 1;
        auto_gain[0] = 1;
        auto_gain[1] = 1;
        auto_white_balance[0] = 1;
        auto_white_balance[1] = 1;
        mirror_enabled[0] = 0;
        mirror_enabled[1] = 0;
        flip_enabled[0] = 0;
        flip_enabled[1] = 0;
        test_pattern_enabled[0] = 0;
        test_pattern_enabled[1] = 0;
        edrv32_uart_puts("CAM/DISP/SCCB defaults restored\n");
    } else {
        edrv32_uart_puts("Control defaults restored; sensor restore failed\n");
    }
}

static void toggle_camera(unsigned int channel)
{
    int enabled = edrv32_cam_is_enabled(channel);

    if (enabled < 0) {
        edrv32_uart_puts("Invalid camera channel\n");
        return;
    }
    (void)edrv32_cam_set_enabled(channel, !enabled);
    edrv32_uart_puts(channel == 0u ? "CAM0 " : "CAM1 ");
    edrv32_uart_puts(enabled ? "disabled\n" : "enabled\n");
}

static void toggle_hdmi(void)
{
    int enabled = edrv32_hdmi_is_enabled();

    edrv32_hdmi_set_enabled(!enabled);
    edrv32_uart_puts(enabled ? "HDMI disabled\n" : "HDMI enabled\n");
}

static void clear_pending(void)
{
    edrv32_cam_clear_irq(EDRV32_CAM_IRQ_ALL);
    edrv32_hdmi_clear_irq(EDRV32_HDMI_IRQ_ALL);
    edrv32_pixel_clear_irq(EDRV32_PIXEL_IRQ_ALL);
    edrv32_uart_puts("CAM/HDMI/PIXEL pending flags cleared\n");
}

static void apply_pixel_mode(void)
{
    struct edrv32_pixel_config pixel = {
        .enable = pixel_mode != 0u || pixel_brightness != 0 ||
            pixel_contrast != 256u,
        .grayscale = pixel_mode == 1u,
        .threshold_enable = pixel_mode >= 2u,
        .invert = pixel_mode == 3u,
        .brightness = pixel_brightness,
        .contrast_q8 = pixel_contrast,
        .threshold = pixel_threshold,
        .spatial_enable = spatial_mode != EDRV32_PIXEL_SPATIAL_BYPASS,
        .spatial_mode = spatial_mode,
        .spatial_threshold = spatial_threshold
    };

    (void)edrv32_pixel_configure(&pixel);
    edrv32_pixel_commit();
}

static void cycle_pixel_mode(void)
{
    static const char *const names[4] = {
        "bypass", "grayscale", "binary", "inverted binary"
    };

    pixel_mode = (pixel_mode + 1u) & 3u;
    apply_pixel_mode();
    edrv32_uart_puts("Pixel mode: ");
    edrv32_uart_puts(names[pixel_mode]);
    edrv32_uart_puts(" (applies at next camera frame)\n");
}

static void adjust_pixel_threshold(int increase)
{
    if (increase) {
        if (pixel_threshold <= 239u)
            pixel_threshold += 16u;
        else
            pixel_threshold = 255u;
    } else if (pixel_threshold >= 16u) {
        pixel_threshold -= 16u;
    } else {
        pixel_threshold = 0u;
    }
    apply_pixel_mode();
    print_label_hex("Pixel threshold  : ", pixel_threshold);
}

static void adjust_pixel_brightness(int increase)
{
    if (increase) {
        if (pixel_brightness <= 239)
            pixel_brightness += 16;
        else
            pixel_brightness = 255;
    } else if (pixel_brightness >= -240) {
        pixel_brightness -= 16;
    } else {
        pixel_brightness = -256;
    }
    apply_pixel_mode();
    print_label_hex("Pixel brightness : ",
                    (unsigned int)pixel_brightness);
}

static void adjust_pixel_contrast(int increase)
{
    if (increase) {
        if (pixel_contrast <= 479u)
            pixel_contrast += 32u;
        else
            pixel_contrast = 511u;
    } else if (pixel_contrast >= 32u) {
        pixel_contrast -= 32u;
    } else {
        pixel_contrast = 0u;
    }
    apply_pixel_mode();
    print_label_hex("Pixel contrast Q8: ", pixel_contrast);
}

static void cycle_spatial_mode(void)
{
    static const char *const names[7] = {
        "off", "Sobel", "mean", "Gaussian", "sharpen",
        "erosion", "dilation"
    };

    spatial_mode++;
    if (spatial_mode > EDRV32_PIXEL_SPATIAL_DILATE)
        spatial_mode = EDRV32_PIXEL_SPATIAL_BYPASS;
    apply_pixel_mode();
    edrv32_uart_puts("Spatial filter: ");
    edrv32_uart_puts(names[spatial_mode]);
    edrv32_uart_puts(" (applies at next camera frame)\n");
}

static void adjust_spatial_threshold(int increase)
{
    if (increase) {
        if (spatial_threshold <= 239u)
            spatial_threshold += 16u;
        else
            spatial_threshold = 255u;
    } else if (spatial_threshold >= 16u) {
        spatial_threshold -= 16u;
    } else {
        spatial_threshold = 0u;
    }
    apply_pixel_mode();
    print_label_hex("Spatial threshold: ", spatial_threshold);
}

static void toggle_config_camera(void)
{
    config_camera ^= 1u;
    edrv32_uart_puts("Runtime configuration target: CAM");
    edrv32_uart_putc(config_camera ? '1' : '0');
    edrv32_uart_puts("\n");
}

static void probe_camera(void)
{
    unsigned int chip_id;
    int result = edrv32_cam_read_chip_id(config_camera, &chip_id,
                                         CAM_SCCB_TIMEOUT);

    if (result == EDRV32_CAM_OK) {
        print_label_hex(config_camera ? "CAM1 chip ID     : " :
                        "CAM0 chip ID     : ", chip_id);
        if (chip_id == 0x5640u)
            edrv32_uart_puts("OV5640 readback verified\n");
        else
            edrv32_uart_puts("Unexpected sensor chip ID\n");
    } else {
        print_cam_result("OV5640 chip-ID read", result);
    }
}

static void toggle_auto_exposure(void)
{
    int result;
    unsigned int channel = config_camera;
    int enable = !auto_exposure[channel];

    result = edrv32_cam_set_auto_exposure(channel, enable,
                                           CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK) {
        auto_exposure[channel] = enable;
        if (!enable)
            result = edrv32_cam_set_exposure(channel,
                manual_exposure[channel], CAM_SCCB_TIMEOUT);
    }
    print_cam_result(enable ? "Auto exposure" : "Manual exposure", result);
}

static void adjust_exposure(int increase)
{
    int result;
    unsigned int channel = config_camera;
    unsigned int value = manual_exposure[channel];

    if (increase) {
        if (value < 0xf0000u)
            value += 0x10000u;
    } else if (value > 0x10000u) {
        value -= 0x10000u;
    }
    result = edrv32_cam_set_auto_exposure(channel, 0,
                                           CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK)
        result = edrv32_cam_set_exposure(channel, value,
                                         CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK) {
        auto_exposure[channel] = 0;
        manual_exposure[channel] = value;
        print_label_hex("Manual exposure  : ", value);
    } else {
        print_cam_result("Manual exposure", result);
    }
}

static void cycle_gain(void)
{
    int result;
    unsigned int channel = config_camera;
    unsigned int value = manual_gain[channel] << 1;

    if (value > 0x200u)
        value = 0x40u;
    result = edrv32_cam_set_auto_gain(channel, 0, CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK)
        result = edrv32_cam_set_gain(channel, value, CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK) {
        auto_gain[channel] = 0;
        manual_gain[channel] = value;
        print_label_hex("Manual gain      : ", value);
    } else {
        print_cam_result("Manual gain", result);
    }
}

static void toggle_auto_white_balance(void)
{
    int result;
    unsigned int channel = config_camera;
    int enable = !auto_white_balance[channel];

    result = edrv32_cam_set_auto_white_balance(channel, enable,
                                                CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK)
        auto_white_balance[channel] = enable;
    print_cam_result(enable ? "Auto white balance" : "Manual white balance",
                     result);
}

static void toggle_mirror(void)
{
    int result;
    unsigned int channel = config_camera;
    int enable = !mirror_enabled[channel];

    result = edrv32_cam_set_mirror(channel, enable, CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK)
        mirror_enabled[channel] = enable;
    print_cam_result(enable ? "Mirror" : "Normal horizontal orientation",
                     result);
}

static void toggle_flip(void)
{
    int result;
    unsigned int channel = config_camera;
    int enable = !flip_enabled[channel];

    result = edrv32_cam_set_flip(channel, enable, CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK)
        flip_enabled[channel] = enable;
    print_cam_result(enable ? "Vertical flip" : "Normal vertical orientation",
                     result);
}

static void toggle_test_pattern(void)
{
    int result;
    unsigned int channel = config_camera;
    int enable = !test_pattern_enabled[channel];

    result = edrv32_cam_set_test_pattern(channel, enable, CAM_SCCB_TIMEOUT);
    if (result == EDRV32_CAM_OK)
        test_pattern_enabled[channel] = enable;
    print_cam_result(enable ? "Sensor color bar" : "Sensor live image",
                     result);
}

static void print_help(void)
{
    edrv32_uart_puts(
        "\n=== Camera / HDMI control ===\n"
        "s  show status and counters\n"
        "v  show peripheral ID/version/capability\n"
        "0  toggle CAM0 capture\n"
        "1  toggle CAM1 capture\n"
        "d  toggle HDMI output at a frame boundary\n"
        "m  sample frame counters for about 0.5 s\n"
        "b  show display triple-buffer addresses\n"
        "c  clear CAM/HDMI sticky pending flags\n"
        "t  switch runtime configuration target CAM0/CAM1\n"
        "q  read and verify the target OV5640 chip ID\n"
        "a  toggle automatic exposure on the target camera\n"
        "+  increase manual exposure on the target camera\n"
        "-  decrease manual exposure on the target camera\n"
        "g  cycle manual sensor gain on the target camera\n"
        "w  toggle automatic white balance on the target camera\n"
        "i  toggle horizontal mirror on the target camera\n"
        "f  toggle vertical flip on the target camera\n"
        "p  toggle the target sensor color-bar pattern\n"
        "y  cycle pixel mode: bypass/gray/binary/inverted\n"
        "[  decrease binary threshold by 16\n"
        "]  increase binary threshold by 16\n"
        "j/k decrease/increase pixel brightness\n"
        "u/o decrease/increase pixel contrast\n"
        "z  cycle spatial filter: off/Sobel/mean/Gaussian/sharpen/erode/dilate\n"
        ",/. decrease/increase erosion/dilation threshold\n"
        "r  restore safe defaults\n"
        "h  show this help\n"
        "KEY1 remains the temporary left/right display debug switch.\n"
        "> ");
}

static void execute_command(char command)
{
    switch (command) {
    case 's': case 'S': print_status(); break;
    case 'v': case 'V': print_identity(); break;
    case '0': toggle_camera(EDRV32_CAM_CHANNEL0); break;
    case '1': toggle_camera(EDRV32_CAM_CHANNEL1); break;
    case 'd': case 'D': toggle_hdmi(); break;
    case 'm': case 'M': monitor_frames(); break;
    case 'b': case 'B': print_buffers(); break;
    case 'c': case 'C': clear_pending(); break;
    case 't': case 'T': toggle_config_camera(); break;
    case 'q': case 'Q': probe_camera(); break;
    case 'a': case 'A': toggle_auto_exposure(); break;
    case '+': adjust_exposure(1); break;
    case '-': adjust_exposure(0); break;
    case 'g': case 'G': cycle_gain(); break;
    case 'w': case 'W': toggle_auto_white_balance(); break;
    case 'i': case 'I': toggle_mirror(); break;
    case 'f': case 'F': toggle_flip(); break;
    case 'p': case 'P': toggle_test_pattern(); break;
    case 'y': case 'Y': cycle_pixel_mode(); break;
    case '[': adjust_pixel_threshold(0); break;
    case ']': adjust_pixel_threshold(1); break;
    case 'j': case 'J': adjust_pixel_brightness(0); break;
    case 'k': case 'K': adjust_pixel_brightness(1); break;
    case 'u': case 'U': adjust_pixel_contrast(0); break;
    case 'o': case 'O': adjust_pixel_contrast(1); break;
    case 'z': case 'Z': cycle_spatial_mode(); break;
    case ',': adjust_spatial_threshold(0); break;
    case '.': adjust_spatial_threshold(1); break;
    case 'r': case 'R': restore_defaults(); break;
    case 'h': case 'H': print_help(); return;
    default:
        edrv32_uart_puts("Unknown command; enter h for help\n");
        break;
    }
    edrv32_uart_puts("> ");
}

int main(void)
{
    char command;
    int uart_status;

    edrv32_uart_init(EDRV32_UART_DIVISOR(EDRV32_SOC_CLOCK_HZ,
                                         EDRV32_UART_BAUD));
    edrv32_uart_puts("Runtime CAM/DISP/SCCB control is active.\n");
    if (edrv32_cam_id() != CAM_EXPECTED_ID ||
        edrv32_hdmi_id() != HDMI_EXPECTED_ID ||
        edrv32_pixel_id() != PIXEL_EXPECTED_ID)
        edrv32_uart_puts("[FAIL] CAM/DISP/PIXEL peripheral ID mismatch\n");
    else
        edrv32_uart_puts("[PASS] CAM/DISP/PIXEL peripheral IDs\n");
    restore_control_defaults();
    print_help();

    for (;;) {
        uart_status = edrv32_uart_getc_timeout(&command, UART_POLL_CYCLES);
        if (uart_status == EDRV32_UART_OK) {
            if (command == '\r' || command == '\n')
                continue;
            edrv32_uart_putc(command);
            edrv32_uart_puts("\n");
            execute_command(command);
        } else if (uart_status == EDRV32_UART_ERROR) {
            edrv32_uart_puts("\nUART RX error recovered\n> ");
        }
    }
}
