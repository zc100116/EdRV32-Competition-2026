// File: edrv32_gpu2_banks_drm.v
// Spec: gpu-v2-spec 2.4/2.6; G-P04; M-8 10.2/10.4.
// Description: C12 RF/constant/program memories and 72 independent 16x92 scratch banks.
//              One RAM read clock, then external capture; no field scheduling implied.
// Clock domain: clk_gpu.
module edrv32_gpu2_banks_drm (
    // Clock.
    input wire clk_i,

    // RF three coherent read replicas, one whole-vec4 write.
    input wire rf_wr_en_i,
    input wire [8:0] rf_wr_addr_i,
    input wire [127:0] rf_wr_data_i,
    input wire [2:0] rf_rd_en_i,
    input wire [26:0] rf_rd_addr_i,
    output wire [383:0] rf_rd_data_o,

    // Draw constants: two coherent read replicas, 128 used addresses.
    input wire const_wr_en_i,
    input wire [6:0] const_wr_addr_i,
    input wire [127:0] const_wr_data_i,
    input wire [1:0] const_rd_en_i,
    input wire [13:0] const_rd_addr_i,
    output wire [255:0] const_rd_data_o,

    // Program width derives from 64 instruction bits plus eight bits/context.
    input wire program_wr_en_i,
    input wire [9:0] program_wr_addr_i,
    input wire [159:0] program_wr_data_i,
    input wire program_rd_en_i,
    input wire [9:0] program_rd_addr_i,
    output wire [159:0] program_rd_data_o,

    // Bank index = triangle_slot*8 + attribute_slot*2 + field_pair.
    // Each element is independent, never an arbitrary mux of the complete record.
    input wire [71:0] setup_wr_en_i,
    input wire [287:0] setup_wr_addr_i,
    input wire [6623:0] setup_wr_data_i,
    input wire [71:0] setup_rd_en_i,
    input wire [287:0] setup_rd_addr_i,
    output wire [6623:0] setup_rd_data_o
);
    localparam VERTEX_CONTEXTS = 12;
    localparam PROGRAM_WIDTH = 64 + 8 * VERTEX_CONTEXTS;
    wire [179:0] program_write_w;
    wire [179:0] program_read_w;
    assign program_write_w = {20'b0, program_wr_data_i};
    genvar p;
    generate
        for (p = 0; p < (PROGRAM_WIDTH+35)/36; p = p+1) begin : g_program
            wire [35:0] data_w;
            reg [35:0] capture_r;
            edrv32_ram_gpu2_sdp36 u_ram (
                .clk_i(clk_i),
                .wr_en_i(program_wr_en_i),
                .wr_addr_i(program_wr_addr_i),
                .wr_data_i(program_write_w[p*36 +: 36]),
                .rd_en_i(program_rd_en_i),
                .rd_addr_i(program_rd_addr_i),
                .rd_data_o(data_w)
            );
            always @(posedge clk_i) begin
                capture_r <= data_w;
            end
            assign program_read_w[p*36 +: 36] = capture_r;
        end
    endgenerate
    assign program_rd_data_o = program_read_w[PROGRAM_WIDTH-1:0];
    wire unused_program_w;
    assign unused_program_w = ^program_read_w[179:160];
    genvar rf_replica;
    generate
        for (rf_replica = 0; rf_replica < 3;
            rf_replica = rf_replica+1) begin : g_rf
            wire [143:0] data_w;
            reg [127:0] capture_r;
            edrv32_ram_gpu2_sdp72 u_half0 (
                .clk_i(clk_i),
                .wr_en_i(rf_wr_en_i),
                .wr_addr_i(rf_wr_addr_i),
                .wr_data_i(rf_wr_data_i[71:0]),
                .rd_en_i(rf_rd_en_i[rf_replica]),
                .rd_addr_i(rf_rd_addr_i[rf_replica*9 +: 9]),
                .rd_data_o(data_w[0 +: 72])
            );
            edrv32_ram_gpu2_sdp72 u_half1 (
                .clk_i(clk_i),
                .wr_en_i(rf_wr_en_i),
                .wr_addr_i(rf_wr_addr_i),
                .wr_data_i({16'b0, rf_wr_data_i[127:72]}),
                .rd_en_i(rf_rd_en_i[rf_replica]),
                .rd_addr_i(rf_rd_addr_i[rf_replica*9 +: 9]),
                .rd_data_o(data_w[72 +: 72])
            );
            always @(posedge clk_i) begin
                capture_r <= data_w[127:0];
            end
            assign rf_rd_data_o[rf_replica*128 +: 128] = capture_r;
            wire unused_w;
            assign unused_w = ^data_w[143:128];
        end
    endgenerate
    genvar const_replica;
    generate
        for (const_replica = 0; const_replica < 2;
            const_replica = const_replica+1) begin : g_const
            wire [143:0] data_w;
            reg [127:0] capture_r;
            edrv32_ram_gpu2_sdp72 u_half0 (
                .clk_i(clk_i),
                .wr_en_i(const_wr_en_i),
                .wr_addr_i({2'b0, const_wr_addr_i}),
                .wr_data_i(const_wr_data_i[71:0]),
                .rd_en_i(const_rd_en_i[const_replica]),
                .rd_addr_i({2'b0, const_rd_addr_i[const_replica*7 +: 7]}),
                .rd_data_o(data_w[0 +: 72])
            );
            edrv32_ram_gpu2_sdp72 u_half1 (
                .clk_i(clk_i),
                .wr_en_i(const_wr_en_i),
                .wr_addr_i({2'b0, const_wr_addr_i}),
                .wr_data_i({16'b0, const_wr_data_i[127:72]}),
                .rd_en_i(const_rd_en_i[const_replica]),
                .rd_addr_i({2'b0, const_rd_addr_i[const_replica*7 +: 7]}),
                .rd_data_o(data_w[72 +: 72])
            );
            always @(posedge clk_i) begin
                capture_r <= data_w[127:0];
            end
            assign const_rd_data_o[const_replica*128 +: 128] = capture_r;
            wire unused_w;
            assign unused_w = ^data_w[143:128];
        end
    endgenerate
    genvar bank;
    generate
        for (bank = 0; bank < 72; bank = bank+1) begin : g_setup
            wire [91:0] data_w;
            reg [91:0] capture_r;
            wire [143:0] padded_w;
            assign data_w = padded_w[91:0];
            wire unused_w;
            assign unused_w = ^padded_w[143:92];
            edrv32_ram_gpu2_sdp72 u_half0 (
                .clk_i(clk_i),
                .wr_en_i(setup_wr_en_i[bank]),
                .wr_addr_i({5'b0, setup_wr_addr_i[bank*4 +: 4]}),
                .wr_data_i(setup_wr_data_i[bank*92 +: 72]),
                .rd_en_i(setup_rd_en_i[bank]),
                .rd_addr_i({5'b0, setup_rd_addr_i[bank*4 +: 4]}),
                .rd_data_o(padded_w[0 +: 72])
            );
            edrv32_ram_gpu2_sdp72 u_half1 (
                .clk_i(clk_i),
                .wr_en_i(setup_wr_en_i[bank]),
                .wr_addr_i({5'b0, setup_wr_addr_i[bank*4 +: 4]}),
                .wr_data_i({52'b0, setup_wr_data_i[bank*92+72 +: 20]}),
                .rd_en_i(setup_rd_en_i[bank]),
                .rd_addr_i({5'b0, setup_rd_addr_i[bank*4 +: 4]}),
                .rd_data_o(padded_w[72 +: 72])
            );
            always @(posedge clk_i) begin
                capture_r <= data_w;
            end
            assign setup_rd_data_o[bank*92 +: 92] = capture_r;
        end
    endgenerate
endmodule
