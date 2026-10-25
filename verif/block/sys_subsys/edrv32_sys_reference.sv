// File: edrv32_sys_reference.sv
// Spec: sys-subsys 2.1/2.2/6; SoC 6.1; testplan 4.
// Description: Independent address/response oracle and byte-strobed reference memory.
// Clock domain: transaction-level, clk_sys.
package edrv32_sys_reference;
    // The generated map intentionally also contains constants for other clients.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    function automatic int region(
        input bit [31:0] addr
    );
        if (addr < EDRV32_ROM_BASE + EDRV32_ROM_SIZE) return 0;
        if (addr >= EDRV32_SRAM_BASE && addr - EDRV32_SRAM_BASE < EDRV32_SRAM_SIZE)
            return 1;
        if (addr >= EDRV32_CLINT_BASE && addr - EDRV32_CLINT_BASE < EDRV32_CLINT_SIZE)
            return 2;
        if (addr >= EDRV32_PLIC_BASE && addr - EDRV32_PLIC_BASE < EDRV32_PLIC_SIZE)
            return 3;
        if (addr >= EDRV32_SYS_APB_BASE && addr - EDRV32_SYS_APB_BASE < EDRV32_SYS_APB_SIZE)
            return 4;
        if (addr >= EDRV32_MEDIA_APB_BASE &&
            addr - EDRV32_MEDIA_APB_BASE < EDRV32_MEDIA_APB_SIZE) return 5;
        if (addr >= EDRV32_DDR_BASE) return 6;
        return -1;
    endfunction
    function automatic bit used_slot(
        input int target,
        input int slot
    );
        if (target == 5) return slot < 10;
        return slot == 0 || slot == 1 || slot == 4 || slot == 5 || slot == 6;
    endfunction
    function automatic bit [1:0] response(
        input int master,
        input bit wr,
        input bit [31:0] addr,
        input int size,
        input int len
    );
        int target;
        target = region(addr);
        if (target < 0 || (master == 0 && target >= 2 && target <= 5)) return 3;
        if (wr && target == 0) return 2;
        if (target >= 2 && target <= 5 && (len != 0 || size != 2)) return 2;
        if (target >= 4 && target <= 5 &&
            (addr[1:0] != 0 || !used_slot(target, int'(addr[15:12])))) return 2;
        return 0;
    endfunction
    function automatic void store(
        input bit [31:0] unused_addr,
        input bit [63:0] data,
        input bit [7:0] strb
    );
        for (int b = 0; b < 8; b++) begin
            if (strb[b])
                edrv32_axi64_memory_pkg::reference_memory[
                    edrv32_axi64_memory_pkg::physical({unused_addr[31:3], 3'b0} + 32'(b))] =
                    data[b*8 +: 8];
        end
    endfunction
endpackage
