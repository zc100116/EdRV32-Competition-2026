// edrv32_cache_ctrl.sv
// cache-spec 3, 5; independent module verification.
// Clock domain: clk_sys.
module edrv32_cache_ctrl (
    // Clock and reset
    input logic clk_i,
    input logic rst_n_i,

    // APB register interface
    input logic [11:0] apb_paddr_i,
    input logic apb_psel_i,
    input logic apb_penable_i,
    input logic apb_pwrite_i,
    input logic [31:0] apb_pwdata_i,
    input logic [3:0] apb_pstrb_i,
    output logic apb_pready_o,
    output logic [31:0] apb_prdata_o,
    output logic apb_pslverr_o,

    // Maintenance and status
    output logic maint_req_valid_o,
    input logic maint_req_ready_i,
    output logic [2:0] maint_cmd_o,
    output logic [31:0] maint_addr_o,
    output logic [31:0] maint_size_o,
    input logic maint_busy_i,
    input logic wb_err_i,
    input logic [31:0] wb_err_addr_i,
    output logic irq_o
);
    logic [31:0] irq_en;
    logic [31:0] irq_stat;
    logic [31:0] err_addr;
    assign apb_pready_o = 1;
    assign apb_pslverr_o = 0;
    assign irq_o = |(irq_en & irq_stat);
    always @(*) begin
        apb_prdata_o = 0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00050001;
            12'h008: apb_prdata_o = {31'b0, maint_busy_i};
            12'h00c: apb_prdata_o = irq_en;
            12'h010: apb_prdata_o = irq_stat;
            12'h014: apb_prdata_o = err_addr;
            12'h020: apb_prdata_o = maint_addr_o;
            12'h024: apb_prdata_o = maint_size_o;
            default: apb_prdata_o = 0;
        endcase
    end
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            irq_en <= 0;
            irq_stat <= 0;
            err_addr <= 0;
            maint_addr_o <= 0;
            maint_size_o <= 0;
            maint_cmd_o <= 0;
            maint_req_valid_o <= 0;
        end else begin
            if (maint_req_valid_o && maint_req_ready_i) maint_req_valid_o <= 0;
            if (apb_psel_i && apb_penable_i && apb_pwrite_i) begin
                case (apb_paddr_i)
                    12'h00c: irq_en <= apb_pwdata_i & 2;
                    12'h010: irq_stat <= irq_stat & ~apb_pwdata_i;
                    12'h020: maint_addr_o <= apb_pwdata_i;
                    12'h024: maint_size_o <= apb_pwdata_i;
                    12'h028: if (!maint_busy_i && apb_pwdata_i >= 1 &&
                                 apb_pwdata_i <= 4) begin
                        maint_req_valid_o <= 1;
                        maint_cmd_o <= apb_pwdata_i[2:0];
                    end
                    default: begin end
                endcase
            end
            if (wb_err_i) begin
                irq_stat <= irq_stat | 2;
                err_addr <= wb_err_addr_i;
            end
        end
    end
    wire unused_inputs = ^{apb_pstrb_i};
endmodule
