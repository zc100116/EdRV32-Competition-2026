// File: tb.sv
// Spec: rnd-spec v0.2 2-7.
// Description: End-to-end DMA byte-enable and command-sequencing tests with an independent
//              integer renderer and an AXI memory model that delays B responses.
// Clock domain: clk_mem.
module tb;
    localparam int MEM_SIZE=8388608;
    localparam reg [31:0] BASE=32'h80000000;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0;
    reg [11:0] paddr=0;
    reg psel=0;
    reg penable=0;
    reg pwrite=0;
    reg [31:0] pwdata=0;
    wire [31:0] prdata;
    wire pready,pslverr,irq;
    wire arid,arvalid;
    wire [31:0] araddr;
    wire [3:0] arlen;
    wire arready;
    reg rvalid=0;
    reg [255:0] rdata;
    reg [1:0] rresp=0;
    reg rlast=0;
    wire rready;
    wire awid,awvalid;
    wire [31:0] awaddr;
    wire [3:0] awlen;
    wire awready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    wire wlast,wvalid,wready;
    reg bvalid=0;
    reg [1:0] bresp=0;
    wire bready;
    reg [7:0] memory [0:MEM_SIZE-1];
    reg [7:0] expected [0:MEM_SIZE-1];
    reg read_active=0;
    reg write_active=0;
    int read_left=0,write_left=0,bdelay=0;
    reg [31:0] read_addr,write_addr;
    int cycle=0;
    bit random_stalls=1;
    bit inject_read=0,inject_write=0;
    bit perf_mode=0;
    bit check_chunk_overlap=0;
    bit checked_chunk_overlap=0;
    int common_issued=0;
    int common_returned=0;
    // A loaded second chunk must start before the first chunk's alpha results drain.
    always @(posedge clk) begin
        if(check_chunk_overlap) begin
            if(u_dut.draw_blend_valid_w && u_dut.blend_ready_w) begin
                if(common_issued==256) begin
                    if(common_returned>=256)
                        $fatal(1,"common chunk issue waited for alpha: issued=%0d returned=%0d",
                            common_issued,common_returned);
                    checked_chunk_overlap=1;
                end
                common_issued++;
            end
            if(u_dut.blend_valid_w) common_returned++;
        end
    end

    int compare_size=65536;
    int cases=0;
    assign arready=!read_active && !rvalid && (!random_stalls || cycle%5!=0);
    assign awready=!write_active && bdelay==0 && !bvalid && (!random_stalls || cycle%7!=0);
    assign wready=write_active && (!random_stalls || cycle%4!=0);
    edrv32_rnd u_dut (
        .clk_mem_i(clk), .rst_mem_n_i(rst_n),
        .apb_paddr_i(paddr), .apb_psel_i(psel), .apb_penable_i(penable),
        .apb_pwrite_i(pwrite), .apb_pwdata_i(pwdata), .apb_pstrb_i(4'b0000),
        .apb_pready_o(pready), .apb_prdata_o(prdata), .apb_pslverr_o(pslverr),
        .p4_arid_o(arid), .p4_araddr_o(araddr), .p4_arlen_o(arlen),
        .p4_arvalid_o(arvalid), .p4_arready_i(arready), .p4_rid_i(1'b0),
        .p4_rdata_i(rdata), .p4_rresp_i(rresp), .p4_rlast_i(rlast),
        .p4_rvalid_i(rvalid), .p4_rready_o(rready),
        .p4_awid_o(awid), .p4_awaddr_o(awaddr), .p4_awlen_o(awlen),
        .p4_awvalid_o(awvalid), .p4_awready_i(awready), .p4_wdata_o(wdata),
        .p4_wstrb_o(wstrb), .p4_wlast_o(wlast), .p4_wvalid_o(wvalid),
        .p4_wready_i(wready), .p4_bid_i(1'b0), .p4_bresp_i(bresp),
        .p4_bvalid_i(bvalid), .p4_bready_o(bready), .irq_o(irq)
    );
    function automatic int idx(input reg [31:0] addr);
        return int'((addr-BASE)&32'h007fffff);
    endfunction
    function automatic reg[255:0] read_beat(input reg[31:0] addr);
        reg[255:0] value;
        for(int i=0;i<32;i++) value[i*8+:8]=memory[idx(addr+32'(i))];
        return value;
    endfunction
    always @(posedge clk) begin
        cycle<=cycle+1;
        if(arvalid && arready) begin
            if(arid || araddr[4:0]!=0 || int'(araddr[11:0])+32*(int'(arlen)+1)>4096)
                $fatal(1,"invalid AR addr=%h len=%0d t=%0t",araddr,arlen,$time);
            read_active<=1;
            read_addr<=araddr;
            read_left<=int'(arlen)+1;
            rresp<=inject_read ? 2'b10 : 2'b00;
        end
        if(read_active && (!rvalid || rready)) begin
            rdata<=read_beat(read_addr);
            rvalid<=1;
            rlast<=read_left==1;
            read_addr<=read_addr+32;
            read_left<=read_left-1;
            if(read_left==1) read_active<=0;
        end else if(rvalid && rready) rvalid<=0;
        if(awvalid && awready) begin
            if(awid || awaddr[4:0]!=0 || int'(awaddr[11:0])+32*(int'(awlen)+1)>4096)
                $fatal(1,"invalid AW addr=%h len=%0d t=%0t",awaddr,awlen,$time);
            write_active<=1;
            write_addr<=awaddr;
            write_left<=int'(awlen)+1;
        end
        if(wvalid && wready) begin
            if(wlast !== (write_left==1)) $fatal(1,"WLAST t=%0t",$time);
            for(int i=0;i<32;i++) if(wstrb[i]) memory[idx(write_addr+32'(i))]=wdata[i*8+:8];
            write_addr<=write_addr+32;
            write_left<=write_left-1;
            if(write_left==1) begin
                write_active<=0;
                bdelay<=5;
                bresp<=inject_write ? 2'b10 : 2'b00;
            end
        end
        if(bdelay>0) begin
            bdelay<=bdelay-1;
            if(bdelay==1) bvalid<=1;
        end
        if(bvalid && bready) bvalid<=0;
    end
    task automatic apb_write(input reg[11:0] addr,input reg[31:0] value);
        @(negedge clk);
        paddr=addr; psel=1; penable=0; pwrite=1; pwdata=value;
        @(negedge clk);
        penable=1;
        @(negedge clk);
        psel=0; penable=0; pwrite=0;
    endtask
    task automatic apb_read(input reg[11:0] addr,output reg[31:0] value);
        @(negedge clk);
        paddr=addr; psel=1; penable=0; pwrite=0;
        @(negedge clk);
        penable=1;
        #1;
        if(!pready || pslverr) $fatal(1,"APB response t=%0t",$time);
        value=prdata;
        @(negedge clk);
        psel=0; penable=0;
    endtask
    task automatic put(input int word_index,input reg[31:0] value);
        for(int b=0;b<4;b++) memory[word_index*4+b]=value[b*8+:8];
    endtask
    function automatic reg[31:0] load_expected(input reg[31:0] addr,input int bytes_value);
        reg[31:0] value=0;
        for(int b=0;b<bytes_value;b++) value[b*8+:8]=expected[idx(addr+32'(b))];
        return value;
    endfunction
    task automatic store_expected(input reg[31:0] addr,input reg[31:0] value,input int bytes_value);
        for(int b=0;b<bytes_value;b++) expected[idx(addr+32'(b))]=value[b*8+:8];
    endtask
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
    function automatic int root(input longint n);
        longint lo = 0;
        longint hi = 65536;
        longint mid;
        while (hi - lo > 1) begin
            mid = (hi + lo) / 2;
            if (mid * mid <= n) lo = mid;
            else hi = mid;
        end
        return int'(lo);
    endfunction
    function automatic int reference_edge(input int w, h, r, j);
        int limit, yd;
        limit = (w < h ? w : h) / 2;
        if (r > limit) r = limit;
        yd = j < h - 1 - j ? j : h - 1 - j;
        if (r == 0 || yd >= r) return 0;
        return 16*r - root(256*longint'(r)*r - (16*(longint'(r)-longint'(yd))-8)**2);
    endfunction
    function automatic int reference_cov(input int w, i, e);
        int a, b, room_value;
        if (i < 0 || i >= w) return 0;
        a = 16*i + 16-e;
        b = 16*w-e-16*i;
        room_value = a < b ? a : b;
        if (room_value <= 0) return 0;
        if (room_value >= 16) return 255;
        return 16*room_value;
    endfunction
    function automatic reg[31:0] expand_color(input reg[31:0] raw_value,input int format_value);
        if(format_value==1) return raw_value;
        return {8'hff,8'(channel_expand(int'(raw_value),2)),
            8'(channel_expand(int'(raw_value),1)),8'(channel_expand(int'(raw_value),0))};
    endfunction
    function automatic int cov(input int x,y,x0,y0,x1,y1,r);
        if(x<x0 || x>x1 || y<y0 || y>y1 || x1<x0 || y1<y0) return 0;
        return reference_cov(x1-x0+1,x-x0,reference_edge(x1-x0+1,y1-y0+1,r,y-y0));
    endfunction
    function automatic int norm(input int value);
        return (value+127)/255;
    endfunction
    function automatic int grad(input int value,k,input reg signed[31:0] step_value);
        longint signed result_value;
        result_value=(longint'(value)*65536+longint'(k)*longint'(step_value)+32768)>>>16;
        if(result_value<0) return 0;
        if(result_value>255) return 255;
        return int'(result_value);
    endfunction
    function automatic int bpp(input int f);
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
    function automatic reg[31:0] source_color(input reg[31:0] base_value,
        palette_addr,input int pixel_index,f,flags_value,key_value);
        int bits_value,shift_value,sample_value;
        reg[31:0] raw_value;
        bits_value=bpp(f);
        raw_value=load_expected(base_value+32'(pixel_index*bits_value/8),
            bits_value<8 ? 1 : bits_value/8);
        if(f<2) begin
            if(f==0 && (flags_value&4)!=0 && int'(raw_value[15:0])==key_value) return 0;
            return expand_color(raw_value,f);
        end
        shift_value=bits_value>=8 ? 0 : 8-bits_value-(pixel_index*bits_value)%8;
        sample_value=(int'(raw_value)>>shift_value)&((1<<bits_value)-1);
        if(f>=6) return load_expected(palette_addr+32'(sample_value*4),4);
        return {8'(sample_value*255/((1<<bits_value)-1)),24'd0};
    endfunction
    task automatic model_command(input int descriptor_index);
        reg[31:0] c[0:15];
        reg[31:0] horizontal[0:16383];
        reg[31:0] snapshot[0:16383];
        int op_value,fmt_value,dformat,flags_value,x0,y0,x1,y1,l,t,r,b,w,h,bytes_value;
        int a,rad,blur_value,ix0,iy0,ix1,iy1,inner_radius,k,sa,mode_input;
        int sx,sy,u,v,tt,tx,ty,entry_value,grid_w,grid_h,grid_l,grid_t,m;
        int sums[0:3];
        reg[31:0] color_value,dest_value,address_value,pixel_value,palette_addr;
        for(int n=0;n<16;n++) c[n]=load_expected(BASE+32'(descriptor_index*64+n*4),4);
        op_value=int'(c[0][7:0]);
        fmt_value=int'(c[0][15:12]);
        dformat=int'(c[0][8]);
        flags_value=int'(c[0][31:16]);
        x0=int'($signed(c[5][15:0])); y0=int'($signed(c[5][31:16]));
        x1=int'($signed(c[6][15:0])); y1=int'($signed(c[6][31:16]));
        w=x1-x0+1; h=y1-y0+1;
        l=x0>int'(c[3][11:0]) ? x0 : int'(c[3][11:0]);
        t=y0>int'(c[3][27:16]) ? y0 : int'(c[3][27:16]);
        r=x1<int'(c[4][11:0]) ? x1 : int'(c[4][11:0]);
        b=y1<int'(c[4][27:16]) ? y1 : int'(c[4][27:16]);
        bytes_value=dformat==1 ? 4 : 2;
        rad=int'(c[8][11:0]);
        a=int'(c[7][31:24]);
        palette_addr=c[13];
        if(op_value==6 || op_value==7) begin
            blur_value=op_value==6 ? int'(c[9][4:0]) : int'(c[8][4:0]);
            m=(65536+blur_value)/(2*blur_value+1);
            if(op_value==6) begin
                grid_l=x0-blur_value; grid_t=y0-blur_value;
                grid_w=w+2*blur_value; grid_h=h+2*blur_value;
                l=grid_l>int'(c[3][11:0]) ? grid_l : int'(c[3][11:0]);
                t=grid_t>int'(c[3][27:16]) ? grid_t : int'(c[3][27:16]);
                r=x1+blur_value<int'(c[4][11:0]) ? x1+blur_value : int'(c[4][11:0]);
                b=y1+blur_value<int'(c[4][27:16]) ? y1+blur_value : int'(c[4][27:16]);
            end else begin
                grid_l=l; grid_t=t; grid_w=r-l+1; grid_h=b-t+1;
            end
            for(int j=0;j<grid_h;j++) for(int i=0;i<grid_w;i++) begin
                for(int ch=0;ch<4;ch++) sums[ch]=0;
                for(int tap=-blur_value;tap<=blur_value;tap++) begin
                    if(op_value==6) begin
                        sums[0]+=cov(grid_l+i+tap,grid_t+j,x0,y0,x1,y1,rad);
                    end else begin
                        sx=i+tap<0 ? 0 : i+tap>=grid_w ? grid_w-1 : i+tap;
                        pixel_value=expand_color(load_expected(c[1]+32'((grid_t+j)*int'(c[2][15:0])+
                            (grid_l+sx)*bytes_value),bytes_value),dformat);
                        if(dformat==0) pixel_value[31:24]=0;
                        for(int ch=0;ch<4;ch++) sums[ch]+=int'(pixel_value[ch*8+:8]);
                    end
                end
                pixel_value=0;
                for(int ch=0;ch<4;ch++) pixel_value[ch*8+:8]=8'((sums[ch]*m+32768)>>16);
                horizontal[j*grid_w+i]=pixel_value;
            end
            for(int j=t;j<=b;j++) for(int i=l;i<=r;i++) begin
                for(int ch=0;ch<4;ch++) sums[ch]=0;
                for(int tap=-blur_value;tap<=blur_value;tap++) begin
                    sy=j-grid_t+tap;
                    if(op_value==6 && (sy<0 || sy>=grid_h)) pixel_value=0;
                    else begin
                        sy=sy<0 ? 0 : sy>=grid_h ? grid_h-1 : sy;
                        pixel_value=horizontal[sy*grid_w+i-grid_l];
                    end
                    for(int ch=0;ch<4;ch++) sums[ch]+=int'(pixel_value[ch*8+:8]);
                end
                pixel_value=0;
                for(int ch=0;ch<4;ch++) pixel_value[ch*8+:8]=8'((sums[ch]*m+32768)>>16);
                address_value=c[1]+32'(j*int'(c[2][15:0])+i*bytes_value);
                if(op_value==6) pixel_value=reference_pixel({8'(norm(a*int'(pixel_value[7:0]))),c[7][23:0]},
                    load_expected(address_value,bytes_value),1'(dformat),0);
                else if(dformat==0) pixel_value={16'd0,pixel_value[23:19],pixel_value[15:10],pixel_value[7:3]};
                store_expected(address_value,pixel_value,bytes_value);
            end
            return;
        end
        if(op_value==5)
            for(int j=t;j<=b;j++) for(int i=l;i<=r;i++)
                snapshot[(j-t)*(r-l+1)+i-l]=load_expected(c[8]+
                    32'((int'(c[10][31:16])+j-y0)*int'(c[9][15:0])+
                    (int'(c[10][15:0])+i-x0)*bytes_value),bytes_value);
        for(int j=t;j<=b;j++) for(int i=l;i<=r;i++) begin
            address_value=c[1]+32'(j*int'(c[2][15:0])+i*bytes_value);
            dest_value=load_expected(address_value,bytes_value);
            color_value={8'hff,c[7][23:0]};
            mode_input=0;
            case(op_value)
                1: begin
                    if((flags_value&1)!=0) begin
                        k=(flags_value&2)!=0 ? j-y0 : i-x0;
                        color_value={8'(grad(int'(c[9][31:24]),k,c[10])),
                            8'(grad(int'(c[9][23:16]),k,c[11])),
                            8'(grad(int'(c[9][15:8]),k,c[12])),
                            8'(grad(int'(c[9][7:0]),k,c[13]))};
                    end
                    color_value[31:24]=8'(norm(norm(a*int'(color_value[31:24]))*
                        cov(i,j,x0,y0,x1,y1,rad)));
                end
                2: begin
                    inner_radius=(w<h ? w:h)/2;
                    if(rad<inner_radius) inner_radius=rad;
                    ix0=x0+((c[9]&32'h00040000)!=0 ? int'(c[9][11:0]) : -inner_radius-1);
                    ix1=x1-((c[9]&32'h00080000)!=0 ? int'(c[9][11:0]) : -inner_radius-1);
                    iy0=y0+((c[9]&32'h00010000)!=0 ? int'(c[9][11:0]) : -inner_radius-1);
                    iy1=y1-((c[9]&32'h00020000)!=0 ? int'(c[9][11:0]) : -inner_radius-1);
                    inner_radius=inner_radius>int'(c[9][11:0]) ? inner_radius-int'(c[9][11:0]) : 0;
                    color_value[31:24]=8'(norm(a*norm(cov(i,j,x0,y0,x1,y1,rad)*
                        (255-cov(i,j,ix0,iy0,ix1,iy1,inner_radius)))));
                end
                3,4: begin
                    if(op_value==4) begin
                        u=int'(c[10][15:0])+int'((64'(int'((flags_value&1)!=0 ? x1-i : i-x0))*64'(c[11]))>>16);
                        v=int'(c[10][31:16])+int'((64'(int'((flags_value&2)!=0 ? y1-j : j-y0))*64'(c[12]))>>16);
                    end else begin
                        u=int'(c[10][15:0])+i-x0; v=int'(c[10][31:16])+j-y0;
                    end
                    color_value=source_color(c[8]+32'(v*int'(c[9][15:0])),palette_addr,
                        u,fmt_value,flags_value,int'(c[14][15:0]));
                    if(op_value==3) color_value[23:0]=c[7][23:0];
                    if(op_value==4 && (flags_value&8)!=0)
                        for(int ch=0;ch<3;ch++) color_value[ch*8+:8]=
                            8'(norm(int'(c[15][31:24])*int'(c[15][ch*8+:8])+
                            (255-int'(c[15][31:24]))*int'(color_value[ch*8+:8])));
                    color_value[31:24]=8'(norm(a*int'(color_value[31:24])));
                    mode_input=op_value==4 ? (flags_value>>4)&7 : 0;
                end
                5: color_value=snapshot[(j-t)*(r-l+1)+i-l];
                8: begin
                    tt=(flags_value&1)!=0 ? 16 : 8;
                    u=int'(c[11][15:0])+i-x0; v=int'(c[11][31:16])+j-y0;
                    entry_value=int'(load_expected(c[9]+32'((v/tt)*int'(c[10][15:0])+2*(u/tt)),2));
                    tx=u%tt; ty=v%tt;
                    if((entry_value&4096)!=0) tx=tt-1-tx;
                    if((entry_value&8192)!=0) ty=tt-1-ty;
                    color_value=source_color(c[8],palette_addr,
                        (entry_value&4095)*tt*tt+ty*tt+tx,fmt_value,flags_value,int'(c[14][15:0]));
                    color_value[31:24]=8'(norm(a*int'(color_value[31:24])));
                end
                default: $fatal(1,"model OP %0d",op_value);
            endcase
            if(op_value!=5) color_value=reference_pixel(color_value,dest_value,1'(dformat),mode_input);
            store_expected(address_value,color_value,bytes_value);
        end
    endtask
    task automatic setup(input int op_value,f,d,flags_value);
        for(int n=0;n<compare_size;n++) memory[n]=8'(n*13+n/257);
        for(int n=0;n<16;n++) put(n,0);
        put(0,32'(op_value)|(32'(f)<<12)|(32'(d)<<8)|(32'(flags_value)<<16));
        put(1,BASE+32'h8000+(d==1 ? 4 : 2));
        put(2,d==1 ? 100 : 50);
        put(3,32'h00010001);
        put(4,32'h0007000c);
        put(5,32'hffff_fffd);
        put(6,32'h0009_000f);
        put(7,32'h9359b2f3);
        put(8,BASE+32'h4000);
        put(9,64);
        put(10,32'h00010003);
        put(11,32'h00010000);
        put(12,32'h00010000);
        put(13,BASE+32'h7000);
        put(14,32'h00001234);
        put(15,32'h6b9f8342);
    endtask
    task automatic execute(input int count_value,input bit compare_value);
        reg[31:0] status_value,irq_value,cur;
        for(int n=0;n<compare_size;n++) expected[n]=memory[n];
        if(compare_value) for(int n=0;n<count_value;n++) model_command(n);
        apb_write(12'h010,3);
        apb_write(12'h020,BASE);
        apb_write(12'h024,32'(count_value));
        apb_write(12'h028,0);
        status_value=1;
        for(int limit_value=0;limit_value<20000000 && status_value[0];limit_value++)
            apb_read(12'h008,status_value);
        if(status_value[0]) $fatal(1,"command timeout case=%0d t=%0t",cases,$time);
        apb_read(12'h010,irq_value);
        apb_read(12'h100,cur);
        if(irq_value!==1 || cur!==32'(count_value) || write_active || read_active || bvalid || rvalid)
            $fatal(1,"completion case=%0d stat=%h cur=%0d t=%0t",cases,irq_value,cur,$time);
        if(compare_value)
            for(int n=0;n<compare_size;n++) begin
                if(n>=32'h10000 && n<32'h20000) continue;
                if(memory[n]!==expected[n])
                    $fatal(1,"memory case=%0d addr=%h want=%h got=%h t=%0t",
                        cases,BASE+32'(n),expected[n],memory[n],$time);
            end
        cases++;
    endtask
    function automatic [31:0] load_memory_word(input int word_index);
        reg [31:0] value;
        for(int byte_index=0;byte_index<4;byte_index++)
            value[byte_index*8+:8]=memory[word_index*4+byte_index];
        return value;
    endfunction
    task automatic performance;
        reg[31:0] cycles_value,pixel_value;
        random_stalls=0;
        compare_size=MEM_SIZE;
        for(int d=0;d<2;d++) begin
            setup(1,0,d,0);
            put(1,BASE+32'h400000); put(2,d==1 ? 5120 : 2560);
            put(3,0); put(4,32'h02cf04ff); put(5,0); put(6,32'h02cf04ff);
            put(7,32'hff55aaf3); put(8,0);
            execute(1,1);
            apb_read(12'h040,cycles_value);
            apb_read(12'h044,pixel_value);
            if(pixel_value!=921600 || cycles_value>(d==1 ? 375000 : 187500))
                $fatal(1,"fill performance fmt=%0d cycles=%0d pixels=%0d",d,cycles_value,pixel_value);
            $display("PERF fill fmt=%0d cycles=%0d pixels=%0d",d,cycles_value,pixel_value);
        end
        setup(4,1,1,0);
        put(1,BASE+32'h400000); put(2,5120); put(3,0); put(4,32'h02cf04ff);
        put(5,0); put(6,32'h02cf04ff); put(8,BASE+32'h10000); put(9,5120); put(10,0);
        execute(1,1);
        apb_read(12'h040,cycles_value);
        apb_read(12'h044,pixel_value);
        if(pixel_value!=921600 || cycles_value>614400)
            $fatal(1,"BLIT throughput cycles=%0d pixels=%0d",cycles_value,pixel_value);
        $display("PERF BLIT cycles=%0d pixels=%0d",cycles_value,pixel_value);
        if(!$test$plusargs("R1_BASELINE") && cycles_value>485052)
            $fatal(1,"R-R2 ARGB regression cycles=%0d pixels=%0d",cycles_value,pixel_value);
        for(int scale_value=1;scale_value<=3;scale_value+=2) begin
            setup(4,6,0,0);
            put(1,BASE+32'h400000); put(2,32'(512*scale_value)); put(3,0);
            put(4,{16'(240*scale_value-1),16'(256*scale_value-1)}); put(5,0);
            put(6,{16'(240*scale_value-1),16'(256*scale_value-1)});
            put(8,BASE+32'h10000); put(9,256); put(10,0);
            put(11,scale_value==1 ? 32'h10000 : 32'h5555);
            put(12,scale_value==1 ? 32'h10000 : 32'h5555);
            common_issued=0; common_returned=0; checked_chunk_overlap=0;
            check_chunk_overlap=scale_value==3 && !$test$plusargs("R1_BASELINE");
            execute(1,1);
            if(check_chunk_overlap && !checked_chunk_overlap)
                $fatal(1,"common chunk overlap was not observed");
            check_chunk_overlap=0;
            apb_read(12'h040,cycles_value);
            apb_read(12'h044,pixel_value);
            if(pixel_value!=32'(61440*scale_value*scale_value))
                $fatal(1,"I8 pixel count scale=%0d got=%0d",scale_value,pixel_value);
            $display("PERF I8 scale=%0d cycles=%0d pixels=%0d",scale_value,cycles_value,pixel_value);
            if(!$test$plusargs("R1_BASELINE") && cycles_value>32'(40960*scale_value*scale_value))
                $fatal(1,"R-R2 I8 throughput scale=%0d cycles=%0d",scale_value,cycles_value);
        end
        setup(3,2,1,0);
        put(1,BASE+32'h400000); put(2,1024); put(3,0); put(4,32'h003f00ff);
        put(5,0); put(6,32'h003f00ff); put(8,BASE+32'h10000); put(9,256); put(10,0);
        execute(1,1);
        apb_read(12'h040,cycles_value); apb_read(12'h044,pixel_value);
        if(pixel_value!=16384 || (!$test$plusargs("R1_BASELINE") && cycles_value>10922))
            $fatal(1,"A8 GLYPH throughput cycles=%0d pixels=%0d",cycles_value,pixel_value);
        $display("PERF A8 GLYPH cycles=%0d pixels=%0d",cycles_value,pixel_value);
        setup(3,3,1,0);
        put(1,BASE+32'h400000); put(2,64); put(3,0); put(4,32'h0013000f);
        put(5,0); put(6,32'h0013000f); put(8,BASE+32'h20000); put(9,8); put(10,0);
        for(int descriptor=1;descriptor<1000;descriptor++)
            for(int word_index=0;word_index<16;word_index++)
                put(descriptor*16+word_index,load_memory_word(word_index));
        execute(1000,1);
        apb_read(12'h040,cycles_value); apb_read(12'h044,pixel_value);
        if(pixel_value!=320000) $fatal(1,"A4 GLYPH count=%0d",pixel_value);
        $display("PERF 1000 A4 GLYPH cycles=%0d pixels=%0d avg_cycles=%0f",
            cycles_value,pixel_value,real'(cycles_value)/1000.0);
        setup(8,6,0,1);
        put(1,BASE+32'h400000); put(2,2560); put(3,0); put(4,32'h02cf04ff);
        put(5,0); put(6,32'h02cf04ff); put(8,BASE+32'h20000);
        put(9,BASE+32'h6000); put(10,160); put(11,0); put(13,BASE+32'h9000);
        for(int tile_index=0;tile_index<80*45;tile_index++) begin
            memory[32'h6000+tile_index*2]=8'(tile_index%256);
            memory[32'h6001+tile_index*2]=8'((tile_index%4)<<4);
        end
        execute(1,1);
        apb_read(12'h040,cycles_value); apb_read(12'h044,pixel_value);
        if(pixel_value!=921600 || (!$test$plusargs("R1_BASELINE") && cycles_value>921600))
            $fatal(1,"TILEMAP throughput cycles=%0d pixels=%0d",cycles_value,pixel_value);
        $display("PERF TILEMAP cycles=%0d pixels=%0d",cycles_value,pixel_value);
        setup(1,0,1,0);
        put(1,BASE+32'h400000); put(2,4096); put(3,0); put(4,32'h01ff03ff);
        put(5,0); put(6,32'h01ff03ff); put(8,16);
        execute(1,1);
        apb_read(12'h040,cycles_value); apb_read(12'h044,pixel_value);
        if(pixel_value!=524288 || (!$test$plusargs("R1_BASELINE") && cycles_value>349525))
            $fatal(1,"round FILL throughput cycles=%0d pixels=%0d",cycles_value,pixel_value);
        $display("PERF round FILL cycles=%0d pixels=%0d",cycles_value,pixel_value);
        $display("PASS RND throughput and pixel comparisons");
        $finish;
    endtask
    initial begin
        reg[31:0] value;
        repeat(4) @(negedge clk);
        rst_n=1;
        apb_read(0,value);
        if(value!==32'h00040001) $fatal(1,"ID %h",value);
        if($test$plusargs("PERF")) performance();
        apb_write(12'h00c,3);
        for(int d=0;d<2;d++) begin
            setup(1,0,d,0); put(8,0); put(7,32'hff59b2f3); execute(1,1);
            setup(1,9,d,0); put(8,4); execute(1,1);
            begin
                int read_beats_value,bytes_per_pixel,stride_value;
                bytes_per_pixel=d==1 ? 4 : 2;
                stride_value=d==1 ? 100 : 50;
                read_beats_value=2;
                for(int j=1;j<=7;j++) read_beats_value+=
                    (((2*bytes_per_pixel+j*stride_value)%32)+12*bytes_per_pixel+31)/32;
                apb_read(12'h048,value);
                if(value!==32'(read_beats_value))
                    $fatal(1,"FILL ignored SRC_FMT caused source reads want=%0d got=%0d",
                        read_beats_value,value);
            end
            setup(1,0,d,3); put(8,5); put(9,32'h7f08f529);
            put(10,32'h00004000); put(11,32'hfffe2000); put(12,32'h00024000);
            put(13,32'h00018000); execute(1,1);
            setup(1,0,d,1); put(8,4095); put(9,32'hf052a670);
            put(10,32'hffffa000); put(11,32'h0000a000); put(12,32'hffff6000);
            put(13,32'h0002a000); execute(1,1);
            for(int sides=0;sides<16;sides++) begin
                setup(2,0,d,0); put(8,5); put(9,(32'(sides)<<16)|3); execute(1,1);
            end
            for(int f=2;f<6;f++) begin setup(3,f,d,0); execute(1,1); end
            for(int f=0;f<10;f++) begin
                if(f>=2 && f<=5) continue;
                for(int mode_value=0;mode_value<4;mode_value++) begin
                    setup(4,f,d,(mode_value<<4)|15);
                    put(11,32'h0000b000); put(12,32'h00018000); execute(1,1);
                end
            end
            for(int direction=0;direction<4;direction++) begin
                setup(5,d,d,0); put(9,d==1 ? 100 : 50);
                put(8,BASE+32'h8000+(d==1 ? 4 : 2));
                put(10,{16'(direction<2 ? 3 : 0),16'(direction%2==0 ? 5 : 0)});
                execute(1,1);
            end
            for(int tile_value=0;tile_value<2;tile_value++)
                for(int f=0;f<8;f++) begin
                    if(f>=2 && f<=5) continue;
                    setup(8,f,d,tile_value|4); put(8,BASE+32'h4000);
                    put(9,BASE+32'h6000); put(10,16); put(11,32'h00070006);
                    for(int n=0;n<64;n++) begin
                        memory[32'h6000+n*2]=8'(n%3);
                        memory[32'h6001+n*2]=8'((n%4)<<4);
                    end
                    execute(1,1);
                end
            for(int radius_value=0;radius_value<3;radius_value++) begin
                setup(7,0,d,0); put(8,32'(radius_value)); put(9,BASE+32'h10000);
                execute(1,1);
                setup(6,0,d,0); put(8,4); put(9,32'(radius_value)); put(10,BASE+32'h10000);
                execute(1,1);
            end
        end
        if($test$plusargs("FULL")) begin
            for(int d=0;d<2;d++) begin
                setup(7,0,d,0); put(8,31); put(9,BASE+32'h10000); execute(1,1);
                setup(6,0,d,0); put(8,4095); put(9,31); put(10,BASE+32'h10000); execute(1,1);
            end
        end
        if($test$plusargs("FULL")) begin
            // Source pixels straddle beats; the two lanes can require four separate beats.
            for(int source_format=0;source_format<2;source_format++) begin
                setup(4,source_format,1,0);
                put(1,BASE+32'h8004); put(2,160); put(3,0); put(4,32'h00020024);
                put(5,0); put(6,32'h00020024); put(8,BASE+32'h401f);
                put(9,103); put(10,0); execute(1,1);
                setup(4,source_format,1,3);
                // rnd 2.5: sparse samples include 0x801f; keep the target disjoint.
                put(1,BASE+32'h1004); put(2,80); put(3,0); put(4,32'h00010012);
                put(5,0); put(6,32'h00010012); put(8,BASE+32'h401f);
                put(9,257); put(10,0);
                put(11,source_format==0 ? 32'h04000000 : 32'h02000000);
                execute(1,1);
            end
            // Unaligned palette start and disjoint target chunks across a long row.
            setup(4,6,0,0);
            put(1,BASE+32'h8002); put(2,2112); put(3,0); put(4,32'h00020416);
            put(5,0); put(6,32'h00020416); put(8,BASE+32'h4001); put(9,1053);
            put(10,0); put(13,BASE+32'h7004); execute(1,1);
            for(int source_format=0;source_format<8;source_format++) begin
                if(source_format>=2 && source_format<=5) continue;
                setup(8,source_format,1,0);
                put(1,BASE+32'h8004); put(2,4160); put(3,0); put(4,32'h0002040c);
                put(5,0); put(6,32'h0002040c); put(8,BASE+32'h4000);
                put(9,BASE+32'h6000); put(10,300); put(11,6); put(13,BASE+32'h7004);
                for(int tile_index=0;tile_index<132;tile_index++) begin
                    memory[32'h6000+tile_index*2]=8'(tile_index%3);
                    memory[32'h6001+tile_index*2]=8'((tile_index%4)<<4);
                end
                execute(1,1);
            end
        end
        // Empty and inverted primitives consume only their command beats.
        for(int empty_case=0;empty_case<3;empty_case++) begin
            setup(1,0,1,0); put(8,0); put(7,32'hff123456);
            if(empty_case==0) begin put(5,32'h000a000a); put(6,32'h00050005); end
            if(empty_case==1) begin put(5,0); put(6,32'h00050005); put(3,32'h00060006); end
            if(empty_case==2) begin put(5,32'hfff6fff6); put(6,32'hffffffff); end
            execute(1,1);
            apb_read(12'h048,value);
            if(value!==2) $fatal(1,"empty command read beats %0d",value);
            apb_read(12'h04c,value);
            if(value!==0) $fatal(1,"empty command wrote %0d beats",value);
        end
        // Aligned ARGB8888 streaming path, spanning banks and multiple AXI bursts.
        setup(4,1,1,0); put(1,BASE+32'h8000); put(2,256); put(3,0);
        put(4,32'h0007003f); put(5,0); put(6,32'h0007003f);
        put(9,256); put(10,0); execute(1,1);
        // A second command observes the first command's B-fenced output.
        setup(1,0,1,0); put(8,0); put(7,32'hff123456);
        for(int n=0;n<16;n++) for(int z=0;z<4;z++) memory[64+n*4+z]=memory[n*4+z];
        // rnd 2.5: read the first command's result into a distinct second target.
        put(16,32'h00001104); put(17,BASE+32'h9004);
        put(24,BASE+32'h8004); put(25,100); put(26,0);
        put(27,32'h00010000); put(28,32'h00010000); execute(2,1);
        // Three specified error codes and explicit software clearing.
        for(int error_value=1;error_value<=3;error_value++) begin
            setup(error_value==3 ? 255 : 1,0,1,0); put(8,0); put(7,32'hff123456);
            inject_read=error_value==1; inject_write=error_value==2;
            apb_write(12'h010,3); apb_write(12'h020,BASE); apb_write(12'h024,1);
            apb_write(12'h028,0);
            value=1;
            while(value[0]) apb_read(12'h008,value);
            apb_read(12'h014,value);
            if(value!==32'(error_value)) $fatal(1,"error want=%0d got=%0d",error_value,value);
            apb_read(12'h100,value);
            if(value!==0) $fatal(1,"CUR_DESC on error %0d",value);
            inject_read=0; inject_write=0;
            apb_write(12'h010,2); apb_read(12'h014,value);
            if(value!==0) $fatal(1,"error clear %0d",value);
        end
        // ABORT during a long opaque fill leaves no outstanding transactions and no DONE.
        setup(1,0,1,0); put(8,0); put(7,32'hff123456);
        put(4,32'h001f003f); put(6,32'h001f003f);
        apb_write(12'h010,3); apb_write(12'h020,BASE); apb_write(12'h024,1);
        apb_write(12'h028,0);
        repeat(50) @(negedge clk);
        apb_write(12'h004,4);
        value=1;
        while(value[0]) apb_read(12'h008,value);
        apb_read(12'h010,value);
        if(value!==0 || read_active || write_active || rvalid || bvalid)
            $fatal(1,"abort stat=%h t=%0t",value,$time);
        // Cancel the common pipeline with source reads, alpha results and result writes active.
        for(int abort_case=0;abort_case<2;abort_case++) begin
            setup(abort_case==0 ? 3 : 4,abort_case==0 ? 2 : 6,1,0);
            put(1,BASE+32'h8000); put(2,256); put(3,0); put(4,32'h001f003f);
            put(5,0); put(6,32'h001f003f); put(8,BASE+32'h4000); put(9,64); put(10,0);
            apb_write(12'h010,3); apb_write(12'h020,BASE); apb_write(12'h024,1);
            apb_write(12'h028,0);
            repeat(abort_case==0 ? 100 : 1000) @(negedge clk);
            apb_write(12'h004,4);
            value=1;
            while(value[0]) apb_read(12'h008,value);
            apb_read(12'h010,value);
            if(value!==0 || read_active || write_active || rvalid || bvalid)
                $fatal(1,"common pipeline abort case=%0d stat=%h t=%0t",abort_case,value,$time);
        end
        apb_write(12'h004,8); apb_read(12'h02c,value);
        if(value!==0) $fatal(1,"soft reset DONE_COUNT %0d",value);
        $display("PASS %0d rendered command cases, ordering, three errors and ABORT",cases);
        $finish;
    end
endmodule
