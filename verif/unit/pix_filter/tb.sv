// File: tb.sv
// Spec: pix-spec 2.4, 2.7, 2.9, 7; spatial unit coverage.
// Description: Integer 3x3 reference, all operations, zero padding and small/max lines.
// Clock: clk_mem model.
module tb;
    bit clk=0;
    always #4 clk=~clk;
    bit rst_n=0;
    bit advance=1;
    bit clear=0;
    bit valid=0;
    logic [47:0] data;
    bit sof=0;
    bit eol=0;
    bit eof=0;
    logic [2:0] op;
    wire out_valid;
    wire [47:0] out_data;
    wire out_sof;
    wire out_eol;
    wire out_eof;
    logic [23:0] image[0:6399];
    logic [47:0] expected[0:3199];
    int received=0;
    int width;
    int height;
    int widths[6]='{2,4,6,16,1278,1280};
    int heights[4]='{1,2,3,5};
    int cycle=0;
    int input_eof_cycle;
    int input_sof_cycle;
    int maximum_overhead=0;
    bit checking=0;
    bit bound_enabled=0;
    bit stalled=0;
    logic [51:0] held;
    `include "pix_ref.svh"

    edrv32_pix_filter dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(valid),
        .data_i(data),
        .sof_i(sof),
        .eol_i(eol),
        .eof_i(eof),
        .valid_o(out_valid),
        .data_o(out_data),
        .sof_o(out_sof),
        .eol_o(out_eol),
        .eof_o(out_eof),
        .advance_i(advance),
        .clear_i(clear),
        .op_i(op)
    );
    always @(posedge clk) begin
        cycle++;
        if (rst_n && !clear) begin
            if (stalled && {out_valid,out_data,out_sof,out_eol,out_eof} !== held)
                $fatal(1,"FAIL filter changed during freeze t=%0t",$time);
            stalled=!advance && out_valid;
            held={out_valid,out_data,out_sof,out_eol,out_eof};
            if (checking && bound_enabled && advance && received>0
                && received<width*height/2 && !out_valid)
                $fatal(1,"FAIL filter output bubble t=%0t op=%0d beat=%0d",
                    $time,op,received);
            if (checking && advance && out_valid) begin
                if (received>=width*height/2) $fatal(1,"FAIL extra output t=%0t",$time);
                if (out_data!==expected[received]
                    || out_sof!==(received==0)
                    || out_eol!==((received+1)%(width/2)==0)
                    || out_eof!==(received==width*height/2-1))
                    $fatal(1,"FAIL filter t=%0t op=%0d size=%0dx%0d beat=%0d exp=%h got=%h flags=%b%b%b",
                        $time,op,width,height,received,expected[received],out_data,
                        out_sof,out_eol,out_eof);
                if (out_sof && bound_enabled) begin
                    if (op!=0 && op!=7) begin
                        if (cycle-input_sof_cycle-width/2>16)
                            $fatal(1,"FAIL filter first latency=%0d width=%0d",
                                cycle-input_sof_cycle,width);
                        if (cycle-input_sof_cycle-width/2>maximum_overhead)
                            maximum_overhead=cycle-input_sof_cycle-width/2;
                    end
                end
                if (out_eof && bound_enabled && cycle-input_eof_cycle>width/2+16)
                    $fatal(1,"FAIL flush delay=%0d width=%0d",cycle-input_eof_cycle,width);
                received++;
            end
            if (advance && valid && eof) input_eof_cycle=cycle;
            if (advance && valid && sof) input_sof_cycle=cycle;
        end
    end
    task automatic prepare;
        logic [215:0] win;
        int xx;
        int yy;
        for (int n=0; n<width*height; n++)
            image[n]={8'(n*17+3),8'(n*71+61),8'(n*131+127)};
        for (int y=0; y<height; y++) begin
            for (int x=0; x<width; x++) begin
                win='0;
                for (int dy=-1; dy<=1; dy++) begin
                    for (int dx=-1; dx<=1; dx++) begin
                        xx=x+dx; yy=y+dy;
                        if (xx>=0 && xx<width && yy>=0 && yy<height)
                            win[((dy+1)*3+dx+1)*24 +: 24]=image[yy*width+xx];
                    end
                end
                expected[(y*width+x)/2][(x%2)*24 +: 24]=window_ref(int'(op),win);
            end
        end
    endtask
    task automatic run_frame(input bit gaps);
        int sent;
        int ticks;
        received=0; sent=0; ticks=0; checking=1; bound_enabled=!gaps;
        while (received<width*height/2) begin
            @(negedge clk);
            clear=0;
            advance=!gaps || ticks%7!=3;
            valid=sent<width*height/2 && (!gaps || ticks%5!=2);
            sof=sent==0;
            eol=(sent+1)%(width/2)==0;
            eof=sent==width*height/2-1;
            if (valid) data={image[sent*2+1],image[sent*2]};
            @(posedge clk);
            if (advance && valid) sent++;
            #1;
            ticks++;
            if (ticks>width*height*4+80) $fatal(1,"FAIL timeout filter op=%0d",op);
        end
        @(negedge clk);
        valid=0; advance=1; clear=1; checking=0;
        @(posedge clk); #1;
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        for (int operation=0; operation<8; operation++) begin
            foreach(widths[w]) begin
                foreach(heights[h]) begin
                    @(negedge clk);
                    op=3'(operation); width=widths[w]; height=heights[h];
                    prepare();
                    run_frame((w+h)%2==1);
                end
            end
        end
        $display("PASS pix_filter: 192 frames, all ops, borders, freeze/gaps; latency=1 line+%0d",
            maximum_overhead);
        $finish;
    end
endmodule
