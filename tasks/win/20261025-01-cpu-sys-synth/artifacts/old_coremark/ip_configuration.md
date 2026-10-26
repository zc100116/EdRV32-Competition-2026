# 旧 CoreMark 工程 IP 配置

来源：本目录 ipcore/*/*.idf，原样保留全部 15 份。
导入脚本实际添加 cache_tag、cache_data、sram、boot_rom、mul、pll0 共 6 个 IP；其余配置存在于目录中，不代表该测量顶层实际例化。
配置为当前磁盘快照；测量报告日期为 2026-10-07。mul 的关键参数另由当次 compile/run.log 的实例参数确认。

## boot_rom

| 项 | 值 |
|---|---|
| name | 28nm DRM Based ROM |
| version | 1.8 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| ADDR_STROBE_EN | false |
| ADDR_WIDTH | 11 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| CLK_EN | false |
| CLK_OR_POL_INV | false |
| DATA_WIDTH | 64 |
| FAB_REG | false |
| INIT_EN | true |
| INIT_FILE | G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/bootrom.dat |
| INIT_FORMAT | HEX |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |

## cache_data

| 项 | 值 |
|---|---|
| name | 28nm DRM Based Simple Dual Port RAM |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| BE_WIDTH | 16 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| FAB_REG | false |
| INIT_EN | false |
| INIT_FILE | NONE |
| INIT_FORMAT | BIN |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_ADDR_STROBE_EN | false |
| RD_ADDR_WIDTH | 7 |
| RD_BE_WIDTH | 16 |
| RD_CLK_EN | false |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 128 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_ADDR_STROBE_EN | false |
| WR_ADDR_WIDTH | 7 |
| WR_BYTE_EN | true |
| WR_CLK_EN | false |
| WR_DATA_WIDTH | 128 |

## cache_tag

| 项 | 值 |
|---|---|
| name | 28nm DRM Based Simple Dual Port RAM |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| BE_WIDTH | 1 |
| BYTE_SIZE | 8 |
| CAS_MODE | 18K |
| CAS_MODE_SEL | AUTO |
| FAB_REG | false |
| INIT_EN | false |
| INIT_FILE | NONE |
| INIT_FORMAT | BIN |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_ADDR_STROBE_EN | false |
| RD_ADDR_WIDTH | 7 |
| RD_BE_WIDTH | 1 |
| RD_CLK_EN | false |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 21 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_ADDR_STROBE_EN | false |
| WR_ADDR_WIDTH | 7 |
| WR_BYTE_EN | false |
| WR_CLK_EN | false |
| WR_DATA_WIDTH | 21 |

## cam_fifo

| 项 | 值 |
|---|---|
| name | 28nm DRM Based FIFO |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| ALMOST_EMPTY_NUM | 16 |
| ALMOST_FULL_NUM | 960 |
| ASYN_FIFO_EN | true |
| BE_WIDTH | 1 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| EMPTY_WL_EN | false |
| FAB_REG | false |
| FIFO_TYPE | ASYN_FIFO |
| FULL_WL_EN | false |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_BE_WIDTH | 1 |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 258 |
| RD_DEPTH_WIDTH | 10 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_BYTE_EN | false |
| WR_DATA_WIDTH | 258 |
| WR_DEPTH_WIDTH | 10 |

## cam_rom

| 项 | 值 |
|---|---|
| name | 28nm DRM Based ROM |
| version | 1.8 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| ADDR_STROBE_EN | false |
| ADDR_WIDTH | 9 |
| CAS_MODE | 18K |
| CAS_MODE_SEL | AUTO |
| CLK_EN | false |
| CLK_OR_POL_INV | false |
| DATA_WIDTH | 24 |
| FAB_REG | false |
| INIT_EN | true |
| INIT_FILE | G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc/ov5640_720p.dat |
| INIT_FORMAT | HEX |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |

## ddr

| 项 | 值 |
|---|---|
| name | Logos2 HMIC_S |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| A0_DQS_EN | false |
| A0_GROUP_NUM | 0 |
| A10_DQS_EN | false |
| A10_GROUP_NUM | 1 |
| A11_DQS_EN | true |
| A11_GROUP_NUM | 1 |
| A12_DQS_EN | false |
| A12_EN | true |
| A12_GROUP_NUM | 1 |
| A13_DQS_EN | false |
| A13_EN | true |
| A13_GROUP_NUM | 0 |
| A14_DQS_EN | true |
| A14_EN | true |
| A14_GROUP_NUM | 0 |
| A15_DQS_EN | false |
| A15_EN | false |
| A15_GROUP_NUM | 0 |
| A1_DQS_EN | false |
| A1_GROUP_NUM | 0 |
| A2_DQS_EN | false |
| A2_GROUP_NUM | 0 |
| A3_DQS_EN | false |
| A3_GROUP_NUM | 1 |
| A4_DQS_EN | false |
| A4_GROUP_NUM | 1 |
| A5_DQS_EN | true |
| A5_GROUP_NUM | 0 |
| A6_DQS_EN | false |
| A6_GROUP_NUM | 1 |
| A7_DQS_EN | false |
| A7_GROUP_NUM | 0 |
| A8_DQS_EN | false |
| A8_GROUP_NUM | 1 |
| A9_DQS_EN | false |
| A9_GROUP_NUM | 0 |
| ACTUAL_RATE | 1000.000 |
| BA0_DQS_EN | false |
| BA0_GROUP_NUM | 1 |
| BA1_DQS_EN | false |
| BA1_GROUP_NUM | 1 |
| BA2_DQS_EN | false |
| BA2_EN | true |
| BA2_GROUP_NUM | 2 |
| BANK0 | R5 |
| BANK1 | R4 |
| BANK2 | L6 |
| BANK_CA | R5 |
| BANK_DQG_0 | R4 |
| BANK_DQG_1 | R4 |
| BANK_DQG_2 | R4 |
| BANK_DQG_3 | R4 |
| BANK_DQG_4 | L4 |
| BANK_DQG_5 | L4 |
| BANK_DQG_6 | L4 |
| BANK_DQG_7 | L4 |
| BANK_DQG_8 | L5 |
| BANK_NUM | 2 |
| BANK_PLL_REF | R5 |
| CAS_DQS_EN | false |
| CAS_GROUP_NUM | 2 |
| CA_GROUP_NUM | 3 |
| CKE_DQS_EN | true |
| CKE_GROUP_NUM | 1 |
| CK_DQS_EN | true |
| CK_GROUP_NUM | 2 |
| CLKIN_FREQ | 125.000 |
| CS_DQS_EN | false |
| CS_GROUP_NUM | 1 |
| CS_N_EN | true |
| CS_n_EN | true |
| CS_n_En | true |
| CTRL_ADDR_WIDTH | 28 |
| CUSTOMIZE_CA | true |
| CUSTOMIZE_MEM | false |
| DDR2_AL | 2 |
| DDR2_BASE_MEM_PART | MT47H128M16XX-25E |
| DDR2_CL | 4 |
| DDR2_CL_VALUE | 4 |
| DDR2_DFT_MEM_PART | MT47H128M16XX-25E |
| DDR2_INIT_WR | 6 |
| DDR2_MEM_BANK_WIDTH | 3 |
| DDR2_MEM_COLUMN_WIDTH | 10 |
| DDR2_MEM_ROW_WIDTH | 14 |
| DDR2_ODT_VALUE | 01 |
| DDR2_OUTPUT_DRIVER | 0 |
| DDR2_WR | 5 |
| DDR3_AL | 2 |
| DDR3_BASE_MEM_PART | MT41K128M16XX |
| DDR3_CL | 7 |
| DDR3_CL_VALUE | 6 |
| DDR3_CWL | 6 |
| DDR3_DFT_MEM_PART | MT41K256M16XX |
| DDR3_INIT_WR | 8 |
| DDR3_MEM_BANK_WIDTH | 3 |
| DDR3_MEM_COLUMN_WIDTH | 10 |
| DDR3_MEM_ROW_WIDTH | 15 |
| DDR3_ODT_VALUE | 001 |
| DDR3_OUTPUT_DRIVER | 00 |
| DDR3_WR | 4 |
| DDRC_TREFI | 3900 |
| DDRC_TRFC | 150 |
| DDRC_T_FAW | 22 |
| DDRC_T_RAS | 19 |
| DDRC_T_RC | 25 |
| DDRC_T_RCD | 7 |
| DDRC_T_RP | 7 |
| DDRC_T_RRD | 5 |
| DDRC_T_RTP | 4 |
| DDRC_T_WR | 8 |
| DDRC_T_WTR | 4 |
| DDRC_T_XP | 4 |
| DDR_CHIP_DQ_WIDTH | true |
| DDR_MEM_PART | MT41K256M16XX |
| DESIRED_DDR2_RATE | 600.000 |
| DESIRED_DDR3_RATE | 1000.000 |
| DESIRED_LPDDR_RATE | 200.000 |
| DESIRED_RATE | 1000.000 |
| DEVICE_100H_EN | false |
| DFI_CLK_PERIOD | 8000 |
| DQ0_BANK_NUM | 1 |
| DQ0_EN | true |
| DQ1_BANK_NUM | 1 |
| DQ1_EN | true |
| DQ2_BANK_NUM | 1 |
| DQ2_EN | true |
| DQ3_BANK_NUM | 1 |
| DQ3_EN | true |
| DQ4_BANK_NUM | 2 |
| DQ4_EN | false |
| DQ5_BANK_NUM | 2 |
| DQ5_EN | false |
| DQ6_BANK_NUM | 2 |
| DQ6_EN | false |
| DQ7_BANK_NUM | 2 |
| DQ7_EN | false |
| DQ8_BANK_NUM | 0 |
| DQ8_EN | false |
| GPLL_BANDWIDTH | HIGH |
| GROUP_A0 | G1 |
| GROUP_A1 | G1 |
| GROUP_A10 | G2 |
| GROUP_A11 | G2 |
| GROUP_A12 | G2 |
| GROUP_A13 | G1 |
| GROUP_A14 | G1 |
| GROUP_A15 | G3 |
| GROUP_A2 | G1 |
| GROUP_A3 | G2 |
| GROUP_A4 | G2 |
| GROUP_A5 | G1 |
| GROUP_A6 | G2 |
| GROUP_A7 | G1 |
| GROUP_A8 | G2 |
| GROUP_A9 | G1 |
| GROUP_BA0 | G2 |
| GROUP_BA1 | G2 |
| GROUP_BA2 | G3 |
| GROUP_CAS | G3 |
| GROUP_CK | G3 |
| GROUP_CKE | G2 |
| GROUP_CKN | G3 |
| GROUP_CS | G2 |
| GROUP_DQG_0 | G1 |
| GROUP_DQG_1 | G0 |
| GROUP_DQG_2 | G2 |
| GROUP_DQG_3 | G3 |
| GROUP_DQG_4 | G0 |
| GROUP_DQG_5 | G1 |
| GROUP_DQG_6 | G2 |
| GROUP_DQG_7 | G3 |
| GROUP_DQG_8 | G0 |
| GROUP_ODT | G1 |
| GROUP_RAS | G3 |
| GROUP_WE | G3 |
| GUI_DDR2_AL | 2 |
| GUI_DDR2_CL | 4 |
| GUI_DDR2_TRAS | 45.000 |
| GUI_DDR2_TRCD | 12.500 |
| GUI_DDR2_TREFI | 7.800 |
| GUI_DDR2_TRFC | 195.000 |
| GUI_DDR2_TRP | 13.500 |
| GUI_DDR2_TRTP | 7.500 |
| GUI_DDR2_TWR | 15.000 |
| GUI_DDR2_TWTR | 7.500 |
| GUI_DDR3_AL | CL-2 |
| GUI_DDR3_CL_1066 | 7 |
| GUI_DDR3_CL_800 | 6 |
| GUI_DDR3_CWL_1066 | 6 |
| GUI_DDR3_CWL_800 | 5 |
| GUI_DDR3_TRAS | 37.500 |
| GUI_DDR3_TRCD | 13.500 |
| GUI_DDR3_TREFI | 7.800 |
| GUI_DDR3_TRFC | 300.000 |
| GUI_DDR3_TRP | 13.500 |
| GUI_DDR3_TRTP | 7.500 |
| GUI_DDR3_TWR | 15.000 |
| GUI_DDR3_TWTR | 7.500 |
| GUI_LPDDR_CL_200 | 2 |
| GUI_LPDDR_CL_400 | 2 |
| GUI_LPDDR_TRAS | 45.000 |
| GUI_LPDDR_TRCD | 22.500 |
| GUI_LPDDR_TREFI | 7.800 |
| GUI_LPDDR_TRFC | 140.000 |
| GUI_LPDDR_TRP | 22.500 |
| GUI_LPDDR_TWR | 15.000 |
| GUI_LPDDR_TWTR | 2 |
| LPDDR_BASE_MEM_PART | MT46H128M16XXXX-5L-IT |
| LPDDR_CL | 2 |
| LPDDR_CL_VALUE | 2 |
| LPDDR_DFT_MEM_PART | MT46H128M16XXXX-5L-IT |
| LPDDR_DRIVER_STRENGTH | 000 |
| LPDDR_MEM_BANK_WIDTH | 2 |
| LPDDR_MEM_COLUMN_WIDTH | 11 |
| LPDDR_MEM_ROW_WIDTH | 14 |
| MEM_ADDR_WIDTH | 15 |
| MEM_BANK_WIDTH | 3 |
| MEM_COLUMN_WIDTH | 10 |
| MEM_DM_WIDTH | 4 |
| MEM_DQS_WIDTH | 4 |
| MEM_DQ_WIDTH | 32 |
| MEM_ROW_WIDTH | 15 |
| MEM_TYPE | DDR3 |
| ODT_DQS_EN | false |
| ODT_GROUP_NUM | 0 |
| OPERATING_MODE | Controller + PHY |
| PAD_A0 | J1 |
| PAD_A1 | L3 |
| PAD_A10 | T3 |
| PAD_A11 | P1 |
| PAD_A12 | T4 |
| PAD_A13 | M2 |
| PAD_A14 | N1 |
| PAD_A15 | P5 |
| PAD_A2 | L2 |
| PAD_A3 | P3 |
| PAD_A4 | T2 |
| PAD_A5 | M1 |
| PAD_A6 | U1 |
| PAD_A7 | K1 |
| PAD_A8 | U2 |
| PAD_A9 | K2 |
| PAD_BA0 | P4 |
| PAD_BA1 | R2 |
| PAD_BA2 | T5 |
| PAD_CAS | T7 |
| PAD_CK | U6 |
| PAD_CKE | R1 |
| PAD_CKN | U5 |
| PAD_CS | N4 |
| PAD_DM0 | K8 |
| PAD_DM1 | H9 |
| PAD_DM2 | E5 |
| PAD_DM3 | G1 |
| PAD_DM4 | L14 |
| PAD_DM5 | J19 |
| PAD_DM6 | H21 |
| PAD_DM7 | F25 |
| PAD_DM8 | P18 |
| PAD_DQ0 | F4 |
| PAD_DQ1 | F5 |
| PAD_DQ10 | F8 |
| PAD_DQ11 | G6 |
| PAD_DQ12 | G9 |
| PAD_DQ13 | H6 |
| PAD_DQ14 | G9 |
| PAD_DQ15 | H6 |
| PAD_DQ16 | A4 |
| PAD_DQ17 | B5 |
| PAD_DQ18 | B4 |
| PAD_DQ19 | C4 |
| PAD_DQ2 | G4 |
| PAD_DQ20 | D3 |
| PAD_DQ21 | D4 |
| PAD_DQ22 | D5 |
| PAD_DQ23 | E3 |
| PAD_DQ24 | A2 |
| PAD_DQ25 | A3 |
| PAD_DQ26 | C1 |
| PAD_DQ27 | B2 |
| PAD_DQ28 | D1 |
| PAD_DQ29 | E1 |
| PAD_DQ3 | G5 |
| PAD_DQ30 | E2 |
| PAD_DQ31 | F2 |
| PAD_DQ32 | L15 |
| PAD_DQ33 | J15 |
| PAD_DQ34 | M15 |
| PAD_DQ35 | J14 |
| PAD_DQ36 | M16 |
| PAD_DQ37 | J16 |
| PAD_DQ38 | M14 |
| PAD_DQ39 | K15 |
| PAD_DQ4 | J5 |
| PAD_DQ40 | H18 |
| PAD_DQ41 | K21 |
| PAD_DQ42 | G20 |
| PAD_DQ43 | L18 |
| PAD_DQ44 | H19 |
| PAD_DQ45 | L17 |
| PAD_DQ46 | G21 |
| PAD_DQ47 | J18 |
| PAD_DQ48 | H23 |
| PAD_DQ49 | H22 |
| PAD_DQ5 | J6 |
| PAD_DQ50 | J23 |
| PAD_DQ51 | E23 |
| PAD_DQ52 | K23 |
| PAD_DQ53 | F23 |
| PAD_DQ54 | J24 |
| PAD_DQ55 | H24 |
| PAD_DQ56 | E25 |
| PAD_DQ57 | G26 |
| PAD_DQ58 | G25 |
| PAD_DQ59 | J25 |
| PAD_DQ6 | K6 |
| PAD_DQ60 | D25 |
| PAD_DQ61 | J26 |
| PAD_DQ62 | G24 |
| PAD_DQ63 | H26 |
| PAD_DQ64 | R14 |
| PAD_DQ65 | R15 |
| PAD_DQ66 | P14 |
| PAD_DQ67 | N14 |
| PAD_DQ68 | N16 |
| PAD_DQ69 | N17 |
| PAD_DQ7 | K7 |
| PAD_DQ70 | R16 |
| PAD_DQ71 | R17 |
| PAD_DQ8 | E6 |
| PAD_DQ9 | F7 |
| PAD_DQS0 | H4 |
| PAD_DQS1 | G7 |
| PAD_DQS2 | A5 |
| PAD_DQS3 | B1 |
| PAD_DQS4 | K16 |
| PAD_DQS5 | K20 |
| PAD_DQS6 | G22 |
| PAD_DQS7 | E26 |
| PAD_DQS8 | P15 |
| PAD_DQSN0 | J4 |
| PAD_DQSN1 | H7 |
| PAD_DQSN2 | B5 |
| PAD_DQSN3 | C1 |
| PAD_DQSN4 | K17 |
| PAD_DQSN5 | J20 |
| PAD_DQSN6 | F22 |
| PAD_DQSN7 | D26 |
| PAD_DQSN8 | P16 |
| PAD_ODT | H2 |
| PAD_RAS | P6 |
| PAD_RESET | H1 |
| PAD_WE | T8 |
| PHY_TMOD | 12 |
| PHY_TMRD | 4 |
| PHY_TRCD | 2 |
| PHY_TRFC | 38 |
| PHY_TRP | 2 |
| PHY_TXPR | 39 |
| PPLL_BANDWIDTH | HIGH |
| RAS_DQS_EN | false |
| RAS_GROUP_NUM | 2 |
| STATIC_RATIO0 | 2 |
| STATIC_RATIOF | 16 |
| STATIC_RATIOI | 1 |
| USER_FDC_PATH | Please select a fdc file |
| USER_PINS_CON_EN | false |
| WE_DQS_EN | false |
| WE_GROUP_NUM | 2 |
| tREFI | 7800 |
| tRFC_MIN | 300000.000 |

## geometry_band_ram

| 项 | 值 |
|---|---|
| name | 28nm DRM Based Simple Dual Port RAM |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| BE_WIDTH | 32 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| FAB_REG | false |
| INIT_EN | false |
| INIT_FILE | NONE |
| INIT_FORMAT | BIN |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_ADDR_STROBE_EN | false |
| RD_ADDR_WIDTH | 11 |
| RD_BE_WIDTH | 32 |
| RD_CLK_EN | true |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 256 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_ADDR_STROBE_EN | false |
| WR_ADDR_WIDTH | 11 |
| WR_BYTE_EN | true |
| WR_CLK_EN | false |
| WR_DATA_WIDTH | 256 |

## geometry_tile_ram

| 项 | 值 |
|---|---|
| name | 28nm DRM Based Simple Dual Port RAM |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| BE_WIDTH | 32 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| FAB_REG | false |
| INIT_EN | false |
| INIT_FILE | NONE |
| INIT_FORMAT | BIN |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_ADDR_STROBE_EN | false |
| RD_ADDR_WIDTH | 6 |
| RD_BE_WIDTH | 32 |
| RD_CLK_EN | true |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 256 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_ADDR_STROBE_EN | false |
| WR_ADDR_WIDTH | 6 |
| WR_BYTE_EN | true |
| WR_CLK_EN | false |
| WR_DATA_WIDTH | 256 |

## hdmi_fifo

| 项 | 值 |
|---|---|
| name | 28nm DRM Based FIFO |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| ALMOST_EMPTY_NUM | 64 |
| ALMOST_FULL_NUM | 480 |
| ASYN_FIFO_EN | true |
| BE_WIDTH | 1 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| EMPTY_WL_EN | true |
| FAB_REG | false |
| FIFO_TYPE | ASYN_FIFO |
| FULL_WL_EN | true |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_BE_WIDTH | 1 |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 256 |
| RD_DEPTH_WIDTH | 9 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_BYTE_EN | false |
| WR_DATA_WIDTH | 256 |
| WR_DEPTH_WIDTH | 9 |

## hdmi_pll

| 项 | 值 |
|---|---|
| name | 28nm PLL |
| version | 1.4 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| APB_EN | false |
| APB_EN_advancedPage | false |
| APB_EN_basicPage | false |
| BANDWIDTH | OPTIMIZED |
| BANDWIDTH_advancedPage | OPTIMIZED |
| CLKIN1_BUFG_EN | false |
| CLKIN1_INBUFDS_EN | false |
| CLKIN1_INBUF_EN | false |
| CLKIN1_NOBUF_EN | true |
| CLKIN1_SOURCE_advancedPage | No Buffer |
| CLKIN1_SOURCE_basicPage | No Buffer |
| CLKIN2_BUFG_EN | false |
| CLKIN2_INBUFDS_EN | false |
| CLKIN2_INBUF_EN | false |
| CLKIN2_NOBUF_EN | true |
| CLKIN2_SOURCE_advancedPage | No Buffer |
| CLKIN2_SOURCE_basicPage | No Buffer |
| CLKIN_FREQ | 27.00000000 |
| CLKIN_FREQ_advancedPage | 50.00000000 |
| CLKIN_FREQ_basicPage | 27.00000000 |
| CLKOUT0_BUFCE | false |
| CLKOUT0_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT0_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT0_BUFGCE_EN | false |
| CLKOUT0_BUFG_EN | false |
| CLKOUT0_BUFR_EN | false |
| CLKOUT0_BUFXCE_EN | false |
| CLKOUT0_BUFX_EN | false |
| CLKOUT0_DPS_SEL_advancedPage | false |
| CLKOUT0_DPS_SEL_basicPage | false |
| CLKOUT0_EN | true |
| CLKOUT0_EN_advancedPage | true |
| CLKOUT0_EN_basicPage | true |
| CLKOUT0_GATE_EN_advancedPage | false |
| CLKOUT0_GATE_EN_basicPage | false |
| CLKOUT0_IOCLKBUF_EN | false |
| CLKOUT0_NOBUF_EN | true |
| CLKOUT0_N_EN | false |
| CLKOUT0_N_EN_advancedPage | false |
| CLKOUT0_N_EN_basicPage | false |
| CLKOUT0_REQ_DUTY_advancedPage | 24 |
| CLKOUT0_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT0_REQ_FREQ_basicPage | 74.25000000 |
| CLKOUT0_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT0_SYN_EN | false |
| CLKOUT1_BUFCE | false |
| CLKOUT1_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT1_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT1_BUFGCE_EN | false |
| CLKOUT1_BUFG_EN | false |
| CLKOUT1_BUFR_EN | false |
| CLKOUT1_BUFXCE_EN | false |
| CLKOUT1_BUFX_EN | false |
| CLKOUT1_DPS_SEL_advancedPage | false |
| CLKOUT1_DPS_SEL_basicPage | false |
| CLKOUT1_EN | true |
| CLKOUT1_EN_advancedPage | false |
| CLKOUT1_EN_basicPage | true |
| CLKOUT1_GATE_EN_advancedPage | false |
| CLKOUT1_GATE_EN_basicPage | false |
| CLKOUT1_IOCLKBUF_EN | false |
| CLKOUT1_NOBUF_EN | true |
| CLKOUT1_N_EN | false |
| CLKOUT1_N_EN_advancedPage | false |
| CLKOUT1_N_EN_basicPage | false |
| CLKOUT1_REQ_DUTY_advancedPage | 24 |
| CLKOUT1_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT1_REQ_FREQ_basicPage | 371.25000000 |
| CLKOUT1_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT1_SYN_EN | false |
| CLKOUT2_BUFCE | false |
| CLKOUT2_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT2_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT2_BUFGCE_EN | false |
| CLKOUT2_BUFG_EN | false |
| CLKOUT2_BUFR_EN | false |
| CLKOUT2_BUFXCE_EN | false |
| CLKOUT2_BUFX_EN | false |
| CLKOUT2_DPS_SEL_advancedPage | false |
| CLKOUT2_DPS_SEL_basicPage | false |
| CLKOUT2_EN | false |
| CLKOUT2_EN_advancedPage | false |
| CLKOUT2_EN_basicPage | false |
| CLKOUT2_GATE_EN_advancedPage | false |
| CLKOUT2_GATE_EN_basicPage | false |
| CLKOUT2_IOCLKBUF_EN | false |
| CLKOUT2_NOBUF_EN | true |
| CLKOUT2_N_EN | false |
| CLKOUT2_N_EN_advancedPage | false |
| CLKOUT2_N_EN_basicPage | false |
| CLKOUT2_REQ_DUTY_advancedPage | 24 |
| CLKOUT2_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT2_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT2_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT2_SYN_EN | false |
| CLKOUT3_BUFCE | false |
| CLKOUT3_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT3_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT3_BUFGCE_EN | false |
| CLKOUT3_BUFG_EN | false |
| CLKOUT3_BUFR_EN | false |
| CLKOUT3_BUFXCE_EN | false |
| CLKOUT3_BUFX_EN | false |
| CLKOUT3_DPS_SEL_advancedPage | false |
| CLKOUT3_DPS_SEL_basicPage | false |
| CLKOUT3_EN | false |
| CLKOUT3_EN_advancedPage | false |
| CLKOUT3_EN_basicPage | false |
| CLKOUT3_GATE_EN_advancedPage | false |
| CLKOUT3_GATE_EN_basicPage | false |
| CLKOUT3_IOCLKBUF_EN | false |
| CLKOUT3_NOBUF_EN | true |
| CLKOUT3_N_EN | false |
| CLKOUT3_N_EN_advancedPage | false |
| CLKOUT3_N_EN_basicPage | false |
| CLKOUT3_REQ_DUTY_advancedPage | 24 |
| CLKOUT3_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT3_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT3_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT3_SYN_EN | false |
| CLKOUT4_BUFCE | false |
| CLKOUT4_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT4_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT4_BUFGCE_EN | false |
| CLKOUT4_BUFG_EN | false |
| CLKOUT4_BUFXCE_EN | false |
| CLKOUT4_BUFX_EN | false |
| CLKOUT4_DPS_SEL_advancedPage | false |
| CLKOUT4_DPS_SEL_basicPage | false |
| CLKOUT4_EN | false |
| CLKOUT4_EN_advancedPage | false |
| CLKOUT4_EN_basicPage | false |
| CLKOUT4_GATE_EN_advancedPage | false |
| CLKOUT4_GATE_EN_basicPage | false |
| CLKOUT4_NOBUF_EN | true |
| CLKOUT4_REQ_DUTY_advancedPage | 24 |
| CLKOUT4_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT4_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT4_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT4_SYN_EN | false |
| CLKOUT5_BUFCE | false |
| CLKOUT5_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT5_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT5_BUFGCE_EN | false |
| CLKOUT5_BUFG_EN | false |
| CLKOUT5_BUFXCE_EN | false |
| CLKOUT5_BUFX_EN | false |
| CLKOUT5_DPS_SEL_advancedPage | false |
| CLKOUT5_DPS_SEL_basicPage | false |
| CLKOUT5_EN | false |
| CLKOUT5_EN_advancedPage | false |
| CLKOUT5_EN_basicPage | false |
| CLKOUT5_GATE_EN_advancedPage | false |
| CLKOUT5_GATE_EN_basicPage | false |
| CLKOUT5_NOBUF_EN | true |
| CLKOUT5_REQ_DUTY_advancedPage | 24 |
| CLKOUT5_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT5_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT5_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT5_SYN_EN | false |
| CLKOUT6_BUFCE | false |
| CLKOUT6_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT6_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT6_BUFGCE_EN | false |
| CLKOUT6_BUFG_EN | false |
| CLKOUT6_BUFXCE_EN | false |
| CLKOUT6_BUFX_EN | false |
| CLKOUT6_DPS_SEL_advancedPage | false |
| CLKOUT6_DPS_SEL_basicPage | false |
| CLKOUT6_EN | false |
| CLKOUT6_EN_advancedPage | false |
| CLKOUT6_EN_basicPage | false |
| CLKOUT6_GATE_EN_advancedPage | false |
| CLKOUT6_GATE_EN_basicPage | false |
| CLKOUT6_NOBUF_EN | true |
| CLKOUT6_REQ_DUTY_advancedPage | 24 |
| CLKOUT6_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT6_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT6_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT6_SYN_EN | false |
| CLKOUT7_BUFCE | false |
| CLKOUT7_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT7_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT7_BUFGCE_EN | false |
| CLKOUT7_BUFG_EN | false |
| CLKOUT7_BUFXCE_EN | false |
| CLKOUT7_BUFX_EN | false |
| CLKOUT7_DPS_SEL_advancedPage | false |
| CLKOUT7_DPS_SEL_basicPage | false |
| CLKOUT7_EN | false |
| CLKOUT7_EN_advancedPage | false |
| CLKOUT7_EN_basicPage | false |
| CLKOUT7_GATE_EN_advancedPage | false |
| CLKOUT7_GATE_EN_basicPage | false |
| CLKOUT7_NOBUF_EN | true |
| CLKOUT7_N_EN | false |
| CLKOUT7_N_EN_advancedPage | false |
| CLKOUT7_N_EN_basicPage | false |
| CLKOUT7_REQ_DUTY_advancedPage | 24 |
| CLKOUT7_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT7_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT7_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT7_SYN_EN | false |
| CLKOUT8_EN | false |
| CLKOUT8_EN_advancedPage | false |
| CLKOUT8_EN_basicPage | false |
| CLKOUT8_GATE_EN_advancedPage | false |
| CLKOUT8_GATE_EN_basicPage | false |
| CLKOUT8_N_EN | false |
| CLKOUT8_N_EN_advancedPage | false |
| CLKOUT8_N_EN_basicPage | false |
| CLKOUT8_REQ_DUTY_advancedPage | 24 |
| CLKOUT8_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT8_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT8_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT8_SYN_EN | false |
| CLK_CAS5_EN | false |
| CLK_DPS0_EN | false |
| CLK_DPS1_EN | false |
| CLK_DPS2_EN | false |
| CLK_DPS3_EN | false |
| CLK_DPS4_EN | false |
| CLK_DPS5_EN | false |
| CLK_DPS6_EN | false |
| CLK_DPS7_EN | false |
| DEVICE_PG2L50H | false |
| DEVICE_Titan2 | false |
| DYNAMIC_CLKIN_EN | false |
| DYNAMIC_CLKIN_EN_advancedPage | false |
| DYNAMIC_CLKIN_EN_basicPage | false |
| DYNAMIC_PHASE_EN | false |
| DYNAMIC_PHASE_EN_advancedPage | false |
| DYNAMIC_PHASE_EN_basicPage | false |
| EXTERNAL_FB | DISABLE |
| FB_MODE | false |
| FB_MODE_advancedPage | 0 |
| FB_MODE_basicPage | 0 |
| FB_advancedPage | 7 |
| FB_basicPage | 7 |
| INTERNAL_FB | CLKOUTF |
| InsertPhase_advancedPage | 0 |
| LOCK_MODE | 0 |
| LOCK_MODE_advancedPage | false |
| MODE_CFG | 0 |
| ODIV5_CASCADE_EN_advancedPage | false |
| ODIV5_CASCADE_EN_basicPage | false |
| PLL_MODE | false |
| PLL_PWD_EN | false |
| PLL_PWD_EN_advancedPage | false |
| PLL_PWD_EN_basicPage | false |
| PLL_SEL_advancedPage | 0 |
| PLL_SEL_basicPage | 0 |
| RST_INNER_EN | false |
| RST_INNER_EN_advancedPage | false |
| RST_INNER_EN_basicPage | false |
| SSC_EN_advancedPage | DISABLE |
| SSC_EN_basicPage | DISABLE |
| SSC_FREQ | 25 |
| SSC_FREQ_advancedPage | 25 |
| SSC_FREQ_basicPage | 25 |
| SSC_MODE | DISABLE |
| STATIC_CPHASE0 | 0 |
| STATIC_CPHASE0_advancedPage | 0 |
| STATIC_CPHASE1 | 0 |
| STATIC_CPHASE1_advancedPage | 0 |
| STATIC_CPHASE2 | 0 |
| STATIC_CPHASE2_advancedPage | 0 |
| STATIC_CPHASE3 | 0 |
| STATIC_CPHASE3_advancedPage | 0 |
| STATIC_CPHASE4 | 0 |
| STATIC_CPHASE4_advancedPage | 0 |
| STATIC_CPHASE5 | 0 |
| STATIC_CPHASE5_advancedPage | 0 |
| STATIC_CPHASE6 | 0 |
| STATIC_CPHASE6_advancedPage | 0 |
| STATIC_CPHASE7 | 0 |
| STATIC_CPHASE7_advancedPage | 0 |
| STATIC_CPHASE8 | 0 |
| STATIC_CPHASE8_advancedPage | 0 |
| STATIC_DUTY0 | 10 |
| STATIC_DUTY1 | 2 |
| STATIC_DUTY2 | 15 |
| STATIC_DUTY3 | 15 |
| STATIC_DUTY4 | 15 |
| STATIC_DUTY5 | 15 |
| STATIC_DUTY6 | 15 |
| STATIC_DUTY7 | 13 |
| STATIC_DUTY8 | 2 |
| STATIC_FRAC0_advancedPage | 0 |
| STATIC_FRAC7_advancedPage | 0 |
| STATIC_PHASE | 0 |
| STATIC_PHASE0 | 0 |
| STATIC_PHASE0_advancedPage | 0 |
| STATIC_PHASE1 | 0 |
| STATIC_PHASE1_advancedPage | 0 |
| STATIC_PHASE2 | 0 |
| STATIC_PHASE2_advancedPage | 0 |
| STATIC_PHASE3 | 0 |
| STATIC_PHASE3_advancedPage | 0 |
| STATIC_PHASE4 | 0 |
| STATIC_PHASE4_advancedPage | 0 |
| STATIC_PHASE5 | 0 |
| STATIC_PHASE5_advancedPage | 0 |
| STATIC_PHASE6 | 0 |
| STATIC_PHASE6_advancedPage | 0 |
| STATIC_PHASE7 | 0 |
| STATIC_PHASE7_advancedPage | 0 |
| STATIC_PHASE8 | 0 |
| STATIC_PHASE8_advancedPage | 0 |
| STATIC_RATIO0 | 10.0 |
| STATIC_RATIO0_advancedPage | 24 |
| STATIC_RATIO1 | 2 |
| STATIC_RATIO1_advancedPage | 24 |
| STATIC_RATIO2 | 15 |
| STATIC_RATIO2_advancedPage | 24 |
| STATIC_RATIO3 | 15 |
| STATIC_RATIO3_advancedPage | 24 |
| STATIC_RATIO4 | 15 |
| STATIC_RATIO4_advancedPage | 24 |
| STATIC_RATIO5 | 15 |
| STATIC_RATIO5_advancedPage | 24 |
| STATIC_RATIO5_basicPage | 1 |
| STATIC_RATIO6 | 15 |
| STATIC_RATIO6_advancedPage | 24 |
| STATIC_RATIO7 | 13.75 |
| STATIC_RATIO7_advancedPage | 24 |
| STATIC_RATIO8 | 1 |
| STATIC_RATIO8_advancedPage | 24 |
| STATIC_RATIOI | 1 |
| STATIC_RATIOI_advancedPage | 1 |
| STATIC_RATIOM | 2 |
| STATIC_RATIOM_advancedPage | 1 |

## mul

| 项 | 值 |
|---|---|
| name | 28nm Simple Multiplier |
| version | 1.5 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| ADVANCED_BOOL | true |
| APM10_BOOL | false |
| APM11_BOOL | false |
| APM12_BOOL | false |
| APM13_BOOL | false |
| APM14_BOOL | false |
| APM1_BOOL | false |
| APM2_BOOL | false |
| APM3_BOOL | false |
| APM4_BOOL | false |
| APM5_BOOL | false |
| APM6_BOOL | false |
| APM7_BOOL | false |
| APM8_BOOL | false |
| APM9_BOOL | false |
| ASIZE | 33 |
| ASYNC_RST | 1 |
| ASYNC_RST_BOOL | true |
| A_SIGNED | 1 |
| BSIZE | 33 |
| B_SIGNED | 1 |
| CPO_REG | 14'b00000000000000 |
| INREG_BOOL | false |
| INREG_EN | 0 |
| MREG_BOOL | true |
| OPTIMAL_TIMING | 0 |
| OPTIMAL_TIMING_BOOL | false |
| OUTREG_BOOL | false |
| OUTREG_EN | 0 |
| PIPELINE_TXT | 0 |
| PIPEREG_EN_1 | 1 |
| PIPEREG_EN_2 | 1 |
| PIPEREG_EN_3 | 1 |
| PIPE_STATUS | 3 |
| PREG_BOOL | true |
| XYREG_BOOL | true |

## pixel_line_ram

| 项 | 值 |
|---|---|
| name | 28nm DRM Based Simple Dual Port RAM |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| BE_WIDTH | 4 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| FAB_REG | false |
| INIT_EN | false |
| INIT_FILE | NONE |
| INIT_FORMAT | BIN |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_ADDR_STROBE_EN | false |
| RD_ADDR_WIDTH | 10 |
| RD_BE_WIDTH | 4 |
| RD_CLK_EN | true |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 32 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_ADDR_STROBE_EN | false |
| WR_ADDR_WIDTH | 10 |
| WR_BYTE_EN | true |
| WR_CLK_EN | false |
| WR_DATA_WIDTH | 32 |

## pll0

| 项 | 值 |
|---|---|
| name | 28nm PLL |
| version | 1.4 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| APB_EN | false |
| APB_EN_advancedPage | false |
| APB_EN_basicPage | false |
| BANDWIDTH | OPTIMIZED |
| BANDWIDTH_advancedPage | OPTIMIZED |
| CLKIN1_BUFG_EN | false |
| CLKIN1_INBUFDS_EN | false |
| CLKIN1_INBUF_EN | false |
| CLKIN1_NOBUF_EN | true |
| CLKIN1_SOURCE_advancedPage | No Buffer |
| CLKIN1_SOURCE_basicPage | No Buffer |
| CLKIN2_BUFG_EN | false |
| CLKIN2_INBUFDS_EN | false |
| CLKIN2_INBUF_EN | false |
| CLKIN2_NOBUF_EN | true |
| CLKIN2_SOURCE_advancedPage | No Buffer |
| CLKIN2_SOURCE_basicPage | No Buffer |
| CLKIN_FREQ | 27.00000000 |
| CLKIN_FREQ_advancedPage | 50.00000000 |
| CLKIN_FREQ_basicPage | 27.00000000 |
| CLKOUT0_BUFCE | false |
| CLKOUT0_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT0_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT0_BUFGCE_EN | false |
| CLKOUT0_BUFG_EN | false |
| CLKOUT0_BUFR_EN | false |
| CLKOUT0_BUFXCE_EN | false |
| CLKOUT0_BUFX_EN | false |
| CLKOUT0_DPS_SEL_advancedPage | false |
| CLKOUT0_DPS_SEL_basicPage | false |
| CLKOUT0_EN | true |
| CLKOUT0_EN_advancedPage | true |
| CLKOUT0_EN_basicPage | true |
| CLKOUT0_GATE_EN_advancedPage | false |
| CLKOUT0_GATE_EN_basicPage | false |
| CLKOUT0_IOCLKBUF_EN | false |
| CLKOUT0_NOBUF_EN | true |
| CLKOUT0_N_EN | false |
| CLKOUT0_N_EN_advancedPage | false |
| CLKOUT0_N_EN_basicPage | false |
| CLKOUT0_REQ_DUTY_advancedPage | 24 |
| CLKOUT0_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT0_REQ_FREQ_basicPage | 100.00000000 |
| CLKOUT0_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT0_SYN_EN | false |
| CLKOUT1_BUFCE | false |
| CLKOUT1_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT1_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT1_BUFGCE_EN | false |
| CLKOUT1_BUFG_EN | false |
| CLKOUT1_BUFR_EN | false |
| CLKOUT1_BUFXCE_EN | false |
| CLKOUT1_BUFX_EN | false |
| CLKOUT1_DPS_SEL_advancedPage | false |
| CLKOUT1_DPS_SEL_basicPage | false |
| CLKOUT1_EN | false |
| CLKOUT1_EN_advancedPage | false |
| CLKOUT1_EN_basicPage | false |
| CLKOUT1_GATE_EN_advancedPage | false |
| CLKOUT1_GATE_EN_basicPage | false |
| CLKOUT1_IOCLKBUF_EN | false |
| CLKOUT1_NOBUF_EN | true |
| CLKOUT1_N_EN | false |
| CLKOUT1_N_EN_advancedPage | false |
| CLKOUT1_N_EN_basicPage | false |
| CLKOUT1_REQ_DUTY_advancedPage | 24 |
| CLKOUT1_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT1_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT1_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT1_SYN_EN | false |
| CLKOUT2_BUFCE | false |
| CLKOUT2_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT2_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT2_BUFGCE_EN | false |
| CLKOUT2_BUFG_EN | false |
| CLKOUT2_BUFR_EN | false |
| CLKOUT2_BUFXCE_EN | false |
| CLKOUT2_BUFX_EN | false |
| CLKOUT2_DPS_SEL_advancedPage | false |
| CLKOUT2_DPS_SEL_basicPage | false |
| CLKOUT2_EN | false |
| CLKOUT2_EN_advancedPage | false |
| CLKOUT2_EN_basicPage | false |
| CLKOUT2_GATE_EN_advancedPage | false |
| CLKOUT2_GATE_EN_basicPage | false |
| CLKOUT2_IOCLKBUF_EN | false |
| CLKOUT2_NOBUF_EN | true |
| CLKOUT2_N_EN | false |
| CLKOUT2_N_EN_advancedPage | false |
| CLKOUT2_N_EN_basicPage | false |
| CLKOUT2_REQ_DUTY_advancedPage | 24 |
| CLKOUT2_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT2_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT2_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT2_SYN_EN | false |
| CLKOUT3_BUFCE | false |
| CLKOUT3_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT3_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT3_BUFGCE_EN | false |
| CLKOUT3_BUFG_EN | false |
| CLKOUT3_BUFR_EN | false |
| CLKOUT3_BUFXCE_EN | false |
| CLKOUT3_BUFX_EN | false |
| CLKOUT3_DPS_SEL_advancedPage | false |
| CLKOUT3_DPS_SEL_basicPage | false |
| CLKOUT3_EN | false |
| CLKOUT3_EN_advancedPage | false |
| CLKOUT3_EN_basicPage | false |
| CLKOUT3_GATE_EN_advancedPage | false |
| CLKOUT3_GATE_EN_basicPage | false |
| CLKOUT3_IOCLKBUF_EN | false |
| CLKOUT3_NOBUF_EN | true |
| CLKOUT3_N_EN | false |
| CLKOUT3_N_EN_advancedPage | false |
| CLKOUT3_N_EN_basicPage | false |
| CLKOUT3_REQ_DUTY_advancedPage | 24 |
| CLKOUT3_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT3_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT3_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT3_SYN_EN | false |
| CLKOUT4_BUFCE | false |
| CLKOUT4_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT4_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT4_BUFGCE_EN | false |
| CLKOUT4_BUFG_EN | false |
| CLKOUT4_BUFXCE_EN | false |
| CLKOUT4_BUFX_EN | false |
| CLKOUT4_DPS_SEL_advancedPage | false |
| CLKOUT4_DPS_SEL_basicPage | false |
| CLKOUT4_EN | false |
| CLKOUT4_EN_advancedPage | false |
| CLKOUT4_EN_basicPage | false |
| CLKOUT4_GATE_EN_advancedPage | false |
| CLKOUT4_GATE_EN_basicPage | false |
| CLKOUT4_NOBUF_EN | true |
| CLKOUT4_REQ_DUTY_advancedPage | 24 |
| CLKOUT4_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT4_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT4_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT4_SYN_EN | false |
| CLKOUT5_BUFCE | false |
| CLKOUT5_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT5_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT5_BUFGCE_EN | false |
| CLKOUT5_BUFG_EN | false |
| CLKOUT5_BUFXCE_EN | false |
| CLKOUT5_BUFX_EN | false |
| CLKOUT5_DPS_SEL_advancedPage | false |
| CLKOUT5_DPS_SEL_basicPage | false |
| CLKOUT5_EN | false |
| CLKOUT5_EN_advancedPage | false |
| CLKOUT5_EN_basicPage | false |
| CLKOUT5_GATE_EN_advancedPage | false |
| CLKOUT5_GATE_EN_basicPage | false |
| CLKOUT5_NOBUF_EN | true |
| CLKOUT5_REQ_DUTY_advancedPage | 24 |
| CLKOUT5_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT5_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT5_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT5_SYN_EN | false |
| CLKOUT6_BUFCE | false |
| CLKOUT6_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT6_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT6_BUFGCE_EN | false |
| CLKOUT6_BUFG_EN | false |
| CLKOUT6_BUFXCE_EN | false |
| CLKOUT6_BUFX_EN | false |
| CLKOUT6_DPS_SEL_advancedPage | false |
| CLKOUT6_DPS_SEL_basicPage | false |
| CLKOUT6_EN | false |
| CLKOUT6_EN_advancedPage | false |
| CLKOUT6_EN_basicPage | false |
| CLKOUT6_GATE_EN_advancedPage | false |
| CLKOUT6_GATE_EN_basicPage | false |
| CLKOUT6_NOBUF_EN | true |
| CLKOUT6_REQ_DUTY_advancedPage | 24 |
| CLKOUT6_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT6_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT6_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT6_SYN_EN | false |
| CLKOUT7_BUFCE | false |
| CLKOUT7_BUFFER_OPTION_advancedPage | NO BUFFER |
| CLKOUT7_BUFFER_OPTION_basicPage | NO BUFFER |
| CLKOUT7_BUFGCE_EN | false |
| CLKOUT7_BUFG_EN | false |
| CLKOUT7_BUFXCE_EN | false |
| CLKOUT7_BUFX_EN | false |
| CLKOUT7_DPS_SEL_advancedPage | false |
| CLKOUT7_DPS_SEL_basicPage | false |
| CLKOUT7_EN | false |
| CLKOUT7_EN_advancedPage | false |
| CLKOUT7_EN_basicPage | false |
| CLKOUT7_GATE_EN_advancedPage | false |
| CLKOUT7_GATE_EN_basicPage | false |
| CLKOUT7_NOBUF_EN | true |
| CLKOUT7_N_EN | false |
| CLKOUT7_N_EN_advancedPage | false |
| CLKOUT7_N_EN_basicPage | false |
| CLKOUT7_REQ_DUTY_advancedPage | 24 |
| CLKOUT7_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT7_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT7_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT7_SYN_EN | false |
| CLKOUT8_EN | false |
| CLKOUT8_EN_advancedPage | false |
| CLKOUT8_EN_basicPage | false |
| CLKOUT8_GATE_EN_advancedPage | false |
| CLKOUT8_GATE_EN_basicPage | false |
| CLKOUT8_N_EN | false |
| CLKOUT8_N_EN_advancedPage | false |
| CLKOUT8_N_EN_basicPage | false |
| CLKOUT8_REQ_DUTY_advancedPage | 24 |
| CLKOUT8_REQ_DUTY_basicPage | 50.000000 |
| CLKOUT8_REQ_FREQ_basicPage | 50.00000000 |
| CLKOUT8_REQ_PHASE_basicPage | 0.000000 |
| CLKOUT8_SYN_EN | false |
| CLK_CAS5_EN | false |
| CLK_DPS0_EN | false |
| CLK_DPS1_EN | false |
| CLK_DPS2_EN | false |
| CLK_DPS3_EN | false |
| CLK_DPS4_EN | false |
| CLK_DPS5_EN | false |
| CLK_DPS6_EN | false |
| CLK_DPS7_EN | false |
| DEVICE_PG2L50H | false |
| DEVICE_Titan2 | false |
| DYNAMIC_CLKIN_EN | false |
| DYNAMIC_CLKIN_EN_advancedPage | false |
| DYNAMIC_CLKIN_EN_basicPage | false |
| DYNAMIC_PHASE_EN | false |
| DYNAMIC_PHASE_EN_advancedPage | false |
| DYNAMIC_PHASE_EN_basicPage | false |
| EXTERNAL_FB | DISABLE |
| FB_MODE | false |
| FB_MODE_advancedPage | 0 |
| FB_MODE_basicPage | 0 |
| FB_advancedPage | 7 |
| FB_basicPage | 7 |
| INTERNAL_FB | CLKOUTF |
| InsertPhase_advancedPage | 0 |
| LOCK_MODE | 0 |
| LOCK_MODE_advancedPage | false |
| MODE_CFG | 0 |
| ODIV5_CASCADE_EN_advancedPage | false |
| ODIV5_CASCADE_EN_basicPage | false |
| PLL_MODE | false |
| PLL_PWD_EN | false |
| PLL_PWD_EN_advancedPage | false |
| PLL_PWD_EN_basicPage | false |
| PLL_SEL_advancedPage | 0 |
| PLL_SEL_basicPage | 0 |
| RST_INNER_EN | false |
| RST_INNER_EN_advancedPage | false |
| RST_INNER_EN_basicPage | false |
| SSC_EN_advancedPage | DISABLE |
| SSC_EN_basicPage | DISABLE |
| SSC_FREQ | 25 |
| SSC_FREQ_advancedPage | 25 |
| SSC_FREQ_basicPage | 25 |
| SSC_MODE | DISABLE |
| STATIC_CPHASE0 | 0 |
| STATIC_CPHASE0_advancedPage | 0 |
| STATIC_CPHASE1 | 0 |
| STATIC_CPHASE1_advancedPage | 0 |
| STATIC_CPHASE2 | 0 |
| STATIC_CPHASE2_advancedPage | 0 |
| STATIC_CPHASE3 | 0 |
| STATIC_CPHASE3_advancedPage | 0 |
| STATIC_CPHASE4 | 0 |
| STATIC_CPHASE4_advancedPage | 0 |
| STATIC_CPHASE5 | 0 |
| STATIC_CPHASE5_advancedPage | 0 |
| STATIC_CPHASE6 | 0 |
| STATIC_CPHASE6_advancedPage | 0 |
| STATIC_CPHASE7 | 0 |
| STATIC_CPHASE7_advancedPage | 0 |
| STATIC_CPHASE8 | 0 |
| STATIC_CPHASE8_advancedPage | 0 |
| STATIC_DUTY0 | 10 |
| STATIC_DUTY1 | 20 |
| STATIC_DUTY2 | 20 |
| STATIC_DUTY3 | 20 |
| STATIC_DUTY4 | 20 |
| STATIC_DUTY5 | 20 |
| STATIC_DUTY6 | 20 |
| STATIC_DUTY7 | 18 |
| STATIC_DUTY8 | 2 |
| STATIC_FRAC0_advancedPage | 0 |
| STATIC_FRAC7_advancedPage | 0 |
| STATIC_PHASE | 0 |
| STATIC_PHASE0 | 0 |
| STATIC_PHASE0_advancedPage | 0 |
| STATIC_PHASE1 | 0 |
| STATIC_PHASE1_advancedPage | 0 |
| STATIC_PHASE2 | 0 |
| STATIC_PHASE2_advancedPage | 0 |
| STATIC_PHASE3 | 0 |
| STATIC_PHASE3_advancedPage | 0 |
| STATIC_PHASE4 | 0 |
| STATIC_PHASE4_advancedPage | 0 |
| STATIC_PHASE5 | 0 |
| STATIC_PHASE5_advancedPage | 0 |
| STATIC_PHASE6 | 0 |
| STATIC_PHASE6_advancedPage | 0 |
| STATIC_PHASE7 | 0 |
| STATIC_PHASE7_advancedPage | 0 |
| STATIC_PHASE8 | 0 |
| STATIC_PHASE8_advancedPage | 0 |
| STATIC_RATIO0 | 10.125 |
| STATIC_RATIO0_advancedPage | 24 |
| STATIC_RATIO1 | 20 |
| STATIC_RATIO1_advancedPage | 24 |
| STATIC_RATIO2 | 20 |
| STATIC_RATIO2_advancedPage | 24 |
| STATIC_RATIO3 | 20 |
| STATIC_RATIO3_advancedPage | 24 |
| STATIC_RATIO4 | 20 |
| STATIC_RATIO4_advancedPage | 24 |
| STATIC_RATIO5 | 20 |
| STATIC_RATIO5_advancedPage | 24 |
| STATIC_RATIO5_basicPage | 1 |
| STATIC_RATIO6 | 20 |
| STATIC_RATIO6_advancedPage | 24 |
| STATIC_RATIO7 | 18.75 |
| STATIC_RATIO7_advancedPage | 24 |
| STATIC_RATIO8 | 42 |
| STATIC_RATIO8_advancedPage | 24 |
| STATIC_RATIOI | 1 |
| STATIC_RATIOI_advancedPage | 1 |
| STATIC_RATIOM | 2 |
| STATIC_RATIOM_advancedPage | 1 |

## sram

| 项 | 值 |
|---|---|
| name | 28nm DRM Based Simple Dual Port RAM |
| version | 1.10 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| BE_WIDTH | 8 |
| BYTE_SIZE | 8 |
| CAS_MODE | 36K |
| CAS_MODE_SEL | AUTO |
| FAB_REG | false |
| INIT_EN | true |
| INIT_FILE | G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/sram.dat |
| INIT_FORMAT | HEX |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_ADDR_STROBE_EN | false |
| RD_ADDR_WIDTH | 12 |
| RD_BE_WIDTH | 8 |
| RD_CLK_EN | false |
| RD_CLK_OR_POL_INV | false |
| RD_DATA_WIDTH | 64 |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
| SAMEWIDTH_EN | true |
| WR_ADDR_STROBE_EN | false |
| WR_ADDR_WIDTH | 12 |
| WR_BYTE_EN | true |
| WR_CLK_EN | false |
| WR_DATA_WIDTH | 64 |

## trig_rom

| 项 | 值 |
|---|---|
| name | 28nm DRM Based ROM |
| version | 1.8 |
| device | PG2L200H |
| package | FBB676 |
| speedgrade | -6 |

| 参数 | 原始值 |
|---|---|
| ADDR_STROBE_EN | false |
| ADDR_WIDTH | 9 |
| CAS_MODE | 18K |
| CAS_MODE_SEL | AUTO |
| CLK_EN | false |
| CLK_OR_POL_INV | false |
| DATA_WIDTH | 36 |
| FAB_REG | false |
| INIT_EN | true |
| INIT_FILE | G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc/trig_q2_16.dat |
| INIT_FORMAT | HEX |
| OUTPUT_REG | false |
| POWER_OPT | false |
| RD_OCE_EN | false |
| RESET_TYPE | ASYNC |
| RST_VAL | 0 |
| RST_VAL_EN | false |
