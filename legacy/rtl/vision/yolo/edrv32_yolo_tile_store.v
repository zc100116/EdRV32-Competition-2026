// ============================================================================
// File        : edrv32_yolo_tile_store.v
// Description : Local weight and activation tiles for one 32-channel CONV.
// Notes       : Eight 512x256 weight banks give one 2048-bit K row/cycle.
//               The 2048x128 activation tile stores two pixels x eight INT8
//               terms per row. Both read ports have one-cycle latency.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_yolo_tile_store (
    input  wire          clk_i,
    input  wire          rst_n_i,

    input  wire          weight_wr_en_i,
    input  wire [11:0]   weight_wr_addr_i,
    input  wire [255:0]  weight_wr_data_i,
    input  wire          activation_wr_en_i,
    input  wire [10:0]   activation_wr_addr_i,
    input  wire [127:0]  activation_wr_data_i,

    input  wire          rd_en_i,
    input  wire [8:0]    weight_rd_addr_i,
    input  wire [10:0]   activation_rd_addr_i,
    output wire [2047:0] weight_rd_data_o,
    output wire [127:0]  activation_rd_data_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    genvar bank;
    generate
        for (bank = 0; bank < 8; bank = bank + 1) begin : g_weight_bank
            localparam [2:0] BANK_ID = bank;
            wire bank_write_w = weight_wr_en_i &&
                                weight_wr_addr_i[2:0] == BANK_ID;

            yolo_weight_ram u_weight_ram (
                .wr_data    (weight_wr_data_i),
                .wr_addr    (weight_wr_addr_i[11:3]),
                .wr_en      (bank_write_w),
                .wr_clk     (clk_i),
                .wr_rst     (~rst_n_i),
                .wr_byte_en (32'hffff_ffff),
                .rd_data    (weight_rd_data_o[bank*256 +: 256]),
                .rd_addr    (weight_rd_addr_i),
                .rd_clk     (clk_i),
                .rd_rst     (~rst_n_i),
                .rd_clk_en  (rd_en_i)
            );
        end
    endgenerate

    yolo_activation_ram u_activation_ram (
        .wr_data    (activation_wr_data_i),
        .wr_addr    (activation_wr_addr_i),
        .wr_en      (activation_wr_en_i),
        .wr_clk     (clk_i),
        .wr_rst     (~rst_n_i),
        .wr_byte_en (16'hffff),
        .rd_data    (activation_rd_data_o),
        .rd_addr    (activation_rd_addr_i),
        .rd_clk     (clk_i),
        .rd_rst     (~rst_n_i),
        .rd_clk_en  (rd_en_i)
    );
`else
    reg [255:0] weight_memory_r [0:4095];
    reg [127:0] activation_memory_r [0:2047];
    reg [2047:0] weight_rd_r;
    reg [127:0] activation_rd_r;
    integer bank;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            weight_rd_r     <= 2048'b0;
            activation_rd_r <= 128'b0;
        end else begin
            if (weight_wr_en_i)
                weight_memory_r[weight_wr_addr_i] <= weight_wr_data_i;
            if (activation_wr_en_i)
                activation_memory_r[activation_wr_addr_i] <=
                    activation_wr_data_i;
            if (rd_en_i) begin
                for (bank = 0; bank < 8; bank = bank + 1)
                    weight_rd_r[bank*256 +: 256] <=
                        weight_memory_r[{weight_rd_addr_i, 3'b000} +
                                        bank[11:0]];
                activation_rd_r <=
                    activation_memory_r[activation_rd_addr_i];
            end
        end
    end

    assign weight_rd_data_o = weight_rd_r;
    assign activation_rd_data_o = activation_rd_r;
`endif

endmodule
