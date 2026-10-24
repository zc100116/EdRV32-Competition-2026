// ============================================================================
// File        : edrv32_cached_core_native_harness.sv
// Description : Simulation-only compatibility harness for cached-core tests.
// Notes       : The production cached core drives AXI4 directly.  This harness
//               translates those transactions to the existing 32-bit native
//               Harvard memory model so old CPU tests can keep their memory
//               loading and checking infrastructure.
// ============================================================================
`include "edrv32_axi4.vh"
`include "edrv32_bus.vh"

module edrv32_axi_native_test_adapter (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input  wire [`AXI_ID_W-1:0]         axi_awid_i,
    input  wire [31:0]                  axi_awaddr_i,
    input  wire [`AXI_LEN_W-1:0]        axi_awlen_i,
    input  wire [`AXI_SIZE_W-1:0]       axi_awsize_i,
    input  wire [`AXI_BURST_W-1:0]      axi_awburst_i,
    input  wire                         axi_awvalid_i,
    output wire                         axi_awready_o,
    input  wire [`AXI_DATA_W-1:0]       axi_wdata_i,
    input  wire [`AXI_STRB_W-1:0]       axi_wstrb_i,
    input  wire                         axi_wlast_i,
    input  wire                         axi_wvalid_i,
    output wire                         axi_wready_o,
    output wire [`AXI_ID_W-1:0]         axi_bid_o,
    output wire [`AXI_RESP_W-1:0]       axi_bresp_o,
    output wire                         axi_bvalid_o,
    input  wire                         axi_bready_i,

    input  wire [`AXI_ID_W-1:0]         axi_arid_i,
    input  wire [31:0]                  axi_araddr_i,
    input  wire [`AXI_LEN_W-1:0]        axi_arlen_i,
    input  wire [`AXI_SIZE_W-1:0]       axi_arsize_i,
    input  wire [`AXI_BURST_W-1:0]      axi_arburst_i,
    input  wire                         axi_arvalid_i,
    output wire                         axi_arready_o,
    output wire [`AXI_ID_W-1:0]         axi_rid_o,
    output wire [`AXI_DATA_W-1:0]       axi_rdata_o,
    output wire [`AXI_RESP_W-1:0]       axi_rresp_o,
    output wire                         axi_rlast_o,
    output wire                         axi_rvalid_o,
    input  wire                         axi_rready_i,

    output wire                         native_req_valid_o,
    input  wire                         native_req_ready_i,
    output wire [31:0]                  native_req_addr_o,
    output wire                         native_req_write_o,
    output wire [`BUS_SZ_W-1:0]         native_req_size_o,
    output wire [3:0]                   native_req_wstrb_o,
    output wire [31:0]                  native_req_wdata_o,
    input  wire                         native_resp_valid_i,
    output wire                         native_resp_ready_o,
    input  wire [31:0]                  native_resp_rdata_i,
    input  wire                         native_resp_error_i
);

    localparam [2:0] STATE_IDLE       = 3'd0;
    localparam [2:0] STATE_READ_REQ   = 3'd1;
    localparam [2:0] STATE_READ_WAIT  = 3'd2;
    localparam [2:0] STATE_READ_RESP  = 3'd3;
    localparam [2:0] STATE_WRITE_DATA = 3'd4;
    localparam [2:0] STATE_WRITE_REQ  = 3'd5;
    localparam [2:0] STATE_WRITE_WAIT = 3'd6;
    localparam [2:0] STATE_WRITE_RESP = 3'd7;

    reg [2:0] state_r;

    reg [`AXI_ID_W-1:0] read_id_r;
    reg [31:0] read_addr_r;
    reg [`AXI_LEN_W-1:0] read_len_r;
    reg [`AXI_LEN_W-1:0] read_beat_r;
    reg [`AXI_SIZE_W-1:0] read_size_r;
    reg read_word_r;
    reg [`AXI_DATA_W-1:0] read_data_r;
    reg read_error_r;

    reg [`AXI_ID_W-1:0] write_id_r;
    reg [31:0] write_addr_r;
    reg [`AXI_LEN_W-1:0] write_len_r;
    reg [`AXI_LEN_W-1:0] write_beat_r;
    reg [`AXI_SIZE_W-1:0] write_size_r;
    reg write_word_r;
    reg [`AXI_DATA_W-1:0] write_data_r;
    reg [`AXI_STRB_W-1:0] write_strb_r;
    reg write_error_r;

    wire read_two_words_w = (read_size_r == `AXI_SIZE_8B);
    wire write_two_words_w = (write_size_r == `AXI_SIZE_8B);
    wire read_last_word_w = !read_two_words_w || read_word_r;
    wire write_last_word_w = !write_two_words_w || write_word_r;
    wire read_last_beat_w = (read_beat_r == read_len_r);
    wire write_last_beat_w = (write_beat_r == write_len_r);

    assign axi_awready_o = (state_r == STATE_IDLE);
    assign axi_wready_o = (state_r == STATE_WRITE_DATA);
    assign axi_bid_o = write_id_r;
    assign axi_bresp_o = write_error_r ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
    assign axi_bvalid_o = (state_r == STATE_WRITE_RESP);

    // Give writes priority only when both address channels are presented on
    // the same cycle.  The production caches never issue both concurrently.
    assign axi_arready_o = (state_r == STATE_IDLE) && !axi_awvalid_i;
    assign axi_rid_o = read_id_r;
    assign axi_rdata_o = read_data_r;
    assign axi_rresp_o = read_error_r ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
    assign axi_rlast_o = read_last_beat_w;
    assign axi_rvalid_o = (state_r == STATE_READ_RESP);

    assign native_req_valid_o = (state_r == STATE_READ_REQ) ||
                                (state_r == STATE_WRITE_REQ);
    assign native_req_addr_o = (state_r == STATE_READ_REQ)
        ? (read_addr_r + (read_word_r ? 32'd4 : 32'd0))
        : (write_addr_r + (write_word_r ? 32'd4 : 32'd0));
    assign native_req_write_o = (state_r == STATE_WRITE_REQ);
    assign native_req_size_o = `BUS_SZ_WORD;
    assign native_req_wdata_o = write_two_words_w
        ? (write_word_r ? write_data_r[63:32] : write_data_r[31:0])
        : (write_addr_r[2] ? write_data_r[63:32] : write_data_r[31:0]);
    assign native_req_wstrb_o = write_two_words_w
        ? (write_word_r ? write_strb_r[7:4] : write_strb_r[3:0])
        : (write_addr_r[2] ? write_strb_r[7:4] : write_strb_r[3:0]);
    assign native_resp_ready_o = (state_r == STATE_READ_WAIT) ||
                                 (state_r == STATE_WRITE_WAIT);

    wire native_request_fire_w = native_req_valid_o && native_req_ready_i;
    wire native_response_fire_w = native_resp_valid_i && native_resp_ready_o;
    wire read_response_fire_w = axi_rvalid_o && axi_rready_i;
    wire write_response_fire_w = axi_bvalid_o && axi_bready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            read_beat_r <= {`AXI_LEN_W{1'b0}};
            read_word_r <= 1'b0;
            read_data_r <= {`AXI_DATA_W{1'b0}};
            read_error_r <= 1'b0;
            write_beat_r <= {`AXI_LEN_W{1'b0}};
            write_word_r <= 1'b0;
            write_error_r <= 1'b0;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    if (axi_awvalid_i && axi_awready_o) begin
                        write_id_r <= axi_awid_i;
                        write_addr_r <= axi_awaddr_i;
                        write_len_r <= axi_awlen_i;
                        write_size_r <= axi_awsize_i;
                        write_beat_r <= {`AXI_LEN_W{1'b0}};
                        write_word_r <= 1'b0;
                        write_error_r <=
                            (axi_awburst_i != `AXI_BURST_INCR) ||
                            ((axi_awsize_i != `AXI_SIZE_4B) &&
                             (axi_awsize_i != `AXI_SIZE_8B));
                        state_r <= STATE_WRITE_DATA;
                    end else if (axi_arvalid_i && axi_arready_o) begin
                        read_id_r <= axi_arid_i;
                        read_addr_r <= axi_araddr_i;
                        read_len_r <= axi_arlen_i;
                        read_size_r <= axi_arsize_i;
                        read_beat_r <= {`AXI_LEN_W{1'b0}};
                        read_word_r <= 1'b0;
                        read_data_r <= {`AXI_DATA_W{1'b0}};
                        read_error_r <=
                            (axi_arburst_i != `AXI_BURST_INCR) ||
                            ((axi_arsize_i != `AXI_SIZE_4B) &&
                             (axi_arsize_i != `AXI_SIZE_8B));
                        state_r <= STATE_READ_REQ;
                    end
                end
                STATE_READ_REQ: begin
                    if (native_request_fire_w)
                        state_r <= STATE_READ_WAIT;
                end
                STATE_READ_WAIT: begin
                    if (native_response_fire_w) begin
                        read_error_r <= read_error_r || native_resp_error_i;
                        if (read_two_words_w) begin
                            if (read_word_r)
                                read_data_r[63:32] <= native_resp_rdata_i;
                            else
                                read_data_r[31:0] <= native_resp_rdata_i;
                        end else if (read_addr_r[2]) begin
                            read_data_r[63:32] <= native_resp_rdata_i;
                        end else begin
                            read_data_r[31:0] <= native_resp_rdata_i;
                        end

                        if (read_last_word_w) begin
                            state_r <= STATE_READ_RESP;
                        end else begin
                            read_word_r <= 1'b1;
                            state_r <= STATE_READ_REQ;
                        end
                    end
                end
                STATE_READ_RESP: begin
                    if (read_response_fire_w) begin
                        if (read_last_beat_w) begin
                            state_r <= STATE_IDLE;
                        end else begin
                            read_addr_r <= read_addr_r +
                                           (32'd1 << read_size_r);
                            read_beat_r <= read_beat_r + 1'b1;
                            read_word_r <= 1'b0;
                            read_data_r <= {`AXI_DATA_W{1'b0}};
                            state_r <= STATE_READ_REQ;
                        end
                    end
                end
                STATE_WRITE_DATA: begin
                    if (axi_wvalid_i && axi_wready_o) begin
                        write_data_r <= axi_wdata_i;
                        write_strb_r <= axi_wstrb_i;
                        write_word_r <= 1'b0;
                        write_error_r <= write_error_r ||
                                         (axi_wlast_i != write_last_beat_w);
                        state_r <= STATE_WRITE_REQ;
                    end
                end
                STATE_WRITE_REQ: begin
                    if (native_request_fire_w)
                        state_r <= STATE_WRITE_WAIT;
                end
                STATE_WRITE_WAIT: begin
                    if (native_response_fire_w) begin
                        write_error_r <= write_error_r || native_resp_error_i;
                        if (!write_last_word_w) begin
                            write_word_r <= 1'b1;
                            state_r <= STATE_WRITE_REQ;
                        end else if (write_last_beat_w) begin
                            state_r <= STATE_WRITE_RESP;
                        end else begin
                            write_addr_r <= write_addr_r +
                                            (32'd1 << write_size_r);
                            write_beat_r <= write_beat_r + 1'b1;
                            write_word_r <= 1'b0;
                            state_r <= STATE_WRITE_DATA;
                        end
                    end
                end
                STATE_WRITE_RESP: begin
                    if (write_response_fire_w)
                        state_r <= STATE_IDLE;
                end
                default: state_r <= STATE_IDLE;
            endcase
        end
    end

endmodule

module edrv32_cached_core_native_harness #(
    parameter [31:0] RESET_PC = 32'h8000_0000,
    parameter integer FRONTEND_DUAL_WINDOW = 0,
    parameter integer DUAL_ISSUE = 0,
    parameter integer FETCH_WIDE = 0,
    parameter integer ICACHE_LINE_COUNT = 256,
    parameter integer DCACHE_LINE_COUNT = 256,
    parameter integer CPU_HPM_ENABLE = 1
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,

    output wire                 imem_req_valid_o,
    input  wire                 imem_req_ready_i,
    output wire [31:0]          imem_req_addr_o,
    input  wire                 imem_resp_valid_i,
    output wire                 imem_resp_ready_o,
    input  wire [31:0]          imem_resp_rdata_i,
    input  wire                 imem_resp_error_i,

    output wire                 dmem_req_valid_o,
    input  wire                 dmem_req_ready_i,
    output wire [31:0]          dmem_req_addr_o,
    output wire                 dmem_req_we_o,
    output wire [`BUS_SZ_W-1:0] dmem_req_size_o,
    output wire [3:0]           dmem_req_wstrb_o,
    output wire [31:0]          dmem_req_wdata_o,
    input  wire                 dmem_resp_valid_i,
    output wire                 dmem_resp_ready_o,
    input  wire [31:0]          dmem_resp_rdata_i,
    input  wire                 dmem_resp_error_i,

    output wire                 itcm_req_valid_o,
    input  wire                 itcm_req_ready_i,
    output wire [31:0]          itcm_req_addr_o,
    input  wire                 itcm_resp_valid_i,
    output wire                 itcm_resp_ready_o,
    input  wire [31:0]          itcm_resp_rdata_i,
    input  wire                 itcm_resp_error_i,
    output wire                 dtcm_req_valid_o,
    input  wire                 dtcm_req_ready_i,
    output wire [31:0]          dtcm_req_addr_o,
    output wire                 dtcm_req_we_o,
    output wire [`BUS_SZ_W-1:0] dtcm_req_size_o,
    output wire [3:0]           dtcm_req_wstrb_o,
    output wire [31:0]          dtcm_req_wdata_o,
    input  wire                 dtcm_resp_valid_i,
    output wire                 dtcm_resp_ready_o,
    input  wire [31:0]          dtcm_resp_rdata_i,
    input  wire                 dtcm_resp_error_i,

    input  wire                 irq_soft_i,
    input  wire                 irq_timer_i,
    input  wire                 irq_ext_i,
    input  wire [63:0]          time_value_i,
    output wire                 retire_o,
    output wire [31:0]          retire_pc_o,
    output wire [31:0]          retire_instr_o,
    output wire                 retire_exception_o,
    output wire [31:0]          retire_cause_o,
    output wire                 core_sleep_o,
    output wire [31:0]          debug_decode_pc_o,
    output wire [31:0]          debug_decode_instr_o
);

    wire [`AXI_ID_W-1:0] i_arid_w;
    wire [31:0] i_araddr_w;
    wire [`AXI_LEN_W-1:0] i_arlen_w;
    wire [`AXI_SIZE_W-1:0] i_arsize_w;
    wire [`AXI_BURST_W-1:0] i_arburst_w;
    wire i_arvalid_w;
    wire i_arready_w;
    wire [`AXI_ID_W-1:0] i_rid_w;
    wire [`AXI_DATA_W-1:0] i_rdata_w;
    wire [`AXI_RESP_W-1:0] i_rresp_w;
    wire i_rlast_w;
    wire i_rvalid_w;
    wire i_rready_w;

    wire [`AXI_ID_W-1:0] d_awid_w;
    wire [31:0] d_awaddr_w;
    wire [`AXI_LEN_W-1:0] d_awlen_w;
    wire [`AXI_SIZE_W-1:0] d_awsize_w;
    wire [`AXI_BURST_W-1:0] d_awburst_w;
    wire d_awvalid_w;
    wire d_awready_w;
    wire [`AXI_DATA_W-1:0] d_wdata_w;
    wire [`AXI_STRB_W-1:0] d_wstrb_w;
    wire d_wlast_w;
    wire d_wvalid_w;
    wire d_wready_w;
    wire [`AXI_ID_W-1:0] d_bid_w;
    wire [`AXI_RESP_W-1:0] d_bresp_w;
    wire d_bvalid_w;
    wire d_bready_w;
    wire [`AXI_ID_W-1:0] d_arid_w;
    wire [31:0] d_araddr_w;
    wire [`AXI_LEN_W-1:0] d_arlen_w;
    wire [`AXI_SIZE_W-1:0] d_arsize_w;
    wire [`AXI_BURST_W-1:0] d_arburst_w;
    wire d_arvalid_w;
    wire d_arready_w;
    wire [`AXI_ID_W-1:0] d_rid_w;
    wire [`AXI_DATA_W-1:0] d_rdata_w;
    wire [`AXI_RESP_W-1:0] d_rresp_w;
    wire d_rlast_w;
    wire d_rvalid_w;
    wire d_rready_w;

    edrv32_cached_core #(
        .RESET_PC(RESET_PC),
        .FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW),
        .DUAL_ISSUE(DUAL_ISSUE),
        .FETCH_WIDE(FETCH_WIDE),
        .ICACHE_LINE_COUNT(ICACHE_LINE_COUNT),
        .DCACHE_LINE_COUNT(DCACHE_LINE_COUNT),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE)
    ) u_cached_core (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .icache_axi_arid_o(i_arid_w),
        .icache_axi_araddr_o(i_araddr_w),
        .icache_axi_arlen_o(i_arlen_w),
        .icache_axi_arsize_o(i_arsize_w),
        .icache_axi_arburst_o(i_arburst_w),
        .icache_axi_arvalid_o(i_arvalid_w),
        .icache_axi_arready_i(i_arready_w),
        .icache_axi_rid_i(i_rid_w),
        .icache_axi_rdata_i(i_rdata_w),
        .icache_axi_rresp_i(i_rresp_w),
        .icache_axi_rlast_i(i_rlast_w),
        .icache_axi_rvalid_i(i_rvalid_w),
        .icache_axi_rready_o(i_rready_w),
        .dcache_axi_awid_o(d_awid_w),
        .dcache_axi_awaddr_o(d_awaddr_w),
        .dcache_axi_awlen_o(d_awlen_w),
        .dcache_axi_awsize_o(d_awsize_w),
        .dcache_axi_awburst_o(d_awburst_w),
        .dcache_axi_awvalid_o(d_awvalid_w),
        .dcache_axi_awready_i(d_awready_w),
        .dcache_axi_wdata_o(d_wdata_w),
        .dcache_axi_wstrb_o(d_wstrb_w),
        .dcache_axi_wlast_o(d_wlast_w),
        .dcache_axi_wvalid_o(d_wvalid_w),
        .dcache_axi_wready_i(d_wready_w),
        .dcache_axi_bid_i(d_bid_w),
        .dcache_axi_bresp_i(d_bresp_w),
        .dcache_axi_bvalid_i(d_bvalid_w),
        .dcache_axi_bready_o(d_bready_w),
        .dcache_axi_arid_o(d_arid_w),
        .dcache_axi_araddr_o(d_araddr_w),
        .dcache_axi_arlen_o(d_arlen_w),
        .dcache_axi_arsize_o(d_arsize_w),
        .dcache_axi_arburst_o(d_arburst_w),
        .dcache_axi_arvalid_o(d_arvalid_w),
        .dcache_axi_arready_i(d_arready_w),
        .dcache_axi_rid_i(d_rid_w),
        .dcache_axi_rdata_i(d_rdata_w),
        .dcache_axi_rresp_i(d_rresp_w),
        .dcache_axi_rlast_i(d_rlast_w),
        .dcache_axi_rvalid_i(d_rvalid_w),
        .dcache_axi_rready_o(d_rready_w),
        .itcm_req_valid_o(itcm_req_valid_o),
        .itcm_req_ready_i(itcm_req_ready_i),
        .itcm_req_addr_o(itcm_req_addr_o),
        .itcm_resp_valid_i(itcm_resp_valid_i),
        .itcm_resp_ready_o(itcm_resp_ready_o),
        .itcm_resp_rdata_i(itcm_resp_rdata_i),
        .itcm_resp_error_i(itcm_resp_error_i),
        .dtcm_req_valid_o(dtcm_req_valid_o),
        .dtcm_req_ready_i(dtcm_req_ready_i),
        .dtcm_req_addr_o(dtcm_req_addr_o),
        .dtcm_req_we_o(dtcm_req_we_o),
        .dtcm_req_size_o(dtcm_req_size_o),
        .dtcm_req_wstrb_o(dtcm_req_wstrb_o),
        .dtcm_req_wdata_o(dtcm_req_wdata_o),
        .dtcm_resp_valid_i(dtcm_resp_valid_i),
        .dtcm_resp_ready_o(dtcm_resp_ready_o),
        .dtcm_resp_rdata_i(dtcm_resp_rdata_i),
        .dtcm_resp_error_i(dtcm_resp_error_i),
        .irq_soft_i(irq_soft_i),
        .irq_timer_i(irq_timer_i),
        .irq_ext_i(irq_ext_i),
        .time_value_i(time_value_i),
        .retire_o(retire_o),
        .retire_pc_o(retire_pc_o),
        .retire_instr_o(retire_instr_o),
        .retire_exception_o(retire_exception_o),
        .retire_cause_o(retire_cause_o),
        .core_sleep_o(core_sleep_o),
        .debug_decode_pc_o(debug_decode_pc_o),
        .debug_decode_instr_o(debug_decode_instr_o)
    );

    edrv32_axi_native_test_adapter u_imem_adapter (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .axi_awid_i({`AXI_ID_W{1'b0}}), .axi_awaddr_i(32'd0),
        .axi_awlen_i({`AXI_LEN_W{1'b0}}), .axi_awsize_i(`AXI_SIZE_4B),
        .axi_awburst_i(`AXI_BURST_INCR), .axi_awvalid_i(1'b0),
        .axi_awready_o(), .axi_wdata_i({`AXI_DATA_W{1'b0}}),
        .axi_wstrb_i({`AXI_STRB_W{1'b0}}), .axi_wlast_i(1'b1),
        .axi_wvalid_i(1'b0), .axi_wready_o(), .axi_bid_o(),
        .axi_bresp_o(), .axi_bvalid_o(), .axi_bready_i(1'b1),
        .axi_arid_i(i_arid_w), .axi_araddr_i(i_araddr_w),
        .axi_arlen_i(i_arlen_w), .axi_arsize_i(i_arsize_w),
        .axi_arburst_i(i_arburst_w), .axi_arvalid_i(i_arvalid_w),
        .axi_arready_o(i_arready_w), .axi_rid_o(i_rid_w),
        .axi_rdata_o(i_rdata_w), .axi_rresp_o(i_rresp_w),
        .axi_rlast_o(i_rlast_w), .axi_rvalid_o(i_rvalid_w),
        .axi_rready_i(i_rready_w),
        .native_req_valid_o(imem_req_valid_o),
        .native_req_ready_i(imem_req_ready_i),
        .native_req_addr_o(imem_req_addr_o), .native_req_write_o(),
        .native_req_size_o(), .native_req_wstrb_o(),
        .native_req_wdata_o(), .native_resp_valid_i(imem_resp_valid_i),
        .native_resp_ready_o(imem_resp_ready_o),
        .native_resp_rdata_i(imem_resp_rdata_i),
        .native_resp_error_i(imem_resp_error_i)
    );

    edrv32_axi_native_test_adapter u_dmem_adapter (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .axi_awid_i(d_awid_w), .axi_awaddr_i(d_awaddr_w),
        .axi_awlen_i(d_awlen_w), .axi_awsize_i(d_awsize_w),
        .axi_awburst_i(d_awburst_w), .axi_awvalid_i(d_awvalid_w),
        .axi_awready_o(d_awready_w), .axi_wdata_i(d_wdata_w),
        .axi_wstrb_i(d_wstrb_w), .axi_wlast_i(d_wlast_w),
        .axi_wvalid_i(d_wvalid_w), .axi_wready_o(d_wready_w),
        .axi_bid_o(d_bid_w), .axi_bresp_o(d_bresp_w),
        .axi_bvalid_o(d_bvalid_w), .axi_bready_i(d_bready_w),
        .axi_arid_i(d_arid_w), .axi_araddr_i(d_araddr_w),
        .axi_arlen_i(d_arlen_w), .axi_arsize_i(d_arsize_w),
        .axi_arburst_i(d_arburst_w), .axi_arvalid_i(d_arvalid_w),
        .axi_arready_o(d_arready_w), .axi_rid_o(d_rid_w),
        .axi_rdata_o(d_rdata_w), .axi_rresp_o(d_rresp_w),
        .axi_rlast_o(d_rlast_w), .axi_rvalid_o(d_rvalid_w),
        .axi_rready_i(d_rready_w),
        .native_req_valid_o(dmem_req_valid_o),
        .native_req_ready_i(dmem_req_ready_i),
        .native_req_addr_o(dmem_req_addr_o),
        .native_req_write_o(dmem_req_we_o),
        .native_req_size_o(dmem_req_size_o),
        .native_req_wstrb_o(dmem_req_wstrb_o),
        .native_req_wdata_o(dmem_req_wdata_o),
        .native_resp_valid_i(dmem_resp_valid_i),
        .native_resp_ready_o(dmem_resp_ready_o),
        .native_resp_rdata_i(dmem_resp_rdata_i),
        .native_resp_error_i(dmem_resp_error_i)
    );

endmodule
