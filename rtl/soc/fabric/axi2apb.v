// ============================================================================
// File        : axi2apb.v
// Author      : Edward ZC
// Description : AXI4 Full single-beat slave to APB bridge (design §6.2).
//               AW and W are accepted independently, APB completion payloads
//               are retained through AXI backpressure, and unsupported bursts
//               complete with a framed SLVERR response without APB side effects.
// Notes       : Verilog-2001. Single outstanding transaction. APB address/data
//               width is 32 bit; slot decoding is downstream of this bridge.
// ============================================================================
`include "edrv32_axi4.vh"

module axi2apb #(
    parameter ID_W = `AXI_ID_W                 // global ID width from fabric
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire [ID_W-1:0]     awid_i,
    input  wire [31:0]              awaddr_i,
    input  wire [`AXI_LEN_W-1:0]    awlen_i,
    input  wire [`AXI_SIZE_W-1:0]   awsize_i,
    input  wire                     awvalid_i,
    output wire                     awready_o,
    input  wire [`AXI_DATA_W-1:0]   wdata_i,
    input  wire [`AXI_STRB_W-1:0]   wstrb_i,
    input  wire                     wlast_i,
    input  wire                     wvalid_i,
    output wire                     wready_o,
    output wire [ID_W-1:0]     bid_o,
    output wire [`AXI_RESP_W-1:0]   bresp_o,
    output wire                     bvalid_o,
    input  wire                     bready_i,
    input  wire [ID_W-1:0]     arid_i,
    input  wire [31:0]              araddr_i,
    input  wire [`AXI_LEN_W-1:0]    arlen_i,
    input  wire [`AXI_SIZE_W-1:0]   arsize_i,
    input  wire                     arvalid_i,
    output wire                     arready_o,
    output wire [ID_W-1:0]     rid_o,
    output wire [`AXI_DATA_W-1:0]   rdata_o,
    output wire [`AXI_RESP_W-1:0]   rresp_o,
    output wire                     rlast_o,
    output wire                     rvalid_o,
    input  wire                     rready_i,
    output wire [31:0]              paddr_o,
    output wire                     psel_o,
    output wire                     penable_o,
    output wire                     pwrite_o,
    output wire [31:0]              pwdata_o,
    output wire [3:0]               pstrb_o,
    input  wire                     pready_i,
    input  wire [31:0]              prdata_i,
    input  wire                     pslverr_i
);

    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_SETUP  = 3'd1;
    localparam [2:0] ST_ACCESS = 3'd2;
    localparam [2:0] ST_RESP   = 3'd3;
    localparam [2:0] ST_WDRAIN = 3'd4;
    localparam [2:0] ST_RERR   = 3'd5;

    reg [2:0] state_r;
    reg [ID_W-1:0] id_r;
    reg [31:0] addr_r;
    reg [`AXI_DATA_W-1:0] wdata_r;
    reg [`AXI_STRB_W-1:0] strb_r;
    reg        is_write_r;
    reg [31:0] resp_data_r;
    reg        resp_err_r;

    reg                       aw_hold_r;
    reg [ID_W-1:0]       aw_id_r;
    reg [31:0]                aw_addr_r;
    reg [`AXI_LEN_W-1:0]      aw_len_r;
    reg [`AXI_SIZE_W-1:0]     aw_size_r;
    reg                       w_hold_r;
    reg [`AXI_DATA_W-1:0]     w_data_r;
    reg [`AXI_STRB_W-1:0]     w_strb_r;
    reg                       w_last_r;
    reg [`AXI_LEN_W-1:0]      drain_left_r;
    reg [`AXI_LEN_W-1:0]      rerr_left_r;

    assign paddr_o   = addr_r;
    assign psel_o    = (state_r == ST_SETUP) || (state_r == ST_ACCESS);
    assign penable_o = (state_r == ST_ACCESS);
    assign pwrite_o  = is_write_r;
    // 32-bit APB payload extracted from the addr[2] byte lane of the AXI beat.
    assign pwdata_o  = addr_r[2] ? wdata_r[63:32] : wdata_r[31:0];
    assign pstrb_o   = addr_r[2] ? strb_r[7:4] : strb_r[3:0];

    wire apb_done_w = (state_r == ST_ACCESS) && pready_i;

    assign awready_o = (state_r == ST_IDLE) && !aw_hold_r;
    assign wready_o  = ((state_r == ST_IDLE) && !w_hold_r) ||
                       (state_r == ST_WDRAIN);
    assign arready_o = (state_r == ST_IDLE) && !aw_hold_r && !w_hold_r &&
                       !awvalid_i && !wvalid_i;

    wire aw_fire_w = awvalid_i && awready_o;
    wire w_fire_w  = wvalid_i && wready_o;
    wire ar_fire_w = arvalid_i && arready_o;
    wire write_pair_w = (aw_hold_r || aw_fire_w) &&
                        (w_hold_r || (w_fire_w && (state_r == ST_IDLE)));

    wire [ID_W-1:0] pair_id_w = aw_fire_w ? awid_i : aw_id_r;
    wire [31:0] pair_addr_w = aw_fire_w ? awaddr_i : aw_addr_r;
    wire [`AXI_LEN_W-1:0] pair_len_w = aw_fire_w ? awlen_i : aw_len_r;
    wire [`AXI_SIZE_W-1:0] pair_awsize_w = aw_fire_w ? awsize_i : aw_size_r;
    wire [`AXI_DATA_W-1:0] pair_data_w = w_fire_w ? wdata_i : w_data_r;
    wire [`AXI_STRB_W-1:0] pair_strb_w = w_fire_w ? wstrb_i : w_strb_r;
    wire pair_last_w = w_fire_w ? wlast_i : w_last_r;

    assign bvalid_o = (state_r == ST_RESP) && is_write_r;
    assign bid_o    = id_r;
    assign bresp_o  = resp_err_r ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
    assign rvalid_o = ((state_r == ST_RESP) && !is_write_r) ||
                      (state_r == ST_RERR);
    assign rid_o    = id_r;
    assign rdata_o  = (state_r == ST_RERR) ? {`AXI_DATA_W{1'b0}} :
                      (addr_r[2] ? {resp_data_r, 32'h0} : {32'h0, resp_data_r});
    assign rresp_o  = (state_r == ST_RERR) ? `AXI_RESP_SLVERR :
                      (resp_err_r ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY);
    assign rlast_o  = (state_r == ST_RERR) ? (rerr_left_r == 0) : 1'b1;

    wire b_fire_w = bvalid_o && bready_i;
    wire r_fire_w = rvalid_o && rready_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r       <= ST_IDLE;
            id_r          <= {ID_W{1'b0}};
            addr_r        <= 32'h0;
            wdata_r       <= {`AXI_DATA_W{1'b0}};
            strb_r        <= {`AXI_STRB_W{1'b0}};
            is_write_r    <= 1'b0;
            resp_data_r   <= 32'h0;
            resp_err_r    <= 1'b0;
            aw_hold_r     <= 1'b0;
            aw_id_r       <= {ID_W{1'b0}};
            aw_addr_r     <= 32'h0;
            aw_len_r      <= {`AXI_LEN_W{1'b0}};
            aw_size_r     <= {`AXI_SIZE_W{1'b0}};
            w_hold_r      <= 1'b0;
            w_data_r      <= {`AXI_DATA_W{1'b0}};
            w_strb_r      <= {`AXI_STRB_W{1'b0}};
            w_last_r      <= 1'b0;
            drain_left_r  <= {`AXI_LEN_W{1'b0}};
            rerr_left_r   <= {`AXI_LEN_W{1'b0}};
        end else begin
            if (state_r == ST_IDLE) begin
                if (aw_fire_w) begin
                    aw_hold_r <= 1'b1;
                    aw_id_r   <= awid_i;
                    aw_addr_r <= awaddr_i;
                    aw_len_r  <= awlen_i;
                    aw_size_r <= awsize_i;
                end
                if (w_fire_w) begin
                    w_hold_r <= 1'b1;
                    w_data_r <= wdata_i;
                    w_strb_r <= wstrb_i;
                    w_last_r <= wlast_i;
                end

                if (write_pair_w) begin
                    aw_hold_r   <= 1'b0;
                    w_hold_r    <= 1'b0;
                    id_r        <= pair_id_w;
                    addr_r      <= pair_addr_w;
                    wdata_r     <= pair_data_w;
                    strb_r      <= pair_strb_w;
                    is_write_r  <= 1'b1;
                    resp_data_r <= 32'h0;
                    resp_err_r  <= (pair_len_w != 0) || !pair_last_w ||
                                   (pair_awsize_w != `AXI_SIZE_4B);
                    if (pair_len_w != 0) begin
                        drain_left_r <= pair_len_w;
                        state_r <= ST_WDRAIN;
                    end else if (!pair_last_w) begin
                        state_r <= ST_RESP;
                    end else begin
                        state_r <= ST_SETUP;
                    end
                end else if (ar_fire_w) begin
                    id_r        <= arid_i;
                    addr_r      <= araddr_i;
                    is_write_r  <= 1'b0;
                    resp_data_r <= 32'h0;
                    resp_err_r  <= (arlen_i != 0) ||
                                   (arsize_i != `AXI_SIZE_4B);
                    if (arlen_i != 0) begin
                        rerr_left_r <= arlen_i;
                        state_r <= ST_RERR;
                    end else begin
                        state_r <= ST_SETUP;
                    end
                end
            end else begin
                case (state_r)
                    ST_SETUP: state_r <= ST_ACCESS;
                    ST_ACCESS: begin
                        if (apb_done_w) begin
                            resp_data_r <= prdata_i;
                            resp_err_r  <= pslverr_i;
                            state_r     <= ST_RESP;
                        end
                    end
                    ST_WDRAIN: begin
                        if (w_fire_w) begin
                            if (drain_left_r == 1) begin
                                drain_left_r <= {`AXI_LEN_W{1'b0}};
                                state_r <= ST_RESP;
                            end else begin
                                drain_left_r <= drain_left_r - 1'b1;
                            end
                        end
                    end
                    ST_RERR: begin
                        if (r_fire_w) begin
                            if (rerr_left_r == 0)
                                state_r <= ST_IDLE;
                            else
                                rerr_left_r <= rerr_left_r - 1'b1;
                        end
                    end
                    ST_RESP: begin
                        if (b_fire_w || r_fire_w)
                            state_r <= ST_IDLE;
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
