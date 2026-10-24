// ============================================================================
// File        : edrv32_render_write_guard.v
// Description : Reject command-list writes into HDMI target buffer slots.
// Notes       : One AXI write burst may be outstanding. Rejected bursts are
//               drained locally and completed with DECERR, without DDR writes.
// ============================================================================

module edrv32_render_write_guard #(
    parameter [31:0] TARGET_BASE0 = 32'h0200_0000,
    parameter [31:0] TARGET_BASE1 = 32'h0220_0000,
    parameter [31:0] TARGET_BASE2 = 32'h0240_0000,
    parameter [31:0] TARGET_SLOT_BYTES = 32'h0020_0000
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         draw_active_i,
    input  wire         compose_direct_active_i,
    input  wire [31:0]  compose_direct_target_base_i,

    input  wire [3:0]   s_awid_i,
    input  wire [31:0]  s_awaddr_i,
    input  wire [7:0]   s_awlen_i,
    input  wire [2:0]   s_awsize_i,
    input  wire [1:0]   s_awburst_i,
    input  wire [3:0]   s_awqos_i,
    input  wire         s_awvalid_i,
    output wire         s_awready_o,
    input  wire [255:0] s_wdata_i,
    input  wire [31:0]  s_wstrb_i,
    input  wire         s_wlast_i,
    input  wire         s_wvalid_i,
    output wire         s_wready_o,
    output wire [3:0]   s_bid_o,
    output wire [1:0]   s_bresp_o,
    output wire         s_bvalid_o,
    input  wire         s_bready_i,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire [3:0]   m_awqos_o,
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

    localparam [1:0] ST_PASS = 2'd0;
    localparam [1:0] ST_DROP_W = 2'd1;
    localparam [1:0] ST_DROP_B = 2'd2;

    reg [1:0] state_r;
    reg [3:0] rejected_id_r;

    // The renderer's AXI port transfers 32-byte INCR beats only.
    wire [32:0] burst_end_w = {1'b0,s_awaddr_i} +
        {20'd0,s_awlen_i,5'b0} + 33'd31;
    wire malformed_w = (s_awsize_i != 3'd5) ||
        (s_awburst_i != 2'b01);
    wire [32:0] slot_end0_w = {1'b0,TARGET_BASE0} +
        {1'b0,TARGET_SLOT_BYTES};
    wire [32:0] slot_end1_w = {1'b0,TARGET_BASE1} +
        {1'b0,TARGET_SLOT_BYTES};
    wire [32:0] slot_end2_w = {1'b0,TARGET_BASE2} +
        {1'b0,TARGET_SLOT_BYTES};
    wire overlap0_w = ({1'b0,s_awaddr_i} < slot_end0_w) &&
        (burst_end_w >= {1'b0,TARGET_BASE0});
    wire overlap1_w = ({1'b0,s_awaddr_i} < slot_end1_w) &&
        (burst_end_w >= {1'b0,TARGET_BASE1});
    wire overlap2_w = ({1'b0,s_awaddr_i} < slot_end2_w) &&
        (burst_end_w >= {1'b0,TARGET_BASE2});
    wire [32:0] direct_slot_end_w =
        {1'b0,compose_direct_target_base_i} +
        {1'b0,TARGET_SLOT_BYTES};
    wire direct_outside_w =
        ({1'b0,s_awaddr_i} < {1'b0,compose_direct_target_base_i}) ||
        (burst_end_w >= direct_slot_end_w);
    wire reject_w =
        (draw_active_i && (overlap0_w || overlap1_w || overlap2_w ||
                           burst_end_w[32] || malformed_w)) ||
        (compose_direct_active_i && (direct_outside_w || malformed_w));
    wire reject_aw_w = (state_r == ST_PASS) &&
        s_awvalid_i && reject_w;

    assign s_awready_o = (state_r == ST_PASS) &&
        (reject_w || m_awready_i);
    assign s_wready_o = (state_r == ST_DROP_W) ||
        reject_aw_w || ((state_r == ST_PASS) && m_wready_i);
    assign s_bid_o = state_r == ST_DROP_B ? rejected_id_r : m_bid_i;
    assign s_bresp_o = state_r == ST_DROP_B ? 2'b11 : m_bresp_i;
    assign s_bvalid_o = state_r == ST_DROP_B ? 1'b1 :
        ((state_r == ST_PASS) && m_bvalid_i);

    assign m_awid_o = s_awid_i;
    assign m_awaddr_o = s_awaddr_i;
    assign m_awlen_o = s_awlen_i;
    assign m_awsize_o = s_awsize_i;
    assign m_awburst_o = s_awburst_i;
    assign m_awqos_o = s_awqos_i;
    assign m_awvalid_o = (state_r == ST_PASS) &&
        s_awvalid_i && !reject_w;
    assign m_wdata_o = s_wdata_i;
    assign m_wstrb_o = s_wstrb_i;
    assign m_wlast_o = s_wlast_i;
    assign m_wvalid_o = (state_r == ST_PASS) &&
        s_wvalid_i && !reject_aw_w;
    assign m_bready_o = (state_r == ST_PASS) && s_bready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_PASS;
            rejected_id_r <= 4'd0;
        end else begin
            case (state_r)
                ST_PASS: begin
                    if (reject_aw_w) begin
                        rejected_id_r <= s_awid_i;
                        if (s_wvalid_i && s_wlast_i)
                            state_r <= ST_DROP_B;
                        else
                            state_r <= ST_DROP_W;
                    end
                end
                ST_DROP_W: begin
                    if (s_wvalid_i && s_wlast_i)
                        state_r <= ST_DROP_B;
                end
                ST_DROP_B: begin
                    if (s_bready_i)
                        state_r <= ST_PASS;
                end
                default: state_r <= ST_PASS;
            endcase
        end
    end

endmodule
