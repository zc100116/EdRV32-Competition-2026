// File: edrv32_cpu_regfile.v
// Spec: cpu-spec 4.2, 4.3
// Description: Store the architectural integer registers with four reads and two writes.
// Forward current writes to reads and give the younger write port priority.
// Clock domain: clk_sys.
module edrv32_cpu_regfile (
    // Clock; data array intentionally has no reset (CLAUDE 5.2).
    input wire clk_i,
    // Four asynchronous read ports.
    input wire [19:0] read_addr0_i,
    output wire [31:0] read_data0_o,
    input wire [19:0] read_addr1_i,
    output wire [31:0] read_data1_o,
    input wire [19:0] read_addr2_i,
    output wire [31:0] read_data2_o,
    input wire [19:0] read_addr3_i,
    output wire [31:0] read_data3_o,
    // Ordered writeback ports: port 1 is younger.
    input wire write_valid0_i,
    input wire [4:0] write_addr0_i,
    input wire [31:0] write_data0_i,
    input wire write_valid1_i,
    input wire [4:0] write_addr1_i,
    input wire [31:0] write_data1_i
);
    reg [31:0] registers_r [1:31];
    always @(posedge clk_i) begin
        if (write_valid0_i && write_addr0_i != 0)
            registers_r[write_addr0_i] <= write_data0_i;
        if (write_valid1_i && write_addr1_i != 0)
            registers_r[write_addr1_i] <= write_data1_i;
    end
    // IB supplies equivalent address copies from the same queue edge.
    // Keep each asynchronous read mux and its write-through selection within eight data bits.
    genvar read_slice;
    generate
        for (read_slice = 0; read_slice < 4;
            read_slice = read_slice + 1) begin : g_read_slice
            wire [4:0] addr0_w;
            assign addr0_w = read_addr0_i[read_slice*5 +: 5];
            assign read_data0_o[read_slice*8 +: 8] = addr0_w == 0 ? 8'b0 :
                (write_valid1_i && write_addr1_i == addr0_w) ?
                    write_data1_i[read_slice*8 +: 8] :
                (write_valid0_i && write_addr0_i == addr0_w) ?
                    write_data0_i[read_slice*8 +: 8] :
                registers_r[addr0_w][read_slice*8 +: 8];
            wire [4:0] addr1_w;
            assign addr1_w = read_addr1_i[read_slice*5 +: 5];
            assign read_data1_o[read_slice*8 +: 8] = addr1_w == 0 ? 8'b0 :
                (write_valid1_i && write_addr1_i == addr1_w) ?
                    write_data1_i[read_slice*8 +: 8] :
                (write_valid0_i && write_addr0_i == addr1_w) ?
                    write_data0_i[read_slice*8 +: 8] :
                registers_r[addr1_w][read_slice*8 +: 8];
            wire [4:0] addr2_w;
            assign addr2_w = read_addr2_i[read_slice*5 +: 5];
            assign read_data2_o[read_slice*8 +: 8] = addr2_w == 0 ? 8'b0 :
                (write_valid1_i && write_addr1_i == addr2_w) ?
                    write_data1_i[read_slice*8 +: 8] :
                (write_valid0_i && write_addr0_i == addr2_w) ?
                    write_data0_i[read_slice*8 +: 8] :
                registers_r[addr2_w][read_slice*8 +: 8];
            wire [4:0] addr3_w;
            assign addr3_w = read_addr3_i[read_slice*5 +: 5];
            assign read_data3_o[read_slice*8 +: 8] = addr3_w == 0 ? 8'b0 :
                (write_valid1_i && write_addr1_i == addr3_w) ?
                    write_data1_i[read_slice*8 +: 8] :
                (write_valid0_i && write_addr0_i == addr3_w) ?
                    write_data0_i[read_slice*8 +: 8] :
                registers_r[addr3_w][read_slice*8 +: 8];
        end
    endgenerate
endmodule
