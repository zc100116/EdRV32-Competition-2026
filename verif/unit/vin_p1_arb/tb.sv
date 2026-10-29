// File: tb.sv
// Spec: vin 2.9; SoC 4.2.
// Description: Independent burst ownership oracle checks whole-burst admission and B order.
// Clock domain: clk_mem.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit [95:0] ch_addr;
    bit [11:0] ch_len;
    bit [2:0] ch_valid;
    wire [2:0] ch_ready;
    bit [767:0] ch_data;
    bit [95:0] ch_strb = '1;
    bit [2:0] ch_last;
    bit [2:0] ch_wvalid;
    wire [2:0] ch_wready;
    wire [5:0] ch_resp;
    wire [2:0] ch_bvalid;
    bit [29:0] count;
    wire id;
    wire [31:0] addr;
    wire [3:0] len;
    wire valid;
    bit ready;
    wire [255:0] data;
    wire [31:0] strb;
    wire last;
    wire wvalid;
    bit wready;
    bit bvalid;
    wire bready;
    int issued[3];
    int position[3];
    bit active[3];
    int cycle;
    int received;
    int completed;
    int write_owner = -1;
    int write_left;
    int write_position;
    int write_serial;
    int response_owners[$];
    bit stalled;
    bit [35:0] saved_address;
    int previous_owner = -1;
    edrv32_vin_p1_arb u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ch_awaddr_i(ch_addr),
        .ch_awlen_i(ch_len),
        .ch_awvalid_i(ch_valid),
        .ch_awready_o(ch_ready),
        .ch_wdata_i(ch_data),
        .ch_wstrb_i(ch_strb),
        .ch_wlast_i(ch_last),
        .ch_wvalid_i(ch_wvalid),
        .ch_wready_o(ch_wready),
        .ch_bresp_o(ch_resp),
        .ch_bvalid_o(ch_bvalid),
        .ch_bready_i(3'b111),
        .ch_count_i(count),
        .ch_abort_i(3'b000),
        .p1_awid_o(id),
        .p1_awaddr_o(addr),
        .p1_awlen_o(len),
        .p1_awvalid_o(valid),
        .p1_awready_i(ready),
        .p1_wdata_o(data),
        .p1_wstrb_o(strb),
        .p1_wlast_o(last),
        .p1_wvalid_o(wvalid),
        .p1_wready_i(wready),
        .p1_bid_i(1'b0),
        .p1_bresp_i(2'b10),
        .p1_bvalid_i(bvalid),
        .p1_bready_o(bready)
    );
    function automatic bit [31:0] pattern(input int owner, input int serial, input int p);
        return 32'habcd0000 | (32'(owner) << 12) | (32'(serial) << 4) | 32'(p);
    endfunction
    always @(negedge clk) begin
        cycle++;
        ready = cycle % 5 != 0 && cycle > 8;
        wready = cycle % 7 != 0 && cycle % 7 != 1;
        bvalid = response_owners.size() != 0 && cycle % 4 != 0;
        for (int c = 0; c < 3; c++) begin
            ch_valid[c] = !active[c] && issued[c] < 16;
            ch_len[c*4 +: 4] = 4'(issued[c] % 16);
            ch_addr[c*32 +: 32] = 32'(c*65536 + issued[c]*512);
            count[c*10 +: 10] = c == 0 && cycle < 30 ? 10'd0 : 10'd16;
            ch_data[c*256 +: 256] = {8{pattern(c, issued[c], position[c])}};
            ch_last[c] = position[c] == issued[c] % 16;
        end
    end
    // W is permitted in the AW handshake cycle, so use the committed grant combinationally.
    always @(*) begin
        for (int c = 0; c < 3; c++) begin
            ch_wvalid[c] = active[c] || (ch_valid[c] && ch_ready[c]);
        end
    end
    always @(posedge clk) begin
        int owner;
        int expected_owner;
        if (rst_n) begin
            if (stalled && (!valid || {addr, len} !== saved_address))
                $fatal(1, "FAIL stalled AW changed t=%0t", $time);
            stalled = valid && !ready;
            saved_address = {addr, len};
            if (valid && ready) begin
                owner = int'(addr[17:16]);
                if (write_owner != -1) $fatal(1, "FAIL AW interleaves unfinished W");
                if (count[owner*10 +: 10] < {6'd0, len} + 10'd1)
                    $fatal(1, "FAIL AW without complete burst");
                if (cycle > 30 && issued[0] < 16 && issued[1] < 16 &&
                    previous_owner == owner)
                    $fatal(1, "FAIL round robin repeated owner %0d", owner);
                previous_owner = owner;
                write_owner = owner;
                write_left = int'(len) + 1;
                write_position = 0;
                write_serial = issued[owner];
                active[owner] = 1;
                received++;
                if (id) $fatal(1, "FAIL nonzero P1 ID");
            end
            if (wvalid && wready) begin
                if (write_owner == -1) $fatal(1, "FAIL W before AW");
                if (data !== {8{pattern(write_owner, write_serial, write_position)}} ||
                    strb !== 32'hffffffff || last !== (write_left == 1))
                    $fatal(1, "FAIL W owner=%0d serial=%0d beat=%0d data=%h",
                        write_owner, write_serial, write_position, data[31:0]);
                position[write_owner]++;
                write_position++;
                write_left--;
                if (write_left == 0) begin
                    response_owners.push_back(write_owner);
                    active[write_owner] = 0;
                    position[write_owner] = 0;
                    issued[write_owner]++;
                    write_owner = -1;
                end
            end
            if (bvalid && bready) begin
                if (response_owners.size() == 0) $fatal(1, "FAIL unexpected B");
                expected_owner = response_owners.pop_front();
                if (ch_bvalid !== (3'b001 << expected_owner) ||
                    ch_resp[expected_owner*2 +: 2] !== 2'b10)
                    $fatal(1, "FAIL B owner wanted=%0d actual=%b", expected_owner, ch_bvalid);
                completed++;
            end
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (completed == 48);
        @(negedge clk);
        if (received != 48 || write_owner != -1 || response_owners.size() != 0)
            $fatal(1, "FAIL burst accounting");
        $display("PASS vin_p1_arb");
        $finish;
    end
    initial begin #1000000; $fatal(1, "FAIL timeout"); end
endmodule
