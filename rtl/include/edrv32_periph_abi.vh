// ============================================================================
// File        : edrv32_periph_abi.vh
// Author      : Edward ZC
// Description : Peripheral register ABI - register offsets, bit fields and
//               device-side encodings (CLINT/PLIC/UART/GPIO/SPI/TIMER).
// Notes       : Hand-maintained on purpose: these are device register
//               contracts, not address-map data, so they are NOT part of the
//               soc_address_map.json single source.  Region bases, APB slot
//               addresses, decode fields and PLIC source numbering are
//               GENERATED in edrv32_soc_map.vh / edrv32_pma.vh from
//               rtl/include/soc_address_map.json.  This file is included by
//               edrv32_soc_map.vh, so consumers get both via that include.
// ============================================================================
`ifndef EDRV32_PERIPH_ABI_VH
`define EDRV32_PERIPH_ABI_VH

// ----------------------------------------------------------------------------
// CLINT register offsets (SiFive layout, design §6.5.1).  mtime/mtimecmp are
// 64-bit; low/high word accessed as two 32-bit transfers under RV32.
// ----------------------------------------------------------------------------
`define CLINT_MSIP        16'h0000       // bit0: software-interrupt pending
`define CLINT_MTIMECMP_LO 16'h4000
`define CLINT_MTIMECMP_HI 16'h4004
`define CLINT_MTIME_LO    16'hBFF8
`define CLINT_MTIME_HI    16'hBFFC

// ----------------------------------------------------------------------------
// PLIC register offsets (single M-context, design §6.5.1).
// priority[i] at PRIORITY_BASE + 4*i (source 0 reserved, reads 0).
// ----------------------------------------------------------------------------
`define PLIC_PRIORITY_BASE 24'h00_0000   // priority[i] = base + 4*i
`define PLIC_PENDING       24'h00_1000   // pending bitmap (read-only)
`define PLIC_ENABLE        24'h00_2000   // context0 enable bitmap
`define PLIC_THRESHOLD     24'h20_0000   // context0 priority threshold
`define PLIC_CLAIM         24'h20_0004   // read=claim, write=complete
`define PLIC_PRIORITY_WIDTH 3

// ----------------------------------------------------------------------------
// UART register offsets.  Configurable frame format + FIFO + error detection
// + loopback + sticky interrupts.
// ----------------------------------------------------------------------------
`define UART_TXDATA       8'h00          // write: enqueue TX byte [7:0]
`define UART_RXDATA       8'h04          // read: dequeue RX byte [7:0]
`define UART_STATUS       8'h08          // status flags (see bits below)
`define UART_CTRL         8'h0C          // control (see bits below)
`define UART_CLKDIV       8'h10          // baud-rate divisor
`define UART_FORMAT       8'h14          // frame format (data/stop/parity)
`define UART_IP           8'h18          // sticky interrupt-pending (write 1 clear)
`define UART_IE           8'h1C          // interrupt enable
`define UART_FIFO_DEPTH   8'h20          // implemented TX/RX FIFO depths
`define UART_RTS_CTRL     8'h24          // RTS threshold and RTS/CTS polarity

// STATUS bits
`define UART_STATUS_TX_EMPTY 0           // TX FIFO empty
`define UART_STATUS_TX_FULL  1           // TX FIFO full
`define UART_STATUS_RX_EMPTY 2           // RX FIFO empty
`define UART_STATUS_RX_FULL  3           // RX FIFO full
`define UART_STATUS_TX_BUSY  4           // shifter busy
`define UART_STATUS_FRAME_ERR 5
`define UART_STATUS_PARITY_ERR 6
`define UART_STATUS_OVERRUN_ERR 7
// CTRL bits
`define UART_CTRL_EN         0
`define UART_CTRL_LOOPBACK   1
`define UART_CTRL_FIFO_CLR_TX 2          // self-clearing TX FIFO flush
`define UART_CTRL_FIFO_CLR_RX 3          // self-clearing RX FIFO flush
`define UART_CTRL_RTS_EN     4
`define UART_CTRL_CTS_EN     5
// FORMAT fields
`define UART_FMT_DATA_LSB    0           // [1:0] data bits: 0=5,1=6,2=7,3=8
`define UART_FMT_DATA_MSB    1
`define UART_FMT_STOP        2           // 0=1 stop, 1=2 stop
`define UART_FMT_PAR_LSB     3           // [4:3] parity: 0=none,1=odd,2=even
`define UART_FMT_PAR_MSB     4
// IP bits (sticky, write 1 to clear)
`define UART_IP_TX          0            // TX empty
`define UART_IP_RX          1            // RX non-empty
`define UART_IP_ERR         2            // frame/parity/overrun error
`define UART_IP_CTS_CHANGE  3
`define UART_IP_RX_TIMEOUT  4
// IE bits
`define UART_IE_TX          0
`define UART_IE_RX          1
`define UART_IE_ERR         2
`define UART_IE_CTS_CHANGE  3
`define UART_IE_RX_TIMEOUT  4

