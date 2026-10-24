/* ============================================================================
 * File        : edrv32_hdmi.h
 * Description : HDMI display APB HAL.
 * Notes       : Timing mode changes remain unavailable until the clock/timing
 *               reconfiguration hardware is implemented.
 * ========================================================================== */
#ifndef EDRV32_HDMI_H
#define EDRV32_HDMI_H

#define EDRV32_HDMI_IRQ_FRAME     (1u << 0)
#define EDRV32_HDMI_IRQ_UNDERFLOW (1u << 1)
#define EDRV32_HDMI_IRQ_ERROR     (1u << 2)
#define EDRV32_HDMI_IRQ_ALL       0x7u

#define EDRV32_HDMI_DEBUG_PLL_LOCK       (1u << 0)
#define EDRV32_HDMI_DEBUG_PIXEL_RESET_N  (1u << 1)
#define EDRV32_HDMI_DEBUG_SERIAL_RESET_N (1u << 2)
#define EDRV32_HDMI_DEBUG_PREFILL_DONE   (1u << 3)
#define EDRV32_HDMI_DEBUG_FIFO_VALID     (1u << 4)
#define EDRV32_HDMI_DEBUG_FIFO_COUNT(v)  (((v) >> 5) & 3u)

struct edrv32_hdmi_status {
    unsigned int control;
    unsigned int status;
    unsigned int frame_count;
    unsigned int underflow_count;
    unsigned int buffer_base[3];
    unsigned int irq_enable;
    unsigned int irq_status;
    unsigned int scanout_frame_count;
    unsigned int debug_status;
};

unsigned int edrv32_hdmi_id(void);
unsigned int edrv32_hdmi_version(void);
unsigned int edrv32_hdmi_capability(void);
void edrv32_hdmi_set_enabled(int enabled);
int edrv32_hdmi_is_enabled(void);
unsigned int edrv32_hdmi_active_buffer(void);
unsigned int edrv32_hdmi_buffer_base(unsigned int index);
void edrv32_hdmi_set_irq_enable(unsigned int mask);
unsigned int edrv32_hdmi_get_irq_status(void);
void edrv32_hdmi_clear_irq(unsigned int mask);
void edrv32_hdmi_get_status(struct edrv32_hdmi_status *status);

#endif /* EDRV32_HDMI_H */
