// File: edrv32_cpu2_fpu_rf.v
// Spec: fpu-spec 2.4, 3.2, 5.1; cpu-v2-spec 3.4.
// Description: Independent 32-register FP RF, three F or two FD asynchronous read copies.
// Registered commit WB values explicitly forward to reads, including f0.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_rf #(
    parameter [31:0] FPU_FORMAT = "F"
) (
    // Clock and reset (RF data does not reset).
    input wire clk_i,
    input wire rst_n_i,

    // Issue reads; FD omits the third physical read copy.
    input wire [4:0] fp_read0_addr_i,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_read0_data_o,
    input wire [4:0] fp_read1_addr_i,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_read1_data_o,
    input wire [4:0] fp_read2_addr_i,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_read2_data_o,

    // Single committed write, supplied by the existing WB register.
    input wire fp_wb_valid_i,
    input wire [4:0] fp_wb_rd_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_wb_data_i
);
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam R = FPU_FORMAT == "FD" ? 2 : 3;
    wire [14:0] read_addr_w;
    wire [3*B-1:0] read_data_w;
    assign read_addr_w = {fp_read2_addr_i,fp_read1_addr_i,fp_read0_addr_i};
    assign {fp_read2_data_o,fp_read1_data_o,fp_read0_data_o} = read_data_w;
    genvar portnum;
    generate
        for (portnum = 0; portnum < 3; portnum = portnum + 1) begin : g_read
            localparam ACTIVE = portnum < R;
            if (ACTIVE) begin : g_active
                wire [4:0] addr_w;
                wire [B-1:0] stored_w;
                assign addr_w = read_addr_w[portnum*5 +: 5];
                edrv32_ram_cpu2_rf u_low (
                    .clk_i(clk_i),
                    .wr_en_i(fp_wb_valid_i),
                    .wr_addr_i(fp_wb_rd_i),
                    .wr_data_i(fp_wb_data_i[31:0]),
                    .rd_addr_i(addr_w),
                    .rd_data_o(stored_w[31:0])
                );
                if (FPU_FORMAT == "FD") begin : g_high
                    edrv32_ram_cpu2_rf u_high (
                        .clk_i(clk_i),
                        .wr_en_i(fp_wb_valid_i),
                        .wr_addr_i(fp_wb_rd_i),
                        .wr_data_i(fp_wb_data_i[63:32]),
                        .rd_addr_i(addr_w),
                        .rd_data_o(stored_w[63:32])
                    );
                end
                assign read_data_w[portnum*B +: B] = fp_wb_valid_i
                    && (fp_wb_rd_i == addr_w) ? fp_wb_data_i : stored_w;
            end else begin : g_inactive
                assign read_data_w[portnum*B +: B] = {B{1'b0}};
            end
        end
    endgenerate
    wire unused_w;
    assign unused_w = ^{rst_n_i,read_addr_w[14:10]};
endmodule
