// File: tb.sv
// Spec: rnd-spec 2.2.
// Description: Independent integer-division reference; exhaustive alpha pairs, all modes,
//              RGB565 and ARGB8888, saturated colors, random stalls and pipeline clear.
// Clock domain: clk_mem.
module tb;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0;
    reg clear_value=0;
    reg valid=0;
    wire ready;
    reg [63:0] src;
    reg [63:0] dst;
    reg argb_value;
    reg [1:0] mode_value;
    reg [31:0] tag;
    wire out_valid;
    reg out_ready=0;
    wire [63:0] pixels;
    wire [31:0] out_tag;
    wire [39:0] out_offset;
    reg [63:0] expected[$];
    reg [31:0] tags[$];
    int checked=0;
    int stalls=0;
    edrv32_rnd_alpha_pipe u_alpha (
        .clk_i(clk), .rst_n_i(rst_n), .in_valid_i(valid), .in_ready_o(ready),
        .in_src_i(src), .in_dst_i(dst), .in_argb_i(argb_value), .in_mode_i(mode_value),
        .in_tag_i(tag), .out_valid_o(out_valid), .out_ready_i(out_ready),
        .out_pixel_o(pixels), .out_tag_o(out_tag), .out_offset_o(out_offset), .clear_i(clear_value)
    );
    function automatic int channel_expand(input int value,input int channel_value);
        case(channel_value)
            0: return ((value&31)<<3)|((value&31)>>2);
            1: return (((value>>5)&63)<<2)|(((value>>5)&63)>>4);
            2: return (((value>>11)&31)<<3)|(((value>>11)&31)>>2);
            default: return 0;
        endcase
    endfunction
    function automatic reg [31:0] reference_pixel(input reg[31:0] source_value,
        destination_value,input bit is_argb,input int mode_input);
        int sa,da,oa,ratio,q,sc,dc,tc,c;
        reg [23:0] color_value;
        sa=int'(source_value[31:24]);
        if(sa==0) return destination_value;
        da=is_argb ? int'(destination_value[31:24]) : 255;
        oa=sa+((255-sa)*da+127)/255;
        q=oa==0 ? 0 : (255*65536+oa/2)/oa;
        ratio=is_argb ? (sa*q+32768)/65536 : sa;
        for(c=0;c<3;c++) begin
            sc=int'(source_value[8*c+:8]);
            dc=is_argb ? int'(destination_value[8*c+:8]) : channel_expand(int'(destination_value),c);
            case(mode_input)
                0: tc=sc;
                1: tc=sc+dc>255 ? 255 : sc+dc;
                2: tc=dc<sc ? 0 : dc-sc;
                3: tc=(sc*dc+127)/255;
                default: tc=0;
            endcase
            color_value[c*8+:8]=8'((ratio*tc+(255-ratio)*dc+127)/255);
        end
        if(is_argb) return oa==0 ? 32'd0 : {8'(oa),color_value};
        return {16'd0,color_value[23:19],color_value[15:10],color_value[7:3]};
    endfunction
    always @(posedge clk) begin
        reg [63:0] want;
        reg [31:0] want_tag;
        if(rst_n && !clear_value && out_valid && out_ready) begin
            if(expected.size()==0) $fatal(1,"unexpected alpha output t=%0t",$time);
            want=expected.pop_front();
            want_tag=tags.pop_front();
            if(pixels !== want || out_tag !== want_tag)
                $fatal(1,"alpha tag=%0d want_tag=%0d want=%h got=%h t=%0t",
                    out_tag,want_tag,want,pixels,$time);
            for (int quadrant=0;quadrant<8;quadrant++)
                if(out_offset[quadrant*5+:5] !== want_tag[4:0])
                    $fatal(1,"alpha offset quadrant=%0d tag=%h offset=%h t=%0t",
                        quadrant,want_tag,out_offset,$time);
            checked++;
        end
    end
    task automatic send_pair(input int sa,da,m,d);
        reg [63:0] want;
        @(negedge clk);
        src={$urandom,$urandom};
        dst={$urandom,$urandom};
        src[31:24]=8'(sa);
        src[63:56]=8'(255-sa);
        dst[31:24]=8'(da);
        dst[63:56]=8'(255-da);
        argb_value=1'(d);
        mode_value=2'(m);
        tag=32'(checked+expected.size());
        valid=1;
        out_ready=$urandom_range(0,7)!=0;
        want={reference_pixel(src[63:32],dst[63:32],argb_value,m),
            reference_pixel(src[31:0],dst[31:0],argb_value,m)};
        #1;
        while(!ready) begin
            stalls++;
            @(negedge clk);
            out_ready=$urandom_range(0,7)!=0;
            #1;
        end
        expected.push_back(want);
        tags.push_back(tag);
        @(posedge clk);
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        for(int d=0;d<2;d++)
            for(int m=0;m<4;m++)
                for(int sa=0;sa<256;sa++)
                    for(int da=0;da<256;da++) send_pair(sa,da,m,d);
        @(negedge clk);
        valid=0;
        out_ready=1;
        while(expected.size()!=0) @(negedge clk);
        if(checked!=524288 || stalls==0) $fatal(1,"alpha coverage checked=%0d stalls=%0d",checked,stalls);
        repeat(4) send_pair(128,128,0,1);
        @(negedge clk);
        clear_value=1;
        valid=0;
        expected.delete();
        tags.delete();
        @(negedge clk);
        clear_value=0;
        repeat(12) @(negedge clk);
        if(out_valid) $fatal(1,"pipeline clear failed t=%0t",$time);
        $display("PASS 1048576 pixels: exhaustive sa/Da, modes, formats and backpressure");
        $finish;
    end
endmodule
