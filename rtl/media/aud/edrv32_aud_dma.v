// File: edrv32_aud_dma.v
// Spec: aud-spec 2.2-2.4, 4, 6; edrv32-soc-spec 4.2.
// Description: One-outstanding AXI256 ring reader and little-endian sample unpacker.
//              Bursts stop at availability, ring end, 512 bytes and 4 KiB boundaries.
// Clock domain: clk_mem.
module edrv32_aud_dma (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Ring configuration and lifecycle.
    input wire enable_i,
    input wire restart_i,
    input wire clear_error_i,
    input wire [31:0] ring_base_i,
    input wire [23:0] ring_size_i,
    input wire [23:0] wr_ptr_i,
    output reg [23:0] rd_ptr_o,
    output wire [23:0] avail_o,
    output wire busy_o,
    output wire error_o,

    // Sample FIFO producer and conservative free space.
    input wire [9:0] free_i,
    output wire sample_valid_o,
    input wire sample_ready_i,
    output wire [31:0] sample_data_o,

    // AXI256 read address and response.
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    output reg [31:0] m_axi_araddr_o,
    output reg [3:0] m_axi_arlen_o,
    output wire m_axi_arid_o,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rid_i
);
    localparam S_IDLE = 2'd0;
    localparam S_ADDR = 2'd1;
    localparam S_READ = 2'd2;
    localparam S_EMIT = 2'd3;
    reg [1:0] state_r;
    reg stopped_r;
    reg last_r;
    reg [2:0] sample_idx_r;
    reg [255:0] beat_r;
    wire [31:0] addr_w;
    wire [23:0] ring_left_w;
    wire [12:0] page_left_w;
    reg [23:0] bytes_w;
    wire unused_rid_w;

    assign unused_rid_w = m_axi_rid_i;
    assign avail_o = wr_ptr_i >= rd_ptr_o ? wr_ptr_i - rd_ptr_o :
        ring_size_i - rd_ptr_o + wr_ptr_i;
    assign addr_w = ring_base_i + {8'd0, rd_ptr_o};
    assign ring_left_w = ring_size_i - rd_ptr_o;
    assign page_left_w = 13'd4096 - {1'b0, addr_w[11:0]};
    always @(*) begin
        bytes_w = 24'd512;
        if (avail_o < bytes_w) begin
            bytes_w = avail_o;
        end
        if (ring_left_w < bytes_w) begin
            bytes_w = ring_left_w;
        end
        if ({11'd0, page_left_w} < bytes_w) begin
            bytes_w = {11'd0, page_left_w};
        end
    end

    assign m_axi_arvalid_o = (state_r == S_ADDR);
    assign m_axi_arid_o = 1'b0;
    assign m_axi_rready_o = (state_r == S_READ);
    assign sample_valid_o = (state_r == S_EMIT);
    assign sample_data_o = beat_r[sample_idx_r*32 +: 32];
    assign error_o = m_axi_rvalid_i && m_axi_rready_o && (m_axi_rresp_i != 2'b00);
    assign busy_o = (state_r != S_IDLE);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            stopped_r <= 1'b0;
            rd_ptr_o <= 24'd0;
            sample_idx_r <= 3'd0;
            last_r <= 1'b0;
        end else begin
            if (clear_error_i || restart_i) begin
                stopped_r <= 1'b0;
            end
            if (restart_i) begin
                rd_ptr_o <= 24'd0;
            end
            if (error_o) begin
                stopped_r <= 1'b1;
            end
            case (state_r)
                S_IDLE: begin
                    if (enable_i && !restart_i && !stopped_r && (bytes_w != 0) &&
                        ({14'd0, free_i} >= (bytes_w >> 2))) begin
                        state_r <= S_ADDR;
                    end
                end
                S_ADDR: begin
                    if (m_axi_arready_i) begin
                        state_r <= S_READ;
                    end
                end
                S_READ: begin
                    if (m_axi_rvalid_i) begin
                        if (rd_ptr_o + 24'd32 == ring_size_i) begin
                            rd_ptr_o <= 24'd0;
                        end else begin
                            rd_ptr_o <= rd_ptr_o + 24'd32;
                        end
                        last_r <= m_axi_rlast_i;
                        sample_idx_r <= 3'd0;
                        state_r <= error_o ? (m_axi_rlast_i ? S_IDLE : S_READ) : S_EMIT;
                    end
                end
                S_EMIT: begin
                    if (sample_ready_i) begin
                        sample_idx_r <= sample_idx_r + 1'b1;
                        if (sample_idx_r == 3'd7) begin
                            state_r <= last_r ? S_IDLE : S_READ;
                        end
                    end
                end
                default: begin
                    state_r <= S_IDLE;
                end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if ((state_r == S_IDLE) && enable_i && !restart_i && !stopped_r &&
            (bytes_w != 0) && ({14'd0, free_i} >= (bytes_w >> 2))) begin
            m_axi_araddr_o <= addr_w;
            m_axi_arlen_o <= bytes_w[8:5] - 1'b1;
        end
        if (m_axi_rvalid_i && m_axi_rready_o) begin
            beat_r <= m_axi_rdata_i;
        end
    end
endmodule
