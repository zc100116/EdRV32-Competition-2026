// ============================================================================
// File        : edrv32_tmds_serdes.v
// Description : Pango DDR10:1 output serializer and differential buffer.
// Notes       : The portable build exposes bit zero only; protocol simulation
//               verifies the parallel TMDS symbols before this device boundary.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_tmds_serdes (
    input  wire       pixel_clk_i,
    input  wire       serial_clk_i,
    input  wire       serial_rst_n_i,
    input  wire [9:0] symbol_i,
    output wire       data_p_o,
    output wire       data_n_o
);

    // Keep one reset release chain per TMDS lane. The input reset is already
    // synchronized to serial_clk_i at the HDMI clock boundary; these local
    // stages replicate the release point close to the two OSERDES instances
    // instead of routing one high-fanout reset across all four I/O lanes.
    // Asynchronous assertion is retained so a lost PLL lock stops the lane
    // immediately. syn_preserve prevents equivalent lane chains from merging.
    (* syn_preserve = 1 *) reg [1:0] local_reset_pipe_r;

    always @(posedge serial_clk_i or negedge serial_rst_n_i) begin
        if (!serial_rst_n_i)
            local_reset_pipe_r <= 2'b00;
        else
            local_reset_pipe_r <= {local_reset_pipe_r[0], 1'b1};
    end

    wire local_rst_n_w = local_reset_pipe_r[1];

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    wire serial_data_w;
    wire cascade0_w;
    wire cascade1_w;

    GTP_OUTBUFDS #(
        .IOSTANDARD ("TMDS")
    ) u_output_buffer (
        .O  (data_p_o),
        .OB (data_n_o),
        .I  (serial_data_w)
    );

    GTP_OSERDES_E2 #(
        .GRS_EN        ("TRUE"),
        .OSERDES_MODE  ("DDR10TO1"),
        .TSERDES_EN    ("FALSE"),
        .UPD0_SHIFT_EN ("FALSE"),
        .UPD1_SHIFT_EN ("FALSE"),
        .INIT_SET      (2'b00),
        .GRS_TYPE_DQ   ("RESET"),
        .LRS_TYPE_DQ0  ("ASYNC_RESET"),
        .LRS_TYPE_DQ1  ("ASYNC_RESET"),
        .LRS_TYPE_DQ2  ("ASYNC_RESET"),
        .LRS_TYPE_DQ3  ("ASYNC_RESET"),
        .GRS_TYPE_TQ   ("RESET"),
        .LRS_TYPE_TQ0  ("ASYNC_RESET"),
        .LRS_TYPE_TQ1  ("ASYNC_RESET"),
        .LRS_TYPE_TQ2  ("ASYNC_RESET"),
        .LRS_TYPE_TQ3  ("ASYNC_RESET"),
        .TRI_EN        ("FALSE"),
        .TBYTE_EN      ("FALSE"),
        .MIPI_EN       ("FALSE"),
        .OCASCADE_EN   ("FALSE")
    ) u_serializer_master (
        .RST        (~local_rst_n_w),
        .OCE        (1'b1),
        .TCE        (1'b0),
        .OCLKDIV    (pixel_clk_i),
        .SERCLK     (serial_clk_i),
        .OCLK       (serial_clk_i),
        .MIPI_CTRL  (),
        .UPD0_SHIFT (1'b0),
        .UPD1_SHIFT (1'b0),
        .OSHIFTIN0  (cascade0_w),
        .OSHIFTIN1  (cascade1_w),
        .DI         (symbol_i[7:0]),
        .TI         (),
        .TBYTE_IN   (),
        .OSHIFTOUT0 (),
        .OSHIFTOUT1 (),
        .DO         (serial_data_w),
        .TQ         ()
    );

    GTP_OSERDES_E2 #(
        .GRS_EN        ("TRUE"),
        .OSERDES_MODE  ("DDR10TO1"),
        .TSERDES_EN    ("FALSE"),
        .UPD0_SHIFT_EN ("FALSE"),
        .UPD1_SHIFT_EN ("FALSE"),
        .INIT_SET      (2'b00),
        .GRS_TYPE_DQ   ("RESET"),
        .LRS_TYPE_DQ0  ("ASYNC_RESET"),
        .LRS_TYPE_DQ1  ("ASYNC_RESET"),
        .LRS_TYPE_DQ2  ("ASYNC_RESET"),
        .LRS_TYPE_DQ3  ("ASYNC_RESET"),
        .GRS_TYPE_TQ   ("RESET"),
        .LRS_TYPE_TQ0  ("ASYNC_RESET"),
        .LRS_TYPE_TQ1  ("ASYNC_RESET"),
        .LRS_TYPE_TQ2  ("ASYNC_RESET"),
        .LRS_TYPE_TQ3  ("ASYNC_RESET"),
        .TRI_EN        ("FALSE"),
        .TBYTE_EN      ("FALSE"),
        .MIPI_EN       ("FALSE"),
        .OCASCADE_EN   ("TRUE")
    ) u_serializer_slave (
        .RST        (~local_rst_n_w),
        .OCE        (1'b1),
        .TCE        (1'b0),
        .OCLKDIV    (pixel_clk_i),
        .SERCLK     (serial_clk_i),
        .OCLK       (serial_clk_i),
        .MIPI_CTRL  (),
        .UPD0_SHIFT (1'b0),
        .UPD1_SHIFT (1'b0),
        .OSHIFTIN0  (),
        .OSHIFTIN1  (),
        .DI         ({4'b0, symbol_i[9:8], 2'b0}),
        .TI         (),
        .TBYTE_IN   (),
        .OSHIFTOUT0 (cascade0_w),
        .OSHIFTOUT1 (cascade1_w),
        .DO         (),
        .TQ         ()
    );
`else
    assign data_p_o = symbol_i[0];
    assign data_n_o = !symbol_i[0];
    wire unused_pixel_clk_w = pixel_clk_i;
    wire unused_local_rst_n_w = local_rst_n_w;
`endif

endmodule
