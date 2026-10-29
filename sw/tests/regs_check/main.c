/* File: main.c
 * Spec: edrv32-soc-spec 7.1; engine specifications section 4; npu 4.1; eth 2.3/2.6.
 * Description: Compile all generated engine headers together and compare representative
 *              offsets and fields against literal values from the specification tables.
 * Clock domain: none (compile-time checks).
 */
#include "soc_map.h"
#include "regs/vin_regs.h"
#include "regs/pix_regs.h"
#include "regs/geo_regs.h"
#include "regs/disp_regs.h"
#include "regs/npu_regs.h"
#include "regs/eth_regs.h"
#include "regs/mem_xbar_regs.h"
#include "regs/perf_mon_regs.h"

/* vin-spec 4.1: IRQ_STAT.CH2_FRAME. */
_Static_assert(EDRV32_VIN_IRQ_STAT_OFFSET == 0x010, "VIN IRQ_STAT offset");
_Static_assert(EDRV32_VIN_IRQ_STAT_CH2_FRAME_POS == 9, "VIN CH2_FRAME position");
_Static_assert(EDRV32_VIN_IRQ_STAT_CH2_FRAME_WIDTH == 1, "VIN CH2_FRAME width");
_Static_assert(EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK == 0x200, "VIN CH2_FRAME mask");
/* vin-spec 4.2: CAM0_SIZE.WIDTH=[10:0], HEIGHT=[27:16]. */
_Static_assert(EDRV32_VIN_CAM0_SIZE_OFFSET == 0x100, "VIN CAM0_SIZE offset");
_Static_assert(EDRV32_VIN_CAM0_SIZE_WIDTH_WIDTH == 11, "VIN WIDTH width");
_Static_assert(EDRV32_VIN_CAM0_SIZE_HEIGHT_POS == 16, "VIN HEIGHT position");
_Static_assert(EDRV32_VIN_CAM0_SIZE_HEIGHT_MASK == 0x0FFF0000, "VIN HEIGHT mask");
_Static_assert(EDRV32_VIN_CAM0_SIZE_RESET == 0x02D00500, "VIN CAM0_SIZE reset");
/* vin-spec 4.3: CHn=0x200+0x80*n; RING_N=[6:4]; SURF[s]=+8+4*s. */
_Static_assert(EDRV32_VIN_CH_CTRL_OFFSET(0) == 0x200, "VIN CH0 CTRL offset");
_Static_assert(EDRV32_VIN_CH_CTRL_OFFSET(2) == 0x300, "VIN CH2 CTRL offset");
_Static_assert(EDRV32_VIN_CH_CTRL_RING_N_POS == 4, "VIN RING_N position");
_Static_assert(EDRV32_VIN_CH_CTRL_RING_N_WIDTH == 3, "VIN RING_N width");
_Static_assert(EDRV32_VIN_CH_CTRL_RING_N_MASK == 0x70, "VIN RING_N mask");
_Static_assert(EDRV32_VIN_CH_SURF_BASE_OFFSET(2, 0) == 0x308, "VIN CH2 SURF0 offset");
_Static_assert(EDRV32_VIN_CH_SURF_BASE_OFFSET(2, 3) == 0x314, "VIN CH2 SURF3 offset");
_Static_assert(EDRV32_VIN_CH_SURF_BASE_VALUE_MASK == 0xFFFFF000, "VIN SURF base mask");
_Static_assert(EDRV32_VIN_CH_DONE_INFO_OFFSET(2) == 0x320, "VIN CH2 DONE_INFO offset");
_Static_assert(EDRV32_VIN_CH_DONE_INFO_BUS_ERR_POS == 5, "VIN BUS_ERR position");

