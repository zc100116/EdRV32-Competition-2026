// File: edrv32_cpu2_cache_ctrl.v
// Spec: cpu-v2-spec 4.3; cache-spec 4, 5.4, 6.
// Description: APB command mailbox holds the accepted range until D$ takes it.
// Sticky writeback error and address use new-error priority. Clock domain: clk_sys.
module edrv32_cpu2_cache_ctrl (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB slot-local interface.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Maintenance request and writeback error.
    output reg maint_req_valid_o,
    input wire maint_req_ready_i,
    output reg [2:0] maint_cmd_o,
    output reg [31:0] maint_addr_o,
    output reg [31:0] maint_size_o,
    input wire maint_busy_i,
    input wire wb_err_i,
    input wire [31:0] wb_err_addr_i,

    // Error interrupt.
    output wire cache_irq_o
);
    reg irq_en_r;
    reg irq_stat_r;
    reg [31:0] err_addr_r;
    reg [31:0] op_addr_r;
    reg [31:0] op_size_r;
    wire write_w;
    wire busy_w;
    wire launch_w;
    wire [31:0] byte_mask_w;

    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign busy_w = maint_req_valid_o || maint_busy_i;
    assign launch_w = write_w && apb_paddr_i == 12'h028 && apb_pstrb_i[0] &&
        apb_pwdata_i >= 32'd1 && apb_pwdata_i <= 32'd4 && !busy_w;
    assign byte_mask_w = {{8{apb_pstrb_i[3]}}, {8{apb_pstrb_i[2]}},
                        {8{apb_pstrb_i[1]}}, {8{apb_pstrb_i[0]}}};
    assign cache_irq_o = irq_en_r && irq_stat_r;

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h0005_0001;
            12'h008: apb_prdata_o = {31'd0, busy_w};
            12'h00c: apb_prdata_o = {30'd0, irq_en_r, 1'b0};
            12'h010: apb_prdata_o = {30'd0, irq_stat_r, 1'b0};
            12'h014: apb_prdata_o = err_addr_r;
            12'h020: apb_prdata_o = op_addr_r;
            12'h024: apb_prdata_o = op_size_r;
            default: apb_prdata_o = 32'd0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            maint_req_valid_o <= 1'b0;
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            err_addr_r <= 32'd0;
            op_addr_r <= 32'd0;
            op_size_r <= 32'd0;
        end else begin
            if (maint_req_valid_o && maint_req_ready_i)
                maint_req_valid_o <= 1'b0;
            if (launch_w)
                maint_req_valid_o <= 1'b1;
            if (write_w) begin
                case (apb_paddr_i)
                    12'h00c: if (apb_pstrb_i[0]) irq_en_r <= apb_pwdata_i[1];
                    12'h010: if (apb_pstrb_i[0] && apb_pwdata_i[1]) irq_stat_r <= 1'b0;
                    12'h020: op_addr_r <= (op_addr_r & ~byte_mask_w) |
                                            (apb_pwdata_i & byte_mask_w);
                    12'h024: op_size_r <= (op_size_r & ~byte_mask_w) |
                                            (apb_pwdata_i & byte_mask_w);
                    default: begin end
                endcase
            end
            if (wb_err_i) begin
                irq_stat_r <= 1'b1;
                err_addr_r <= wb_err_addr_i;
            end
        end
    end

    always @(posedge clk_i) begin
        if (launch_w) begin
            maint_cmd_o <= apb_pwdata_i[2:0];
            maint_addr_o <= op_addr_r;
            maint_size_o <= op_size_r;
        end
    end
endmodule
