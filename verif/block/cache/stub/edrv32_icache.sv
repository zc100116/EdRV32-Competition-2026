// edrv32_icache.sv
// cache-spec 3, 5; independent module verification.
// Clock domain: clk_sys.
module edrv32_icache (
    // Clock and reset
    input logic clk_i,
    input logic rst_n_i,
    input logic rst_sys_ivalid0_n_i,
    input logic rst_sys_ivalid1_n_i,
    input logic rst_sys_ilru_n_i,


    // Core interface
    input logic ic_req_valid_i,
    input logic [31:0] ic_req_addr_i,
    output logic ic_req_ready_o,
    output logic ic_resp_valid_o,
    output wire [7:0] ic_resp_valid_copy_o,
    output logic [63:0] ic_resp_data_o,
    output wire [43:0] ic_resp_predecode_o,
    output logic ic_resp_err_o,
    input logic ic_kill_i,
    input logic ic_inv_i,
    output logic ic_inv_done_o,

    // AXI memory interface
    output logic [3:0] axi_arid_o,
    output logic [31:0] axi_araddr_o,
    output logic [7:0] axi_arlen_o,
    output logic [2:0] axi_arsize_o,
    output logic [1:0] axi_arburst_o,
    output logic axi_arvalid_o,
    input logic axi_arready_i,
    input logic [3:0] axi_rid_i,
    input logic [63:0] axi_rdata_i,
    input logic [1:0] axi_rresp_i,
    input logic axi_rlast_i,
    input logic axi_rvalid_i,
    output logic axi_rready_o
);
    assign ic_resp_valid_copy_o = {8{ic_resp_valid_o}};
    bit active;
    bit killed;
    bit [31:0] addr;
    logic [63:0] result;
    bit error_seen;
    int beat;
    assign ic_req_ready_o = !active;
    assign axi_arid_o = 0;
    assign axi_arburst_o = 1;
    assign axi_arsize_o = 3;
    assign axi_arlen_o = addr < 32'h4000 ? 0 :
                         ($test$plusargs("BAD_AXI_LEN") ? 2 : 3);
    assign axi_araddr_o = addr < 32'h4000 ? addr : {addr[31:5], 5'b0};
    assign axi_rready_o = 1;
    for (genvar slot = 0; slot < 2; slot++) begin : g_predecode
        edrv32_cpu_predecode u_predecode (
            .instr_i(ic_resp_data_o[slot*32 +: 32]),
            .predecode_o(ic_resp_predecode_o[slot*22 +: 22])
        );
    end
    always @(posedge clk_i) begin
        ic_resp_valid_o <= 0;
        ic_inv_done_o <= ic_inv_i;
        if (!rst_n_i) begin
            active <= 0;
            killed <= 0;
            axi_arvalid_o <= 0;
            ic_resp_err_o <= 0;
            ic_resp_data_o <= 0;
        end else begin
            if (ic_req_valid_i && ic_req_ready_o) begin
                active <= 1;
                killed <= 0;
                addr <= ic_req_addr_i;
                axi_arvalid_o <= 1;
                error_seen <= 0;
                beat <= 0;
            end
            if (ic_kill_i) killed <= 1;
            if (axi_arvalid_o && axi_arready_i) axi_arvalid_o <= 0;
            if (axi_rvalid_i) begin
                if (beat == int'(addr[4:3]) || addr < 32'h4000) result <= axi_rdata_i;
                error_seen <= error_seen || axi_rresp_i != 0;
                beat <= beat + 1;
                if (axi_rlast_i) begin
                    active <= 0;
                    ic_resp_valid_o <= !killed && !ic_kill_i;
                    ic_resp_err_o <= error_seen || axi_rresp_i != 0;
                    ic_resp_data_o <= (beat == int'(addr[4:3]) || addr < 32'h4000) ?
                                      axi_rdata_i : result;
                end
            end
        end
    end
    wire unused_inputs = ^{axi_rid_i};
endmodule
