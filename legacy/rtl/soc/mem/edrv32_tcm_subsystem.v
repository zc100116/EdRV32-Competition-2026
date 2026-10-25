// ============================================================================
// File        : edrv32_tcm_subsystem.v
// Description : CPU-private ITCM/DTCM response adapters.
// Notes       : ITCM and DTCM are direct core-side memories, not AXI slaves.
//               The board profile may enable them independently.
// ============================================================================
`include "edrv32_build_mode.vh"

module edrv32_tcm_subsystem #(
    parameter integer ENABLE          = 0,
    parameter integer ITCM_ENABLE     = ENABLE,
    parameter integer DTCM_ENABLE     = ENABLE,
    parameter [31:0]  ITCM_SIZE_BYTES = 32'd65536,
    parameter [31:0]  DTCM_SIZE_BYTES = 32'd65536,
    parameter         ITCM_INIT_FILE  = ""
) (
    input  wire        clk_i,
    input  wire        rst_n_i,

    input  wire        itcm_req_valid_i,
    output wire        itcm_req_ready_o,
    input  wire [31:0] itcm_req_addr_i,
    output wire        itcm_resp_valid_o,
    input  wire        itcm_resp_ready_i,
    output wire [31:0] itcm_resp_rdata_o,
    output wire        itcm_resp_error_o,

    input  wire        dtcm_req_valid_i,
    output wire        dtcm_req_ready_o,
    input  wire [31:0] dtcm_req_addr_i,
    input  wire        dtcm_req_we_i,
    input  wire [3:0]  dtcm_req_wstrb_i,
    input  wire [31:0] dtcm_req_wdata_i,
    output wire        dtcm_resp_valid_o,
    input  wire        dtcm_resp_ready_i,
    output wire [31:0] dtcm_resp_rdata_o,
    output wire        dtcm_resp_error_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`endif

    generate
        if (ITCM_ENABLE != 0) begin : gen_itcm_enabled
            reg  itcm_resp_valid_r;
            wire itcm_accept_w;
            wire [31:0] itcm_rdata_w;

            assign itcm_req_ready_o  = ~itcm_resp_valid_r |
                                       itcm_resp_ready_i;
            assign itcm_accept_w     = itcm_req_valid_i &&
                                       itcm_req_ready_o;
            assign itcm_resp_valid_o = itcm_resp_valid_r;
            assign itcm_resp_rdata_o = itcm_rdata_w;
            assign itcm_resp_error_o = 1'b0;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    itcm_resp_valid_r <= 1'b0;
                else if (itcm_req_ready_o)
                    itcm_resp_valid_r <= itcm_req_valid_i;
            end

            itcm #(
                .SIZE_BYTES(ITCM_SIZE_BYTES),
                .INIT_FILE (ITCM_INIT_FILE)
            ) u_itcm (
                .clk_i         (clk_i),
                .read_en_i     (itcm_accept_w),
                .local_addr_i  (itcm_req_addr_i),
                .local_rdata_o (itcm_rdata_w)
            );
        end else begin : gen_itcm_disabled
            assign itcm_req_ready_o  = 1'b0;
            assign itcm_resp_valid_o = 1'b0;
            assign itcm_resp_rdata_o = 32'd0;
            assign itcm_resp_error_o = 1'b0;
        end
    endgenerate

    generate
        if (DTCM_ENABLE != 0) begin : gen_dtcm_enabled
`ifdef EDRV32_FPGA_MEMORY_MODE
            edrv32_mes50hp_dtcm_memory_ip_backend_is_not_generated
                u_missing_dtcm_ip ();
            assign dtcm_req_ready_o  = 1'b0;
            assign dtcm_resp_valid_o = 1'b0;
            assign dtcm_resp_rdata_o = 32'd0;
            assign dtcm_resp_error_o = 1'b0;
`else
            reg         dtcm_resp_valid_r;
            reg  [31:0] dtcm_addr_r;
            wire [31:0] dtcm_local_addr_w;
            wire [31:0] dtcm_local_rdata_w;
            wire        dtcm_accept_w;

            assign dtcm_req_ready_o = ~dtcm_resp_valid_r |
                                      dtcm_resp_ready_i;
            assign dtcm_accept_w = dtcm_req_valid_i && dtcm_req_ready_o;
            assign dtcm_local_addr_w = dtcm_req_ready_o
                ? dtcm_req_addr_i : dtcm_addr_r;
            assign dtcm_resp_valid_o = dtcm_resp_valid_r;
            assign dtcm_resp_rdata_o = dtcm_local_rdata_w;
            assign dtcm_resp_error_o = 1'b0;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    dtcm_resp_valid_r <= 1'b0;
                    dtcm_addr_r       <= 32'd0;
                end else begin
                    if (dtcm_req_ready_o)
                        dtcm_resp_valid_r <= dtcm_req_valid_i;
                    if (dtcm_accept_w)
                        dtcm_addr_r <= dtcm_req_addr_i;
                end
            end

            dtcm #(
                .SIZE_BYTES(DTCM_SIZE_BYTES)
            ) u_dtcm (
                .clk              (clk_i),
                .sys_addr_i       (32'd0),
                .sys_we_i         (1'b0),
                .sys_wstrb_i      (4'd0),
                .sys_wdata_i      (32'd0),
                .sys_rdata_o      (),
                .local_addr_i     (dtcm_local_addr_w),
                .local_we_i       (dtcm_accept_w && dtcm_req_we_i),
                .local_wstrb_i    (dtcm_req_wstrb_i),
                .local_wdata_i    (dtcm_req_wdata_i),
                .local_rdata_o    (dtcm_local_rdata_w)
            );
`endif
        end else begin : gen_dtcm_disabled
            assign dtcm_req_ready_o  = 1'b0;
            assign dtcm_resp_valid_o = 1'b0;
            assign dtcm_resp_rdata_o = 32'd0;
            assign dtcm_resp_error_o = 1'b0;
        end
    endgenerate

endmodule
