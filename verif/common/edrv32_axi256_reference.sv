// File: edrv32_axi256_reference.sv
// Spec: mem-subsys-testplan 4.
// Description: Independent sparse byte storage: commit writes in B order, compare every R beat.
// Clock domain: clk_mem; observes the no-backpressure DDR interface.
`timescale 1ns/1ps
module edrv32_axi256_reference #(
    parameter bit DOWNSTREAM = 1
) (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus,
    output int checked_beats_o,
    output int committed_writes_o
);
    typedef struct packed {
        bit [31:0] addr;
        int len;
        bit [3:0] id;
    } address_t;
    typedef struct packed {
        bit [255:0] data;
        bit [31:0] strb;
    } beat_t;
    typedef struct packed {
        bit [31:0] addr;
        int len;
        bit [15:0][255:0] data;
        bit [15:0][31:0] strb;
    } write_t;
    byte unsigned memory[bit [31:0]];
    address_t aw[$];
    address_t ar[16][$];
    beat_t w[$];
    write_t pending[16][$];
    int r_beat[16];

    task automatic poke(input bit [31:0] addr,
        input byte unsigned value);
        memory[addr] = value;
    endtask

    function automatic byte unsigned peek(input bit [31:0] addr);
        if (memory.exists(addr) != 0) return memory[addr];
        return 0;
    endfunction

    always @(posedge clk_i) begin : observe
        address_t a;
        beat_t wb;
        write_t transaction;
        bit [31:0] addr;
        bit [255:0] expected;
        int id;
        if (!rst_n_i) begin
            aw.delete();
            w.delete();
            for (int p = 0; p < 16; p++) begin
                ar[p].delete();
                pending[p].delete();
                r_beat[p] = 0;
            end
            checked_beats_o = 0;
            committed_writes_o = 0;
        end else begin
            if (bus.awvalid && bus.awready) begin
                a.addr = bus.awaddr;
                a.len = int'(bus.awlen);
                a.id = 4'(bus.awid);
                aw.push_back(a);
            end
            if (bus.wvalid && bus.wready) begin
                wb.data = bus.wdata;
                wb.strb = bus.wstrb;
                w.push_back(wb);
            end
            while (aw.size() != 0 && w.size() >= aw[0].len+1) begin
                a = aw.pop_front();
                transaction = '0;
                transaction.addr = a.addr;
                transaction.len = a.len;
                for (int n = 0; n <= a.len; n++) begin
                    wb = w.pop_front();
                    transaction.data[n] = wb.data;
                    transaction.strb[n] = wb.strb;
                end
                pending[int'(a.id)].push_back(transaction);
            end
            if (bus.bvalid && (DOWNSTREAM || bus.bready)) begin
                id = int'(bus.bid);
                if (pending[id].size() == 0)
                    $fatal(1, "FAIL reference B expected=pending write actual=none time=%0t",
                           $time);
                transaction = pending[id].pop_front();
                if (bus.bresp == 0)
                    for (int n = 0; n <= transaction.len; n++)
                        for (int b = 0; b < 32; b++)
                            if (transaction.strb[n][b])
                                memory[transaction.addr+32'(32*n+b)] =
                                    transaction.data[n][b*8 +: 8];
                committed_writes_o++;
            end
            if (bus.arvalid && bus.arready) begin
                a.addr = bus.araddr;
                a.len = int'(bus.arlen);
                a.id = 4'(bus.arid);
                ar[int'(a.id)].push_back(a);
            end
            if (bus.rvalid && (DOWNSTREAM || bus.rready)) begin
                id = int'(bus.rid);
                if (ar[id].size() == 0)
                    $fatal(1, "FAIL reference R expected=pending read actual=none time=%0t", $time);
                a = ar[id][0];
                addr = a.addr+32'(r_beat[id]*32);
                for (int b = 0; b < 32; b++) expected[b*8 +: 8] = peek(addr+32'(b));
                if (bus.rresp == 0 && bus.rdata !== expected)
                    $fatal(1, "FAIL reference addr=%h expected=%h actual=%h time=%0t",
                           addr, expected, bus.rdata, $time);
                checked_beats_o++;
                if (bus.rlast) begin
                    a = ar[id].pop_front();
                    r_beat[id] = 0;
                end else r_beat[id]++;
            end
        end
    end
endmodule
