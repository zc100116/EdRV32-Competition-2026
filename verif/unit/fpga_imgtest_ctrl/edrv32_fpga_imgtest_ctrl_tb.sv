// File: edrv32_fpga_imgtest_ctrl_tb.sv
// Spec: Task B3-9 acceptance; SoC 7.3 R1-R5; DISP v0.3 5.3.
// Description: APB trace oracle, frame ownership, GEO gateway writes and keys.
// Clock domain: synthetic clk_mem.
module edrv32_fpga_imgtest_ctrl_tb;
    // Testbench scoreboards update immediately at the sampled bus edge.
    /* verilator lint_off BLKSEQ */
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    `include "regs/edrv32_vin_regs.vh"
    `include "regs/edrv32_pix_regs.vh"
    `include "regs/edrv32_geo_regs.vh"
    `include "regs/edrv32_disp_regs.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk = 0;
    always #4 clk = !clk;
    /* verilator lint_off SYNCASYNCNET */
    reg rst_n = 0;
    /* verilator lint_on SYNCASYNCNET */
    reg ready = 0;
    reg [2:0] keys = 0;
    wire [11:0] paddr;
    wire [15:0] psel;
    wire penable;
    wire pwrite;
    wire [31:0] pwdata;
    wire [3:0] pstrb;
    reg [511:0] prdata;
    wire [15:0] pready = {16{cycle[1:0] != 2'b0}};
    wire [31:0] awaddr;
    wire awvalid;
    wire awready = cycle[0];
    wire [63:0] wdata;
    wire [7:0] wstrb;
    wire wvalid;
    wire wready = cycle[1];
    reg bvalid = 0;
    wire bready;
    wire frame_led;
    wire error_led;
    int unsigned cycle = 0;
    reg [31:0] registers [0:15][0:1023];
    reg [31:0] write_addr [0:2047];
    reg [31:0] write_data [0:2047];
    int writes = 0;
    int submissions = 0;
    int doorbells = 0;
    reg [31:0] descriptor [0:15];
    reg [31:0] saved_awaddr;
    int descriptor_writes = 0;
    reg aw_live = 0;
    int slot;
    reg [31:0] address;
    reg stalled = 0;
    reg [64:0] stalled_payload;

    edrv32_fpga_imgtest_ctrl u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ready_i(ready),
        .key_press_i(keys),
        .apb_paddr_o(paddr),
        .apb_psel_o(psel),
        .apb_penable_o(penable),
        .apb_pwrite_o(pwrite),
        .apb_pwdata_o(pwdata),
        .apb_pstrb_o(pstrb),
        .apb_pready_i(pready),
        .apb_prdata_i(prdata),
        .gw_awaddr_o(awaddr),
        .gw_awvalid_o(awvalid),
        .gw_awready_i(awready),
        .gw_wdata_o(wdata),
        .gw_wstrb_o(wstrb),
        .gw_wvalid_o(wvalid),
        .gw_wready_i(wready),
        .gw_bvalid_i(bvalid),
        .gw_bready_o(bready),
        .frame_o(frame_led),
        .error_o(error_led)
    );
    reg keys_rst_n = 0;
    reg [2:0] key_n = 3'b111;
    wire [2:0] press;
    int key_pulses = 0;
    edrv32_fpga_imgtest_keys u_keys (
        .clk_i(clk),
        .rst_n_i(keys_rst_n),
        .key_n_i(key_n),
        .press_o(press)
    );
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (|press) begin
            if (press != 3'b111) $fatal(1, "debounce press=%b expected=111", press);
            key_pulses <= key_pulses + 1;
        end
    end
    always @(*) begin
        prdata = 0;
        for (int s = 0; s < 16; s++)
            prdata[32*s +: 32] = registers[s][paddr[11:2]];
    end
    always @(posedge clk) begin
        if (rst_n) begin
            if (stalled && {psel,paddr,pwrite,pwdata,pstrb} != stalled_payload)
                $fatal(1, "APB changed during wait at %t", $time);
            stalled = |psel && penable && !(|(psel & pready));
            stalled_payload = {psel,paddr,pwrite,pwdata,pstrb};
            if (|psel && penable && |(psel & pready)) begin
                if (!$onehot(psel) || pstrb != 4'hf) $fatal(1, "APB control %h", psel);
                slot = 0;
                for (int s = 0; s < 16; s++) if (psel[s]) slot = s;
                address = EDRV32_MEDIA_APB_BASE + 4096*32'(slot) + {20'b0,paddr};
                if (pwrite) begin
                    write_addr[writes] = address;
                    write_data[writes] = pwdata;
                    writes++;
                    if (paddr == EDRV32_VIN_IRQ_STAT_OFFSET[11:0]) begin
                        if (pwdata[1]) $fatal(1, "controller cleared ERROR");
                        registers[slot][paddr[11:2]] &= ~pwdata;
                    end else begin
                        registers[slot][paddr[11:2]] = pwdata;
                    end
                    if (address == EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET) begin
                        if (pwdata < 32'h07000000 &&
                            !registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4][{3'b0,pwdata[22:21]}])
                            $fatal(1, "submitted VIN slot without ownership %h", pwdata);
                        submissions++;
                    end
                    if (address == EDRV32_GEO_BASE + EDRV32_GEO_DOORBELL_OFFSET) begin
                        if (descriptor_writes != 16) $fatal(1, "GEO started before writes completed");
                        doorbells++;
                    end
                end
            end
            if (awvalid && awready) begin
                if (aw_live) $fatal(1, "second gateway AW");
                saved_awaddr = awaddr;
                aw_live = 1;
            end
            if (wvalid && wready) begin
                if (!aw_live) $fatal(1, "W before AW");
                if (saved_awaddr != 32'hc0090000 + 4*32'(descriptor_writes))
                    $fatal(1, "descriptor AW got=%h index=%0d", saved_awaddr, descriptor_writes);
                if (wstrb != (saved_awaddr[2] ? 8'hf0 : 8'h0f))
                    $fatal(1, "gateway lane WSTRB=%h", wstrb);
                descriptor[descriptor_writes] = saved_awaddr[2] ? wdata[63:32] : wdata[31:0];
                descriptor_writes++;
                aw_live = 0;
                bvalid <= 1;
            end else if (bvalid && bready) begin
                bvalid <= 0;
            end
        end
    end

    task automatic step(input int n);
        repeat(n) @(negedge clk);
    endtask
    task automatic expect_write(input int idx, input reg [31:0] addr, data);
        if (write_addr[idx] !== addr || write_data[idx] !== data)
            $fatal(1, "write[%0d] got %h=%h expected %h=%h at %t", idx,
                write_addr[idx], write_data[idx], addr, data, $time);
    endtask
    task automatic vin_done(input int s);
        @(negedge clk);
        registers[1][EDRV32_VIN_CH_DONE_INFO_OFFSET/4] = 32'(s);
        registers[1][EDRV32_VIN_IRQ_STAT_OFFSET/4] |= EDRV32_VIN_IRQ_STAT_FRAME_MASK;
        step(100);
    endtask
    task automatic display_frame(input reg [31:0] current, released, input bit switched);
        @(negedge clk);
        registers[5][EDRV32_DISP_CUR_BASE_OFFSET/4] = current;
        registers[5][EDRV32_DISP_REL_BASE_OFFSET/4] = released;
        registers[5][EDRV32_DISP_IRQ_STAT_OFFSET/4] |=
            EDRV32_DISP_IRQ_STAT_FRAME_MASK | (switched ? EDRV32_DISP_IRQ_STAT_SWITCH_MASK : 0);
        step(100);
    endtask
    task automatic press_key(input reg [1:0] k);
        @(negedge clk);
        keys[k] = 1;
        step(1);
        keys = 0;
        step(150);
    endtask
    task automatic check_geo(input int source, target, mode);
        reg [31:0] expected [0:15];
        for (int i=0;i<16;i++) expected[i]=0;
        expected[0] = 32'h06000000 + 32'(source)*32'h200000;
        expected[1] = 2560;
        expected[2] = 32'h02d00500;
        expected[3] = 32'h07000000 + 32'(target)*32'h200000;
        expected[4] = 2560;
        expected[6] = 32'h02d00500;
        case(mode)
            1: begin
                expected[8]=32'hffff0000; expected[12]=32'hffff0000;
                expected[10]=32'h04ff0000; expected[13]=32'h02cf0000;
            end
            2: begin
                expected[8]=32'h00020000; expected[12]=32'h00020000;
                expected[10]=32'hfd800000; expected[13]=32'hfe980000;
            end
            3: begin
                expected[8]=32'h00008000; expected[12]=32'h00008000;
                expected[10]=32'h01400000; expected[13]=32'h00b40000;
            end
            default: $fatal(1,"bad oracle mode");
        endcase
        for (int i=0;i<16;i++)
            if (descriptor[i] !== expected[i])
                $fatal(1,"GEO mode=%0d word=%0d actual=%h expected=%h",mode,i,descriptor[i],expected[i]);
    endtask

    initial begin
        // Actual fixed 10 ms debounce, bounce rejection, hold and rearm.
        step(3); keys_rst_n=1;
        key_n=0; step(20); key_n=7; step(20);
        if (key_pulses != 0) $fatal(1,"bounce accepted");
        key_n=0; step(1250002);
        if (key_pulses != 1) $fatal(1,"press count %0d",key_pulses);
        step(30);
        if (key_pulses != 1) $fatal(1,"held key repeated");
        key_n=7; step(1250002); key_n=0; step(1250002);
        if (key_pulses != 2) $fatal(1,"release did not rearm");
        keys_rst_n=0;
        for(int s=0;s<16;s++) for(int r=0;r<1024;r++) registers[s][r]=0;
        registers[1][EDRV32_VIN_STATUS_OFFSET/4] = EDRV32_VIN_STATUS_IDLE_MASK;
        rst_n=1;
        step(20);
        if (writes != 0 || |psel || awvalid) $fatal(1,"started before ready");
        ready=1;
        wait(writes==276); step(20);
        for(int i=0;i<256;i++) expect_write(i,EDRV32_PIX_BASE+EDRV32_PIX_GAMMA_WR_OFFSET,
            32'h100 | 32'(i) | ((2*32'(i)-32'(i)*32'(i)/255)<<16));
        expect_write(256,EDRV32_PIX_BASE+EDRV32_PIX_CTRL_OFFSET,1);
        expect_write(257,EDRV32_PIX_BASE+EDRV32_PIX_BC_OFFSET,256);
        expect_write(258,EDRV32_PIX_BASE+EDRV32_PIX_THRESH_OFFSET,128);
        expect_write(259,EDRV32_PIX_BASE+EDRV32_PIX_CFG_OFFSET,4);
        expect_write(260,EDRV32_VIN_BASE+EDRV32_VIN_CAM0_SIZE_OFFSET,32'h02d00500);
        expect_write(261,EDRV32_VIN_BASE+EDRV32_VIN_CAM1_SIZE_OFFSET,32'h02d00500);
        for(int i=0;i<4;i++) expect_write(262+i,
            EDRV32_VIN_BASE+EDRV32_VIN_CH_SURF_BASE_OFFSET+4*32'(i),
            32'h06000000+32'h200000*32'(i));
        expect_write(266,EDRV32_VIN_BASE+EDRV32_VIN_CH_STRIDE_OFFSET,2560);
        expect_write(267,EDRV32_VIN_BASE+EDRV32_VIN_CH_SLOT_BUSY_OFFSET,0);
        expect_write(268,EDRV32_VIN_BASE+EDRV32_VIN_CH_CTRL_OFFSET,32'h41);
        expect_write(269,EDRV32_DISP_BASE+EDRV32_DISP_LAYER_CTRL_OFFSET,1);
        expect_write(270,EDRV32_DISP_BASE+EDRV32_DISP_L0_SCROLL_OFFSET,0);
        expect_write(271,EDRV32_DISP_BASE+EDRV32_DISP_STRIDE_OFFSET,2560);
        expect_write(272,EDRV32_GEO_BASE+EDRV32_GEO_CTRL_OFFSET,1);
        expect_write(273,EDRV32_GEO_BASE+EDRV32_GEO_DESC_BASE_OFFSET,32'h90000);
        expect_write(274,EDRV32_GEO_BASE+EDRV32_GEO_DESC_COUNT_OFFSET,1);
        expect_write(275,EDRV32_VIN_BASE+EDRV32_VIN_CTRL_OFFSET,1);
        if (registers[5][EDRV32_DISP_CTRL_OFFSET/4] != 0) $fatal(1,"displayed unwritten DDR");
        vin_done(0);
        if(submissions!=1 || registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4]!=1)
            $fatal(1,"first VIN submit/lock");
        if(registers[5][EDRV32_DISP_NEXT_BASE_OFFSET/4]!=32'h6000000)
            $fatal(1,"first DISP base");
        vin_done(1); // Pending submission must not be overwritten or lose its identity.
        if(submissions!=1 || registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4]!=1)
            $fatal(1,"pending frame overwritten");
        display_frame(32'h6000000,0,0);
        if(!frame_led) $fatal(1,"first frame LED");
        vin_done(2);
        if(submissions!=2 || registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4]!=5)
            $fatal(1,"second submit ownership");
        display_frame(32'h6400000,32'h6000000,1);
        if(frame_led || registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4]!=4)
            $fatal(1,"SWITCH must release exactly slot0");
        display_frame(32'h6400000,32'h6000000,0);
        if(registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4]!=4)
            $fatal(1,"FRAME without SWITCH released slot");
        // All PIX presets and wrap, with stop/idle preceding the shadow group.
        for(int mode=1;mode<=5;mode++) begin
            int before_writes;
            reg [31:0] cfg;
            before_writes=writes;
            if(mode==1) registers[1][EDRV32_VIN_STATUS_OFFSET/4]=0;
            press_key(0);
            if(mode==1) begin
                if(writes!=before_writes+1) $fatal(1,"PIX changed before VIN idle");
                registers[1][EDRV32_VIN_STATUS_OFFSET/4]=EDRV32_VIN_STATUS_IDLE_MASK;
                step(100);
            end
            if(writes!=before_writes+6) $fatal(1,"config write count");
            expect_write(before_writes,EDRV32_VIN_BASE+EDRV32_VIN_CTRL_OFFSET,0);
            expect_write(before_writes+1,EDRV32_PIX_BASE+EDRV32_PIX_BC_OFFSET,
                mode==1 ? 32'h00180140 : 256);
            expect_write(before_writes+2,EDRV32_PIX_BASE+EDRV32_PIX_THRESH_OFFSET,128);
            case(mode)
                1: cfg=5;
                2: cfg=6;
                3: cfg=32'h24;
                4: cfg=32'h10044;
                default: cfg=4;
            endcase
            expect_write(before_writes+3,EDRV32_PIX_BASE+EDRV32_PIX_CFG_OFFSET,cfg);
            expect_write(before_writes+4,EDRV32_VIN_BASE+EDRV32_VIN_CH_CTRL_OFFSET,32'h41);
            expect_write(before_writes+5,EDRV32_VIN_BASE+EDRV32_VIN_CTRL_OFFSET,1);
        end
        registers[1][EDRV32_VIN_STATUS_OFFSET/4]=0;
        press_key(2);
        begin
            bit previous_led;
            previous_led=frame_led;
            display_frame(32'h6400000,0,0);
            if(frame_led==previous_led) $fatal(1,"DISP polling stopped while VIN drained");
        end
        registers[1][EDRV32_VIN_STATUS_OFFSET/4]=EDRV32_VIN_STATUS_IDLE_MASK;
        step(100);
        if(registers[1][EDRV32_VIN_CH_CTRL_OFFSET/4]!=32'h43) $fatal(1,"camera1 select");
        press_key(2);
        if(registers[1][EDRV32_VIN_CH_CTRL_OFFSET/4]!=32'h41) $fatal(1,"camera0 select");
        for(int mode=1;mode<=3;mode++) begin
            int previous;
            int target;
            reg [31:0] released;
            target=(mode==2 ? 1 : 0);
            released=(mode==1 ? 32'h6400000 : (mode==2 ? 32'h7000000 : 32'h7200000));
            press_key(1);
            descriptor_writes=0;
            previous=doorbells;
            vin_done(1);
            wait(doorbells==previous+1); step(10);
            check_geo(1,target,mode);
            if(registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4] != (mode==1 ? 6 : 2))
                $fatal(1,"GEO source not locked");
            previous=submissions;
            vin_done(3); // A dropped VIN completion cannot replace the active GEO source.
            if(submissions!=previous) $fatal(1,"submitted before GEO DONE");
            @(negedge clk);
            registers[3][EDRV32_GEO_IRQ_STAT_OFFSET/4] |= EDRV32_GEO_IRQ_STAT_DONE_MASK;
            step(100);
            if(submissions!=previous+1 ||
                registers[5][EDRV32_DISP_NEXT_BASE_OFFSET/4] != 32'h7000000+32'(target)*32'h200000)
                $fatal(1,"GEO result submission");
            if(registers[1][EDRV32_VIN_CH_SLOT_BUSY_OFFSET/4] != (mode==1 ? 4 : 0))
                $fatal(1,"GEO DONE released wrong source");
            display_frame(32'h7000000+32'(target)*32'h200000,released,1);
        end
        press_key(1); // Four-way GEO wrap to off.
        vin_done(0);
        if(registers[5][EDRV32_DISP_NEXT_BASE_OFFSET/4]!=32'h6000000)
            $fatal(1,"GEO wrap did not bypass");
        display_frame(32'h6000000,32'h7000000,1);
        // Each engine's ERROR is polled, remains W1C-uncleared, and never resets engines.
        for(int engine_idx=0;engine_idx<4;engine_idx++) begin
            int engine_slot;
            rst_n=0; ready=0; stalled=0; step(3);
            for(int s=0;s<16;s++) for(int r=0;r<1024;r++) registers[s][r]=0;
            registers[1][EDRV32_VIN_STATUS_OFFSET/4]=EDRV32_VIN_STATUS_IDLE_MASK;
            writes=0; rst_n=1; ready=1;
            wait(writes==276); step(20);
            if(error_led) $fatal(1,"ERROR did not reset");
            engine_slot=(engine_idx==3 ? 5 : engine_idx+1);
            @(negedge clk);
            registers[engine_slot][EDRV32_VIN_IRQ_STAT_OFFSET/4] |= 2;
            step(100);
            if(!error_led || !registers[engine_slot][EDRV32_VIN_IRQ_STAT_OFFSET/4][1])
                $fatal(1,"engine ERROR not indicated/preserved slot=%0d",engine_slot);
        end
        $display("PASS fpga_imgtest_ctrl startup, APB stalls, ownership, PIX/GEO, camera keys, debounce, ERROR");
        $finish;
    end
    initial begin
        #40000000;
        $fatal(1,"unit timeout state=%0d writes=%0d",u_dut.state_r,writes);
    end
endmodule