/* pix-spec 4.2: CFG, BC, THRESH and GAMMA_WR. */
_Static_assert(EDRV32_PIX_CFG_OFFSET == 0x100, "PIX CFG offset");
_Static_assert(EDRV32_PIX_CFG_S2_OP_POS == 8, "PIX S2_OP position");
_Static_assert(EDRV32_PIX_CFG_S2_OP_WIDTH == 3, "PIX S2_OP width");
_Static_assert(EDRV32_PIX_CFG_S2_OP_MASK == 0x700, "PIX S2_OP mask");
_Static_assert(EDRV32_PIX_BC_OFFSET == 0x104, "PIX BC offset");
_Static_assert(EDRV32_PIX_BC_BRIGHTNESS_POS == 16, "PIX BRIGHTNESS position");
_Static_assert(EDRV32_PIX_BC_BRIGHTNESS_WIDTH == 9, "PIX BRIGHTNESS width");
_Static_assert(EDRV32_PIX_BC_RESET == 0x100, "PIX BC reset");
_Static_assert(EDRV32_PIX_THRESH_OFFSET == 0x108, "PIX THRESH offset");
_Static_assert(EDRV32_PIX_THRESH_VALUE_MASK == 0xFF, "PIX THRESH mask");
_Static_assert(EDRV32_PIX_GAMMA_WR_OFFSET == 0x10C, "PIX GAMMA_WR offset");
_Static_assert(EDRV32_PIX_GAMMA_WR_BANK_POS == 8, "PIX GAMMA BANK position");
_Static_assert(EDRV32_PIX_GAMMA_WR_VALUE_MASK == 0xFF0000, "PIX GAMMA VALUE mask");
/* SoC 7.1; pix-spec 4.1/4.3: PERF[15] at end of common window. */
_Static_assert(EDRV32_PIX_PERF_OFFSET(15) == 0x07C, "PIX PERF15 offset");

/* SoC 7.1; geo-spec 4.1: CTRL, DESC_BASE, DESC_COUNT and DOORBELL. */
_Static_assert(EDRV32_GEO_CTRL_OFFSET == 0x004, "GEO CTRL offset");
_Static_assert(EDRV32_GEO_CTRL_ABORT_MASK == 0x4, "GEO ABORT mask");
_Static_assert(EDRV32_GEO_DESC_BASE_OFFSET == 0x020, "GEO DESC_BASE offset");
_Static_assert(EDRV32_GEO_DESC_BASE_VALUE_POS == 5, "GEO DESC_BASE position");
_Static_assert(EDRV32_GEO_DESC_BASE_VALUE_WIDTH == 27, "GEO DESC_BASE width");
_Static_assert(EDRV32_GEO_DESC_BASE_VALUE_MASK == 0xFFFFFFE0, "GEO DESC_BASE mask");
_Static_assert(EDRV32_GEO_DESC_COUNT_OFFSET == 0x024, "GEO DESC_COUNT offset");
_Static_assert(EDRV32_GEO_DESC_COUNT_VALUE_MASK == 0xFFFF, "GEO DESC_COUNT mask");
_Static_assert(EDRV32_GEO_DOORBELL_OFFSET == 0x028, "GEO DOORBELL offset");
/* geo-spec 4.2: CUR_DESC. */
_Static_assert(EDRV32_GEO_CUR_DESC_OFFSET == 0x100, "GEO CUR_DESC offset");

/* disp-spec 4.1: IRQ_STAT.SWITCH=bit8. */
_Static_assert(EDRV32_DISP_IRQ_STAT_OFFSET == 0x010, "DISP IRQ_STAT offset");
_Static_assert(EDRV32_DISP_IRQ_STAT_SWITCH_POS == 8, "DISP SWITCH position");
_Static_assert(EDRV32_DISP_IRQ_STAT_SWITCH_WIDTH == 1, "DISP SWITCH width");
_Static_assert(EDRV32_DISP_IRQ_STAT_SWITCH_MASK == 0x100, "DISP SWITCH mask");
/* disp-spec 4.2: NEXT_BASE, STRIDE, REL_BASE, FRAME_CNT. */
_Static_assert(EDRV32_DISP_NEXT_BASE_OFFSET == 0x100, "DISP NEXT_BASE offset");
_Static_assert(EDRV32_DISP_NEXT_BASE_VALUE_POS == 12, "DISP NEXT_BASE position");
_Static_assert(EDRV32_DISP_NEXT_BASE_VALUE_WIDTH == 20, "DISP NEXT_BASE width");
_Static_assert(EDRV32_DISP_NEXT_BASE_VALUE_MASK == 0xFFFFF000, "DISP NEXT_BASE mask");
_Static_assert(EDRV32_DISP_STRIDE_OFFSET == 0x104, "DISP STRIDE offset");
_Static_assert(EDRV32_DISP_STRIDE_VALUE_MASK == 0xFFE0, "DISP STRIDE mask");
_Static_assert(EDRV32_DISP_STRIDE_RESET == 0xA00, "DISP STRIDE reset");
_Static_assert(EDRV32_DISP_REL_BASE_OFFSET == 0x10C, "DISP REL_BASE offset");
_Static_assert(EDRV32_DISP_FRAME_CNT_OFFSET == 0x110, "DISP FRAME_CNT offset");

