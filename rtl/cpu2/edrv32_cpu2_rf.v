// File: edrv32_cpu2_rf.v
// Spec: cpu-v2-spec 5.2, 7.
// Description: Four asynchronous reads, two owner writes and explicit WB forwarding.
// Clock domain: clk_sys.
module edrv32_cpu2_rf (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    // Registered ID source addresses and owners from IB.
    input wire [19:0] id_rs_i,
    input wire [3:0] id_owner_i,
    // WB slots in increasing age order.
    input wire [1:0] wb_valid_i,
    input wire [9:0] wb_rd_i,
    input wire [63:0] wb_data_i,
    // F2 LVT queries use the physical cache-bank instruction fields.
    output wire [31:1] lvt_o,
    output wire [127:0] id_data_o
);
    wire [31:1] lvt_flat_w;
    wire [1:0] wb_write_w;
    assign wb_write_w[0] = wb_valid_i[0] && (wb_rd_i[4:0] != 5'd0);
    assign wb_write_w[1] = wb_valid_i[1] && (wb_rd_i[9:5] != 5'd0);
    assign lvt_o = lvt_flat_w;
    // Each architectural LVT bit has one writer; younger WB wins a WAW.
    genvar regnum;
    generate
        for (regnum = 1; regnum < 32; regnum = regnum + 1) begin : g_lvt
            reg lvt_r;
            assign lvt_flat_w[regnum] = lvt_r;
            localparam [4:0] REGNUM = regnum;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    lvt_r <= 1'b0;
                else if (wb_write_w[1] && (wb_rd_i[9:5] == REGNUM))
                    lvt_r <= 1'b1;
                else if (wb_write_w[0] && (wb_rd_i[4:0] == REGNUM))
                    lvt_r <= 1'b0;
            end
        end
    endgenerate
    genvar portnum;
    generate
        for (portnum = 0; portnum < 4; portnum = portnum + 1) begin : g_read
            wire [4:0] id_rs_w;
            wire [31:0] bank0_data_w;
            wire [31:0] bank1_data_w;
            wire [31:0] owner_data_w;
            assign id_rs_w = id_rs_i[5*portnum +: 5];
            edrv32_ram_cpu2_rf u_bank0 (
                .clk_i(clk_i),
                .wr_en_i(wb_write_w[0]),
                .wr_addr_i(wb_rd_i[4:0]),
                .wr_data_i(wb_data_i[31:0]),
                .rd_addr_i(id_rs_w),
                .rd_data_o(bank0_data_w)
            );
            edrv32_ram_cpu2_rf u_bank1 (
                .clk_i(clk_i),
                .wr_en_i(wb_write_w[1]),
                .wr_addr_i(wb_rd_i[9:5]),
                .wr_data_i(wb_data_i[63:32]),
                .rd_addr_i(id_rs_w),
                .rd_data_o(bank1_data_w)
            );
            assign owner_data_w = id_owner_i[portnum] ? bank1_data_w : bank0_data_w;
            assign id_data_o[32*portnum +: 32] = (id_rs_w == 5'd0) ? 32'd0 :
                (wb_write_w[1] && (wb_rd_i[9:5] == id_rs_w)) ? wb_data_i[63:32] :
                (wb_write_w[0] && (wb_rd_i[4:0] == id_rs_w)) ? wb_data_i[31:0] :
                owner_data_w;
        end
    endgenerate
endmodule
