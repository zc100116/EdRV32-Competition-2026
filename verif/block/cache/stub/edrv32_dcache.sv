// edrv32_dcache.sv
// cache-spec 3, 5; independent module verification.
// Clock domain: clk_sys.
module edrv32_dcache (
    // Clock and reset
    input logic clk_i,
    input logic rst_n_i,

    // Core interface
    input logic dc_req_valid_i,
    input logic [31:0] dc_req_addr_i,
    input logic dc_req_store_i,
    input logic [1:0] dc_req_size_i,
    input logic dc_kill_i,
    input logic dc_commit_i,
    input logic [31:0] dc_store_data_i,
    input logic dc_fence_i,
    input logic dc_clean_all_i,
    output logic dc_req_ready_o,
    output logic dc_resp_valid_o,
    output logic [31:0] dc_resp_data_o,
    output logic dc_resp_err_o,
    output logic dc_resp_device_o,
    output logic dc_fence_done_o,

    // AXI memory interface
    output logic [3:0] axi_awid_o,
    output logic [31:0] axi_awaddr_o,
    output logic [7:0] axi_awlen_o,
    output logic [2:0] axi_awsize_o,
    output logic [1:0] axi_awburst_o,
    output logic axi_awvalid_o,
    input logic axi_awready_i,
    output logic [3:0] axi_arid_o,
    output logic [31:0] axi_araddr_o,
    output logic [7:0] axi_arlen_o,
    output logic [2:0] axi_arsize_o,
    output logic [1:0] axi_arburst_o,
    output logic axi_arvalid_o,
    input logic axi_arready_i,
    output logic [63:0] axi_wdata_o,
    output logic [7:0] axi_wstrb_o,
    output logic axi_wlast_o,
    output logic axi_wvalid_o,
    input logic axi_wready_i,
    input logic [3:0] axi_bid_i,
    input logic [1:0] axi_bresp_i,
    input logic axi_bvalid_i,
    output logic axi_bready_o,
    input logic [3:0] axi_rid_i,
    input logic [63:0] axi_rdata_i,
    input logic [1:0] axi_rresp_i,
    input logic axi_rlast_i,
    input logic axi_rvalid_i,
    output logic axi_rready_o,

    // Maintenance and status
    input logic maint_req_valid_i,
    output logic maint_req_ready_o,
    input logic [2:0] maint_cmd_i,
    input logic [31:0] maint_addr_i,
    input logic [31:0] maint_size_i,
    output logic maint_busy_o,
    output logic wb_err_o,
    output logic [31:0] wb_err_addr_o
);
    bit active;
    bit store;
    bit killed;
    bit [31:0] addr;
    bit [1:0] size;
    assign dc_req_ready_o = !active && !maint_busy_o;
    assign dc_resp_device_o = active;
    assign axi_arid_o = 0;
    assign axi_araddr_o = addr;
    assign axi_arlen_o = 0;
    assign axi_arsize_o = {1'b0, size};
    assign axi_arburst_o = 1;
    assign axi_rready_o = 1;
    assign axi_awid_o = 0;
    assign axi_awaddr_o = addr;
    assign axi_awlen_o = 0;
    assign axi_awsize_o = {1'b0, size};
    assign axi_awburst_o = 1;
    assign axi_wlast_o = 1;
    assign axi_bready_o = 1;
    assign maint_req_ready_o = !maint_busy_o;
    assign wb_err_o = 0;
    assign wb_err_addr_o = 0;
    always @(posedge clk_i) begin
        dc_resp_valid_o <= 0;
        dc_fence_done_o <= dc_fence_i || dc_clean_all_i;
        maint_busy_o <= maint_req_valid_i && maint_req_ready_o && maint_size_i != 0;
        if (!rst_n_i) begin
            active <= 0;
            killed <= 0;
            axi_arvalid_o <= 0;
            axi_awvalid_o <= 0;
            axi_wvalid_o <= 0;
            dc_resp_err_o <= 0;
            dc_resp_data_o <= 0;
            axi_wdata_o <= 0;
            axi_wstrb_o <= 0;
        end else begin
            if (dc_req_valid_i && dc_req_ready_o) begin
                active <= 1;
                killed <= 0;
                store <= dc_req_store_i;
                addr <= dc_req_addr_i;
                size <= dc_req_size_i;
            end
            if (dc_kill_i) begin
                killed <= 1;
                active <= 0;
            end
            if (dc_commit_i && active && !killed) begin
                if (store) begin
                    axi_awvalid_o <= 1;
                    axi_wdata_o <= 64'(dc_store_data_i) << (8 * addr[2:0]);
                    axi_wstrb_o <= 8'(((1 << (1 << size)) - 1) << addr[2:0]);
                end else axi_arvalid_o <= 1;
            end
            if (axi_arvalid_o && axi_arready_i) axi_arvalid_o <= 0;
            if (axi_awvalid_o && axi_awready_i) begin
                axi_awvalid_o <= 0;
                axi_wvalid_o <= 1;
            end
            if (axi_wvalid_o && axi_wready_i) axi_wvalid_o <= 0;
            if (axi_rvalid_i || axi_bvalid_i) begin
                active <= 0;
                dc_resp_valid_o <= !killed;
                dc_resp_data_o <= 32'(axi_rdata_i >> (8 * addr[2:0]));
                dc_resp_err_o <= store ? axi_bresp_i != 0 : axi_rresp_i != 0;
            end
        end
    end
    wire unused_inputs = ^{maint_cmd_i, maint_addr_i, axi_bid_i, axi_rid_i, axi_rlast_i};
endmodule
