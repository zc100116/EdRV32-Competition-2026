// File: tb.sv
// Spec: geo-spec 2, 4, 5.
// Description: Independent formula-based unit checks.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = !clk;
    reg s_clk_i;
    reg s_wr_en_i;
    reg s_wr_group_i;
    reg [6:0] s_wr_row_i;
    reg [2:0] s_wr_word_i;
    reg [255:0] s_wr_data_i;
    reg s_rd_en_i;
    reg s_rd_group_i;
    reg [31:0] s_x_i;
    reg [31:0] s_y_i;
    reg [11:0] s_origin_x_i;
    reg [11:0] s_origin_y_i;
    reg [11:0] s_src_w_i;
    reg [11:0] s_src_h_i;
    reg [15:0] s_bg_i;
    wire [15:0] s_p00_o;
    wire [15:0] s_p01_o;
    wire [15:0] s_p10_o;
    wire [15:0] s_p11_o;
    edrv32_geo_source u_s_ (
        .clk_i(s_clk_i),
        .wr_en_i(s_wr_en_i),
        .wr_group_i(s_wr_group_i),
        .wr_row_i(s_wr_row_i),
        .wr_word_i(s_wr_word_i),
        .wr_data_i(s_wr_data_i),
        .rd_en_i(s_rd_en_i),
        .rd_group_i(s_rd_group_i),
        .x_i(s_x_i),
        .y_i(s_y_i),
        .origin_x_i(s_origin_x_i),
        .origin_y_i(s_origin_y_i),
        .src_w_i(s_src_w_i),
        .src_h_i(s_src_h_i),
        .bg_i(s_bg_i),
        .p00_o(s_p00_o),
        .p01_o(s_p01_o),
        .p10_o(s_p10_o),
        .p11_o(s_p11_o)
    );
    integer group_idx;
    integer row_idx;
    integer word_idx;
    integer lane;
    integer trial;
    integer x;
    integer y;
    integer ox;
    integer oy;
    integer phase;
    reg [15:0] expected [0:3];
    function automatic [15:0] pattern(input integer px,py,gr);
        pattern=16'(px*31+py*211+gr*9127);
    endfunction
    function automatic [15:0] sample(input integer px,py,gr,w,h);
        if(px<0 || py<0 || px>=w || py>=h) sample=16'hb4e9;
        else sample=pattern(px,py,gr);
    endfunction
    initial begin

        s_wr_en_i = 0;
        s_wr_group_i = 0;
        s_wr_row_i = 0;
        s_wr_word_i = 0;
        s_wr_data_i = 0;
        s_rd_en_i = 0;
        s_rd_group_i = 0;
        s_x_i = 0;
        s_y_i = 0;
        s_origin_x_i = 0;
        s_origin_y_i = 0;
        s_src_w_i = 0;
        s_src_h_i = 0;
        s_bg_i = 0;
        s_bg_i=16'hb4e9;
        for(phase=0;phase<2;phase++) begin
            ox=(phase==0)?0:16;oy=(phase==0)?0:3;
            s_origin_x_i=12'(ox);s_origin_y_i=12'(oy);
            for(group_idx=0;group_idx<2;group_idx++)
                for(row_idx=0;row_idx<80;row_idx++)
                    for(word_idx=0;word_idx<6;word_idx++) begin
                        @(negedge clk);
                        s_wr_en_i=1;s_wr_group_i=1'(group_idx);
                        s_wr_row_i=7'(row_idx);s_wr_word_i=3'(word_idx);
                        for(lane=0;lane<16;lane++)
                            s_wr_data_i[lane*16 +: 16]=
                                pattern(ox+word_idx*16+lane,oy+row_idx,group_idx);
                    end
            @(negedge clk);s_wr_en_i=0;
            for(trial=0;trial<1200;trial++) begin
                if(phase==0) begin
                    s_src_w_i=(trial%5==0)?0:((trial%5==1)?1:80);
                    s_src_h_i=(trial%7==0)?0:((trial%7==1)?1:80);
                    x=int'($urandom_range(0,85))-3;
                    y=int'($urandom_range(0,85))-3;
                    if(trial<16) begin x=trial%4-2;y=trial/4-2;end
                end else begin
                    s_src_w_i=96;s_src_h_i=83;
                    x=ox+int'($urandom_range(0,78));
                    y=oy+int'($urandom_range(0,78));
                end
                group_idx=trial%2;
                s_rd_en_i=1;s_rd_group_i=1'(group_idx);
                s_x_i=32'(x*65536+32768);s_y_i=32'(y*65536+65280);
                expected[0]=sample(x,y,group_idx,int'(s_src_w_i),int'(s_src_h_i));
                expected[1]=sample(x+1,y,group_idx,int'(s_src_w_i),int'(s_src_h_i));
                expected[2]=sample(x,y+1,group_idx,int'(s_src_w_i),int'(s_src_h_i));
                expected[3]=sample(x+1,y+1,group_idx,int'(s_src_w_i),int'(s_src_h_i));
                @(posedge clk);#1;
                if({s_p11_o,s_p10_o,s_p01_o,s_p00_o}!==
                    {expected[3],expected[2],expected[1],expected[0]})
                    $fatal(1,"FAIL source phase=%d group=%d x=%d y=%d exp=%h got=%h",
                        phase,group_idx,x,y,
                        {expected[3],expected[2],expected[1],expected[0]},
                        {s_p11_o,s_p10_o,s_p01_o,s_p00_o});
                @(negedge clk);
            end
        end
        $display("PASS geo_source bank addressing, groups, clipping and background samples");
        $finish;
    end
    always @(*) s_clk_i=clk;
endmodule
