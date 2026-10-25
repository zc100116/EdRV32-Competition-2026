// ============================================================================
// File        : edrv32_render_cmd_fetch.v
// Description : Ordered 64-byte render-command fetch from 256-bit AXI.
// Notes       : One prefetched command; each descriptor is one two-beat burst.
// ============================================================================

module edrv32_render_cmd_fetch #(
    parameter [3:0] AXI_ID = 4'h5
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    input  wire         cancel_i,
    output wire         start_ready_o,
    input  wire [31:0]  list_base_i,
    input  wire [15:0]  list_count_i,

    output wire         cmd_valid_o,
    input  wire         cmd_ready_i,
    output wire [511:0] cmd_data_o,
    output wire [15:0]  cmd_index_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
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

    localparam [1:0] ST_AR = 2'd0;
    localparam [1:0] ST_R0 = 2'd1;
    localparam [1:0] ST_R1 = 2'd2;

    reg          active_r;
    reg          done_r;
    reg          error_r;
    reg [1:0]    state_r;
    reg [31:0]   base_r;
    reg [15:0]   count_r;
    reg [15:0]   fetched_r;
    reg [15:0]   consumed_r;
    reg          cmd_valid_r;
    reg [511:0]  cmd_data_r;
    reg [15:0]   cmd_index_r;
    reg          read_error_r;

    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w  = m_rvalid_i && m_rready_o;
    wire cmd_fire_w = cmd_valid_r && cmd_ready_i;
    wire read_fault_w = (m_rid_i != AXI_ID) || (m_rresp_i != 2'b00);

    assign start_ready_o = !active_r;
    assign cmd_valid_o   = cmd_valid_r;
    assign cmd_data_o    = cmd_data_r;
    assign cmd_index_o   = cmd_index_r;
    assign busy_o        = active_r;
    assign done_o        = done_r;
    assign error_o       = error_r;

    assign m_arid_o    = AXI_ID;
    assign m_araddr_o  = base_r + {10'd0, fetched_r, 6'd0};
    assign m_arlen_o   = 8'd1;
    assign m_arsize_o  = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arvalid_o = active_r && (state_r == ST_AR) &&
                         !cmd_valid_r && (fetched_r < count_r);
    assign m_rready_o  = active_r &&
                         ((state_r == ST_R0) || (state_r == ST_R1));

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r     <= 1'b0;
            done_r       <= 1'b0;
            error_r      <= 1'b0;
            state_r      <= ST_AR;
            base_r       <= 32'b0;
            count_r      <= 16'b0;
            fetched_r    <= 16'b0;
            consumed_r   <= 16'b0;
            cmd_valid_r  <= 1'b0;
            cmd_index_r  <= 16'b0;
            read_error_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (cancel_i) begin
                active_r    <= 1'b0;
                cmd_valid_r <= 1'b0;
                state_r     <= ST_AR;
            end else if (start_i && start_ready_o) begin
                active_r     <= (list_count_i != 16'd0) &&
                                (list_base_i[5:0] == 6'd0);
                done_r       <= (list_count_i == 16'd0) ||
                                (list_base_i[5:0] != 6'd0);
                error_r      <= list_base_i[5:0] != 6'd0;
                state_r      <= ST_AR;
                base_r       <= list_base_i;
                count_r      <= list_count_i;
                fetched_r    <= 16'b0;
                consumed_r   <= 16'b0;
                cmd_valid_r  <= 1'b0;
                read_error_r <= 1'b0;
            end else if (active_r) begin
                if (cmd_fire_w) begin
                    cmd_valid_r <= 1'b0;
                    consumed_r <= consumed_r + 16'd1;
                    if (consumed_r == count_r - 16'd1) begin
                        active_r <= 1'b0;
                        done_r   <= 1'b1;
                    end
                end
                if (ar_fire_w) begin
                    state_r      <= ST_R0;
                    read_error_r <= 1'b0;
                end
                if (r_fire_w && (state_r == ST_R0)) begin
                    cmd_data_r[255:0] <= m_rdata_i;
                    read_error_r <= read_fault_w || m_rlast_i;
                    state_r <= ST_R1;
                end
                if (r_fire_w && (state_r == ST_R1)) begin
                    state_r <= ST_AR;
                    fetched_r <= fetched_r + 16'd1;
                    if (read_error_r || read_fault_w || !m_rlast_i) begin
                        active_r <= 1'b0;
                        done_r   <= 1'b1;
                        error_r  <= 1'b1;
                    end else begin
                        cmd_data_r[511:256] <= m_rdata_i;
                        cmd_index_r <= fetched_r;
                        cmd_valid_r <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