// ----------------------------------------------------------------------------
// GPIO register offsets.  SET/CLR atomic + level/edge interrupts + sticky
// pending.  Phase-1 GPIO is 16 bit (design §6.5.1).
// ----------------------------------------------------------------------------
`define GPIO_DIR          8'h00          // 1=output, 0=input (per bit)
`define GPIO_OUT          8'h04          // output value
`define GPIO_IN           8'h08          // input readback
`define GPIO_OUT_SET      8'h0C          // write 1 sets OUT bit (atomic)
`define GPIO_OUT_CLR      8'h10          // write 1 clears OUT bit (atomic)
`define GPIO_INT_EN       8'h14          // per-bit interrupt enable
`define GPIO_INT_TYPE     8'h18          // per-bit 0=level, 1=edge
`define GPIO_INT_POL      8'h1C          // level: 0=low/1=high; edge: 0=falling/1=rising
`define GPIO_INT_EDGE_BOTH 8'h20         // per-bit 1=both edges (edge mode)
`define GPIO_INT_PENDING  8'h24          // sticky pending (write 1 clear)
`define GPIO_INT_STATUS   8'h28          // live interrupt condition

// ----------------------------------------------------------------------------
// SPI register offsets.  Full/half duplex, Mode 0-3, MSB/LSB, configurable
// bit width, multi chip-select, sticky interrupt.
// ----------------------------------------------------------------------------
`define SPI_CTRL          8'h00          // control (see bits below)
`define SPI_STATUS        8'h04          // bit0 busy / bit1 done
`define SPI_TXDATA        8'h08          // write: transmit data, starts transfer
`define SPI_RXDATA        8'h0C          // read: last received data
`define SPI_CLKDIV        8'h10          // SCLK divisor
`define SPI_CSMASK        8'h14          // selected chip-select bitmap
`define SPI_CS            `SPI_CSMASK    // legacy generic name
`define SPI_BITS          8'h18          // transfer bit width (1..SPI_MAX_BITS)
`define SPI_IP            8'h1C          // sticky interrupt-pending (write 1 clear)
`define SPI_IE            8'h20          // interrupt enable
`define SPI_MODE          8'h24          // Single/Dual/Quad and command phase
`define SPI_CMD           8'h28          // command byte and length

`define SPI_CTRL_EN       0
`define SPI_CTRL_CPOL     1
`define SPI_CTRL_CPHA     2
`define SPI_CTRL_IE       3
`define SPI_CTRL_LSB      4              // 0=MSB-first, 1=LSB-first
`define SPI_CTRL_HALF     5              // 1=half-duplex (shared IO line)
`define SPI_CTRL_HALF_DIR 6             // half-duplex: 0=receive, 1=transmit
`define SPI_CTRL_FIFO_CLR 7             // write pulse: clear TX/RX FIFOs and error status
`define SPI_CTRL_CS_AUTO  8             // 1=assert selected CS only while busy
`define SPI_STATUS_BUSY   0
`define SPI_STATUS_DONE   1
`define SPI_STATUS_TX_EMPTY 2
`define SPI_STATUS_TX_FULL  3
`define SPI_STATUS_RX_EMPTY 4
`define SPI_STATUS_RX_FULL  5
`define SPI_STATUS_MODE_FAULT 6
`define SPI_STATUS_TX_OVERFLOW 7
`define SPI_STATUS_RX_UNDERFLOW 8
`define SPI_STATUS_RX_OVERFLOW 9
`define SPI_IP_DONE       0             // transfer-complete pending
`define SPI_IP_ERROR      1             // mode/FIFO error pending
`define SPI_IE_DONE       0
`define SPI_IE_ERROR      1
`define SPI_MODE_WIDTH_LSB 0
`define SPI_MODE_WIDTH_MSB 1
`define SPI_MODE_SINGLE   2'd0
`define SPI_MODE_DUAL     2'd1
`define SPI_MODE_QUAD     2'd2
`define SPI_MODE_CMD_PHASE 4
`define SPI_CMD_DATA_LSB  0
`define SPI_CMD_DATA_MSB  7
`define SPI_CMD_BITS_LSB  8
`define SPI_CMD_BITS_MSB  11            // 0=8 bits, otherwise 1..8

// ----------------------------------------------------------------------------
// DDR monitor register offsets.  The APB control plane runs in the SoC clock
// domain; commands and result snapshots cross into/out of the DDR AXI domain.
// All traffic consists of aligned 256-bit INCR bursts.
// ----------------------------------------------------------------------------
`define DDR_MON_ID                 8'h00
`define DDR_MON_VERSION            8'h04
`define DDR_MON_CONTROL            8'h08
`define DDR_MON_STATUS             8'h0C
`define DDR_MON_MODE               8'h10
`define DDR_MON_BASE_ADDR          8'h14
`define DDR_MON_TOTAL_BEATS        8'h18
`define DDR_MON_BURST_LEN          8'h1C // AxLEN, hardware caps at 4'hf
`define DDR_MON_PATTERN_SEED       8'h20
`define DDR_MON_LOOP_COUNT         8'h24
`define DDR_MON_TOTAL_CYCLES       8'h30
`define DDR_MON_WRITE_BEATS        8'h34
`define DDR_MON_READ_BEATS         8'h38
`define DDR_MON_AW_STALL_CYCLES    8'h3C
`define DDR_MON_W_STALL_CYCLES     8'h40
`define DDR_MON_AR_STALL_CYCLES    8'h44
`define DDR_MON_R_WAIT_CYCLES      8'h48
`define DDR_MON_ERROR_COUNT        8'h4C
`define DDR_MON_FIRST_ERROR_ADDR   8'h50
`define DDR_MON_EXPECTED_DATA      8'h54
`define DDR_MON_ACTUAL_DATA        8'h58