/* SoC 7.1; npu-spec 4: ID, STATUS, DESC_BASE, OUTPUT_BASE and CUR_DESC. */
_Static_assert(EDRV32_NPU_ID_OFFSET == 0x000, "NPU ID offset");
_Static_assert(EDRV32_NPU_ID_RESET == 0x00060001, "NPU ID reset");
_Static_assert(EDRV32_NPU_STATUS_OFFSET == 0x008, "NPU STATUS offset");
_Static_assert(EDRV32_NPU_STATUS_IDLE_POS == 1, "NPU IDLE position");
_Static_assert(EDRV32_NPU_STATUS_IDLE_WIDTH == 1, "NPU IDLE width");
_Static_assert(EDRV32_NPU_STATUS_IDLE_MASK == 0x2, "NPU IDLE mask");
_Static_assert(EDRV32_NPU_STATUS_RESET == 0x2, "NPU STATUS reset");
_Static_assert(EDRV32_NPU_DESC_BASE_OFFSET == 0x020, "NPU DESC_BASE offset");
_Static_assert(EDRV32_NPU_OUTPUT_BASE_OFFSET == 0x10C, "NPU OUTPUT_BASE offset");
_Static_assert(EDRV32_NPU_CUR_DESC_OFFSET == 0x110, "NPU CUR_DESC offset");
/* npu-spec 4.1: descriptor words 0, 7, 8, 10, 11, 12 and 64-byte size. */
_Static_assert(EDRV32_NPU_DESC_SIZE == 64, "NPU descriptor size");
_Static_assert(EDRV32_NPU_DESC_HALF_TAIL_OFFSET == 0, "NPU HALF_TAIL byte offset");
_Static_assert(EDRV32_NPU_DESC_HALF_TAIL_POS == 9, "NPU HALF_TAIL position");
_Static_assert(EDRV32_NPU_DESC_HALF_TAIL_MASK == 0x200, "NPU HALF_TAIL mask");
_Static_assert(EDRV32_NPU_DESC_QUANT_OFFSET_OFFSET == 28, "NPU QUANT byte offset");
_Static_assert(EDRV32_NPU_DESC_QUANT_OFFSET_WIDTH == 32, "NPU QUANT width");
_Static_assert(EDRV32_NPU_DESC_QUANT_OFFSET_MASK == 0xFFFFFFFF, "NPU QUANT mask");
_Static_assert(EDRV32_NPU_DESC_IN_H_OFFSET == 32, "NPU IN_H byte offset");
_Static_assert(EDRV32_NPU_DESC_IN_H_POS == 16, "NPU IN_H position");
_Static_assert(EDRV32_NPU_DESC_IN_H_WIDTH == 12, "NPU IN_H width");
_Static_assert(EDRV32_NPU_DESC_OUT_ZP_OFFSET == 40, "NPU OUT_ZP byte offset");
_Static_assert(EDRV32_NPU_DESC_OUT_ZP_MASK == 0xFF0000, "NPU OUT_ZP mask");
_Static_assert(EDRV32_NPU_DESC_K_COUNT_OFFSET == 44, "NPU K_COUNT byte offset");
_Static_assert(EDRV32_NPU_DESC_K_COUNT_POS == 16, "NPU K_COUNT position");
_Static_assert(EDRV32_NPU_DESC_K_COUNT_WIDTH == 11, "NPU K_COUNT width");
_Static_assert(EDRV32_NPU_DESC_WEIGHT_BLOCK_BYTES_OFFSET == 48, "NPU WEIGHT byte offset");
_Static_assert(EDRV32_NPU_DESC_WEIGHT_BLOCK_BYTES_MASK == 0xFFFFF, "NPU WEIGHT mask");

