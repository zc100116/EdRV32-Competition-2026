// File: edrv32_cache_ctrl.v
// Spec: cache-spec 3.3, 4, 6.
// Description: APB maintenance mailbox and sticky writeback error interrupt.
// APB maintenance command mailbox and sticky writeback-error interrupt.
// Byte strobes qualify each writable byte. Clock domain: clk_sys.
module edrv32_cache_ctrl (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // D$ maintenance mailbox.
    output reg maint_req_valid_o,
    input wire maint_req_ready_i,
    output reg [2:0] maint_cmd_o,
    output reg [31:0] maint_addr_o,
    output reg [31:0] maint_size_o,
    input wire maint_busy_i,
    input wire wb_err_i,
    input wire [31:0] wb_err_addr_i,

    // PLIC level interrupt.
    output wire irq_o
);
    reg irq_en_r;
    reg irq_stat_r;
    reg [31:0] err_addr_r;
    reg [31:0] op_addr_r;
    reg [31:0] op_size_r;
    wire write_w;
    wire busy_w;
    wire launch_w;
    integer byte_idx_r;

    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign busy_w = maint_busy_i || maint_req_valid_o;
    assign launch_w = write_w && apb_paddr_i == 12'h028 && apb_pstrb_i[0] &&
                        apb_pwdata_i >= 32'd1 && apb_pwdata_i <= 32'd4 && !busy_w;
    assign irq_o = irq_en_r && irq_stat_r;

    always @(*) begin
        apb_prdata_o = 32'b0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h0005_0001;
            12'h008: apb_prdata_o = {31'b0, busy_w};
            12'h00c: apb_prdata_o = {30'b0, irq_en_r, 1'b0};
            12'h010: apb_prdata_o = {30'b0, irq_stat_r, 1'b0};
            12'h014: apb_prdata_o = err_addr_r;
            12'h020: apb_prdata_o = op_addr_r;
            12'h024: apb_prdata_o = op_size_r;
            default: apb_prdata_o = 32'b0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            maint_req_valid_o <= 1'b0;
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            err_addr_r <= 32'b0;
            op_addr_r <= 32'b0;
            op_size_r <= 32'b0;
        end else begin
            if (maint_req_ready_i) begin
                maint_req_valid_o <= 1'b0;
            end
            if (launch_w) begin
                maint_req_valid_o <= 1'b1;
            end
            if (write_w) begin
                case (apb_paddr_i)
                    12'h00c: if (apb_pstrb_i[0]) irq_en_r <= apb_pwdata_i[1];
                    12'h010: if (apb_pstrb_i[0] && apb_pwdata_i[1]) irq_stat_r <= 1'b0;
                    12'h020: begin
                        for (byte_idx_r = 0; byte_idx_r < 4; byte_idx_r = byte_idx_r + 1) begin
                            if (apb_pstrb_i[byte_idx_r]) begin
                                op_addr_r[byte_idx_r*8 +: 8] <= apb_pwdata_i[byte_idx_r*8 +: 8];
                            end
                        end
                    end
                    12'h024: begin
                        for (byte_idx_r = 0; byte_idx_r < 4; byte_idx_r = byte_idx_r + 1) begin
                            if (apb_pstrb_i[byte_idx_r]) begin
                                op_size_r[byte_idx_r*8 +: 8] <= apb_pwdata_i[byte_idx_r*8 +: 8];
                            end
                        end
                    end
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
