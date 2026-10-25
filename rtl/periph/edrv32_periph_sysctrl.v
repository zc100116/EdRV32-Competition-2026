// File: edrv32_periph_sysctrl.v
// Spec: sys-subsys-spec 2.9, 3.2, 4.6.
// Description: APB system information, persistent scratch and software requests.
//              rst_n_i is the power-on reset, independent of SoC software reset.
// Clock domain: clk_sys; mem_ready_i is synchronized at the input.
module edrv32_periph_sysctrl (
    // Clock and power-on reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output reg [31:0] apb_prdata_o,
    output wire apb_pready_o,
    output wire apb_pslverr_o,

    // System status and software request pulses.
    input wire mem_ready_i,
    output reg soft_reset_media_o,
    output reg soft_reset_soc_o,
    output reg sim_exit_valid_o,
    output reg [31:0] sim_exit_code_o
);
    // Other users of the generated map need its remaining constants.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg [31:0] scratch0_r;
    reg [31:0] scratch1_r;
    wire mem_ready_w;
    wire write_w;
    wire unused_w;

    assign unused_w = &{1'b0, apb_pstrb_i};
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;

    edrv32_cdc_sync_bit u_mem_ready (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bit_i(mem_ready_i),
        .bit_o(mem_ready_w)
    );
    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00060001;
            12'h004: apb_prdata_o = 32'hED320001;
            12'h008: apb_prdata_o = EDRV32_CLK_SYS_HZ;
            12'h00C: apb_prdata_o = {31'd0, mem_ready_w};
            12'h010: apb_prdata_o = scratch0_r;
            12'h014: apb_prdata_o = scratch1_r;
            default: apb_prdata_o = 32'd0;
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scratch0_r <= 32'd0;
            scratch1_r <= 32'd0;
            soft_reset_media_o <= 1'b0;
            soft_reset_soc_o <= 1'b0;
            sim_exit_valid_o <= 1'b0;
        end else begin
            soft_reset_media_o <= write_w && apb_paddr_i == 12'h018 && apb_pwdata_i[0];
            soft_reset_soc_o <= write_w && apb_paddr_i == 12'h018 && apb_pwdata_i[1];
            sim_exit_valid_o <= write_w && apb_paddr_i == 12'h01C;
            if (write_w && apb_paddr_i == 12'h010) begin
                scratch0_r <= apb_pwdata_i;
            end
            if (write_w && apb_paddr_i == 12'h014) begin
                scratch1_r <= apb_pwdata_i;
            end
        end
    end
    always @(posedge clk_i) begin
        if (write_w && apb_paddr_i == 12'h01C) begin
            sim_exit_code_o <= apb_pwdata_i;
        end
    end
endmodule
