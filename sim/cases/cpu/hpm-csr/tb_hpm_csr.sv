`timescale 1ns/1ps
`include "edrv32_csr.vh"
`include "edrv32_hpm.vh"

module tb_hpm_csr #(parameter DUAL_ISSUE=0);
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg [11:0] read_addr = 12'd0;
    reg read_access = 1'b0;
    reg write_intent = 1'b0;
    wire [31:0] read_data;
    wire access_illegal;
    reg write_fire = 1'b0;
    reg [11:0] write_addr = 12'd0;
    reg [31:0] write_data = 32'd0;
    reg retire = 1'b0;
    reg retire_second = 1'b0;
    reg [`EDRV32_HPM_EVENT_W-1:0] second_events=0;
    reg [`EDRV32_HPM_EVENT_W-1:0] events = {`EDRV32_HPM_EVENT_W{1'b0}};

    edrv32_csr_file #(.CPU_HPM_ENABLE(1),.DUAL_ISSUE(DUAL_ISSUE)) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .read_addr_i(read_addr), .read_access_i(read_access),
        .write_intent_i(write_intent), .read_data_o(read_data),
        .access_illegal_o(access_illegal),
        .write_fire_i(write_fire), .write_addr_i(write_addr),
        .write_data_i(write_data), .retire_i(retire), .retire_second_i(retire_second),
        .trap_enter_i(1'b0), .trap_epc_i(32'd0),
        .trap_cause_i(32'd0), .trap_tval_i(32'd0), .mret_fire_i(1'b0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0), .hpm_events_i(events), .hpm_second_events_i(second_events),
        .mtvec_o(), .mepc_o(), .mie_o(), .mip_o(), .mstatus_mie_o()
    );

    task csr_write;
        input [11:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            write_addr = address;
            write_data = value;
            // HPM commands are decoded during the CSR validation cycle.
            @(posedge clk);
            @(negedge clk);
            write_fire = 1'b1;
            @(negedge clk);
            write_fire = 1'b0;
        end
    endtask

    task pulse_event;
        input integer event_index;
        begin
            @(negedge clk);
            events[event_index] = 1'b1;
            @(negedge clk);
            events[event_index] = 1'b0;
            // The HPM black box registers platform events before applying the
            // programmable selector.  Wait for the sampled pulse to retire.
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task expect_csr;
        input [11:0] address;
        input [31:0] expected;
        begin
            read_addr = address;
            #1;
            if (read_data !== expected)
                $fatal(1, "CSR %03x expected %08x got %08x",
                       address, expected, read_data);
        end
    endtask

    task expect_counter_low;
        input integer counter_index;
        input [31:0] expected;
        reg [11:0] address;
        begin
            address = (counter_index < 29)
                ? (12'hb03 + counter_index)
                : (12'h7c0 + counter_index - 29);
            expect_csr(address, expected);
        end
    endtask

    reg [31:0] frozen_cycle;
    integer event_counter;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        expect_csr(12'h323, 32'd1);
        expect_csr(12'h33f, 32'd29);
        expect_csr(12'h7e0, 32'd30);
        expect_csr(12'h7ea, 32'd40);

        // Every reset selector maps counter N to event N+1.  Exercise all
        // four physical event-sample banks, including every bank boundary.
        for (event_counter = 0; event_counter < 40;
             event_counter = event_counter + 1)
            pulse_event(event_counter);
        for (event_counter = 0; event_counter < 40;
             event_counter = event_counter + 1)
            expect_counter_low(event_counter, 32'd1);

        csr_write(12'h320, 32'hffff_fffd);
        csr_write(12'h7f0, 32'h0000_07ff);
        read_addr = 12'hb00;
        #1 frozen_cycle = read_data;
        @(negedge clk); events[0] = 1'b1; events[39] = 1'b1; retire = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk); events = {`EDRV32_HPM_EVENT_W{1'b0}}; retire = 1'b0;
        expect_csr(12'hb00, frozen_cycle);
        expect_csr(12'hb03, 32'd1);
        expect_csr(12'h7ca, 32'd1);

        // Remap standard counter 3 to event 40, then verify zero disables it.
        csr_write(12'h323, 32'd40);
        csr_write(12'hb03, 32'd0);
        csr_write(12'h320, 32'd0);
        csr_write(12'h7f0, 32'd0);
        pulse_event(39);
        expect_csr(12'hb03, 32'd1);
        csr_write(12'h323, 32'd0);
        pulse_event(39);
        expect_csr(12'hb03, 32'd1);

        // Unsupported selectors are WARL-coerced to event zero.
        csr_write(12'h323, 32'd99);
        expect_csr(12'h323, 32'd0);

        // The 7-bit selector field admits the extended attribution events.
        csr_write(12'h323, 32'd41);
        csr_write(12'hb03, 32'd0);
        pulse_event(40);
        expect_csr(12'hb03, 32'd1);
        csr_write(12'h323, 32'd83);
        csr_write(12'hb03, 32'd0);
        pulse_event(82);
        expect_csr(12'hb03, 32'd1);
        csr_write(12'h323, 32'd98);
        csr_write(12'hb03, 32'd0);
        pulse_event(97);
        expect_csr(12'hb03, 32'd1);
        csr_write(12'h323, 32'd0);

        // An event sampled on the same edge as a selector write retains the
        // old selector.  The write only affects events sampled afterwards.
        csr_write(12'h323, 32'd1);
        csr_write(12'hb03, 32'd0);
        repeat (2) @(posedge clk);
        @(negedge clk);
        write_addr = 12'h323;
        write_data = 32'd40;
        @(posedge clk);
        @(negedge clk);
        events[0] = 1'b1;
        write_fire = 1'b1;
        @(negedge clk);
        events[0] = 1'b0;
        write_fire = 1'b0;
        @(posedge clk);
        @(negedge clk);
        expect_csr(12'hb03, 32'd1);
        expect_csr(12'h323, 32'd40);

        // Inhibit is sampled with the event.  Disabling on the event edge does
        // not discard that event; enabling on an event edge does not admit an
        // event that occurred while the counter was still inhibited.
        csr_write(12'h323, 32'd1);
        csr_write(12'hb03, 32'd0);
        csr_write(12'h320, 32'd0);
        repeat (2) @(posedge clk);
        @(negedge clk);
        events[0] = 1'b1;
        write_addr = 12'h320;
        write_data = 32'h0000_0008;
        write_fire = 1'b1;
        @(negedge clk);
        events[0] = 1'b0;
        write_fire = 1'b0;
        @(posedge clk);
        @(negedge clk);
        expect_csr(12'hb03, 32'd1);

        @(negedge clk);
        events[0] = 1'b1;
        write_addr = 12'h320;
        write_data = 32'd0;
        write_fire = 1'b1;
        @(negedge clk);
        events[0] = 1'b0;
        write_fire = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        expect_csr(12'hb03, 32'd1);

        if(DUAL_ISSUE!=0)begin
            // Exercise +2 carries in all four physical sample banks.
            csr_write(12'h320,32'd0);csr_write(12'h7f0,32'd0);
            for(event_counter=0;event_counter<40;event_counter=event_counter+1)begin
                if(event_counter<29)begin
                    csr_write(12'h323+event_counter,event_counter+1);
                    csr_write(12'hb83+event_counter,32'd7);
                    csr_write(12'hb03+event_counter,32'hfffffffe);
                end else begin
                    csr_write(12'h7e0+(event_counter-29),event_counter+1);
                    csr_write(`EDRV32_CSR_MHPMEXTRAH_FIRST+(event_counter-29),32'd7);
                    csr_write(12'h7c0+(event_counter-29),32'hfffffffe);
                end
                @(negedge clk);events[event_counter]=1;second_events[event_counter]=1;
                @(negedge clk);events=0;second_events=0;
                repeat(2)@(negedge clk);
                expect_counter_low(event_counter,32'd0);
                if(event_counter<29)expect_csr(12'hb83+event_counter,32'd8);
                else expect_csr(`EDRV32_CSR_MHPMEXTRAH_FIRST+(event_counter-29),32'd8);
                // +1 with only a B event also counts once.
                @(negedge clk);second_events[event_counter]=1;
                @(negedge clk);second_events=0;
                repeat(2)@(negedge clk);expect_counter_low(event_counter,32'd1);
            end
            csr_write(12'hb82,32'd3);csr_write(12'hb02,32'hfffffffe);
            @(negedge clk);retire=1;retire_second=1;
            @(negedge clk);retire=0;retire_second=0;
            expect_csr(12'hb02,32'd0);expect_csr(12'hb82,32'd4);
            csr_write(12'h320,32'hfffffffd);csr_write(12'h7f0,32'h7ff);
            @(negedge clk);events={98{1'b1}};second_events={98{1'b1}};retire=1;retire_second=1;
            repeat(3)@(negedge clk);
            events=0;second_events=0;retire=0;retire_second=0;
            repeat(2)@(negedge clk);
            expect_csr(12'hb02,32'd0);expect_csr(12'hb82,32'd4);
            for(event_counter=0;event_counter<40;event_counter=event_counter+1)
                expect_counter_low(event_counter,32'd1);
        end

        $display("PASS: 98-event HPM CSR bank, 7-bit selectors, banked events and inhibit control");
        $finish;
    end
endmodule
