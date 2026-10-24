// ============================================================================
// File        : edrv32_yolo_line_cache.v
// Description : Two-read-bank cache for packed C16 feature-map beats.
// Notes       : Each bank holds 1024 x 256 bits. One read per bank per clock;
//               two requests to the same bank must use the same address.
//               Reads are synchronous with one clock of latency. The caller
//               assigns row/channel/column locations to bank addresses.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_yolo_line_cache (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         wr_valid_i,
    input  wire         wr_bank_i,
    input  wire [9:0]   wr_addr_i,
    input  wire [255:0] wr_data_i,

    input  wire         rd_valid_i,
    output wire         rd_ready_o,
    input  wire         rd_bank0_i,
    input  wire [9:0]   rd_addr0_i,
    input  wire         rd_bank1_i,
    input  wire [9:0]   rd_addr1_i,
    output wire         rd_valid_o,
    output wire [255:0] rd_data0_o,
    output wire [255:0] rd_data1_o
);

    wire conflict_w = rd_bank0_i == rd_bank1_i &&
                      rd_addr0_i != rd_addr1_i;
    wire rd_fire_w = rd_valid_i && rd_ready_o;
    reg rd_valid_r;
    reg rd_bank0_r;
    reg rd_bank1_r;
    reg rd_segment0_r;
    reg rd_segment1_r;
    wire [1:0] bank_rd_en_w;
    wire [9:0] bank_rd_addr_w [0:1];
    wire [255:0] bank_rd_data_w [0:1];

    assign rd_ready_o = !conflict_w;
    assign rd_valid_o = rd_valid_r;
    assign rd_data0_o = bank_rd_data_w[rd_bank0_r];
    assign rd_data1_o = bank_rd_data_w[rd_bank1_r];

    genvar bank;
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank_select
            assign bank_rd_en_w[bank] = rd_fire_w &&
                (rd_bank0_i == bank || rd_bank1_i == bank);
            assign bank_rd_addr_w[bank] = rd_bank0_i == bank ?
                rd_addr0_i : rd_addr1_i;
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_valid_r    <= 1'b0;
            rd_bank0_r    <= 1'b0;
            rd_bank1_r    <= 1'b0;
            rd_segment0_r <= 1'b0;
            rd_segment1_r <= 1'b0;
        end else begin
            rd_valid_r <= rd_fire_w;
            if (rd_fire_w) begin
                rd_bank0_r    <= rd_bank0_i;
                rd_bank1_r    <= rd_bank1_i;
                rd_segment0_r <= rd_addr0_i[9];
                rd_segment1_r <= rd_addr1_i[9];
            end
        end
    end

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    wire [255:0] bank_segment_data_w [0:3];
    genvar segment;
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
            for (segment = 0; segment < 2; segment = segment + 1)
                begin : g_segment
                yolo_weight_ram u_line_ram (
                    .wr_data    (wr_data_i),
                    .wr_addr    (wr_addr_i[8:0]),
                    .wr_en      (wr_valid_i && wr_bank_i == bank &&
                                 wr_addr_i[9] == segment),
                    .wr_clk     (clk_i),
                    .wr_rst     (~rst_n_i),
                    .wr_byte_en (32'hffff_ffff),
                    .rd_data    (bank_segment_data_w[bank*2+segment]),
                    .rd_addr    (bank_rd_addr_w[bank][8:0]),
                    .rd_clk     (clk_i),
                    .rd_rst     (~rst_n_i),
                    .rd_clk_en  (bank_rd_en_w[bank] &&
                                 bank_rd_addr_w[bank][9] == segment)
                );
            end
            assign bank_rd_data_w[bank] = bank == rd_bank0_r ?
                bank_segment_data_w[bank*2+rd_segment0_r] :
                bank_segment_data_w[bank*2+rd_segment1_r];
        end
    endgenerate
`else
    reg [255:0] bank0_r [0:1023];
    reg [255:0] bank1_r [0:1023];
    reg [255:0] bank0_read_r;
    reg [255:0] bank1_read_r;
    always @(posedge clk_i) begin
        if (wr_valid_i) begin
            if (wr_bank_i)
                bank1_r[wr_addr_i] <= wr_data_i;
            else
                bank0_r[wr_addr_i] <= wr_data_i;
        end
        if (bank_rd_en_w[0])
            bank0_read_r <= bank0_r[bank_rd_addr_w[0]];
        if (bank_rd_en_w[1])
            bank1_read_r <= bank1_r[bank_rd_addr_w[1]];
    end
    assign bank_rd_data_w[0] = bank0_read_r;
    assign bank_rd_data_w[1] = bank1_read_r;
`endif

endmodule
