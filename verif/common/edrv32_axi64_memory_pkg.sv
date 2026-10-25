// edrv32_axi64_memory_pkg.sv
// cache-spec 2.3, 5: shared physical byte memory, DDR aliases share storage.
// Clock domain: clk_sys.
package edrv32_axi64_memory_pkg;
    byte unsigned memory[bit [31:0]];
    byte unsigned reference_memory[bit [31:0]];
    bit [31:0] error_read_addr = '1;
    bit [31:0] error_write_addr = '1;
    int unsigned delay_max = 3;
    bit random_stalls = 1;

    function automatic bit [31:0] physical(bit [31:0] addr);
        return addr[31] ? {2'b10, addr[29:0]} : addr;
    endfunction

    function automatic byte unsigned initial_byte(bit [31:0] addr);
        return 8'(addr ^ (addr >> 8) ^ (addr >> 16) ^ 32'h5a);
    endfunction

    function automatic byte unsigned read_byte(bit [31:0] addr, bit architectural = 0);
        bit [31:0] p;
        p = physical(addr);
        if (architectural && reference_memory.exists(p) != 0) return reference_memory[p];
        if (!architectural && memory.exists(p) != 0) return memory[p];
        return initial_byte(p);
    endfunction

    function automatic bit [63:0] read_data(bit [31:0] addr, int bytes,
                                           bit architectural = 0);
        bit [63:0] result;
        result = 0;
        for (int i = 0; i < bytes; i++) result[i*8 +: 8] = read_byte(addr + 32'(i),
                                                                 architectural);
        return result;
    endfunction

    function automatic void bus_store(bit [31:0] addr, byte unsigned data);
        // Behavioral shared memory updates atomically at the accepted W beat.
        /* verilator lint_off BLKSEQ */
        memory[physical(addr)] = data;
        /* verilator lint_on BLKSEQ */
    endfunction

    function automatic void commit_store(bit [31:0] addr, bit [31:0] data, int size);
        for (int i = 0; i < (1 << size); i++)
            reference_memory[physical(addr + 32'(i))] = data[i*8 +: 8];
    endfunction
endpackage