`define DDR_MON_CONTROL_START      0
`define DDR_MON_CONTROL_CLEAR      1
`define DDR_MON_STATUS_BUSY        0
`define DDR_MON_STATUS_DONE        1
`define DDR_MON_STATUS_ERROR       2
`define DDR_MON_STATUS_CMD_READY   3

`define DDR_MON_MODE_WRITE         2'd0
`define DDR_MON_MODE_READ_VERIFY   2'd1
`define DDR_MON_MODE_WRITE_READ    2'd2

// ----------------------------------------------------------------------------
// Camera control block (APB slot 6). Runtime sensor writes use a bundled-data
// toggle handshake to the SCCB clock domain.
// ----------------------------------------------------------------------------
`define CAM_ID                      8'h00
`define CAM_VERSION                 8'h04
`define CAM_CAPABILITY              8'h08
`define CAM_CONTROL                 8'h0C
`define CAM_STATUS                  8'h10
`define CAM_FRAME_COUNT0            8'h14
`define CAM_FRAME_COUNT1            8'h18
`define CAM_IRQ_ENABLE              8'h1C
`define CAM_IRQ_STATUS              8'h20
`define CAM_SCCB_TARGET             8'h24
`define CAM_SCCB_REG_ADDR           8'h28
`define CAM_SCCB_WRITE_DATA         8'h2C
`define CAM_SCCB_COMMAND            8'h30
`define CAM_SCCB_STATUS             8'h34
`define CAM_SCCB_READ_DATA          8'h38

`define CAM_CONTROL_CAM0_ENABLE     0
`define CAM_CONTROL_CAM1_ENABLE     1
`define CAM_STATUS_CAM0_INIT_DONE   0
`define CAM_STATUS_CAM1_INIT_DONE   1
`define CAM_STATUS_ERROR            2
`define CAM_IRQ_FRAME0              0
`define CAM_IRQ_FRAME1              1
`define CAM_IRQ_ERROR               2
`define CAM_IRQ_SCCB_DONE           3
`define CAM_IRQ_SCCB_ERROR          4
`define CAM_SCCB_COMMAND_SUBMIT      0
`define CAM_SCCB_COMMAND_READ        1
`define CAM_SCCB_STATUS_BUSY         0
`define CAM_SCCB_STATUS_DONE         1
`define CAM_SCCB_STATUS_ERROR        2
`define CAM_SCCB_STATUS_READY        3

