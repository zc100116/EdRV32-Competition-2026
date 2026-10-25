// File: edrv32_cpu_regfile.v
// Spec: cpu-spec 4.2, 4.3
// Description: Store the architectural integer registers with four reads and two writes.
// Forward current writes to reads and give the younger write port priority.
// Clock domain: clk_sys.
module edrv32_cpu_regfile (
    // Clock; data array intentionally has no reset (CLAUDE 5.2).
    input wire clk_i,
    // Four asynchronous read ports.
    input wire [4:0] read_addr0_i,
    output wire [31:0] read_data0_o,
    input wire [4:0] read_addr1_i,
    output wire [31:0] read_data1_o,
    input wire [4:0] read_addr2_i,
    output wire [31:0] read_data2_o,
    input wire [4:0] read_addr3_i,
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
    assign read_data0_o = read_addr0_i == 0 ? 32'b0 :
        (write_valid1_i && write_addr1_i == read_addr0_i) ? write_data1_i :
        (write_valid0_i && write_addr0_i == read_addr0_i) ? write_data0_i :
        registers_r[read_addr0_i];
    assign read_data1_o = read_addr1_i == 0 ? 32'b0 :
        (write_valid1_i && write_addr1_i == read_addr1_i) ? write_data1_i :
        (write_valid0_i && write_addr0_i == read_addr1_i) ? write_data0_i :
        registers_r[read_addr1_i];
    assign read_data2_o = read_addr2_i == 0 ? 32'b0 :
        (write_valid1_i && write_addr1_i == read_addr2_i) ? write_data1_i :
        (write_valid0_i && write_addr0_i == read_addr2_i) ? write_data0_i :
        registers_r[read_addr2_i];
    assign read_data3_o = read_addr3_i == 0 ? 32'b0 :
        (write_valid1_i && write_addr1_i == read_addr3_i) ? write_data1_i :
        (write_valid0_i && write_addr0_i == read_addr3_i) ? write_data0_i :
        registers_r[read_addr3_i];
endmodule
