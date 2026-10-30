// File: tb.sv
// Spec: pix-spec 2.1, 2.4, 7; V-R6 exact constant division and spatial pipeline.
// Description: Exhaust all mean sums and reciprocal inputs; compare all kernels
// against independent integer formulas, including gaps and pipeline freezes.
// Clock: clk_mem model.
module tb;
    bit clk=0;
    always #4 clk=~clk;
    bit advance=1;
    bit source_valid=0;
    logic [215:0] window_data='0;
    logic [71:0] shared_delay[0:3];
    logic [2:0] op=0;
    wire [23:0] result;
    bit [7:0] valid_pipe=0;
    logic [23:0] expected[$];
    logic [23:0] want;
    logic [31:0] reciprocal_product;
    int checked=0;
    int residue;
    int value;
    `include "pix_ref.svh"

    edrv32_pix_kernel dut (
        .clk_i(clk),
        .advance_i({21{advance}}),
        .early_rgb_i(window_data),
        .window_i(shared_delay[3]),
        .data_o(result),
        .op_i(op)
    );

    always @(posedge clk) begin
        if (advance) begin
            // Pack the accepted RGB window into the four-advance shared-Y input.
            for (int pixel=0; pixel<9; pixel++)
                shared_delay[0][pixel*8 +: 8] <= 8'(gray_ref(window_data[pixel*24 +: 24]));
            for (int stage=1; stage<4; stage++) shared_delay[stage] <= shared_delay[stage-1];
            if (valid_pipe[7]) begin
                want=expected.pop_front();
                if (result!==want)
                    $fatal(1,"FAIL kernel t=%0t op=%0d exp=%h got=%h",$time,op,want,result);
                checked++;
            end
            if (source_valid) expected.push_back(window_ref(int'(op),window_data));
            valid_pipe={valid_pipe[6:0],source_valid};
        end
    end

    task automatic send;
        do begin
            @(negedge clk);
            advance=$urandom_range(0,3)!=0;
            source_valid=1;
            @(posedge clk); #1;
        end while (!advance);
    endtask
    task automatic drain;
        @(negedge clk);
        source_valid=0;
        advance=1;
        repeat(9) @(negedge clk);
        if (expected.size()!=0) $fatal(1,"FAIL kernel did not drain");
    endtask

    initial begin
        // This includes the four extra values above the reachable sum+4 maximum.
        for (int x=0; x<=2303; x++) begin
            reciprocal_product=32'(x)*32'd3641;
            if ((reciprocal_product>>15)!=32'(x/9))
                $fatal(1,"FAIL divide9 x=%0d exp=%0d got=%0d",x,x/9,
                    reciprocal_product>>15);
        end
        op=1;
        for (int sum=0; sum<=2295; sum++) begin
            residue=sum;
            for (int pixel=0; pixel<9; pixel++) begin
                value=residue>255 ? 255 : residue;
                residue-=value;
                window_data[pixel*24 +: 24]={8'(value),8'(value),8'(value)};
            end
            send();
            @(negedge clk);
            source_valid=0;
        end
        drain();
        for (int operation=0; operation<8; operation++) begin
            op=3'(operation);
            for (int n=0; n<1024; n++) begin
                for (int pixel=0; pixel<9; pixel++) begin
                    case (n)
                        0: window_data[pixel*24 +: 24]=0;
                        1: window_data[pixel*24 +: 24]=24'hffffff;
                        2: window_data[pixel*24 +: 24]=pixel==4 ? 24'hffffff : 0;
                        3: window_data[pixel*24 +: 24]=pixel%3==0 ? 24'hffffff : 0;
                        default: window_data[pixel*24 +: 24]=24'($urandom);
                    endcase
                end
                send();
                @(negedge clk);
                source_valid=0;
            end
            drain();
        end
        $display("PASS pix_kernel: reciprocal=2304 mean_sums=2296 windows=%0d all ops/stalls",
            checked);
        $finish;
    end
endmodule
