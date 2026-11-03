/* File: lv_conf.h
 * Spec: design rnd-disp 4.3; SoC 7.3/7.4; Task B3-3b.
 * Description: Identical freestanding and Linux LVGL v9.6 configuration.
 * Clock domain: clk_sys; tick supplied by the CLINT-backed platform service.
 */
#ifndef LV_CONF_H
#define LV_CONF_H
#define LV_COLOR_DEPTH 32
#define LV_COLOR_FORMAT_DEFAULT LV_COLOR_FORMAT_ARGB8888
#define LV_USE_OS LV_OS_NONE
#define LV_USE_STDLIB_MALLOC LV_STDLIB_BUILTIN
#define LV_USE_STDLIB_STRING LV_STDLIB_BUILTIN
#define LV_USE_STDLIB_SPRINTF LV_STDLIB_BUILTIN
#define LV_ATTRIBUTE_LARGE_RAM_ARRAY __attribute__((section(".noinit")))
#define LV_MEM_SIZE (24 * 1024 * 1024)
#define LV_DEF_REFR_PERIOD 34
#define LV_DRAW_BUF_ALIGN 64
#define LV_DRAW_BUF_STRIDE_ALIGN 32
/* 96 KiB > 1280 * 720 * 2 / 20 = 92160 B, as benchmark recommends for opa_layer. */
#define LV_DRAW_LAYER_SIMPLE_BUF_SIZE (96 * 1024)
#define LV_USE_DRAW_SW 1
#define LV_DRAW_SW_DRAW_UNIT_CNT 1
#define LV_DRAW_SW_COMPLEX 1
#define LV_USE_DRAW_SW_COMPLEX_GRADIENTS 1
#define LV_GRADIENT_MAX_STOPS 4
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN
#define LV_LOG_PRINTF 0
#define LV_USE_CHECK_ARG 0
#define LV_USE_ASSERT 0
#define LV_USE_ASSERT_NULL 0
#define LV_USE_ASSERT_MALLOC 0
#define LV_USE_FLOAT 0
#define LV_FONT_MONTSERRAT_12 1
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_18 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_22 1
#define LV_FONT_MONTSERRAT_24 1
#define LV_FONT_MONTSERRAT_26 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_MONTSERRAT_32 1
#define LV_FONT_MONTSERRAT_40 1
#define LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1
#define LV_FONT_SOURCE_HAN_SANS_SC_14_CJK 1
#define LV_FONT_DEFAULT &lv_font_source_han_sans_sc_16_cjk
#define LV_USE_SYSMON 1
#define LV_USE_PERF_MONITOR 1
#define LV_USE_PERF_MONITOR_LOG_MODE 0
#define LV_USE_DEMO_WIDGETS 1
#define LV_USE_DEMO_BENCHMARK 1
#define LV_USE_FS_STDIO 0
#define LV_USE_FS_POSIX 0
#define LV_BUILD_EXAMPLES 0
#endif
