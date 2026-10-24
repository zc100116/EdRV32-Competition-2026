/* ============================================================================
 * File        : edrv32_cam.h
 * Description : Dual-camera APB and runtime OV5640 SCCB HAL.
 * ========================================================================== */
#ifndef EDRV32_CAM_H
#define EDRV32_CAM_H

#define EDRV32_CAM_CHANNEL0 0u
#define EDRV32_CAM_CHANNEL1 1u

#define EDRV32_CAM_IRQ_FRAME0 (1u << 0)
#define EDRV32_CAM_IRQ_FRAME1 (1u << 1)
#define EDRV32_CAM_IRQ_ERROR  (1u << 2)
#define EDRV32_CAM_IRQ_SCCB_DONE  (1u << 3)
#define EDRV32_CAM_IRQ_SCCB_ERROR (1u << 4)
#define EDRV32_CAM_IRQ_ALL        0x1fu

#define EDRV32_CAM_OK            0
#define EDRV32_CAM_INVALID      -1
#define EDRV32_CAM_BUSY         -2
#define EDRV32_CAM_NOT_READY    -3
#define EDRV32_CAM_IO_ERROR     -4
#define EDRV32_CAM_TIMEOUT      -5

struct edrv32_cam_status {
    unsigned int control;
    unsigned int status;
    unsigned int frame_count0;
    unsigned int frame_count1;
    unsigned int irq_enable;
    unsigned int irq_status;
    unsigned int sccb_status;
};

unsigned int edrv32_cam_id(void);
unsigned int edrv32_cam_version(void);
unsigned int edrv32_cam_capability(void);
int edrv32_cam_set_enabled(unsigned int channel, int enabled);
int edrv32_cam_is_enabled(unsigned int channel);
void edrv32_cam_set_irq_enable(unsigned int mask);
unsigned int edrv32_cam_get_irq_status(void);
void edrv32_cam_clear_irq(unsigned int mask);
void edrv32_cam_get_status(struct edrv32_cam_status *status);
unsigned int edrv32_cam_sccb_status(void);
int edrv32_cam_write_reg_async(unsigned int channel,
                               unsigned int reg_addr,
                               unsigned int value);
int edrv32_cam_wait_sccb(unsigned int timeout_cycles);
int edrv32_cam_write_reg(unsigned int channel,
                         unsigned int reg_addr,
                         unsigned int value,
                         unsigned int timeout_cycles);
int edrv32_cam_read_reg_async(unsigned int channel,
                              unsigned int reg_addr);
int edrv32_cam_read_reg(unsigned int channel,
                        unsigned int reg_addr,
                        unsigned int *value,
                        unsigned int timeout_cycles);
int edrv32_cam_read_chip_id(unsigned int channel, unsigned int *chip_id,
                            unsigned int timeout_cycles);
int edrv32_cam_set_auto_exposure(unsigned int channel, int enabled,
                                 unsigned int timeout_cycles);
int edrv32_cam_set_auto_gain(unsigned int channel, int enabled,
                             unsigned int timeout_cycles);
int edrv32_cam_set_exposure(unsigned int channel, unsigned int exposure,
                            unsigned int timeout_cycles);
int edrv32_cam_set_gain(unsigned int channel, unsigned int gain,
                        unsigned int timeout_cycles);
int edrv32_cam_set_auto_white_balance(unsigned int channel, int enabled,
                                      unsigned int timeout_cycles);
int edrv32_cam_set_mirror(unsigned int channel, int enabled,
                          unsigned int timeout_cycles);
int edrv32_cam_set_flip(unsigned int channel, int enabled,
                        unsigned int timeout_cycles);
int edrv32_cam_set_test_pattern(unsigned int channel, int enabled,
                                unsigned int timeout_cycles);

#endif /* EDRV32_CAM_H */
