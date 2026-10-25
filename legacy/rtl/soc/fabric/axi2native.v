// ============================================================================
// File        : axi2native.v
// Author      : Edward ZC
// Description : AXI4 Full single-beat slave to the project Native req/resp
//               protocol. AW/W are independently buffered and native response
//               payloads are retained until the AXI response handshake.
// Notes       : Verilog-2001. Native targets are single-beat; AXI bursts are
//               rejected with correctly framed SLVERR responses and no target
//               side effect. Read and write share one native request channel.
// ============================================================================
`include "edrv32_axi4.vh"

module axi2native #(
    parameter ID_W = `AXI_ID_W                 // global ID width from fabric
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI write-address channel.
    input  wire [ID_W-1:0]          awid_i,
    input  wire [31:0]              awaddr_i,
    input  wire [`AXI_LEN_W-1:0]    awlen_i,
    input  wire [`AXI_SIZE_W-1:0]   awsize_i,
    input  wire                     awvalid_i,
    output wire                     awready_o,

    // AXI write-data channel.
    input  wire [`AXI_DATA_W-1:0]   wdata_i,
    input  wire [`AXI_STRB_W-1:0]   wstrb_i,
    input  wire                     wlast_i,
    input  wire                     wvalid_i,
    output wire                     wready_o,

    // AXI write-response channel.
    output wire [ID_W-1:0]          bid_o,
    output wire [`AXI_RESP_W-1:0]   bresp_o,
    output wire                     bvalid_o,
    input  wire                     bready_i,

    // AXI read-address channel.
    input  wire [ID_W-1:0]          arid_i,
    input  wire [31:0]              araddr_i,
    input  wire [`AXI_LEN_W-1:0]    arlen_i,
    input  wire [`AXI_SIZE_W-1:0]   arsize_i,
    input  wire                     arvalid_i,
    output wire                     arready_o,

    // AXI read-data channel.
    output wire [ID_W-1:0]          rid_o,
    output wire [`AXI_DATA_W-1:0]   rdata_o,
    output wire [`AXI_RESP_W-1:0]   rresp_o,
    output wire                     rlast_o,
    output wire                     rvalid_o,
    input  wire                     rready_i,

    // Shared native request/response channel.
    output wire                     req_valid_o,
    input  wire                     req_ready_i,
    output wire [31:0]              req_addr_o,
    output wire                     req_we_o,
    output wire [3:0]               req_wstrb_o,
    output wire [31:0]              req_wdata_o,
    input  wire                     resp_valid_i,
    output wire                     resp_ready_o,
    input  wire [31:0]              resp_rdata_i,
    input  wire                     resp_error_i
);

    // --------------------------------------------------------------------
    // Transaction state and retained payload
    // --------------------------------------------------------------------
    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_WRITE  = 3'd1;
    localparam [2:0] ST_READ   = 3'd2;
    localparam [2:0] ST_WDRAIN = 3'd3;
    localparam [2:0] ST_BERR   = 3'd4;
    localparam [2:0] ST_RERR   = 3'd5;

    reg [2:0] state_r;
    reg [ID_W-1:0] id_r;
    reg [31:0] addr_r;
    reg [3:0] strb_r;
    reg [31:0] wdata_r;
    reg req_fired_r;
    reg resp_hold_r;
    reg [31:0] resp_data_r;
    reg resp_err_r;

    // Independent one-entry skid buffers pair AXI AW and W arrivals.
    reg aw_hold_r;
    reg [ID_W-1:0] aw_id_r;
    reg [31:0] aw_addr_r;
    reg [`AXI_LEN_W-1:0] aw_len_r;
    reg [`AXI_SIZE_W-1:0] aw_size_r;
    reg wr_size_err_r;
    reg rd_size_err_r;
    reg w_hold_r;
    reg [`AXI_DATA_W-1:0] w_data_r;
    reg [`AXI_STRB_W-1:0] w_strb_r;
    reg w_last_r;
    reg [`AXI_LEN_W-1:0] drain_left_r;
    reg [`AXI_LEN_W-1:0] rerr_left_r;

    // Write traffic has priority when either half of a write is already held.
    assign awready_o = (state_r == ST_IDLE) && !aw_hold_r;
    assign wready_o = ((state_r == ST_IDLE) && !w_hold_r) ||
                      (state_r == ST_WDRAIN);
    assign arready_o = (state_r == ST_IDLE) && !aw_hold_r && !w_hold_r &&
                       !awvalid_i && !wvalid_i;

    wire aw_fire_w = awvalid_i && awready_o;
    wire w_fire_w = wvalid_i && wready_o;
    wire ar_fire_w = arvalid_i && arready_o;
    wire write_pair_w = (aw_hold_r || aw_fire_w) &&
                        (w_hold_r || (w_fire_w && (state_r == ST_IDLE)));
    wire [ID_W-1:0] pair_id_w = aw_fire_w ? awid_i : aw_id_r;
    wire [31:0] pair_addr_w = aw_fire_w ? awaddr_i : aw_addr_r;
    wire [`AXI_LEN_W-1:0] pair_len_w = aw_fire_w ? awlen_i : aw_len_r;
    wire [`AXI_SIZE_W-1:0] pair_awsize_w = aw_fire_w ? awsize_i : aw_size_r;
    wire lane_hi_w = pair_addr_w[2];
    wire [31:0] pair_data_w = w_fire_w
        ? (lane_hi_w ? wdata_i[63:32] : wdata_i[31:0])
        : (w_data_r[63:32] & {32{lane_hi_w}}) | (w_data_r[31:0] & {32{~lane_hi_w}});
    wire [3:0] pair_strb_w = w_fire_w
        ? (lane_hi_w ? wstrb_i[7:4] : wstrb_i[3:0])
        : (lane_hi_w ? w_strb_r[7:4] : w_strb_r[3:0]);
    wire pair_last_w = w_fire_w ? wlast_i : w_last_r;

    // One accepted AXI transaction owns the native request until its response.
    assign req_valid_o = ((state_r == ST_WRITE) || (state_r == ST_READ)) &&
                         !req_fired_r && !resp_hold_r;
    assign req_addr_o  = addr_r;
    assign req_we_o    = (state_r == ST_WRITE);
    assign req_wstrb_o = strb_r;
    assign req_wdata_o = wdata_r;

    wire native_fire_w = req_valid_o && req_ready_i;
    assign resp_ready_o = ((state_r == ST_WRITE) || (state_r == ST_READ)) &&
                          !resp_hold_r && (req_fired_r || native_fire_w);
    wire native_resp_fire_w = resp_valid_i && resp_ready_o;

    // Native completion is retained until the corresponding AXI handshake.
    // Unsupported bursts are framed locally as SLVERR and never reach native.
    assign bvalid_o = ((state_r == ST_WRITE) && resp_hold_r) ||
                      (state_r == ST_BERR);
    assign bid_o = id_r;
    assign bresp_o = (state_r == ST_BERR) ? `AXI_RESP_SLVERR :
                     ((resp_err_r || wr_size_err_r) ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY);
    assign rvalid_o = ((state_r == ST_READ) && resp_hold_r) ||
                      (state_r == ST_RERR);
    assign rid_o = id_r;
    assign rdata_o = (state_r == ST_RERR) ? {`AXI_DATA_W{1'b0}} :
                     (addr_r[2] ? {resp_data_r, 32'h0} : {32'h0, resp_data_r});
    assign rresp_o = (state_r == ST_RERR) ? `AXI_RESP_SLVERR :
                     ((resp_err_r || rd_size_err_r) ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY);
    assign rlast_o = (state_r == ST_RERR) ? (rerr_left_r == 0) : 1'b1;

    wire b_fire_w = bvalid_o && bready_i;
    wire r_fire_w = rvalid_o && rready_i;

    // The single state owner controls channel buffers, native ownership and
    // malformed-burst draining. Response payload remains stable under AXI
    // backpressure because it changes only on native_resp_fire_w.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r       <= ST_IDLE;
            id_r          <= {ID_W{1'b0}};
            addr_r        <= 32'h0;
            strb_r        <= 4'h0;
            wdata_r       <= 32'h0;
            req_fired_r   <= 1'b0;
            resp_hold_r   <= 1'b0;
            resp_data_r   <= 32'h0;
            resp_err_r    <= 1'b0;
            aw_hold_r     <= 1'b0;
            aw_id_r       <= {ID_W{1'b0}};
            aw_addr_r     <= 32'h0;
            aw_len_r      <= {`AXI_LEN_W{1'b0}};
            aw_size_r     <= {`AXI_SIZE_W{1'b0}};
            wr_size_err_r <= 1'b0;
            rd_size_err_r <= 1'b0;
            w_hold_r      <= 1'b0;
            w_data_r      <= {`AXI_DATA_W{1'b0}};
            w_strb_r      <= {`AXI_STRB_W{1'b0}};
            w_last_r      <= 1'b0;
            drain_left_r  <= {`AXI_LEN_W{1'b0}};
            rerr_left_r   <= {`AXI_LEN_W{1'b0}};
        end else begin
            if (state_r == ST_IDLE) begin
                req_fired_r <= 1'b0;
                resp_hold_r <= 1'b0;

                // Capture AW and W independently; consume both when paired.
                if (aw_fire_w) begin
                    aw_hold_r <= 1'b1;
                    aw_id_r <= awid_i;
                    aw_addr_r <= awaddr_i;
                    aw_len_r <= awlen_i;
                    aw_size_r <= awsize_i;
                end
                if (w_fire_w) begin
                    w_hold_r <= 1'b1;
                    w_data_r <= wdata_i;
                    w_strb_r <= wstrb_i;
                    w_last_r <= wlast_i;
                end

                if (write_pair_w) begin
                    aw_hold_r <= 1'b0;
                    w_hold_r <= 1'b0;
                    id_r <= pair_id_w;
                    addr_r <= pair_addr_w;
                    strb_r <= pair_strb_w;
                    wdata_r <= pair_data_w;
                    wr_size_err_r <= (pair_awsize_w != `AXI_SIZE_4B);
                    if (pair_len_w != 0) begin
                        drain_left_r <= pair_len_w;
                        state_r <= ST_WDRAIN;
                    end else if (!pair_last_w) begin
                        state_r <= ST_BERR;
                    end else begin
                        state_r <= ST_WRITE;
                    end
                end else if (ar_fire_w) begin
                    id_r <= arid_i;
                    addr_r <= araddr_i;
                    strb_r <= 4'h0;
                    wdata_r <= 32'h0;
                    rd_size_err_r <= (arsize_i != `AXI_SIZE_4B);
                    if (arlen_i != 0) begin
                        rerr_left_r <= arlen_i;
                        state_r <= ST_RERR;
                    end else begin
                        state_r <= ST_READ;
                    end
                end
            end else begin
                // A same-cycle native request/response is legal, so response
                // readiness includes native_fire_w as an ownership proof.
                if (native_fire_w)
                    req_fired_r <= 1'b1;
                if (native_resp_fire_w) begin
                    req_fired_r <= 1'b1;
                    resp_hold_r <= 1'b1;
                    resp_data_r <= resp_rdata_i;
                    resp_err_r <= resp_error_i;
                end

                case (state_r)
                    ST_WRITE: begin
                        if (b_fire_w) begin
                            req_fired_r <= 1'b0;
                            resp_hold_r <= 1'b0;
                            state_r <= ST_IDLE;
                        end
                    end
                    ST_READ: begin
                        if (r_fire_w) begin
                            req_fired_r <= 1'b0;
                            resp_hold_r <= 1'b0;
                            state_r <= ST_IDLE;
                        end
                    end
                    ST_WDRAIN: begin
                        if (w_fire_w) begin
                            if (drain_left_r == 1) begin
                                drain_left_r <= {`AXI_LEN_W{1'b0}};
                                state_r <= ST_BERR;
                            end else begin
                                drain_left_r <= drain_left_r - 1'b1;
                            end
                        end
                    end
                    ST_BERR: begin
                        if (b_fire_w)
                            state_r <= ST_IDLE;
                    end
                    ST_RERR: begin
                        if (r_fire_w) begin
                            if (rerr_left_r == 0)
                                state_r <= ST_IDLE;
                            else
                                rerr_left_r <= rerr_left_r - 1'b1;
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
