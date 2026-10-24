/* ============================================================================
 * File        : edrv32_pixel.h
 * Description : Pixel Pipeline APB HAL.
 * ========================================================================== */
#ifndef EDRV32_PIXEL_H
#define EDRV32_PIXEL_H

#define EDRV32_PIXEL_IRQ_FRAME  (1u << 0)
#define EDRV32_PIXEL_IRQ_ERROR  (1u << 1)
#define EDRV32_PIXEL_IRQ_COMMIT (1u << 2)
#define EDRV32_PIXEL_IRQ_ALL    0x7u

#define EDRV32_PIXEL_SPATIAL_BYPASS   0u
#define EDRV32_PIXEL_SPATIAL_SOBEL    1u
#define EDRV32_PIXEL_SPATIAL_MEAN     2u
#define EDRV32_PIXEL_SPATIAL_GAUSSIAN 3u
#define EDRV32_PIXEL_SPATIAL_SHARPEN  4u
#define EDRV32_PIXEL_SPATIAL_ERODE    5u
#define EDRV32_PIXEL_SPATIAL_DILATE   6u

struct edrv32_pixel_config {
    int enable;
    int grayscale;
    int threshold_enable;
    int invert;
    int brightness;
    unsigned int contrast_q8;
    unsigned int threshold;
    int spatial_enable;
    unsigned int spatial_mode;
    unsigned int spatial_threshold;
};

unsigned int edrv32_pixel_id(void);
unsigned int edrv32_pixel_version(void);
unsigned int edrv32_pixel_capability(void);
unsigned int edrv32_pixel_status(void);
unsigned int edrv32_pixel_frame_count(void);
unsigned int edrv32_pixel_error_count(void);
int edrv32_pixel_configure(const struct edrv32_pixel_config *config);
void edrv32_pixel_commit(void);
void edrv32_pixel_set_irq_enable(unsigned int mask);
unsigned int edrv32_pixel_get_irq_status(void);
void edrv32_pixel_clear_irq(unsigned int mask);

#endif /* EDRV32_PIXEL_H */
