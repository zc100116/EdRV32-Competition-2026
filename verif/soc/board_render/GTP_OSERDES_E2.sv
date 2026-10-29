// File: GTP_OSERDES_E2.sv
// Spec: fpga/rtl/edrv32_fpga_tmds.v; Task B3-6.
// Description: DDR10TO1 cascade/serializer model for board connectivity simulation.
//              Only the fixed TMDS configuration is modeled; frames are not checked.
// Clock domains: related OCLKDIV and SERCLK.
module GTP_OSERDES_E2 #(
    parameter GRS_EN = "TRUE",
    parameter OSERDES_MODE = "DDR10TO1",
    parameter TSERDES_EN = "FALSE",
    parameter UPD0_SHIFT_EN = "FALSE",
    parameter UPD1_SHIFT_EN = "FALSE",
    parameter INIT_SET = 2'b00,
    parameter GRS_TYPE_DQ = "RESET",
    parameter LRS_TYPE_DQ0 = "ASYNC_RESET",
    parameter LRS_TYPE_DQ1 = "ASYNC_RESET",
    parameter LRS_TYPE_DQ2 = "ASYNC_RESET",
    parameter LRS_TYPE_DQ3 = "ASYNC_RESET",
    parameter GRS_TYPE_TQ = "RESET",
    parameter LRS_TYPE_TQ0 = "ASYNC_RESET",
    parameter LRS_TYPE_TQ1 = "ASYNC_RESET",
    parameter LRS_TYPE_TQ2 = "ASYNC_RESET",
    parameter LRS_TYPE_TQ3 = "ASYNC_RESET",
    parameter TRI_EN = "FALSE",
    parameter TBYTE_EN = "FALSE",
    parameter MIPI_EN = "FALSE",
    parameter OCASCADE_EN = "FALSE"
) (
    input wire RST,
    input wire OCE,
    input wire TCE,
    input wire OCLKDIV,
    input wire SERCLK,
    input wire OCLK,
    input wire MIPI_CTRL,
    input wire UPD0_SHIFT,
    input wire UPD1_SHIFT,
    input wire OSHIFTIN0,
    input wire OSHIFTIN1,
    input wire [7:0] DI,
    input wire TI,
    input wire TBYTE_IN,
    output wire OSHIFTOUT0,
    output wire OSHIFTOUT1,
    output reg DO = 0,
    output wire TQ
);
    reg [9:0] symbol;
    reg [3:0] index = 0;
    assign OSHIFTOUT0 = DI[2];
    assign OSHIFTOUT1 = DI[3];
    assign TQ = 1'b0;
    always @(posedge OCLKDIV) symbol <= {OSHIFTIN1, OSHIFTIN0, DI};
    always @(SERCLK) begin
        DO <= symbol[index];
        index <= index == 9 ? 0 : index + 1'b1;
    end
    wire unused_controls = &{1'b0, RST, OCE, TCE, OCLK, MIPI_CTRL, UPD0_SHIFT,
        UPD1_SHIFT, TI, TBYTE_IN};
    wire unused_configuration = &{1'b0,
        GRS_EN,
        OSERDES_MODE,
        TSERDES_EN,
        UPD0_SHIFT_EN,
        UPD1_SHIFT_EN,
        INIT_SET,
        GRS_TYPE_DQ,
        LRS_TYPE_DQ0,
        LRS_TYPE_DQ1,
        LRS_TYPE_DQ2,
        LRS_TYPE_DQ3,
        GRS_TYPE_TQ,
        LRS_TYPE_TQ0,
        LRS_TYPE_TQ1,
        LRS_TYPE_TQ2,
        LRS_TYPE_TQ3,
        TRI_EN,
        TBYTE_EN,
        MIPI_EN,
        OCASCADE_EN};
endmodule
