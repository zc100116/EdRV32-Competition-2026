// File: edrv32_mem_write_scoreboard.sv
// Spec: mem-subsys-testplan 2.2/4; SoC 4.2 write routing and byte enables.
// Description: Compare source write intent with DDR writes before reference storage commits.
// Clock domain: clk_mem. Gateway conversion is checked by gateway_observation.svh.
`timescale 1ns/1ps
module edrv32_mem_write_scoreboard (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if masters[7],
    edrv32_axi256_if pmon,
    edrv32_axi256_if downstream
);
    typedef struct packed {
        bit id;
        bit [31:0] addr;
        int beats;
    } address_t;
    typedef struct packed {
        bit [255:0] data;
        bit [31:0] strb;
    } beat_t;
    typedef struct packed {
        address_t address;
        bit gateway;
        bit [15:0][255:0] data;
        bit [15:0][31:0] strb;
    } write_t;
    address_t addresses[8][$];
    beat_t data[8][$];
    write_t completed[8][$];
    write_t granted[$];
    int current_beat;
    bit [7:0] aw_take;
    bit [7:0] w_take;
    bit [7:0] aw_id;
    bit [255:0] aw_addr;
    bit [31:0] aw_len;
    bit [2047:0] w_data;
    bit [255:0] w_strb;
    for (genvar p = 0; p < 7; p++) begin : g_source
        assign aw_take[p] = masters[p].awvalid && masters[p].awready;
        assign w_take[p] = masters[p].wvalid && masters[p].wready;
        assign aw_id[p] = masters[p].awid;
        assign aw_addr[p*32 +: 32] = masters[p].awaddr;
        assign aw_len[p*4 +: 4] = masters[p].awlen;
        assign w_data[p*256 +: 256] = masters[p].wdata;
        assign w_strb[p*32 +: 32] = masters[p].wstrb;
    end
    assign aw_take[7] = pmon.awvalid && pmon.awready;
    assign w_take[7] = pmon.wvalid && pmon.wready;
    assign aw_id[7] = pmon.awid;
    assign aw_addr[224 +: 32] = pmon.awaddr;
    assign aw_len[28 +: 4] = pmon.awlen;
    assign w_data[1792 +: 256] = pmon.wdata;
    assign w_strb[224 +: 32] = pmon.wstrb;

    always @(posedge clk_i) begin : compare_write_intent
        address_t address;
        beat_t source_beat;
        write_t transaction;
        int port;
        int source;
        if (!rst_n_i) begin
            for (int p = 0; p < 8; p++) begin
                addresses[p].delete();
                data[p].delete();
                completed[p].delete();
            end
            granted.delete();
            current_beat = 0;
        end else begin
            for (int p = 0; p < 8; p++) begin
                if (aw_take[p]) begin
                    address.addr = aw_addr[p*32 +: 32];
                    address.beats = int'(aw_len[p*4 +: 4])+1;
                    address.id = aw_id[p];
                    addresses[p].push_back(address);
                end
                if (w_take[p]) begin
                    source_beat.data = w_data[p*256 +: 256];
                    source_beat.strb = w_strb[p*32 +: 32];
                    data[p].push_back(source_beat);
                end
                while (addresses[p].size() != 0 && data[p].size() >= addresses[p][0].beats) begin
                    address = addresses[p].pop_front();
                    transaction = '0;
                    transaction.address = address;
                    for (int n = 0; n < address.beats; n++) begin
                        source_beat = data[p].pop_front();
                        transaction.data[n] = source_beat.data;
                        transaction.strb[n] = source_beat.strb;
                    end
                    // MX-09 illegal transactions must be consumed locally, never forwarded.
                    if (address.addr[4:0] == 0 &&
                        int'(address.addr[11:0])+address.beats*32 <= 4096)
                        completed[p].push_back(transaction);
                end
            end
            if (downstream.awvalid && downstream.awready) begin
                port = int'(downstream.awid)>>1;
                if (port == 2) begin
                    transaction = '0;
                    transaction.gateway = 1;
                    transaction.address.beats = int'(downstream.awlen)+1;
                end
                else begin
                    source = port == 6 && !downstream.awid[0] ? 7 : port;
                    if (completed[source].size() == 0)
                        $fatal(1, "FAIL write intent expected=source%0d actual=none time=%0t",
                               source, $time);
                    transaction = completed[source].pop_front();
                    if (transaction.address.addr != downstream.awaddr ||
                        transaction.address.beats != int'(downstream.awlen)+1 ||
                        transaction.address.id != downstream.awid[0])
                        $fatal(1, "FAIL AW expected=%h/%0d/%0b actual=%h/%0d/%0b time=%0t",
                               transaction.address.addr, transaction.address.beats,
                               transaction.address.id, downstream.awaddr,
                               int'(downstream.awlen)+1, downstream.awid[0], $time);
                end
                granted.push_back(transaction);
            end
            if (downstream.wvalid && downstream.wready) begin
                transaction = granted[0];
                if (!transaction.gateway) begin
                    if (transaction.strb[current_beat] !== downstream.wstrb)
                        $fatal(1, "FAIL write strobe expected=%h actual=%h time=%0t",
                               transaction.strb[current_beat], downstream.wstrb, $time);
                    for (int b = 0; b < 32; b++)
                        if (transaction.strb[current_beat][b] &&
                            transaction.data[current_beat][b*8 +: 8] !==
                            downstream.wdata[b*8 +: 8])
                            $fatal(1, "FAIL write data expected=%h actual=%h byte=%0d time=%0t",
                                   transaction.data[current_beat], downstream.wdata, b, $time);
                end
                current_beat++;
                if (current_beat == transaction.address.beats) begin
                    transaction = granted.pop_front();
                    current_beat = 0;
                end
            end
        end
    end
endmodule
