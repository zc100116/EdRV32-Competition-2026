// cpu_csr/tb.sv
// cpu-testplan U-10; cpu-spec 2, 4, 5.
// Check CSR permissions, WARL masks, performance counters and precise trap state.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    reg access_valid_i=0;
    reg [11:0] addr_i=0;
    reg write_i=0;
    reg commit_i=1;
    reg [1:0] command_i=1;
    reg [31:0] write_data_i=0;
    wire [31:0] read_data_o;
    wire illegal_o;
    wire decode_illegal_o;
    reg decode_override_r=0;
    reg [11:0] decode_addr_r=0;
    reg [1:0] retire_count_i=0;
    reg [31:0] event_count_i=0;
    reg trap_i=0;
    reg [31:0] trap_pc_i=0;
    reg [31:0] trap_cause_i=0;
    reg [31:0] trap_value_i=0;
    reg mret_i=0;
    wire [31:0] mstatus_o;
    wire [31:0] mie_o;
    wire [31:0] mtvec_o;
    wire [31:0] mepc_o;
    reg irq_meip_i=0;
    reg irq_msip_i=0;
    reg irq_mtip_i=0;
    reg [63:0] mtime_i=64'h12345678deadbeef;
    integer i;
    integer j;
    integer k;
    integer code;
    reg exists;
    reg ro;
    reg [63:0] expected;
    reg [31:0] data;
    wire [31:0] no_c_read;
    wire no_c_illegal;
    wire [41:0] access_select_w;

    edrv32_cpu_csr dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .access_valid_i(access_valid_i),
        .select_i(access_select_w),
        .write_i(write_i),
        .commit_i(commit_i),
        .command_i(command_i),
        .write_data_i(write_data_i),
        .read_data_o(read_data_o),
        .illegal_o(illegal_o),
        .decode_valid_i(access_valid_i),
        .decode_addr_i(decode_override_r ? decode_addr_r : addr_i),
        .decode_write_i(write_i),
        .decode_illegal_o(decode_illegal_o),
        .decode_select_o(),
        .retire_count_i(retire_count_i),
        .event_count_i(event_count_i),
        .trap_i(trap_i),
        .trap_pc_i(trap_pc_i),
        .trap_cause_i(trap_cause_i),
        .trap_value_i(trap_value_i),
        .mret_i(mret_i),
        .mstatus_o(mstatus_o),
        .mie_o(mie_o),
        .mtvec_o(mtvec_o),
        .mepc_o(mepc_o),
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),
        .mtime_i(mtime_i)
    );
    // Second configuration checks misa.C and mepc alignment with C disabled.
    edrv32_cpu_csr #(.RVC_EN(0)) no_c (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .access_valid_i(access_valid_i),
        .select_i(access_select_w),
        .write_i(write_i),
        .commit_i(commit_i),
        .command_i(command_i),
        .write_data_i(write_data_i),
        .read_data_o(no_c_read),
        .illegal_o(no_c_illegal),
        .decode_valid_i(1'b0),
        .decode_addr_i(addr_i),
        .decode_write_i(1'b0),
        .decode_illegal_o(),
        .decode_select_o(access_select_w),
        .retire_count_i(retire_count_i),
        .event_count_i(event_count_i),
        .trap_i(trap_i),
        .trap_pc_i(trap_pc_i),
        .trap_cause_i(trap_cause_i),
        .trap_value_i(trap_value_i),
        .mret_i(mret_i),
        .mstatus_o(),
        .mie_o(),
        .mtvec_o(),
        .mepc_o(),
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),
        .mtime_i(mtime_i)
    );
    task automatic read_check(input reg [11:0] address,input reg [31:0] value);
        begin
            addr_i=address;access_valid_i=1;write_i=0;#1;
            if(illegal_o || read_data_o!==value)
                $fatal(1,"FAIL CSR addr=%h expected=%h actual=%h illegal=%b time=%t",
                    address,value,read_data_o,illegal_o,$time);
        end
    endtask
    task automatic csr_write(input reg [11:0] address,input reg [31:0] value);
        begin
            @(negedge clk_i);
            addr_i=address;access_valid_i=1;write_i=1;command_i=1;write_data_i=value;
            #1;if(illegal_o)$fatal(1,"FAIL unexpected illegal CSR write %h",address);
            @(posedge clk_i);#1;
            @(negedge clk_i);write_i=0;
        end
    endtask
    task automatic counter_check(input reg [11:0] address,input reg [63:0] value);
        begin
            read_check(address,value[31:0]);
            read_check(address+12'h80,value[63:32]);
            read_check(address+12'h100,value[31:0]);
            read_check(address+12'h180,value[63:32]);
        end
    endtask
    initial begin
        // Hold reset to inspect every architectural reset value before mcycle runs.
        @(negedge clk_i);
        read_check('h300,'h1800);read_check('h301,'h40001104);
        if(no_c_read!==32'h40001100)$fatal(1,"FAIL misa RVC_EN=0");
        read_check('h304,0);read_check('h305,0);read_check('h320,0);
        read_check('h340,0);read_check('h341,0);read_check('h342,0);
        read_check('h343,0);read_check('h344,0);
        read_check('hc01,32'hdeadbeef);read_check('hc81,32'h12345678);
        for(i='hf11;i<='hf14;i=i+1)read_check(12'(i),0);
        counter_check('hb00,0);counter_check('hb02,0);
        for(i=0;i<8;i=i+1)begin
            read_check(12'h323+12'(i),0);counter_check(12'hb03+12'(i),0);
        end
        @(negedge clk_i);rst_n_i=1;
        csr_write('h320,32'hffffffff);read_check('h320,'h7fd);
        // Full address-space legality, including read-only aliases and absent CSRs.
        for(i=0;i<4096;i=i+1)begin
            addr_i=12'(i);access_valid_i=1;write_i=0;
            exists=(i=='h300 || i=='h301 || i=='h304 || i=='h305 || i=='h320 || i=='h340 || i=='h341 || i=='h342 || i=='h343 || i=='h344 || i=='hb00 || i=='hb80 || i=='hb02 || i=='hb82 || i=='hc00 || i=='hc80 || i=='hc02 || i=='hc82 || i=='hc01 || i=='hc81 || i=='hf11 || i=='hf12 || i=='hf13 || i=='hf14) ||
                (i>='h323 && i<='h32a) || (i>='hb03 && i<='hb0a) ||
                (i>='hb83 && i<='hb8a) || (i>='hc03 && i<='hc0a) ||
                (i>='hc83 && i<='hc8a);
            ro=(i=='h344 || (i>='hc00 && i<='hcff) || i>='hf00);
            #1;if(illegal_o!==!exists || no_c_illegal!==!exists || decode_illegal_o!==!exists)
                $fatal(1,"FAIL CSR read legality %h",addr_i);
            // Avoid a rising edge while probing writes: no commit is intended.
            @(negedge clk_i);write_i=1;
            #1;if(illegal_o!==(!exists || ro) || decode_illegal_o!==(!exists || ro))$fatal(1,"FAIL CSR write legality %h",addr_i);
            write_i=0;
        end
        // C-F1 path 1: D permission probing cannot change the simultaneous M data access.
        @(negedge clk_i);decode_override_r=1;decode_addr_r=12'hfff;
        addr_i='h340;access_valid_i=1;write_i=1;command_i=1;write_data_i=32'h13579bdf;
        #1;if(!decode_illegal_o || illegal_o)$fatal(1,"FAIL independent D/M legality");
        @(posedge clk_i);#1;
        if(read_data_o!==32'h13579bdf)$fatal(1,"FAIL D address changed M CSR write");
        @(negedge clk_i);write_i=0;decode_addr_r=12'hb03;
        #1;if(decode_illegal_o || read_data_o!==32'h13579bdf)
            $fatal(1,"FAIL D address changed M CSR read");
        decode_override_r=0;
        csr_write('h301,0);read_check('h301,'h40001104);
        csr_write('h300,32'hffffffff);read_check('h300,'h1888);
        csr_write('h300,0);read_check('h300,'h1800);
        csr_write('h304,32'hffffffff);read_check('h304,'h888);
        csr_write('h304,0);read_check('h304,0);
        for(i=0;i<4;i=i+1)begin
            csr_write('h305,32'habcdef00|32'(i));
            read_check('h305,32'habcdef00|(i==1?1:0));
        end
        csr_write('h341,32'hffffffff);read_check('h341,32'hfffffffe);
        if(no_c_read!==32'hfffffffc)$fatal(1,"FAIL mepc RVC_EN=0");
        for(i=0;i<100;i=i+1)begin
            data=$urandom;
            csr_write('h340,data);read_check('h340,data);
            csr_write('h342,data);read_check('h342,data);
            csr_write('h343,data);read_check('h343,data);
        end
        csr_write('h340,32'h12345678);
        // D may probe access legality; only the M-stage commit may mutate the CSR.
        @(negedge clk_i);addr_i='h340;access_valid_i=1;write_i=1;
        command_i=1;write_data_i=32'hdeadbeef;commit_i=0;
        @(posedge clk_i);#1;@(negedge clk_i);write_i=0;commit_i=1;
        read_check('h340,32'h12345678);
        @(negedge clk_i);addr_i='h340;write_data_i='hff;write_i=1;command_i=2;
        @(posedge clk_i);#1;@(negedge clk_i);write_i=0;
        read_check('h340,32'h123456ff);
        @(negedge clk_i);write_data_i='hff00;write_i=1;command_i=3;
        @(posedge clk_i);#1;@(negedge clk_i);write_i=0;
        read_check('h340,32'h123400ff);
        irq_meip_i=1;irq_mtip_i=1;irq_msip_i=1;read_check('h344,'h888);
        irq_meip_i=0;irq_mtip_i=0;irq_msip_i=0;
        // All writable counter halves and RO aliases, with rollover.
        for(i=0;i<10;i=i+1)begin
            if(i!=1)begin
            csr_write(12'hb00+12'(i),32'hffffffff);
            csr_write(12'hb80+12'(i),32'h12345678);
            counter_check(12'hb00+12'(i),64'h12345678ffffffff);
        end
        end
        // Each HPM selector supports 0..31; reserved codes never count.
        for(code=0;code<32;code=code+1)begin
            for(i=0;i<8;i=i+1)begin
                csr_write(12'h323+12'(i),32'hffffffe0|32'(code));
                read_check(12'h323+12'(i),32'(code));
                csr_write(12'hb03+12'(i),32'hffffffff);
                csr_write(12'hb83+12'(i),0);
            end
            @(negedge clk_i);event_count_i=0;
            if(code>=1 && code<=16)event_count_i[(code-1)*2+:2]=code[0]?2'd1:2'd2;
            else event_count_i=32'haaaaaaaa;
            addr_i='h320;write_i=1;command_i=1;write_data_i=5;
            @(posedge clk_i);#1;@(negedge clk_i);write_i=0;
            repeat(5)@(posedge clk_i);
            @(negedge clk_i);addr_i='h320;write_i=1;write_data_i='h7fd;
            @(posedge clk_i);#1;@(negedge clk_i);write_i=0;event_count_i=0;
            expected=64'hffffffff;
            if(code>=1 && code<=16)expected=expected+(code[0]?64'd6:64'd12);
            for(i=0;i<8;i=i+1)counter_check(12'hb03+12'(i),expected);
        end
        // cpu-spec 7.1: every event pulse appears one edge later, including rollover.
        for(code=1;code<=16;code=code+1)begin
            csr_write('h323,32'(code));
            csr_write('hb03,32'hffffffff);csr_write('hb83,0);
            csr_write('h320,'h7f5);
            @(negedge clk_i);event_count_i[(code-1)*2+:2]=2'd2;
            @(posedge clk_i);#1;read_check('hb03,32'hffffffff);read_check('hb83,0);
            @(negedge clk_i);event_count_i=0;
            @(posedge clk_i);#1;counter_check('hb03,64'h100000001);
            @(posedge clk_i);#1;counter_check('hb03,64'h100000001);
            csr_write('h320,'h7fd);
        end
        // Register the whole vector: a selector write chooses from that vector next cycle.
        csr_write('h323,1);csr_write('hb03,0);csr_write('hb83,0);
        csr_write('h320,'h7f5);
        @(negedge clk_i);event_count_i=32'h9;
        addr_i='h323;write_i=1;command_i=1;write_data_i=2;
        @(posedge clk_i);#1;read_check('hb03,0);
        @(negedge clk_i);write_i=0;event_count_i=0;
        @(posedge clk_i);#1;counter_check('hb03,2);
        csr_write('h320,'h7fd);
        // mcycle and minstret increments and write priority, including overflow.
        csr_write('hb00,32'hffffffff);csr_write('hb80,0);
        csr_write('hb02,32'hffffffff);csr_write('hb82,0);
        @(negedge clk_i);retire_count_i=2;addr_i='h320;write_i=1;write_data_i='h7f8;
        @(posedge clk_i);#1;@(negedge clk_i);write_i=0;
        repeat(5)@(posedge clk_i);
        @(negedge clk_i);addr_i='h320;write_i=1;write_data_i='h7fd;
        @(posedge clk_i);#1;@(negedge clk_i);write_i=0;retire_count_i=0;
        counter_check('hb00,64'h100000005);counter_check('hb02,64'h10000000b);
        csr_write('h323,1);
        // Counter writes win over active increments, including a pending low-half carry.
        @(negedge clk_i);addr_i='h320;write_i=1;command_i=1;write_data_i=0;
        @(posedge clk_i);#1;@(negedge clk_i);
        addr_i='hb00;write_data_i=32'hffffffff;
        @(posedge clk_i);#1;
        read_check('hb00,32'hffffffff);read_check('hb80,1);
        @(negedge clk_i);addr_i='hb00;write_i=1;write_data_i=32'h12345678;
        @(posedge clk_i);#1;
        read_check('hb00,32'h12345678);read_check('hb80,1);
        @(negedge clk_i);addr_i='hb02;write_i=1;write_data_i=32'hffffffff;
        retire_count_i=1;
        @(posedge clk_i);#1;
        read_check('hb02,32'hffffffff);read_check('hb82,1);
        @(negedge clk_i);addr_i='hb02;write_i=1;write_data_i=32'h12345678;
        @(posedge clk_i);#1;
        read_check('hb02,32'h12345678);read_check('hb82,1);
        @(negedge clk_i);event_count_i=32'hffffffff;
        @(posedge clk_i);#1;
        @(negedge clk_i);addr_i='hb03;write_i=1;write_data_i=32'h11223344;
        @(posedge clk_i);#1;read_check('hb03,32'h11223344);
        @(negedge clk_i);retire_count_i=0;event_count_i=0;
        addr_i='h320;write_i=1;write_data_i='h7fd;
        @(posedge clk_i);#1;@(negedge clk_i);write_i=0;
        // Trap beats simultaneous mret and CSR update, then mret restores MIE.
        csr_write('h300,8);
        @(negedge clk_i);trap_i=1;mret_i=1;trap_pc_i='h1234567b;
        trap_cause_i='h8000000b;trap_value_i='h87654321;
        addr_i='h300;write_i=1;command_i=1;write_data_i=0;
        @(posedge clk_i);#1;@(negedge clk_i);trap_i=0;mret_i=0;write_i=0;
        read_check('h300,'h1880);read_check('h341,'h1234567a);
        if(no_c_read!==32'h12345678)$fatal(1,"FAIL trap mepc alignment");
        read_check('h342,'h8000000b);read_check('h343,'h87654321);
        @(negedge clk_i);mret_i=1;
        @(posedge clk_i);#1;@(negedge clk_i);mret_i=0;
        read_check('h300,'h1888);
        if(mstatus_o!==32'h1888 || mie_o!==0 || mtvec_o!==32'habcdef00 ||
            mepc_o!==32'h1234567a)$fatal(1,"FAIL CSR state outputs");
        $display("PASS U-10 all CSR addresses, WARL, counters, events, traps");$finish;
    end

endmodule
