// File: edrv32_ram_gpu_palette_current.v
// Spec: gpu-spec 2.6; GPU microarchitecture 4.8; CLAUDE.md 8.
// Description: Fixed 256x20 distributed palette replica, sixteen 16-row pages.
// Registered index, page read, four-page selection and final selection: four cycles.
// Clock: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu_palette_current (
    // Clock and broadcast preload.
    input wire clk_i,
    input wire wr_en_i,
    input wire [7:0] wr_addr_i,
    input wire [19:0] wr_data_i,

    // Independent sampling port.
    input wire rd_en_i,
    input wire [7:0] rd_addr_i,
    output reg [19:0] rd_data_o
);
    reg [7:0] rd_addr_r;
    reg select_en_r;
    wire [319:0] page_data_w;
    reg [319:0] page_data_r;
    reg [79:0] group_data_r;
    reg [3:0] page_select_r;
    reg [1:0] group_select_r;
    genvar page;
    generate
        for (page = 0; page < 16; page = page + 1) begin : g_page
            // One preserved enable per page, at the original read-index boundary.
            (* keep = "true", syn_preserve = 1 *) reg rd_en_r;
            always @(posedge clk_i) begin
                rd_en_r <= rd_en_i;
                if (rd_en_r) page_data_r[page*20 +: 20] <= page_data_w[page*20 +: 20];
            end
`ifdef EDRV32_FPGA_MEMORY_MODE
            ip_lutram_gpu_palette_current u_ip (
                .wr_clk(clk_i),
                .wr_en(wr_en_i && wr_addr_i[7:4] == page),
                .wr_addr(wr_addr_i[3:0]),
                .wr_data(wr_data_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .rd_addr(rd_addr_r[3:0]),
                .rd_data(page_data_w[page*20 +: 20])
            );
`else
            reg [19:0] memory_r [0:15];
            assign page_data_w[page*20 +: 20] = memory_r[rd_addr_r[3:0]];
            always @(posedge clk_i) begin
                if (wr_en_i && wr_addr_i[7:4] == page) begin
                    memory_r[wr_addr_i[3:0]] <= wr_data_i;
                end
            end
`endif
        end
    endgenerate
    integer group_idx;
    always @(posedge clk_i) begin
        if (rd_en_i) begin
            rd_addr_r <= rd_addr_i;
        end
        select_en_r <= rd_en_i;
        if (select_en_r) page_select_r <= rd_addr_r[7:4];
        for (group_idx = 0; group_idx < 4; group_idx = group_idx + 1) begin
            group_data_r[group_idx*20 +: 20] <=
                page_data_r[(group_idx*4 + {30'b0, page_select_r[1:0]})*20 +: 20];
        end
        group_select_r <= page_select_r[3:2];
        rd_data_o <= group_data_r[group_select_r*20 +: 20];
    end
endmodule