// ----------------------------------------------------------------------------
// Pixel point-processing control block (APB slot 12).
// ----------------------------------------------------------------------------
`define PIXEL_ID                     8'h00
`define PIXEL_VERSION                8'h04
`define PIXEL_CAPABILITY             8'h08
`define PIXEL_CONTROL                8'h0C
`define PIXEL_BRIGHTNESS             8'h10
`define PIXEL_CONTRAST               8'h14
`define PIXEL_THRESHOLD              8'h18
`define PIXEL_COMMAND                8'h1C
`define PIXEL_STATUS                 8'h20
`define PIXEL_FRAME_COUNT            8'h24
`define PIXEL_ERROR_COUNT            8'h28
`define PIXEL_IRQ_ENABLE             8'h2C
`define PIXEL_IRQ_STATUS             8'h30
`define PIXEL_SPATIAL_CONTROL        8'h34
`define PIXEL_SPATIAL_THRESHOLD      8'h38

`define PIXEL_CONTROL_ENABLE         0
`define PIXEL_CONTROL_GRAYSCALE      1
`define PIXEL_CONTROL_THRESHOLD      2
`define PIXEL_CONTROL_INVERT         3
`define PIXEL_COMMAND_COMMIT         0
`define PIXEL_STATUS_PENDING         0
`define PIXEL_IRQ_FRAME              0
`define PIXEL_IRQ_ERROR              1
`define PIXEL_IRQ_COMMIT             2
`define PIXEL_SPATIAL_ENABLE         0
`define PIXEL_SPATIAL_MODE_LSB       1
`define PIXEL_SPATIAL_MODE_MSB       3

`define PIXEL_SPATIAL_BYPASS         3'd0
`define PIXEL_SPATIAL_SOBEL          3'd1
`define PIXEL_SPATIAL_MEAN           3'd2
`define PIXEL_SPATIAL_GAUSSIAN       3'd3
`define PIXEL_SPATIAL_SHARPEN        3'd4
`define PIXEL_SPATIAL_ERODE          3'd5
`define PIXEL_SPATIAL_DILATE         3'd6

// ----------------------------------------------------------------------------
// Display control block (APB slot 7). Buffer addresses describe the fixed
// initial display pool; programmable relocation is added with descriptor DMA.
// ----------------------------------------------------------------------------
`define DISP_ID                     8'h00
`define DISP_VERSION                8'h04
`define DISP_CAPABILITY             8'h08
`define DISP_CONTROL                8'h0C
`define DISP_STATUS                 8'h10
`define DISP_FRAME_COUNT            8'h14
`define DISP_UNDERFLOW_COUNT        8'h18
`define DISP_BUFFER0_BASE           8'h1C
`define DISP_BUFFER1_BASE           8'h20
`define DISP_BUFFER2_BASE           8'h24
`define DISP_IRQ_ENABLE             8'h28
`define DISP_IRQ_STATUS             8'h2C
`define DISP_SCANOUT_FRAME_COUNT    8'h30
`define DISP_DEBUG_STATUS           8'h34

`define DISP_CONTROL_ENABLE         0
`define DISP_STATUS_ENABLED         0
`define DISP_STATUS_ACTIVE_BUFFER_LSB 1
`define DISP_STATUS_ACTIVE_BUFFER_MSB 2
`define DISP_STATUS_ERROR           3
`define DISP_IRQ_FRAME              0
`define DISP_IRQ_UNDERFLOW          1
`define DISP_IRQ_ERROR              2

// ----------------------------------------------------------------------------
// GPT register offsets.  GPT is kept as source for Phase-2 enablement
// (design decision 2026-08-27); it has no Phase-1 APB slot.  Shared counter
// + compare/PWM channels.  Per-channel CCR/CCTRL at CH_BASE + 8*i.
// ----------------------------------------------------------------------------
`define TIMER_CTRL        8'h00          // enable / oneshot / count direction
`define TIMER_STATUS      8'h04          // bit0 running
`define TIMER_CNT         8'h08          // current counter (RW)
`define TIMER_PERIOD      8'h0C          // reload/period value
`define TIMER_IP          8'h10          // sticky period/compare/capture pending
`define TIMER_IE          8'h14          // interrupt enables
`define TIMER_PSC         8'h18          // 8-bit prescaler; tick every PSC+1 clocks
`define TIMER_CH_BASE     8'h20          // channel i: CCR at CH_BASE+8*i, CCTRL at +4
`define TIMER_CCR_OFF     8'h00          // compare value / captured count
`define TIMER_CCTRL_OFF   8'h04          // within channel: control

`define TIMER_CTRL_EN     0
`define TIMER_CTRL_ONESHOT 1
`define TIMER_CTRL_DOWN   2
`define TIMER_IP_PERIOD   0             // period terminal
`define TIMER_IP_CMP_BASE 1             // compare channel i: bit (1+i)
`define TIMER_IP_CAP_BASE 5             // capture channel i: bit (5+i)
`define TIMER_CCTRL_PWM_EN 0
`define TIMER_CCTRL_PWM_POL 1
`define TIMER_CCTRL_CAP_EN 2
`define TIMER_CCTRL_CAP_RISE 3
`define TIMER_CCTRL_CAP_FILTER 4

`endif // EDRV32_PERIPH_ABI_VH