/* eth-spec 4.1: IRQ_STAT.RX_NOTIFY3. */
_Static_assert(EDRV32_ETH_IRQ_STAT_OFFSET == 0x010, "ETH IRQ_STAT offset");
_Static_assert(EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_POS == 11, "ETH RX_NOTIFY3 position");
_Static_assert(EDRV32_ETH_IRQ_STAT_RX_NOTIFY3_MASK == 0x800, "ETH RX_NOTIFY3 mask");
/* eth-spec 4.2: TX_PORT, WINn_BASE, WINn_SIZE and MDIO_CMD. */
_Static_assert(EDRV32_ETH_TX_PORT_OFFSET == 0x11C, "ETH TX_PORT offset");
_Static_assert(EDRV32_ETH_TX_PORT_TX_SRC_PORT_POS == 16, "ETH source port position");
_Static_assert(EDRV32_ETH_TX_PORT_TX_SRC_PORT_WIDTH == 16, "ETH source port width");
_Static_assert(EDRV32_ETH_TX_PORT_TX_SRC_PORT_MASK == 0xFFFF0000, "ETH source port mask");
_Static_assert(EDRV32_ETH_WIN_BASE_OFFSET(0) == 0x140, "ETH WIN0_BASE offset");
_Static_assert(EDRV32_ETH_WIN_BASE_OFFSET(3) == 0x170, "ETH WIN3_BASE offset");
_Static_assert(EDRV32_ETH_WIN_BASE_VALUE_MASK == 0xFFFFFFE0, "ETH window base mask");
_Static_assert(EDRV32_ETH_WIN_SIZE_OFFSET(3) == 0x174, "ETH WIN3_SIZE offset");
_Static_assert(EDRV32_ETH_WIN_SIZE_VALUE_WIDTH == 28, "ETH window size width");
_Static_assert(EDRV32_ETH_MDIO_CMD_OFFSET == 0x180, "ETH MDIO_CMD offset");
_Static_assert(EDRV32_ETH_MDIO_CMD_PHY_POS == 5, "ETH PHY position");
_Static_assert(EDRV32_ETH_MDIO_CMD_WDATA_MASK == 0xFFFF0000, "ETH WDATA mask");
/* eth-spec 2.6: TX descriptor fields in little endian words. */
_Static_assert(EDRV32_ETH_TX_DESC_SIZE == 32, "ETH TX descriptor size");
_Static_assert(EDRV32_ETH_TX_DESC_SRC_ADDR_OFFSET == 0, "ETH SRC_ADDR byte offset");
_Static_assert(EDRV32_ETH_TX_DESC_SRC_ADDR_POS == 5, "ETH SRC_ADDR position");
_Static_assert(EDRV32_ETH_TX_DESC_SRC_ADDR_MASK == 0xFFFFFFE0, "ETH SRC_ADDR mask");
_Static_assert(EDRV32_ETH_TX_DESC_LEN_OFFSET == 4, "ETH LEN byte offset");
_Static_assert(EDRV32_ETH_TX_DESC_LEN_WIDTH == 24, "ETH LEN width");
_Static_assert(EDRV32_ETH_TX_DESC_NOTIFY_OFFSET == 8, "ETH NOTIFY byte offset");
_Static_assert(EDRV32_ETH_TX_DESC_NOTIFY_POS == 8, "ETH NOTIFY position");
_Static_assert(EDRV32_ETH_TX_DESC_OFFSET_OFFSET == 12, "ETH OFFSET byte offset");
/* eth-spec 2.3: application header offsets address bytes, OFFSET is network order. */
_Static_assert(EDRV32_ETH_APP_HEADER_SIZE == 8, "ETH application header size");
_Static_assert(EDRV32_ETH_APP_HEADER_WIN_OFFSET == 0, "ETH application WIN byte offset");
_Static_assert(EDRV32_ETH_APP_HEADER_WIN_MASK == 3, "ETH application WIN mask");
_Static_assert(EDRV32_ETH_APP_HEADER_FLAGS_OFFSET == 1, "ETH application FLAGS offset");
_Static_assert(EDRV32_ETH_APP_HEADER_NOTIFY_OFFSET == 1, "ETH application NOTIFY offset");
_Static_assert(EDRV32_ETH_APP_HEADER_NOTIFY_POS == 0, "ETH application NOTIFY position");
_Static_assert(EDRV32_ETH_APP_HEADER_OFFSET_OFFSET == 4, "ETH application OFFSET offset");
_Static_assert(EDRV32_ETH_APP_HEADER_OFFSET_WIDTH == 32, "ETH application OFFSET width");

