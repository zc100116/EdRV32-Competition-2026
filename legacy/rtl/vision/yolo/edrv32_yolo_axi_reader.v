// ============================================================================
// File        : edrv32_yolo_axi_reader.v
// Description : Ordered 256-bit AXI burst reader for weight or feature rows.
// Notes       : Up to four outstanding 1..16-beat bursts. The destination
//               accepts one returned beat per clock; no read-side stall is
//               propagated to DDR. Requests are 32-byte aligned and split
//               at 4 KiB boundaries. One AXI ID keeps responses in order.
// ============================================================================

module edrv32_yolo_axi_reader #(
    parameter [3:0] AXI_ID = 4'h8
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         req_valid_i,
    output wire         req_ready_o,
    input  wire [31:0]  req_addr_i,
    input  wire [15:0]  req_beats_i,
    output wire         beat_valid_o,
    output wire [15:0]  beat_index_o,
    output wire [255:0] beat_data_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [3:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o
);

    reg active_r;
    reg done_r;
    reg error_r;
    reg [31:0] base_r;
    reg [15:0] total_beats_r;
    reg [15:0] issued_beats_r;
    reg [15:0] returned_beats_r;
    reg [2:0] outstanding_r;

    wire [31:0] next_addr_w = base_r + {11'd0, issued_beats_r, 5'd0};
    wire [15:0] remaining_w = total_beats_r - issued_beats_r;
    wire [7:0] boundary_beats_w = 8'd128 - {1'b0, next_addr_w[11:5]};
    wire [7:0] remaining_capped_w = remaining_w < 16'd16 ?
        {1'b0, remaining_w[6:0]} : 8'd16;
    wire [7:0] burst_beats_w = remaining_capped_w < boundary_beats_w ?
        remaining_capped_w : boundary_beats_w;
    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w = m_rvalid_i && m_rready_o;
    wire rlast_fire_w = r_fire_w && m_rlast_i;

    assign req_ready_o = !active_r;
    assign beat_valid_o = r_fire_w;
    assign beat_index_o = returned_beats_r;
    assign beat_data_o = m_rdata_i;
    assign busy_o = active_r;
    assign done_o = done_r;
    assign error_o = error_r;
    assign m_arid_o = AXI_ID;
    assign m_araddr_o = next_addr_w;
    assign m_arlen_o = burst_beats_w[3:0] - 4'd1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arvalid_o = active_r && issued_beats_r < total_beats_r &&
                         outstanding_r < 3'd4;
    assign m_rready_o = active_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r         <= 1'b0;
            done_r           <= 1'b0;
            error_r          <= 1'b0;
            base_r           <= 32'd0;
            total_beats_r    <= 16'd0;
            issued_beats_r   <= 16'd0;
            returned_beats_r <= 16'd0;
            outstanding_r    <= 3'd0;
        end else begin
            done_r <= 1'b0;
            if (req_valid_i && req_ready_o && req_beats_i != 16'd0) begin
                active_r         <= 1'b1;
                error_r          <= req_addr_i[4:0] != 5'd0;
                base_r           <= req_addr_i;
                total_beats_r    <= req_beats_i;
                issued_beats_r   <= 16'd0;
                returned_beats_r <= 16'd0;
                outstanding_r    <= 3'd0;
            end else if (active_r) begin
                if (ar_fire_w)
                    issued_beats_r <= issued_beats_r + {8'd0, burst_beats_w};
                if (r_fire_w) begin
                    returned_beats_r <= returned_beats_r + 16'd1;
                    if (m_rid_i != AXI_ID || m_rresp_i != 2'b00)
                        error_r <= 1'b1;
                    if (returned_beats_r == total_beats_r - 16'd1) begin
                        active_r <= 1'b0;
                        done_r   <= 1'b1;
                        if (!m_rlast_i)
                            error_r <= 1'b1;
                    end
                end
                case ({ar_fire_w, rlast_fire_w})
                    2'b10: outstanding_r <= outstanding_r + 3'd1;
                    2'b01: outstanding_r <= outstanding_r - 3'd1;
                    default: outstanding_r <= outstanding_r;
                endcase
            end
        end
    end

endmodule
