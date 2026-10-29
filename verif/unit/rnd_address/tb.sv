// File: tb.sv
// Spec: rnd-spec 2.1, 2.5, 2.6 and 6 error 3.
// Description: Exhaust command legality; independently calculate sampling, tile and mask bytes.
// Clock domain: combinational.
module tb;
    reg [511:0] command_value=0;
    reg [11:0] x=0;
    reg [11:0] y=0;
    reg [15:0] entry_value=0;
    wire illegal;
    wire empty_value;
    wire [7:0] op;
    wire argb_value;
    wire [3:0] fmt;
    wire [15:0] flags_value;
    wire signed [17:0] left_value,top_value,right_value,bottom_value;
    wire [16:0] width_value,height_value;
    wire fast_value;
    wire [31:0] dst_addr,src_addr,map_addr,u,v;
    wire [2:0] shift_value;
    wire [7:0] mask_value;
    reg [31:0] raw_value=0;
    reg [31:0] palette_value=0;
    wire [31:0] pixel_value;
    wire [7:0] index_value;
    edrv32_rnd_decode u_decode (
        .command_i(command_value), .illegal_o(illegal), .empty_o(empty_value),
        .op_o(op), .argb_o(argb_value), .src_fmt_o(fmt), .flags_o(flags_value),
        .left_o(left_value), .top_o(top_value), .right_o(right_value), .bottom_o(bottom_value),
        .width_o(width_value), .height_o(height_value), .fast_fill_o(fast_value)
    );
    edrv32_rnd_address u_address (
        .command_i(command_value), .x_i(x), .y_i(y), .map_entry_i(entry_value),
        .dst_addr_o(dst_addr), .src_addr_o(src_addr), .map_addr_o(map_addr),
        .sub_shift_o(shift_value), .sub_mask_o(mask_value), .sample_x_o(u), .sample_y_o(v)
    );
    edrv32_rnd_source u_source (
        .format_i(fmt), .glyph_i(op==3), .raw_i(raw_value),
        .sub_shift_i(shift_value), .sub_mask_i(mask_value), .palette_i(palette_value),
        .color_i(command_value[247:224]), .opacity_i(command_value[255:248]),
        .colorkey_i(flags_value[2]), .key_i(command_value[463:448]),
        .recolor_i(op==4 && flags_value[3]), .recolor_value_i(command_value[511:480]),
        .index_o(index_value), .pixel_o(pixel_value)
    );
    task automatic word_value(input int n,input int unsigned value);
        command_value[32*n+:32]=value;
    endtask
    function automatic int bytes_bits(input int f);
        case(f)
            0: return 16;
            1: return 32;
            2,6: return 8;
            3,7: return 4;
            4,8: return 2;
            5,9: return 1;
            default: return 0;
        endcase
    endfunction
    function automatic bit legal(input int o,f,d,m);
        case(o)
            1,2,6,7: return 1;
            3: return f>=2 && f<=5;
            4: return (f==0 || f==1 || (f>=6 && f<=9)) && m<=3;
            5: return f==d;
            8: return f==0 || f==1 || f==6 || f==7;
            default: return 0;
        endcase
    endfunction
    initial begin
        command_value='1;
        #1;
        for(int o=0;o<256;o++)
            for(int f=0;f<16;f++)
                for(int d=0;d<2;d++)
                    for(int m=0;m<8;m++) begin
                        word_value(0,32'(o)|(32'(f)<<12)|(32'(d)<<8)|(32'(m)<<20));
                        #1;
                        if(illegal !== !legal(o,f,d,m))
                            $fatal(1,"decode op=%0d fmt=%0d dst=%0d mode=%0d cmd=%h illegal=%b legal=%b t=%0t",
                                o,f,d,m,command_value[31:0],illegal,legal(o,f,d,m),$time);
                    end
        for(int n=0;n<10000;n++) begin
            int o,f,d,x0,y0,x1,y1,sx,sy,sstride,dstride,t,tx,ty,fl;
            longint unsigned ux,vy,bits_value,want_src,want_dst,want_map,kx,ky,scx,scy,source_base;
            o=int'($urandom_range(3,8));
            if(o==6 || o==7) o=4;
            f=int'($urandom_range(0,9));
            d=int'($urandom_range(0,1));
            if(o==3) f=int'($urandom_range(2,5));
            if(o==4 && f>=2 && f<=5) f+=4;
            if(o==5) f=d;
            if(o==8) f=f%4<2 ? f%4 : f%4+4;
            x0=-int'($urandom_range(0,300));
            y0=-int'($urandom_range(0,300));
            x1=int'($urandom_range(100,2000));
            y1=int'($urandom_range(100,2000));
            x=12'($urandom_range(0,x1));
            y=12'($urandom_range(0,y1));
            sx=int'($urandom_range(0,65535));
            sy=int'($urandom_range(0,65535));
            sstride=int'($urandom_range(1,65535));
            dstride=int'($urandom_range(1,65535));
            if(f==0) sstride=(sstride&~1)|2;
            if(f==1) sstride=(sstride&~3)|4;
            dstride=d==1 ? (dstride&~3)|4 : (dstride&~1)|2;
            source_base=o==8 ? 64'h82000000 : f==1 ? 64'h82000004 : 64'h82000002;
            if(o==8) sx=(sx&~1)|2;
            scx=64'($urandom);
            scy=64'($urandom);
            fl=int'($urandom_range(0,3));
            word_value(0,32'(o)|(32'(f)<<12)|(32'(d)<<8)|(32'(fl)<<16));
            word_value(1,32'h81000200);
            word_value(2,32'(dstride));
            word_value(3,0);
            word_value(4,32'h0fff0fff);
            word_value(5,{16'(y0),16'(x0)});
            word_value(6,{16'(y1),16'(x1)});
            word_value(7,32'hff5379bd);
            word_value(8,32'(source_base));
            word_value(9,o==8 ? 32'h83000020 : 32'(sstride));
            word_value(10,{16'(sy),16'(sx)});
            word_value(11,32'(scx));
            word_value(12,32'(scy));
            word_value(13,32'h84000000);
            entry_value=16'($urandom);
            kx=o==4 && (fl&1)!=0 ? 64'(x1)-64'(x) : 64'(x)-64'(x0);
            ky=o==4 && (fl&2)!=0 ? 64'(y1)-64'(y) : 64'(y)-64'(y0);
            ux=64'(sx)+(o==4 ? ((kx*scx)>>16) : kx);
            vy=64'(sy)+(o==4 ? ((ky*scy)>>16) : ky);
            want_map=0;
            if(o==8) begin
                t=(fl&1)!=0 ? 16 : 8;
                ux=64'(command_value[367:352])+kx;
                vy=64'(command_value[383:368])+ky;
                want_map=64'h83000020+(vy/64'(t))*64'(command_value[335:320])+2*(ux/64'(t));
                tx=int'(ux%64'(t));
                ty=int'(vy%64'(t));
                if(entry_value[12]) tx=t-1-tx;
                if(entry_value[13]) ty=t-1-ty;
                bits_value=(64'(entry_value[11:0])*64'(t)*64'(t)+64'(ty)*64'(t)+64'(tx))*
                    64'(bytes_bits(f));
                want_src=source_base+bits_value/8;
            end else begin
                bits_value=ux*64'(bytes_bits(f));
                want_src=source_base+vy*64'(sstride)+bits_value/8;
            end
            want_dst=64'h81000200+64'(y)*64'(dstride)+64'(x)*64'(d==1 ? 4 : 2);
            #1;
            if(src_addr!==32'(want_src) || dst_addr!==32'(want_dst) || u!==32'(ux) || v!==32'(vy))
                $fatal(1,"address op=%0d fmt=%0d want src=%h got=%h t=%0t",o,f,32'(want_src),src_addr,$time);
            if(o==8 && map_addr!==32'(want_map))
                $fatal(1,"map want=%h got=%h t=%0t",32'(want_map),map_addr,$time);
            if(bytes_bits(f)<8) begin
                int expected_shift;
                expected_shift=8-bytes_bits(f)-int'(bits_value%8);
                if(int'(shift_value)!=expected_shift || int'(mask_value)!=(1<<bytes_bits(f))-1)
                    $fatal(1,"sub-byte shift=%0d mask=%h t=%0t",shift_value,mask_value,$time);
            end
        end
        // Independently check all packed alpha samples and bit positions.
        for(int f=2;f<=5;f++) begin
            for(int b=0;b<256;b++) begin
                for(int p=0;p<8/bytes_bits(f);p++) begin
                    int sample_value, alpha_value;
                    word_value(0,3|(32'(f)<<12));
                    word_value(5,0);
                    word_value(6,32'h00100010);
                    word_value(7,32'hff123456);
                    word_value(10,0);
                    x=12'(p);
                    y=0;
                    raw_value=32'(b);
                    sample_value=(b>>(8-bytes_bits(f)*(p+1)))&((1<<bytes_bits(f))-1);
                    alpha_value=sample_value*255/((1<<bytes_bits(f))-1);
                    #1;
                    if(pixel_value!=={8'(alpha_value),24'h123456})
                        $fatal(1,"alpha f=%0d b=%h p=%0d want=%0d got=%h t=%0t",
                            f,b,p,alpha_value,pixel_value,$time);
                end
            end
        end
        $display("PASS exhaustive legality, 10000 addresses and packed mask expansion");
        $finish;
    end
endmodule
