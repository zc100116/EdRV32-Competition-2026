// ============================================================================
// File        : edrv32_yolo_uart_boot.v
// Description : UART configuration front end for the YOLO DDR image loader.
// Notes       : After enable, YCFG + base/size/CRC32 (little endian) starts
//               a paced YM packet transfer. All writes use one AXI
//               master and are independent of the convolution operator.
// ============================================================================

module edrv32_yolo_uart_boot #(
    parameter integer CLK_HZ = 150000000,
    parameter integer UART_BAUD = 115200
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         enable_i,
    input  wire         uart_rx_i,
    output wire         tx_valid_o,
    input  wire         tx_ready_i,
    output wire [7:0]   tx_data_o,
    output wire         transfer_busy_o,
    output wire         model_ready_o,
    output wire         model_error_o,
    output wire [31:0]  model_base_o,
    output wire [31:0]  model_size_o,
    output wire [31:0]  model_crc_o,
    output wire [31:0]  received_bytes_o,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire         m_awvalid_o,
    input  wire         m_awready_i,
    output wire [255:0] m_wdata_o,
    output wire [31:0]  m_wstrb_o,
    output wire         m_wlast_o,
    output wire         m_wvalid_o,
    input  wire         m_wready_i,
    input  wire [3:0]   m_bid_i,
    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output wire         m_bready_o
);

    localparam [2:0] C_SYNC0 = 3'd0;
    localparam [2:0] C_SYNC1 = 3'd1;
    localparam [2:0] C_SYNC2 = 3'd2;
    localparam [2:0] C_SYNC3 = 3'd3;
    localparam [2:0] C_WORDS = 3'd4;
    localparam [2:0] C_START = 3'd5;
    localparam [2:0] C_TRANSFER = 3'd6;

    reg [2:0] state_r;
    reg [3:0] config_index_r;
    reg [31:0] base_r;
    reg [31:0] size_r;
    reg [31:0] crc_r;
    wire rx_valid_w;
    wire [7:0] rx_data_w;
    wire rx_frame_error_w;
    wire loader_start_ready_w;
    wire loader_busy_w;
    wire loader_done_w;
    wire loader_error_w;
    wire loader_rx_window_w = state_r == C_TRANSFER ||
        (loader_done_w && (state_r == C_SYNC0 || state_r == C_SYNC1));
    wire loader_rx_valid_w = enable_i && rx_valid_w && loader_rx_window_w;
    wire loader_rx_error_w = enable_i && rx_frame_error_w &&
                             loader_rx_window_w;

    assign transfer_busy_o = loader_busy_w;
    assign model_ready_o = loader_done_w;
    assign model_error_o = loader_error_w;
    assign model_base_o = base_r;
    assign model_size_o = size_r;
    assign model_crc_o = crc_r;

    edrv32_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(UART_BAUD)) u_uart_rx (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .rx_i(uart_rx_i),
        .data_valid_o(rx_valid_w), .data_o(rx_data_w),
        .frame_error_o(rx_frame_error_w)
    );

    edrv32_yolo_serial_dma u_dma (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == C_START && enable_i),
        .start_ready_o(loader_start_ready_w),
        .base_i(base_r), .size_i(size_r), .expected_crc_i(crc_r),
        .rx_valid_i(loader_rx_valid_w), .rx_data_i(rx_data_w),
        .rx_frame_error_i(loader_rx_error_w),
        .tx_valid_o(tx_valid_o), .tx_ready_i(tx_ready_i),
        .tx_data_o(tx_data_o),
        .busy_o(loader_busy_w), .done_o(loader_done_w),
        .error_o(loader_error_w),
        .received_bytes_o(received_bytes_o), .next_seq_o(),
        .m_awid_o(m_awid_o), .m_awaddr_o(m_awaddr_o),
        .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awvalid_o(m_awvalid_o),
        .m_awready_i(m_awready_i),
        .m_wdata_o(m_wdata_o), .m_wstrb_o(m_wstrb_o),
        .m_wlast_o(m_wlast_o), .m_wvalid_o(m_wvalid_o),
        .m_wready_i(m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(m_bvalid_i), .m_bready_o(m_bready_o)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= C_SYNC0;
            config_index_r <= 4'd0;
            base_r <= 32'd0;
            size_r <= 32'd0;
            crc_r <= 32'd0;
        end else if (!enable_i) begin
            state_r <= C_SYNC0;
        end else if (rx_frame_error_w && state_r != C_TRANSFER) begin
            state_r <= C_SYNC0;
        end else begin
            case (state_r)
                C_SYNC0: if (rx_valid_w && rx_data_w == 8'h59)
                    state_r <= C_SYNC1;
                C_SYNC1: if (rx_valid_w)
                    state_r <= rx_data_w == 8'h43 ? C_SYNC2 :
                               rx_data_w == 8'h59 ? C_SYNC1 : C_SYNC0;
                C_SYNC2: if (rx_valid_w)
                    state_r <= rx_data_w == 8'h46 ? C_SYNC3 : C_SYNC0;
                C_SYNC3: if (rx_valid_w) begin
                    if (rx_data_w == 8'h47) begin
                        config_index_r <= 4'd0;
                        state_r <= C_WORDS;
                    end else
                        state_r <= C_SYNC0;
                end
                C_WORDS: if (rx_valid_w) begin
                    if (config_index_r < 4'd4)
                        base_r[config_index_r[1:0]*8 +: 8] <= rx_data_w;
                    else if (config_index_r < 4'd8)
                        size_r[config_index_r[1:0]*8 +: 8] <= rx_data_w;
                    else
                        crc_r[config_index_r[1:0]*8 +: 8] <= rx_data_w;
                    if (config_index_r == 4'd11)
                        state_r <= C_START;
                    else
                        config_index_r <= config_index_r + 4'd1;
                end
                C_START: if (loader_start_ready_w)
                    state_r <= C_TRANSFER;
                // A completed transfer keeps YM retry handling in the DMA.
                // A new YCFG starts another DDR region without board reset.
                C_TRANSFER: begin
                    if (loader_start_ready_w && loader_error_w)
                        state_r <= C_SYNC0;
                    else if (loader_done_w && rx_valid_w &&
                             rx_data_w == 8'h59)
                        state_r <= C_SYNC1;
                end
                default: state_r <= C_SYNC0;
            endcase
        end
    end
endmodule
