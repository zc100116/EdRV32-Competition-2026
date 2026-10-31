// File: tb.sv
// Spec: pix-spec 2.6-2.9, 4, 5; frame-control and register unit coverage.
// Description: Check frame ownership, incomplete discard, reset timing and shadow controls.
// Clock: clk_mem model.
module tb;
    bit clk=0;
    always #4 clk=~clk;
    bit rst_n=0;
    bit in_valid=0;
    wire in_ready;
    logic [31:0] in_data;
    bit in_sof=0;
    bit in_eol=0;
    bit in_eof=0;
    wire out_valid;
    bit out_ready=1;
    wire [31:0] out_data;
    wire out_sof;
    wire out_eol;
    wire out_eof;
    logic [11:0] paddr=0;
    bit psel=0;
    bit penable=0;
    bit pwrite=0;
    logic [31:0] pwdata=0;
    logic [3:0] pstrb=0;
    wire pready;
    wire [31:0] prdata;
    wire pslverr;
    wire irq;
    int width;
    int height;
    int received=0;
    int cycle=0;
    int eof_cycle=0;
    int sof_cycle=0;
    int first_cycle=0;
    int stall_in=0;
    int stall_out=0;
    int completed=0;
    int flush_limit=0;
    bit checking=0;
    bit partial_frame=0;
    bit random_ready=0;
    bit stalled=0;
    logic [34:0] held;
    logic [15:0] raw[0:6399];
    logic [23:0] image[0:6399];
    logic [23:0] scratch[0:6399];
    logic [31:0] expected[0:3199];
    logic [31:0] model_cfg=0;
    logic [31:0] model_bc=256;
    int model_thresh=128;
    bit model_enable=0;
    `include "pix_ref.svh"

    edrv32_pix dut (
        .clk_mem_i(clk),
        .rst_mem_n_i(rst_n),
        .pix_in_valid_i(in_valid),
        .pix_in_ready_o(in_ready),
        .pix_in_data_i(in_data),
        .pix_in_sof_i(in_sof),
        .pix_in_eol_i(in_eol),
        .pix_in_eof_i(in_eof),
        .pix_out_valid_o(out_valid),
        .pix_out_ready_i(out_ready),
        .pix_out_data_o(out_data),
        .pix_out_sof_o(out_sof),
        .pix_out_eol_o(out_eol),
        .pix_out_eof_o(out_eof),
        .apb_paddr_i(paddr),
        .apb_psel_i(psel),
        .apb_penable_i(penable),
        .apb_pwrite_i(pwrite),
        .apb_pwdata_i(pwdata),
        .apb_pstrb_i(pstrb),
        .apb_pready_o(pready),
        .apb_prdata_o(prdata),
        .apb_pslverr_o(pslverr),
        .irq_o(irq)
    );

    always @(negedge clk) begin
        if (random_ready) out_ready=cycle%7!=2 && cycle%7!=3;
    end
    always @(posedge clk) begin
        cycle++;
        if (rst_n) begin
            if (in_valid && !in_ready) stall_in++;
            if (out_valid && !out_ready) stall_out++;
            if (stalled && {out_data,out_sof,out_eol,out_eof}!==held && !in_sof)
                $fatal(1,"FAIL output changed under backpressure t=%0t",$time);
            stalled=out_valid && !out_ready;
            held={out_data,out_sof,out_eol,out_eof};
            if (in_valid && in_ready && in_sof) sof_cycle=cycle;
            if (out_valid && out_ready && out_sof) first_cycle=cycle;
            if (in_valid && in_ready && in_eof) eof_cycle=cycle;
            if (out_valid && out_ready) begin
                if (partial_frame && out_eof) $fatal(1,"FAIL incomplete frame emitted EOF");
                if (checking) begin
                    if (received>=width*height/2) $fatal(1,"FAIL extra control output");
                    if (out_data!==expected[received] || out_sof!==(received==0)
                        || out_eol!==((received+1)%(width/2)==0)
                        || out_eof!==(received==width*height/2-1))
                        $fatal(1,"FAIL control t=%0t size=%0dx%0d cfg=%h beat=%0d exp=%h got=%h flags=%b%b%b",
                            $time,width,height,model_cfg,received,expected[received],out_data,
                            out_sof,out_eol,out_eof);
                    received++;
                end
                if (out_eof) begin
                    completed++;
                    $display("PIX latency cfg=%h width=%0d first=%0d flush=%0d",
                        model_cfg,width,first_cycle-sof_cycle,cycle-eof_cycle);
                    if (flush_limit!=0 && cycle-eof_cycle>flush_limit)
                        $fatal(1,"FAIL top flush cycles=%0d limit=%0d width=%0d",
                            cycle-eof_cycle,flush_limit,width);
                end
            end
        end
    end
    task automatic write_reg(input logic [11:0] addr, input logic [31:0] value);
        @(negedge clk); paddr=addr; pwdata=value; psel=1; pwrite=1; penable=0;
        @(negedge clk); penable=1;
        @(posedge clk); #1;
        if (!pready || pslverr) $fatal(1,"FAIL APB write t=%0t addr=%h",$time,addr);
        @(negedge clk); psel=0; penable=0; pwrite=0;
    endtask
    task automatic read_check(input logic [11:0] addr, input logic [31:0] value);
        @(negedge clk); paddr=addr; psel=1; pwrite=0; penable=0;
        @(negedge clk); penable=1;
        #1;
        if (!pready || pslverr || prdata!==value)
            $fatal(1,"FAIL APB read t=%0t addr=%h exp=%h got=%h",$time,addr,value,prdata);
        @(negedge clk); psel=0; penable=0;
    endtask
    task automatic configure(input bit en, input logic [31:0] cfg,
        input logic [31:0] bc=256, input int threshold=128);
        write_reg(12'h004,{31'd0,en});
        write_reg(12'h100,cfg);
        write_reg(12'h104,bc);
        write_reg(12'h108,32'(threshold));
        model_enable=en; model_cfg=cfg; model_bc=bc; model_thresh=threshold;
    endtask
    function automatic logic [23:0] expand_ref(input logic [15:0] p);
        return {p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
    endfunction
    task automatic prepare(input int w, input int h);
        logic [215:0] win;
        logic [23:0] rgb;
        logic [31:0] cfg;
        int value;
        int xx;
        int yy;
        int op;
        width=w; height=h; received=0;
        flush_limit=w+32;
        cfg=model_enable ? model_cfg : 0;
        for (int n=0; n<w*h; n++) begin
            raw[n]=16'(n*523+32'h4397);
            rgb=expand_ref(raw[n]);
            for (int c=0; c<3; c++) begin
                value=int'(rgb[c*8 +: 8]);
                if (cfg[0]) value=clamp_ref((((value-128)*int'(model_bc[8:0])) >>> 8)
                    +128+int'($signed(model_bc[24:16])));
                // Both top-level tables use distinct mappings and are written below.
                if (cfg[1]) value=cfg[2] ? (value*value+127)/255 : 255-value;
                rgb[c*8 +: 8]=8'(value);
            end
            image[n]=rgb;
        end
        for (int stage=0; stage<2; stage++) begin
            op=stage==0 ? int'(cfg[6:4]) : int'(cfg[10:8]);
            for (int y=0; y<h; y++) begin
                for (int x=0; x<w; x++) begin
                    win=0;
                    for (int dy=-1; dy<=1; dy++) begin
                        for (int dx=-1; dx<=1; dx++) begin
                            xx=x+dx; yy=y+dy;
                            if (xx>=0 && xx<w && yy>=0 && yy<h)
                                win[((dy+1)*3+dx+1)*24 +: 24]=image[yy*w+xx];
                        end
                    end
                    scratch[y*w+x]=window_ref(op,win);
                end
            end
            for (int n=0; n<w*h; n++) image[n]=scratch[n];
        end
        for (int n=0; n<w*h; n++) begin
            rgb=image[n];
            if (cfg[16]) begin
                value=gray_ref(rgb); rgb={8'(value),8'(value),8'(value)};
            end
            if (cfg[17]) rgb=gray_ref(rgb)>=model_thresh ? 24'hffffff : 0;
            if (cfg[18]) rgb=24'hffffff-rgb;
            expected[n/2][(n%2)*16 +: 16]={rgb[23:19],rgb[15:10],rgb[7:3]};
        end
    endtask
    task automatic send_beat(input int index, input bit last, input bit continuous=0);
        int ticks;
        @(negedge clk);
        in_valid=1; in_data={raw[2*index+1],raw[2*index]};
        in_sof=index==0; in_eol=(index+1)%(width/2)==0; in_eof=last;
        ticks=0;
        do begin
            @(posedge clk); #1;
            // The handshake is sampled before the edge by a separate capture below.
            ticks++;
            if (ticks>width*4+120) $fatal(1,"FAIL input timeout t=%0t",$time);
            if (continuous && !accepted) $fatal(1,"FAIL bubble in continuous input");
        end while (!accepted);
    endtask
    bit accepted;
    always @(posedge clk) accepted=in_valid && in_ready;
    task automatic stop_input;
        @(negedge clk); in_valid=0; in_sof=0; in_eol=0; in_eof=0;
    endtask
    task automatic drain;
        int ticks;
        ticks=0;
        stop_input();
        while (received<width*height/2) begin
            @(negedge clk); ticks++;
            if (ticks>width*height*4+120) $fatal(1,"FAIL drain timeout got=%0d",received);
        end
        checking=0;
    endtask
    task automatic frame(input int w, input int h, input bit random_flow=0);
        prepare(w,h); checking=1; random_ready=random_flow;
        flush_limit=random_flow ? 0 : w+32;
        for (int n=0; n<w*h/2; n++) begin
            if (random_flow && n%5==3) begin
                stop_input(); repeat(2) @(negedge clk);
            end
            send_beat(n,n==w*h/2-1,!random_flow);
        end
        drain(); random_ready=0; out_ready=1;
    endtask
    task automatic reset_idle;
        write_reg(12'h004,8);
        repeat(2) @(negedge clk);
        stall_in=0; stall_out=0; completed=0;
        read_check(12'h004,0); read_check(12'h008,2);
        read_check(12'h100,0); read_check(12'h104,256); read_check(12'h108,128);
        read_check(12'h02c,0); read_check(12'h010,0);
        for (int p=0; p<16; p++) read_check(12'(32'h040+p*4),0);
        model_enable=0; model_cfg=0; model_bc=256; model_thresh=128;
    endtask

    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        read_check(12'h000,32'h00020001); read_check(12'h008,2);
        read_check(12'h004,0); read_check(12'h100,0);
        read_check(12'h104,256); read_check(12'h108,128);
        read_check(12'h014,0); read_check(12'h10c,0);
        for (int addr=32'h020; addr<=32'h028; addr+=4) begin
            write_reg(12'(addr),32'hffffffff); read_check(12'(addr),0);
        end
        write_reg(12'h000,0); read_check(12'h000,32'h00020001);
        write_reg(12'h100,32'hffffffff); read_check(12'h100,32'h00070777);
        write_reg(12'h104,32'hffffffff); read_check(12'h104,32'h01ff01ff);
        write_reg(12'h108,32'hffffffff); read_check(12'h108,255);
        write_reg(12'h004,7); read_check(12'h004,1);
        read_check(12'hffc,0); write_reg(12'hffc,32'hffffffff); read_check(12'hffc,0);
        reset_idle();
        // Populate both banks and confirm that later soft resets retain their contents.
        for (int bank=0; bank<2; bank++) begin
            for (int n=0; n<256; n++)
                write_reg(12'h10c,((bank==0 ? 255-n : (n*n+127)/255)<<16)|(bank<<8)|n);
        end
        configure(0,32'h00070777); frame(16,3);
        configure(1,0); frame(8,3);
        configure(1,32'h00000770); frame(2,1);
        // All 49 two-stage combinations, including single-row/narrow-line behavior.
        for (int a=0; a<7; a++) begin
            for (int b=0; b<7; b++) begin
                configure(1,32'((a<<4)|(b<<8)));
                frame(2+(a%3)*2,1+b%3,(a+b)%2==1);
            end
        end
        configure(1,32'h00020423,32'h00ff01ff,128); frame(16,5,1);
        configure(1,32'h00000006); frame(16,3);
        configure(1,32'h00000420); frame(1280,5);
        read_check(12'h02c,32'(completed)); read_check(12'h040,32'(completed));
        read_check(12'h044,32'(stall_in)); read_check(12'h048,32'(stall_out));
        read_check(12'h010,4); read_check(12'h014,0);
        write_reg(12'h00c,4); if (!irq) $fatal(1,"FAIL FRAME irq enable");
        write_reg(12'h010,1); if (!irq) $fatal(1,"FAIL reserved RW1C bit");
        write_reg(12'h010,4); if (irq) $fatal(1,"FAIL FRAME irq clear");
        // Shadow writes are intentionally made while the first frame is incomplete.
        configure(1,32'h00000002); prepare(16,3); checking=1;
        for (int n=0; n<4; n++) send_beat(n,0,1);
        stop_input();
        write_reg(12'h100,32'h00070007); write_reg(12'h104,32'h01000000);
        write_reg(12'h108,255); write_reg(12'h004,0);
        for (int n=4; n<24; n++) send_beat(n,n==23,1);
        drain();
        model_enable=0; model_cfg=32'h00070007; model_bc=32'h01000000; model_thresh=255;
        frame(8,2);
        // Keep the next SOF asserted while the preceding output EOF is backpressured.
        configure(1,32'h00000420); prepare(16,3); checking=1;
        for (int n=0; n<24; n++) send_beat(n,n==23,1);
        stop_input(); out_ready=0;
        @(negedge clk); in_valid=1; in_sof=1; in_eol=0; in_eof=0; in_data=0;
        repeat(6) begin
            @(posedge clk); #1;
            if (in_ready || accepted) $fatal(1,"FAIL next SOF accepted before output EOF");
        end
        // End the probe before allowing the next frame to start.
        stop_input(); out_ready=1; drain();
        // Incomplete input can stop in a row, at EOL, or within its final row.
        for (int cut=0; cut<3; cut++) begin
            int count;
            configure(1,32'h00000650); prepare(8,3); checking=0; partial_frame=1;
            count=cut==0 ? 1 : (cut==1 ? 4 : 9);
            for (int n=0; n<count; n++) send_beat(n,0,1);
            stop_input(); repeat(3) @(negedge clk);
            prepare(6,3);
            @(negedge clk); in_valid=1; in_sof=1; in_data={raw[1],raw[0]};
            in_eol=0; in_eof=0;
            #1; if (in_ready) $fatal(1,"FAIL discard must precede SOF handshake");
            @(posedge clk); #1;
            if (accepted) $fatal(1,"FAIL discard cycle accepted SOF");
            @(negedge clk); checking=1; partial_frame=0;
            @(posedge clk); #1;
            if (!accepted) $fatal(1,"FAIL next SOF after discard");
            for (int n=1; n<9; n++) send_beat(n,n==8,1);
            drain(); read_check(12'h04c,32'(cut+1));
        end
        // Busy reset must preserve the frame and register values until output EOF.
        configure(1,32'h00000420); prepare(16,3); checking=1;
        for (int n=0; n<4; n++) send_beat(n,0,1);
        stop_input(); write_reg(12'h004,9);
        read_check(12'h008,1); read_check(12'h100,32'h00000420);
        // A pending reset rejects new SOFs, but must continue accepting this frame.
        for (int n=4; n<24; n++) send_beat(n,n==23,1);
        drain(); repeat(3) @(negedge clk);
        read_check(12'h008,2); read_check(12'h004,0); read_check(12'h100,0);
        read_check(12'h02c,0); read_check(12'h040,0); read_check(12'h04c,0);
        // Pending reset plus an incomplete frame: discard, reset, then new SOF.
        configure(1,32'h00000110); prepare(8,3); partial_frame=1;
        // SOF accepted on the SOFT_RST access edge belongs to the current frame.
        @(negedge clk);paddr=12'h004;pwdata=9;psel=1;pwrite=1;penable=0;
        @(negedge clk);penable=1;
        in_valid=1;in_sof=1;in_eol=0;in_eof=0;in_data={raw[1],raw[0]};
        @(posedge clk);#1;
        if (!accepted) $fatal(1,"FAIL SOF on reset access edge was not accepted");
        @(negedge clk);psel=0;penable=0;pwrite=0;in_valid=0;in_sof=0;
        repeat(2) @(negedge clk);
        read_check(12'h008,1);
        @(negedge clk); in_valid=1; in_sof=1; in_eol=0; in_eof=0;
        repeat(2) begin
            @(posedge clk); #1;
            if (accepted) $fatal(1,"FAIL SOF accepted during discard/reset");
        end
        @(negedge clk); partial_frame=0;
        // Drop the still-unaccepted probe and exercise the retained Gamma table.
        in_valid=0; in_sof=0;
        read_check(12'h008,2); read_check(12'h04c,0);
        configure(1,32'h00000006); frame(16,3);
        reset_idle(); configure(1,32'h00000002); frame(16,3);
        $display("PASS pix_control: registers, 49 cascades, shadow, frame ownership, abort/reset, max flush");
        $finish;
    end
    initial begin
        #2000000; $fatal(1,"FAIL control global timeout");
    end
endmodule
