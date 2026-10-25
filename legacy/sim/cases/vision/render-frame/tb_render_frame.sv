`timescale 1ns/1ps

module tb_render_frame;
    localparam integer WIDTH = 64;
    localparam integer HEIGHT = 32;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    localparam [31:0] FRONT = 32'h0000_4000;
    localparam [31:0] TARGET0 = 32'h0001_0000;
    localparam [31:0] TARGET1 = 32'h0001_2000;
    localparam [31:0] TARGET2 = 32'h0001_4000;
    localparam [31:0] BASE0 = 32'h0002_0000;
    localparam [31:0] BASE1 = 32'h0002_2000;
    localparam [31:0] BASE2 = 32'h0002_4000;
    localparam [31:0] BASE3 = 32'h0002_6000;
    localparam [15:0] BASE_COLOR0 = 16'h001f;
    localparam [15:0] BASE_COLOR1 = 16'h6b4d;
    localparam [15:0] BASE_COLOR2 = 16'h4208;
    localparam [15:0] BASE_COLOR3 = 16'hf800;

    reg clk, rst_n;
    reg [31:0] paddr, pwdata;
    reg psel, penable, pwrite;
    reg [3:0] pstrb;
    wire pready, pslverr, irq;
    wire [31:0] prdata;
    reg base_valid;
    reg [1:0] base_buffer;
    reg [31:0] base_addr, base_stride;
    wire base_release_valid;
    wire [1:0] base_release_buffer;
    wire display_valid;
    reg display_ready;
    wire [2:0] display_token;
    wire [31:0] display_base;
    reg display_retire_valid;
    reg [2:0] display_retire_token;
    wire [3:0] arid, rid, awid, bid;
    wire [31:0] araddr, awaddr;
    wire [7:0] arlen, awlen;
    wire [2:0] arsize, awsize;
    wire [1:0] arburst, awburst;
    wire [3:0] arqos, awqos;
    wire arvalid, arready, rvalid, rready, rlast;
    wire awvalid, awready, wvalid, wready, wlast;
    wire bvalid, bready;
    wire [255:0] rdata, wdata;
    wire [31:0] wstrb;
    wire [1:0] rresp, bresp;
    reg ar_gate, r_gate, aw_gate, w_gate, b_gate;
    reg [511:0] command [0:1];
    integer releases [0:3];
    integer i, j, x, y, cycles;
    integer draw_starts, compose_starts, publish_count;
    reg compose_done_seen;
    reg [31:0] readback;
    reg [15:0] actual, wanted;

    always #5 clk = ~clk;

    edrv32_render_system #(
        .FRONT_BASE(FRONT),
        .TARGET_BASE0(TARGET0),
        .TARGET_BASE1(TARGET1),
        .TARGET_BASE2(TARGET2),
        .TARGET_SLOT_BYTES(32'h0000_2000)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .paddr_i(paddr), .psel_i(psel),
        .penable_i(penable), .pwrite_i(pwrite),
        .pwdata_i(pwdata), .pstrb_i(pstrb),
        .pready_o(pready), .prdata_o(prdata),
        .pslverr_o(pslverr), .irq_o(irq),
        .base_valid_i(base_valid),
        .base_buffer_i(base_buffer),
        .base_addr_i(base_addr), .base_stride_i(base_stride),
        .base_release_valid_o(base_release_valid),
        .base_release_buffer_o(base_release_buffer),
        .display_valid_o(display_valid),
        .display_ready_i(display_ready),
        .display_token_o(display_token),
        .display_base_o(display_base),
        .display_retire_valid_i(display_retire_valid),
        .display_retire_token_i(display_retire_token),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready && ar_gate),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid && r_gate), .m_rready_o(rready),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready && aw_gate),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready && w_gate),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid && b_gate), .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(16384)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst),
        .awvalid_i(awvalid && aw_gate), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid && w_gate),
        .wready_o(wready), .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(bvalid), .bready_i(bready && b_gate),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst),
        .arvalid_i(arvalid && ar_gate), .arready_o(arready),
        .rid_o(rid), .rdata_o(rdata), .rresp_o(rresp),
        .rlast_o(rlast), .rvalid_o(rvalid),
        .rready_i(rready && r_gate)
    );

    function automatic [7:0] mul_ref;
        input [7:0] a, b;
        begin
            mul_ref = (integer'(a)*integer'(b)+127)/255;
        end
    endfunction

    function automatic [15:0] expected_pixel;
        input [15:0] base_color;
        input integer px, py;
        reg [7:0] br, bg, bb, rr, gg, blue;
        begin
            if (px < 8 || px >= 56 || py < 7 || py >= 25)
                expected_pixel = base_color;
            else begin
                br = {base_color[15:11],base_color[15:13]};
                bg = {base_color[10:5],base_color[10:9]};
                bb = {base_color[4:0],base_color[4:2]};
                rr = 8'h80 + mul_ref(br,8'h7f);
                gg = mul_ref(bg,8'h7f);
                blue = mul_ref(bb,8'h7f);
                expected_pixel = {rr[7:3],gg[7:2],blue[7:3]};
            end
        end
    endfunction

    function automatic [15:0] read_pixel16;
        input integer address;
        begin
            read_pixel16 = u_mem.store[address >> 5]
                                       [(address & 31)*8 +: 16];
        end
    endfunction

    task automatic apb_write;
        input [7:0] offset;
        input [31:0] value;
        begin
            @(negedge clk);
            paddr = {24'd0,offset};
            pwdata = value;
            pstrb = 4'hf;
            pwrite = 1'b1;
            psel = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            #1;
            if (!pready || pslverr)
                $fatal(1,"APB write failed offset=%h error=%b",
                       offset,pslverr);
            @(posedge clk);
            @(negedge clk);
            psel = 1'b0;
            penable = 1'b0;
            pwrite = 1'b0;
        end
    endtask

    task automatic apb_write_error;
        input [7:0] offset;
        input [31:0] value;
        begin
            @(negedge clk);
            paddr = {24'd0,offset};
            pwdata = value;
            pstrb = 4'hf;
            pwrite = 1'b1;
            psel = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            #1;
            if (!pready || !pslverr)
                $fatal(1,"APB write was not rejected offset=%h",offset);
            @(posedge clk);
            @(negedge clk);
            psel = 1'b0;
            penable = 1'b0;
            pwrite = 1'b0;
        end
    endtask

    task automatic apb_read;
        input [7:0] offset;
        output [31:0] value;
        begin
            @(negedge clk);
            paddr = {24'd0,offset};
            pwrite = 1'b0;
            psel = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            #1;
            if (!pready || pslverr)
                $fatal(1,"APB read failed offset=%h",offset);
            value = prdata;
            @(negedge clk);
            psel = 1'b0;
            penable = 1'b0;
        end
    endtask

    task automatic send_base;
        input [1:0] id;
        input [31:0] address;
        begin
            @(negedge clk);
            base_buffer = id;
            base_addr = address;
            base_stride = 32'd128;
            base_valid = 1'b1;
            @(negedge clk);
            base_valid = 1'b0;
        end
    endtask

    task automatic accept_display;
        input [2:0] token;
        input [31:0] address;
        begin
            wait(display_valid);
            if (display_token !== token || display_base !== address)
                $fatal(1,"display token/base got=%h/%h want=%h/%h",
                       display_token,display_base,token,address);
            @(negedge clk);
            display_ready = 1'b1;
            @(negedge clk);
            display_ready = 1'b0;
        end
    endtask

    task automatic retire_display;
        input [2:0] token;
        begin
            @(negedge clk);
            display_retire_token = token;
            display_retire_valid = 1'b1;
            @(negedge clk);
            display_retire_valid = 1'b0;
        end
    endtask

    task automatic check_target;
        input [31:0] address;
        input [15:0] base_color;
        begin
            for (y=0; y<HEIGHT; y=y+1)
                for (x=0; x<WIDTH; x=x+1) begin
                    actual = read_pixel16(address+y*128+x*2);
                    wanted = expected_pixel(base_color,x,y);
                    if (actual !== wanted)
                        $fatal(1,"target mismatch addr=%h x=%0d y=%0d got=%h want=%h",
                               address,x,y,actual,wanted);
                end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        paddr = 32'd0;
        pwdata = 32'd0;
        psel = 1'b0;
        penable = 1'b0;
        pwrite = 1'b0;
        pstrb = 4'hf;
        base_valid = 1'b0;
        base_buffer = 2'd0;
        base_addr = 32'd0;
        base_stride = 32'd128;
        display_ready = 1'b0;
        display_retire_valid = 1'b0;
        display_retire_token = 3'd0;
        ar_gate = 1'b1;
        r_gate = 1'b1;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cycles = 0;
        draw_starts = 0;
        compose_starts = 0;
        publish_count = 0;
        compose_done_seen = 1'b0;
        for (i=0; i<4; i=i+1)
            releases[i] = 0;
        for (i=0; i<16384; i=i+1)
            u_mem.store[i] = {32{8'ha5}};
        for (y=0; y<HEIGHT; y=y+1)
            for (j=0; j<4; j=j+1) begin
                u_mem.store[((BASE0+y*128) >> 5)+j] =
                    {16{BASE_COLOR0}};
                u_mem.store[((BASE1+y*128) >> 5)+j] =
                    {16{BASE_COLOR1}};
                u_mem.store[((BASE2+y*128) >> 5)+j] =
                    {16{BASE_COLOR2}};
                u_mem.store[((BASE3+y*128) >> 5)+j] =
                    {16{BASE_COLOR3}};
            end
        command[0] = 512'd0;
        command[1] = 512'd0;
        command[0][7:0] = 8'h02;
        command[0][63:32] = FRONT;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd64,16'd0};
        command[0][143:128] = 16'd32;
        command[1][7:0] = 8'h02;
        command[1][63:32] = FRONT+7*256;
        command[1][95:64] = 32'd256;
        command[1][127:96] = {16'd48,16'd8};
        command[1][143:128] = 16'd18;
        command[1][191:160] = 32'h8080_0000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        u_mem.store[(LIST_BASE >> 5)+2] = command[1][255:0];
        u_mem.store[(LIST_BASE >> 5)+3] = command[1][511:256];
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        send_base(2'd0,BASE0);
        wait(display_valid);
        if (display_token !== 3'd0 || display_base !== BASE0 ||
            compose_starts != 0 || releases[0] != 0)
            $fatal(1,"base bypass publication failed");
        accept_display(3'd0,BASE0);
        repeat (20) @(posedge clk);
        if (releases[0] != 0)
            $fatal(1,"bypass base released before scanout retirement");
        retire_display(3'd0);
        wait(releases[0] == 1);

        apb_write(8'h18,FRONT);
        apb_write(8'h1c,32'd256);
        apb_write(8'h20,{16'd32,16'd64});
        apb_write(8'h24,32'd128);
        apb_write(8'h10,LIST_BASE);
        apb_write_error(8'h28,32'd1);
        apb_write(8'h14,32'd2);
        apb_write(8'h08,32'd1);
        apb_write(8'h2c,32'hf);
        apb_write(8'h28,32'd1);
        wait(u_dut.u_frame_ctrl.state_r == 2'd1);
        apb_write_error(8'h18,FRONT+32'd256);
        send_base(2'd1,BASE1);
        send_base(2'd2,BASE2);
        wait(releases[1] >= 1);
        wait(display_valid);
        if (display_token !== 3'd4 || display_base !== TARGET0 ||
            !compose_done_seen)
            $fatal(1,"automatic composition publication failed");
        check_target(TARGET0,BASE_COLOR2);
        accept_display(3'd4,TARGET0);
        wait(releases[2] >= 1);
        if (u_dut.u_frame_ctrl.target_free_r[0] !== 1'b0)
            $fatal(1,"published target released before scanout");

        send_base(2'd1,BASE1);
        wait(display_valid);
        if (display_token !== 3'd5 || display_base !== TARGET1)
            $fatal(1,"second target allocation failed");
        check_target(TARGET1,BASE_COLOR1);
        accept_display(3'd5,TARGET1);
        wait(releases[1] >= 2);

        send_base(2'd2,BASE2);
        wait(display_valid);
        if (display_token !== 3'd6 || display_base !== TARGET2)
            $fatal(1,"third target allocation failed");
        check_target(TARGET2,BASE_COLOR2);
        accept_display(3'd6,TARGET2);
        wait(releases[2] >= 2);

        send_base(2'd0,BASE0);
        repeat (30) @(posedge clk);
        if (display_valid || compose_starts != 3 ||
            u_dut.u_frame_ctrl.target_free_r !== 3'b000 ||
            !u_dut.u_frame_ctrl.base_pending_r)
            $fatal(1,"target exhaustion did not hold pending base");
        retire_display(3'd4);
        wait(display_valid);
        if (display_token !== 3'd4 || display_base !== TARGET0)
            $fatal(1,"retired target was not reused");
        check_target(TARGET0,BASE_COLOR0);
        accept_display(3'd4,TARGET0);
        wait(releases[0] >= 2);
        retire_display(3'd5);
        retire_display(3'd6);
        retire_display(3'd4);
        repeat (3) @(posedge clk);
        if (!u_dut.u_frame_ctrl.target_free_r[0] ||
            !u_dut.u_frame_ctrl.target_free_r[1] ||
            !u_dut.u_frame_ctrl.target_free_r[2])
            $fatal(1,"retired display target was not freed");

        u_mem.store[LIST_BASE >> 5][7:0] = 8'hff;
        apb_write(8'h14,32'd1);
        apb_write(8'h28,32'd1);
        wait(u_dut.u_frame_ctrl.state_r == 2'd1);
        send_base(2'd3,BASE3);
        wait(display_valid);
        if (display_token !== 3'd3 || display_base !== BASE3)
            $fatal(1,"failed draw did not bypass pending base");
        accept_display(3'd3,BASE3);
        retire_display(3'd3);
        wait(releases[3] >= 1);

        apb_read(8'h34,readback);
        if (readback != 32'd1)
            $fatal(1,"draw count=%0d",readback);
        apb_read(8'h38,readback);
        if (readback != 32'd6)
            $fatal(1,"published frame count=%0d",readback);
        apb_read(8'h3c,readback);
        if (readback != 32'd1)
            $fatal(1,"dropped frame count=%0d",readback);
        apb_read(8'h40,readback);
        if (readback != 32'd1 || !irq)
            $fatal(1,"error count / IRQ mismatch count=%0d irq=%b",
                   readback,irq);
        apb_read(8'h30,readback);
        if (readback[3:0] != 4'hf)
            $fatal(1,"IRQ event bits=%h",readback[3:0]);
        apb_write(8'h30,32'hf);
        apb_read(8'h30,readback);
        if (readback[3:0] != 4'd0 || irq)
            $fatal(1,"IRQ W1C failed bits=%h irq=%b",readback[3:0],irq);

        // Hold a composed base so a later UI-only draw can recompose it.
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        u_mem.store[(LIST_BASE >> 5)+2] = command[1][255:0];
        u_mem.store[(LIST_BASE >> 5)+3] = command[1][511:256];
        apb_write(8'h08,32'd3);
        apb_write(8'h14,32'd2);
        apb_write(8'h28,32'd1);
        wait(u_dut.u_frame_ctrl.state_r == 2'd1);
        send_base(2'd0,BASE0);
        wait(display_valid);
        if (display_token !== 3'd5 || display_base !== TARGET1)
            $fatal(1,"held base first composition failed");
        check_target(TARGET1,BASE_COLOR0);
        accept_display(3'd5,TARGET1);
        repeat (10) @(posedge clk);
        if (releases[0] != 2 ||
            !u_dut.u_frame_ctrl.held_base_valid_r ||
            u_dut.u_frame_ctrl.held_base_addr_r != BASE0)
            $fatal(1,"composed base was released instead of held");

        command[0] = 512'd0;
        command[0][7:0] = 8'h02;
        command[0][63:32] = FRONT;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd8,16'd0};
        command[0][143:128] = 16'd8;
        command[0][191:160] = 32'hff00_ff00;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        apb_write(8'h14,32'd1);
        apb_write(8'h28,32'd1);
        wait(display_valid);
        if (display_token !== 3'd6 || display_base !== TARGET2 ||
            read_pixel16(TARGET2) !== 16'h07e0 ||
            read_pixel16(TARGET2+31*128+63*2) !== BASE_COLOR0 ||
            read_pixel16(TARGET2+15*128+20*2) !==
                expected_pixel(BASE_COLOR0,20,15))
            $fatal(1,"UI-only held-base recomposition failed");
        accept_display(3'd6,TARGET2);
        if (releases[0] != 2)
            $fatal(1,"UI-only recomposition released held base");

        send_base(2'd1,BASE1);
        wait(display_valid);
        if (display_token !== 3'd4 || display_base !== TARGET0 ||
            read_pixel16(TARGET0) !== 16'h07e0 ||
            read_pixel16(TARGET0+31*128+63*2) !== BASE_COLOR1)
            $fatal(1,"replacement base composition failed");
        accept_display(3'd4,TARGET0);
        wait(releases[0] == 3);
        if (releases[1] != 2 ||
            u_dut.u_frame_ctrl.held_base_addr_r != BASE1)
            $fatal(1,"old held base release or new ownership failed");
        apb_write(8'h08,32'd1);
        wait(releases[1] == 3);
        if (u_dut.u_frame_ctrl.held_base_valid_r ||
            u_dut.u_frame_ctrl.recompose_pending_r)
            $fatal(1,"disabling hold did not release base");
        retire_display(3'd5);
        retire_display(3'd6);
        retire_display(3'd4);

        // A new base arriving during composition must not replace the
        // active source address that will become the held reference.
        apb_write(8'h08,32'd3);
        send_base(2'd0,BASE0);
        wait(u_dut.u_frame_ctrl.state_r == 2'd2);
        send_base(2'd1,BASE1);
        wait(display_valid);
        if (display_token !== 3'd5 ||
            read_pixel16(TARGET1+31*128+63*2) !== BASE_COLOR0 ||
            u_dut.u_frame_ctrl.held_base_addr_r !== BASE0)
            $fatal(1,"active base was overwritten by a pending arrival");
        accept_display(3'd5,TARGET1);
        wait(display_valid);
        if (display_token !== 3'd6 ||
            read_pixel16(TARGET2+31*128+63*2) !== BASE_COLOR1)
            $fatal(1,"queued base composition after held source failed");
        accept_display(3'd6,TARGET2);
        wait(releases[0] == 4);
        if (u_dut.u_frame_ctrl.held_base_addr_r !== BASE1 ||
            releases[1] != 3)
            $fatal(1,"replacement held base ownership mismatch");
        apb_write(8'h08,32'd1);
        wait(releases[1] == 4);
        retire_display(3'd5);
        retire_display(3'd6);

        // A command may name a display target directly; no such AXI write
        // may reach DDR even after that target has been retired.
        command[0] = 512'd0;
        command[0][7:0] = 8'h02;
        command[0][63:32] = TARGET0;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd64,16'd0};
        command[0][143:128] = 16'd32;
        command[0][191:160] = 32'hffff_ffff;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        apb_write(8'h28,32'd1);
        wait(u_dut.u_frame_ctrl.error_count_r == 32'd2);
        if (read_pixel16(TARGET0) !== 16'h07e0 || display_valid)
            $fatal(1,"draw command changed a protected display target");

        command[0] = 512'd0;
        command[0][7:0] = 8'h03;
        command[0][63:32] = BASE0;
        command[0][95:64] = 32'd128;
        command[0][127:96] = FRONT;
        command[0][159:128] = 32'd256;
        command[0][191:160] = TARGET1;
        command[0][223:192] = 32'd128;
        command[0][239:224] = 16'd64;
        command[0][255:240] = 16'd32;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        apb_write(8'h28,32'd1);
        wait(u_dut.u_frame_ctrl.error_count_r == 32'd3);
        if (read_pixel16(TARGET1) !== 16'h07e0 || display_valid)
            $fatal(1,"list COMPOSE changed a protected display target");

        command[0] = 512'd0;
        command[0][7:0] = 8'h02;
        command[0][63:32] = FRONT;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd2,16'd0};
        command[0][143:128] = 16'd1;
        command[0][191:160] = 32'hff00_00ff;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        apb_write(8'h28,32'd1);
        wait(u_dut.u_frame_ctrl.draw_count_r == 32'd4);
        if (u_mem.store[FRONT >> 5][63:0] !== 64'hff00_00ff_ff00_00ff)
            $fatal(1,"legal front draw did not recover after guard errors");

        // A malformed compose stride may write its allocated slot's first
        // row, but must never reach the next HDMI target slot.
        apb_write(8'h24,32'h0000_2000);
        send_base(2'd0,BASE0);
        wait(u_dut.u_frame_ctrl.error_count_r == 32'd4);
        if (display_valid || read_pixel16(TARGET1) !== 16'h07e0)
            $fatal(1,"direct compose escaped its allocated target slot");
        apb_write(8'h24,32'd128);

        $display("RENDER_FRAME_PASS published=%0d draws=%0d compose=%0d stale=1 errors=4 cycles=%0d",
                 publish_count,draw_starts,compose_starts,cycles);
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            ar_gate = $urandom_range(0,7) != 0;
            r_gate = $urandom_range(0,7) != 0;
            aw_gate = $urandom_range(0,7) != 0;
            w_gate = $urandom_range(0,7) != 0;
            b_gate = $urandom_range(0,7) != 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (base_release_valid)
                releases[base_release_buffer] =
                    releases[base_release_buffer] + 1;
            if (u_dut.u_frame_ctrl.draw_start_o)
                draw_starts = draw_starts + 1;
            if (u_dut.u_frame_ctrl.compose_start_o) begin
                compose_starts = compose_starts + 1;
                compose_done_seen = 1'b0;
            end
            if (u_dut.u_engine.compose_direct_done_o)
                compose_done_seen = 1'b1;
            if (display_valid && display_token[2] &&
                !compose_done_seen)
                $fatal(1,"composed target published before final B response");
            if (display_valid && display_ready)
                publish_count = publish_count + 1;
            if (cycles > 100000)
                $fatal(1,"frame-control timeout state=%0d pending=%b publish=%b",
                       u_dut.u_frame_ctrl.state_r,
                       u_dut.u_frame_ctrl.base_pending_r,
                       display_valid);
        end
    end
endmodule
