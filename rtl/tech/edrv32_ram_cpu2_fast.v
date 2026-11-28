// File: edrv32_ram_cpu2_fast.v
// Spec: cpu-v2-spec 5.4.
// Description: Three read replicas of a 4096x2 gshare; four 1024x2 IP banks per replica.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu2_fast (
    // Clock and single update port.
    input wire clk_i,
    input wire wr_en_i,
    input wire [11:0] wr_addr_i,
    input wire [1:0] wr_data_i,
    // Two prediction reads plus current-counter training read.
    input wire [23:0] rd_addr_i,
    output wire [3:0] rd_data_o,
    output wire [1:0] update_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    wire [5:0] copy_data_w;
    genvar copy;
    genvar bank;
    generate
        for (copy = 0; copy < 3; copy = copy + 1) begin : g_copy
            wire [11:0] addr_w;
            wire [7:0] data_w;
            if (copy < 2) begin : g_query
                assign addr_w = rd_addr_i[12*copy +: 12];
            end else begin : g_training
                assign addr_w = wr_addr_i;
            end
            for (bank = 0; bank < 4; bank = bank + 1) begin : g_bank
                localparam [1:0] BANK = bank;
                ip_lutram_cpu2_fast u_ip (
                    .wr_clk(clk_i),
                    .rd_clk(clk_i),
                    .rst(1'b0),
                    .wr_en(wr_en_i && (wr_addr_i[11:10] == BANK)),
                    .wr_addr(wr_addr_i[9:0]),
                    .wr_data(wr_data_i),
                    .rd_addr(addr_w[9:0]),
                    .rd_data(data_w[2*bank +: 2])
                );
            end
            assign copy_data_w[2*copy +: 2] = (addr_w[11:10] == 2'd0) ? data_w[1:0] :
                (addr_w[11:10] == 2'd1) ? data_w[3:2] :
                (addr_w[11:10] == 2'd2) ? data_w[5:4] : data_w[7:6];
        end
    endgenerate
    assign rd_data_o = copy_data_w[3:0];
    assign update_data_o = copy_data_w[5:4];
`else
    reg [1:0] memory_r [0:4095];
    integer entry;
    initial begin
        for (entry = 0; entry < 4096; entry = entry + 1)
            memory_r[entry] = 2'd1;
    end
    assign rd_data_o = {memory_r[rd_addr_i[23:12]], memory_r[rd_addr_i[11:0]]};
    assign update_data_o = memory_r[wr_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
