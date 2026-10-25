// File: edrv32_apb_memory.sv
// Spec: sys-subsys-testplan 2.1, AB-01/04/05/06.
// Description: Slot memories, programmable ready delay, error and timeout injection.
// Clock domain: clk_mem (or clk_sys for CACHE_CTRL model).
module edrv32_apb_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_apb_if bus
);
    bit [15:0] used_slots = 16'h03ff;
    int delay_cycles = 0;
    bit inject_error = 0;
    bit never_ready = 0;
    bit [31:0] memory[16][1024];
    int access_cycles;
    int transfers;
    int writes;
    int reads;
    bit [15:0] unused_last_select;
    bit [11:0] unused_last_addr;
    bit [31:0] last_data;
    bit [3:0] last_strb;
    always_comb begin
        bus.pready = 0;
        bus.pslverr = 0;
        bus.prdata = 0;
        for (int s = 0; s < 16; s++) begin
            bus.prdata[s*32 +: 32] = memory[s][bus.paddr[11:2]];
            bus.pready[s] = !used_slots[s] ||
                            (!never_ready && access_cycles >= delay_cycles);
            bus.pslverr[s] = !used_slots[s] || inject_error;
        end
    end
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            access_cycles <= 0;
            transfers <= 0;
            writes <= 0;
            reads <= 0;
        end else begin
            if (!bus.penable) access_cycles <= 0;
            else access_cycles <= access_cycles + 1;
            for (int s = 0; s < 16; s++) begin
                if (used_slots[s] && bus.psel[s] && bus.penable && bus.pready[s]) begin
                    transfers <= transfers + 1;
                    unused_last_select <= bus.psel;
                    unused_last_addr <= bus.paddr;
                    last_data <= bus.pwdata;
                    last_strb <= bus.pstrb;
                    if (bus.pwrite) begin
                        writes <= writes + 1;
                        if (!bus.pslverr[s]) begin
                            for (int b = 0; b < 4; b++) begin
                                if (bus.pstrb[b])
                                    memory[s][bus.paddr[11:2]][b*8 +: 8] <=
                                        bus.pwdata[b*8 +: 8];
                            end
                        end
                    end else reads <= reads + 1;
                end
            end
        end
    end
endmodule
