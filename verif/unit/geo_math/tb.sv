// File: tb.sv
// Spec: geo-spec 2, 4, 5.
// Description: Independent formula-based unit checks.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = !clk;
    reg [511:0] desc_data_i;
    wire [31:0] desc_src_base_o;
    wire [31:0] desc_src_stride_o;
    wire [11:0] desc_src_w_o;
    wire [11:0] desc_src_h_o;
    wire [31:0] desc_dst_base_o;
    wire [31:0] desc_dst_stride_o;
    wire [11:0] desc_rect_x_o;
    wire [11:0] desc_rect_y_o;
    wire [11:0] desc_rect_w_o;
    wire [11:0] desc_rect_h_o;
    wire [15:0] desc_bg_o;
    wire [31:0] desc_a_o;
    wire [31:0] desc_b_o;
    wire [31:0] desc_tx_o;
    wire [31:0] desc_c_o;
    wire [31:0] desc_d_o;
    wire [31:0] desc_ty_o;
    edrv32_geo_desc u_desc_ (
        .data_i(desc_data_i),
        .src_base_o(desc_src_base_o),
        .src_stride_o(desc_src_stride_o),
        .src_w_o(desc_src_w_o),
        .src_h_o(desc_src_h_o),
        .dst_base_o(desc_dst_base_o),
        .dst_stride_o(desc_dst_stride_o),
        .rect_x_o(desc_rect_x_o),
        .rect_y_o(desc_rect_y_o),
        .rect_w_o(desc_rect_w_o),
        .rect_h_o(desc_rect_h_o),
        .bg_o(desc_bg_o),
        .a_o(desc_a_o),
        .b_o(desc_b_o),
        .tx_o(desc_tx_o),
        .c_o(desc_c_o),
        .d_o(desc_d_o),
        .ty_o(desc_ty_o)
    );
    reg [31:0] range_a_i;
    reg [31:0] range_b_i;
    reg [31:0] range_c_i;
    reg [31:0] range_d_i;
    wire range_error_o;
    edrv32_geo_range u_range_ (
        .clk_i(clk),
        .a_i(range_a_i),
        .b_i(range_b_i),
        .c_i(range_c_i),
        .d_i(range_d_i),
        .error_o(range_error_o)
    );
    reg bounds_clk_i;
    reg bounds_rst_n_i;
    reg bounds_start_i;
    reg bounds_clear_i;
    wire bounds_done_o;
    reg [31:0] bounds_x_i;
    reg [31:0] bounds_y_i;
    reg [5:0] bounds_width_i;
    reg [4:0] bounds_height_i;
    reg [31:0] bounds_a_i;
    reg [31:0] bounds_b_i;
    reg [31:0] bounds_c_i;
    reg [31:0] bounds_d_i;
    reg [11:0] bounds_src_w_i;
    reg [11:0] bounds_src_h_i;
    wire bounds_empty_o;
    wire [11:0] bounds_origin_x_o;
    wire [11:0] bounds_origin_y_o;
    wire [15:0] bounds_width_bytes_o;
    wire [11:0] bounds_height_o;
    edrv32_geo_bounds u_bounds_ (
        .clk_i(bounds_clk_i),
        .rst_n_i(bounds_rst_n_i),
        .start_i(bounds_start_i),
        .clear_i(bounds_clear_i),
        .done_o(bounds_done_o),
        .x_i(bounds_x_i),
        .y_i(bounds_y_i),
        .width_i(bounds_width_i),
        .height_i(bounds_height_i),
        .a_i(bounds_a_i),
        .b_i(bounds_b_i),
        .c_i(bounds_c_i),
        .d_i(bounds_d_i),
        .src_w_i(bounds_src_w_i),
        .src_h_i(bounds_src_h_i),
        .empty_o(bounds_empty_o),
        .origin_x_o(bounds_origin_x_o),
        .origin_y_o(bounds_origin_y_o),
        .width_bytes_o(bounds_width_bytes_o),
        .height_o(bounds_height_o)
    );
    integer trial;
    integer word_idx;
    integer corner;
    integer corner_u;
    integer corner_v;
    integer cx;
    integer cy;
    integer min_x;
    integer max_x;
    integer min_y;
    integer max_y;
    integer expect_x;
    integer expect_y;
    integer expect_width;
    integer expect_height;
    reg expect_empty;
    integer expected_range;
    longint unsigned aa;
    longint unsigned bb;
    longint unsigned cc;
    longint unsigned dd;
    reg [511:0] clean;
    reg [511:0] mask;
    reg [511:0] random_bits;
    reg [511:0] expected;
    task check_range(input integer a, input integer b, input integer c, input integer d);
        begin
            range_a_i = 32'(a);
            range_b_i = 32'(b);
            range_c_i = 32'(c);
            range_d_i = 32'(d);
            aa = a < 0 ? -64'(a) : 64'(a);
            bb = b < 0 ? -64'(b) : 64'(b);
            cc = c < 0 ? -64'(c) : 64'(c);
            dd = d < 0 ? -64'(d) : 64'(d);
            expected_range = int'(aa*31+bb*15 > 78*65536 || cc*31+dd*15 > 78*65536);
            repeat (4) @(posedge clk);
            #1;
            if (range_error_o !== 1'(expected_range))
                $fatal(1, "FAIL range a=%d b=%d c=%d d=%d exp=%d got=%d",
                    a,b,c,d,expected_range,range_error_o);
        end
    endtask
    always @(*) bounds_clk_i=clk;
    task run_bounds;
        begin
            @(negedge clk);bounds_start_i=1;
            @(negedge clk);bounds_start_i=0;
            while(!bounds_done_o) @(negedge clk);
            #1;
        end
    endtask
    initial begin
        bounds_start_i=0;bounds_clear_i=0;bounds_rst_n_i=0;
        repeat(2) @(negedge clk);bounds_rst_n_i=1;
        desc_data_i = 0;
        range_a_i = 0;
        range_b_i = 0;
        range_c_i = 0;
        range_d_i = 0;
        bounds_x_i = 0;
        bounds_y_i = 0;
        bounds_width_i = 0;
        bounds_height_i = 0;
        bounds_a_i = 0;
        bounds_b_i = 0;
        bounds_c_i = 0;
        bounds_d_i = 0;
        bounds_src_w_i = 0;
        bounds_src_h_i = 0;
        mask = 0;
        mask[0*32 +: 32] = 32'hfffff000;
        mask[1*32 +: 32] = 32'h0000ffe0;
        mask[2*32 +: 32] = 32'h0fff0fff;
        mask[3*32 +: 32] = 32'hfffff000;
        mask[4*32 +: 32] = 32'h0000ffe0;
        mask[5*32 +: 32] = 32'h0fff0ff0;
        mask[6*32 +: 32] = 32'h0fff0ffe;
        mask[7*32 +: 32] = 32'h0000ffff;
        mask[8*32 +: 192] = '1;
        for (trial=0; trial<200; trial=trial+1) begin
            for (word_idx=0; word_idx<16; word_idx=word_idx+1) begin
                clean[word_idx*32 +: 32] = $urandom;
                random_bits[word_idx*32 +: 32] = $urandom;
            end
            expected = clean & mask;
            desc_data_i = expected | (random_bits & ~mask);
            #1;
            if ({desc_ty_o,desc_d_o,desc_c_o,desc_tx_o,desc_b_o,desc_a_o} !==
                expected[447:256] || desc_src_base_o !== expected[31:0] ||
                desc_src_stride_o !== expected[63:32] ||
                desc_dst_base_o !== expected[127:96] ||
                desc_dst_stride_o !== expected[159:128] ||
                {4'd0,desc_src_h_o,4'd0,desc_src_w_o} !== expected[95:64] ||
                {4'd0,desc_rect_y_o,4'd0,desc_rect_x_o} !== expected[191:160] ||
                {4'd0,desc_rect_h_o,4'd0,desc_rect_w_o} !== expected[223:192] ||
                desc_bg_o !== expected[239:224])
                $fatal(1,"FAIL descriptor ignored bits trial %0d",trial);
        end
        check_range(0,0,0,0);
        check_range(3,340781,0,0);
        check_range(3,340782,0,0);
        check_range(0,0,-3,-340781);
        check_range(0,0,-3,-340782);
        check_range(164897,0,0,0);
        check_range(164898,0,0,0);
        check_range(0,340787,0,0);
        check_range(0,340788,0,0);
        check_range(-164897,0,0,0);
        check_range(-164898,0,0,0);
        check_range(3*65536,0,0,65536);
        check_range(-2147483648,0,0,0);
        check_range(0,0,0,-2147483648);
        for (trial=0; trial<1000; trial=trial+1)
            check_range($signed($urandom_range(0,600000))-300000,
                $signed($urandom_range(0,600000))-300000,
                $signed($urandom_range(0,600000))-300000,
                $signed($urandom_range(0,600000))-300000);
        for (trial=0; trial<360; trial=trial+15)
            check_range($rtoi(2.0*$cos(real'(trial)*3.141592653589793/180.0)*65536),
                $rtoi(-2.0*$sin(real'(trial)*3.141592653589793/180.0)*65536),
                $rtoi(2.0*$sin(real'(trial)*3.141592653589793/180.0)*65536),
                $rtoi(2.0*$cos(real'(trial)*3.141592653589793/180.0)*65536));
        bounds_width_i=32; bounds_height_i=16; bounds_a_i=65536;
        bounds_d_i=65536; bounds_src_w_i=64; bounds_src_h_i=32;
        run_bounds();
        if (bounds_empty_o || bounds_origin_x_o!=0 || bounds_origin_y_o!=0 ||
            bounds_width_bytes_o!=66 || bounds_height_o!=17)
            $fatal(1,"FAIL identity source bounds");
        bounds_x_i=32'hffff8000; bounds_y_i=32'hffff8000;
        run_bounds();
        if (bounds_empty_o || bounds_origin_x_o!=0 || bounds_origin_y_o!=0 ||
            bounds_width_bytes_o!=64 || bounds_height_o!=16)
            $fatal(1,"FAIL negative fraction source clipping");
        bounds_x_i=100*65536;
        run_bounds();
        if (!bounds_empty_o) $fatal(1,"FAIL entirely outside source bounds");
        for (trial=0; trial<300; trial++) begin
            bounds_width_i=6'($urandom_range(1,32));
            bounds_height_i=5'($urandom_range(1,16));
            bounds_x_i=32'((int'($urandom_range(0,140))-20)*65536)+$urandom_range(0,65535);
            bounds_y_i=32'((int'($urandom_range(0,140))-20)*65536)+$urandom_range(0,65535);
            bounds_a_i=32'(int'($urandom_range(0,131072))-65536);
            bounds_b_i=32'(int'($urandom_range(0,131072))-65536);
            bounds_c_i=32'(int'($urandom_range(0,131072))-65536);
            bounds_d_i=32'(int'($urandom_range(0,131072))-65536);
            bounds_src_w_i=12'($urandom_range(0,100));
            bounds_src_h_i=12'($urandom_range(0,100));
            min_x=2147483647;min_y=2147483647;
            max_x=-2147483647;max_y=-2147483647;
            for(corner=0;corner<4;corner++) begin
                corner_u=(corner%2==0)?0:int'(bounds_width_i)-1;
                corner_v=(corner/2==0)?0:int'(bounds_height_i)-1;
                cx=$signed(bounds_x_i)+$signed(bounds_a_i)*corner_u+
                    $signed(bounds_b_i)*corner_v;
                cy=$signed(bounds_y_i)+$signed(bounds_c_i)*corner_u+
                    $signed(bounds_d_i)*corner_v;
                if(cx<min_x) min_x=cx;
                if(cx>max_x) max_x=cx;
                if(cy<min_y) min_y=cy;
                if(cy>max_y) max_y=cy;
            end
            min_x=min_x>>>16;min_y=min_y>>>16;
            max_x=(max_x>>>16)+1;max_y=(max_y>>>16)+1;
            expect_empty=bounds_src_w_i==0 || bounds_src_h_i==0 || max_x<0 || max_y<0 ||
                min_x>=int'(bounds_src_w_i) || min_y>=int'(bounds_src_h_i);
            expect_x=(min_x<0)?0:(min_x&~15);
            expect_y=(min_y<0)?0:min_y;
            if(max_x>=int'(bounds_src_w_i)) max_x=int'(bounds_src_w_i)-1;
            if(max_y>=int'(bounds_src_h_i)) max_y=int'(bounds_src_h_i)-1;
            expect_width=(max_x-expect_x+1)*2;
            expect_height=max_y-expect_y+1;
            run_bounds();
            if(bounds_empty_o!==expect_empty || (!expect_empty &&
                (bounds_origin_x_o!==12'(expect_x)||bounds_origin_y_o!==12'(expect_y)||
                bounds_width_bytes_o!==16'(expect_width)||
                bounds_height_o!==12'(expect_height))))
                $fatal(1,"FAIL random source bounds trial=%d",trial);
        end
        $display("PASS geo_math descriptor masks, range boundary and source bounds");
        $finish;
    end
endmodule