/* mem-subsys-spec 4.1: OUTST_TOTAL, STAT_CTRL, OUTST_RD, RD_TXN and WR_BEAT. */
_Static_assert(EDRV32_MEM_XBAR_OUTST_TOTAL_OFFSET == 0x100, "XBAR OUTST_TOTAL offset");
_Static_assert(EDRV32_MEM_XBAR_OUTST_TOTAL_VALUE_WIDTH == 4, "XBAR OUTST_TOTAL width");
_Static_assert(EDRV32_MEM_XBAR_OUTST_TOTAL_RESET == 8, "XBAR OUTST_TOTAL reset");
_Static_assert(EDRV32_MEM_XBAR_STAT_CTRL_OFFSET == 0x110, "XBAR STAT_CTRL offset");
_Static_assert(EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_POS == 1, "XBAR CLEAR position");
_Static_assert(EDRV32_MEM_XBAR_STAT_CTRL_CLEAR_MASK == 2, "XBAR CLEAR mask");
_Static_assert(EDRV32_MEM_XBAR_OUTST_RD_OFFSET(6) == 0x2C0, "XBAR P6 OUTST_RD offset");
_Static_assert(EDRV32_MEM_XBAR_OUTST_RD_VALUE_MASK == 0xF, "XBAR OUTST_RD mask");
/* edrv32-soc-spec 6.4.5: per-port reset values. */
_Static_assert(EDRV32_MEM_XBAR_OUTST_RD_RESET_1 == 2, "XBAR P1 OUTST_RD reset");
_Static_assert(EDRV32_MEM_XBAR_RD_TXN_OFFSET(0) == 0x400, "XBAR P0 RD_TXN offset");
_Static_assert(EDRV32_MEM_XBAR_RD_TXN_OFFSET(6) == 0x4C0, "XBAR P6 RD_TXN offset");
_Static_assert(EDRV32_MEM_XBAR_WR_BEAT_OFFSET(0) == 0x418, "XBAR P0 WR_BEAT offset");
_Static_assert(EDRV32_MEM_XBAR_WR_BEAT_OFFSET(6) == 0x4D8, "XBAR P6 WR_BEAT offset");

/* mem-subsys-spec 4.2: BASE, SIZE, LAT_MIN, READ_CNT and HIST. */
_Static_assert(EDRV32_PERF_MON_BASE_OFFSET == 0x104, "PERF_MON BASE offset");
_Static_assert(EDRV32_PERF_MON_BASE_VALUE_POS == 12, "PERF_MON BASE position");
_Static_assert(EDRV32_PERF_MON_BASE_VALUE_WIDTH == 18, "PERF_MON BASE width");
_Static_assert(EDRV32_PERF_MON_BASE_VALUE_MASK == 0x3FFFF000, "PERF_MON BASE mask");
_Static_assert(EDRV32_PERF_MON_SIZE_OFFSET == 0x108, "PERF_MON SIZE offset");
_Static_assert(EDRV32_PERF_MON_SIZE_VALUE_POS == 9, "PERF_MON SIZE position");
_Static_assert(EDRV32_PERF_MON_SIZE_VALUE_WIDTH == 21, "PERF_MON SIZE width");
_Static_assert(EDRV32_PERF_MON_SIZE_VALUE_MASK == 0x3FFFFE00, "PERF_MON SIZE mask");
_Static_assert(EDRV32_PERF_MON_SIZE_RESET == 0x1000, "PERF_MON SIZE reset");
_Static_assert(EDRV32_PERF_MON_LAT_MIN_OFFSET == 0x20C, "PERF_MON LAT_MIN offset");
_Static_assert(EDRV32_PERF_MON_LAT_MIN_RESET == 0xFFFFFFFF, "PERF_MON LAT_MIN reset");
_Static_assert(EDRV32_PERF_MON_READ_CNT_OFFSET == 0x218, "PERF_MON READ_CNT offset");
_Static_assert(EDRV32_PERF_MON_HIST_OFFSET(0) == 0x300, "PERF_MON HIST0 offset");
_Static_assert(EDRV32_PERF_MON_HIST_OFFSET(15) == 0x33C, "PERF_MON HIST15 offset");

int main(void)
{
    return 0;
}
