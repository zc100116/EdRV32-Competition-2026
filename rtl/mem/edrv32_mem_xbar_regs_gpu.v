// File: edrv32_mem_xbar_regs_gpu.v
// Spec: gpu-soc-spec 8.3; mem-subsys-spec 4.1, 6; edrv32-soc-spec 7.1.
// Description: Common APB status and sticky violation interrupt/address/type.
//              Removed configuration and statistics addresses read zero and ignore writes.
// Clock: clk_mem.
module edrv32_mem_xbar_regs_gpu (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB control interface; full-word writes ignore PSTRB.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Status and violations.
    input wire busy_i,
    input wire err_valid_i,
    input wire [2:0] err_port_i,
    input wire [31:0] err_addr_i,
    input wire [2:0] err_type_i,
    output wire irq_o
);
    reg [11:0] apb_paddr_r;
    reg apb_pwrite_r;
    reg [31:0] apb_pwdata_r;
    reg irq_en_r;
    reg irq_stat_r;
    reg [2:0] err_port_r;
    reg [31:0] err_addr_r;
    reg [2:0] err_type_r;
    wire write_w;
    wire irq_clear_w;
    wire unused_apb_w;
    assign unused_apb_w = &{apb_pstrb_i, apb_pwdata_r[31:2], apb_pwdata_r[0]};
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign irq_clear_w = write_w && apb_paddr_r == 12'h010 && apb_pwdata_r[1];
    assign irq_o = irq_en_r && irq_stat_r;
    // SoC 4.3: terminate the shared payload at setup-phase registers.
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            apb_paddr_r <= apb_paddr_i;
            apb_pwrite_r <= apb_pwrite_i;
            apb_pwdata_r <= apb_pwdata_i;
        end
    end
    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_r)
            12'h000: apb_prdata_o = 32'h0008_0001;
            12'h008: apb_prdata_o = {29'd0, irq_stat_r, !busy_i, busy_i};
            12'h00c: apb_prdata_o = {30'd0, irq_en_r, 1'b0};
            12'h010: apb_prdata_o = {30'd0, irq_stat_r, 1'b0};
            12'h014: apb_prdata_o = {29'd0, err_type_r};
            12'h120: apb_prdata_o = {29'd0, err_port_r};
            12'h124: apb_prdata_o = err_addr_r;
            12'h128: apb_prdata_o = {29'd0, err_type_r};
            default: begin end
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            err_port_r <= 3'd0;
            err_addr_r <= 32'd0;
            err_type_r <= 3'd0;
        end else begin
            if (write_w && apb_paddr_r == 12'h00c) irq_en_r <= apb_pwdata_r[1];
            if (irq_clear_w) begin
                irq_stat_r <= 1'b0;
                err_port_r <= 3'd0;
                err_addr_r <= 32'd0;
                err_type_r <= 3'd0;
            end
            // Same-cycle violation wins over W1C.
            if (err_valid_i) begin
                irq_stat_r <= 1'b1;
                err_port_r <= err_port_i;
                err_addr_r <= err_addr_i;
                err_type_r <= err_type_i;
            end
        end
    end
endmodule
