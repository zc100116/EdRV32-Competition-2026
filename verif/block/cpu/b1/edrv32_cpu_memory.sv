// File: edrv32_cpu_memory.sv
// Spec: cpu-testplan 2.3; cpu-spec 4.7
// Description: Shared sparse byte memory and device register bank for B1.
// Clock: clk_sys, accessed by the cache models at clock edges.
// Ordered model updates are immediate so later checks see this edge's transaction.
/* verilator lint_off BLKSEQ */
package edrv32_cpu_memory;
    byte unsigned memory[bit [31:0]];
    logic [31:0] device_regs[bit [31:0]];
    logic tohost_valid = 0;
    logic [31:0] tohost_value = 0;
    int device_accesses = 0;

    function automatic bit device(input logic [31:0] addr);
        return !((addr >= 32'h10000000 && addr < 32'h10040000)
            || (addr >= 32'h80000000 && addr < 32'hc0000000));
    endfunction

    function automatic logic [31:0] physical(input logic [31:0] addr);
        return addr >= 32'hc0000000 ? {2'b10, addr[29:0]} : addr;
    endfunction

    function automatic logic [31:0] read_data(input logic [31:0] addr,
                                               input logic [1:0] size);
        logic [31:0] value;
        logic [31:0] index;
        value = 0;
        for (int lane = 0; lane < (1 << size); lane++) begin
            index = physical(addr + 32'(lane));
            if (memory.exists(index) != 0)
                value[lane*8 +: 8] = memory[index];
        end
        return value;
    endfunction

    function automatic void write_data(input logic [31:0] addr,
                                        input logic [1:0] size,
                                        input logic [31:0] value);
        for (int lane = 0; lane < (1 << size); lane++)
            memory[physical(addr + 32'(lane))] = value[lane*8 +: 8];
    endfunction

    function automatic logic [31:0] access_device(input logic [31:0] addr,
                                                   input bit store,
                                                   input logic [1:0] size,
                                                   input logic [31:0] value);
        logic [31:0] result;
        logic [31:0] aligned_addr;
        int shift;
        device_accesses++;
        // Noncached DDR aliases the same flat memory, without device registers.
        if (addr < 32'h00004000 || addr >= 32'hc0000000) begin
            if (store)
                write_data(addr, size, value);
            return read_data(addr, size);
        end
        aligned_addr = {addr[31:2], 2'b00};
        result = device_regs.exists(aligned_addr) != 0 ? device_regs[aligned_addr] : 0;
        shift = int'(addr[1:0]) * 8;
        if (store) begin
            for (int lane = 0; lane < (1 << size); lane++)
                result[shift + lane*8 +: 8] = value[lane*8 +: 8];
            device_regs[aligned_addr] = result;
        end
        return (result >> shift) & (32'hffffffff >> (32 - (8 << size)));
    endfunction
endpackage

/* verilator lint_on BLKSEQ */
