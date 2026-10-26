// File: ddr3_axi256_model.sv
// Spec: mem-subsys-testplan 2.3; SoC 3.2.
// Description: Ordered eight-command DDR model with bank rows, refresh and shared data bus.
// Clock domain: clk_mem. Response channels have no READY signals.
`timescale 1ns/1ps
module ddr3_axi256_model (
    input logic clk_i,
    input logic rst_n_i,
    input logic [3:0] awid_i,
    input logic [31:0] awaddr_i,
    input logic [3:0] awlen_i,
    input logic awvalid_i,
    output logic awready_o,
    input logic [255:0] wdata_i,
    input logic [31:0] wstrb_i,
    input logic wlast_i,
    input logic wvalid_i,
    output logic wready_o,
    output logic [3:0] bid_o,
    output logic [1:0] bresp_o,
    output logic bvalid_o,
    input logic [3:0] arid_i,
    input logic [31:0] araddr_i,
    input logic [3:0] arlen_i,
    input logic arvalid_i,
    output logic arready_o,
    output logic [3:0] rid_o,
    output logic [255:0] rdata_o,
    output logic [1:0] rresp_o,
    output logic rlast_o,
    output logic rvalid_o
);
    typedef struct packed {
        bit write;
        bit [3:0] id;
        bit [31:0] addr;
        int beats;
        int ready_cycle;
        bit [1:0] resp;
    } command_t;
    typedef struct packed {
        bit [255:0] data;
        bit [31:0] strb;
        bit last;
    } write_t;
    typedef struct packed {
        bit [3:0] id;
        int due;
        bit [1:0] resp;
    } response_t;
    command_t commands[$];
    write_t write_beats[$];
    response_t responses[$];
    byte unsigned memory[bit [31:0]];
    bit row_valid[8];
    bit [14:0] row[8];
    int t_hit = 8;
    int t_miss = 4;
    int t_turn = 3;
    int t_refi = 975;
    int t_rfc = 38;
    int t_b = 2;
    int cycle;
    int refresh_left;
    int refresh_next;
    int beat;
    int data_end;
    bit direction_valid;
    bit direction_write;
    int accepted;
    int row_hits;
    int row_misses;
    int turns;
    int refreshes;
    int read_data_beats;
    int write_data_beats;
    // Test-controlled response errors exercise transparent SLVERR/DECERR routing.
    bit [1:0] read_response = 0;
    bit [1:0] write_response = 0;

    initial begin
        void'($value$plusargs("T_HIT=%d", t_hit));
        void'($value$plusargs("T_MISS=%d", t_miss));
        void'($value$plusargs("T_TURN=%d", t_turn));
        void'($value$plusargs("T_REFI=%d", t_refi));
        void'($value$plusargs("T_RFC=%d", t_rfc));
        void'($value$plusargs("T_B=%d", t_b));
    end

    function automatic byte unsigned peek(input bit [31:0] addr);
        if (memory.exists(addr) != 0) return memory[addr];
        return 0;
    endfunction

    task automatic poke(input bit [31:0] addr,
        input byte unsigned value);
        memory[addr] = value;
    endtask

    task automatic enqueue(input bit write,
        input bit [3:0] id,
                           input bit [31:0] addr,
        input bit [3:0] len);
        command_t cmd;
        int bank;
        bank = int'(addr[14:12]);
        cmd.write = write;
        cmd.id = id;
        cmd.addr = addr;
        cmd.beats = int'(len)+1;
        cmd.ready_cycle = cycle + t_hit - 1;
        cmd.resp = write ? write_response : read_response;
        if (!row_valid[bank] || row[bank] != addr[29:15]) begin
            cmd.ready_cycle += t_miss;
            row_misses++;
        end else row_hits++;
        row_valid[bank] = 1;
        row[bank] = addr[29:15];
        commands.push_back(cmd);
        accepted++;
    endtask

    // AW wins simultaneous arrival, and AR consumes only the remaining queue slot.
    always_comb begin
        awready_o = rst_n_i && commands.size() + responses.size() < 8;
        arready_o = rst_n_i && commands.size() + responses.size() +
                    int'(awvalid_i && awready_o) < 8;
        wready_o = rst_n_i && write_beats.size() < 128;
    end

    always @(posedge clk_i) begin : execute
        command_t cmd;
        write_t wb;
        response_t rsp;
        bit [255:0] data;
        bit can_start;
        if (!rst_n_i) begin
            commands.delete();
            write_beats.delete();
            responses.delete();
            for (int b = 0; b < 8; b++) row_valid[b] = 0;
            cycle = 0;
            refresh_left = 0;
            refresh_next = t_refi;
            beat = 0;
            data_end = 0;
            direction_valid = 0;
            bvalid_o <= 0;
            bid_o <= 0;
            bresp_o <= 0;
            rvalid_o <= 0;
            rid_o <= 0;
            rdata_o <= 0;
            rresp_o <= 0;
            rlast_o <= 0;
            accepted = 0;
            row_hits = 0;
            row_misses = 0;
            turns = 0;
            refreshes = 0;
            read_data_beats = 0;
            write_data_beats = 0;
        end else begin
            cycle++;
            bvalid_o <= 0;
            rvalid_o <= 0;
            rlast_o <= 0;
            if (responses.size() != 0 && responses[0].due <= cycle) begin
                rsp = responses.pop_front();
                bid_o <= rsp.id;
                bresp_o <= rsp.resp;
                bvalid_o <= 1;
            end
            if (cycle == refresh_next) begin
                refresh_left = t_rfc;
                refresh_next += t_refi;
                refreshes++;
                for (int b = 0; b < 8; b++) row_valid[b] = 0;
            end
            if (commands.size() != 0 && refresh_left == 0) begin
                cmd = commands[0];
                can_start = cycle >= cmd.ready_cycle;
                if (beat == 0 && direction_valid && direction_write != cmd.write)
                    can_start &= cycle > data_end + t_turn;
                if (can_start && (!cmd.write || write_beats.size() != 0)) begin
                    if (beat == 0 && direction_valid && direction_write != cmd.write)
                        turns++;
                    direction_valid = 1;
                    direction_write = cmd.write;
                    if (cmd.write) begin
                        wb = write_beats.pop_front();
                        if (wb.last != (beat == cmd.beats-1))
                            $fatal(1, "FAIL DDR WLAST expected=%0b actual=%0b time=%0t",
                                   beat == cmd.beats-1, wb.last, $time);
                        for (int b = 0; b < 32; b++)
                            if (wb.strb[b]) memory[cmd.addr+32'(beat*32+b)] = wb.data[b*8 +: 8];
                        write_data_beats++;
                    end else begin
                        for (int b = 0; b < 32; b++)
                            data[b*8 +: 8] = peek(cmd.addr+32'(beat*32+b));
                        rid_o <= cmd.id;
                        rdata_o <= data;
                        rresp_o <= cmd.resp;
                        rlast_o <= beat == cmd.beats-1;
                        rvalid_o <= 1;
                        read_data_beats++;
                    end
                    data_end = cycle;
                    if (beat == cmd.beats-1) begin
                        if (cmd.write) begin
                            rsp.id = cmd.id;
                            rsp.due = cycle+t_b-1;
                            rsp.resp = cmd.resp;
                            responses.push_back(rsp);
                        end
                        cmd = commands.pop_front();
                        beat = 0;
                    end else beat++;
                end
            end
            if (refresh_left != 0) refresh_left--;
            if (awvalid_i && awready_o) enqueue(1, awid_i, awaddr_i, awlen_i);
            if (arvalid_i && arready_o) enqueue(0, arid_i, araddr_i, arlen_i);
            if (wvalid_i && wready_o) begin
                wb.data = wdata_i;
                wb.strb = wstrb_i;
                wb.last = wlast_i;
                write_beats.push_back(wb);
            end
        end
    end
endmodule
