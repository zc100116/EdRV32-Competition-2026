// File: tb.sv
// Spec: rnd-spec 2.4.
// Description: All 32 reciprocals and random/extreme four-channel sums against integer math.
// Clock domain: clk_mem.
module tb;
    reg clk=0;
    always #4 clk=~clk;
    reg rst_n=0;
    reg coeff_valid=0;
    wire coeff_ready;
    reg [4:0] radius;
    wire coeff_out_valid;
    reg coeff_out_ready=0;
    wire [16:0] coefficient;
    reg valid=0;
    wire ready;
    reg [111:0] sums;
    wire out_valid;
    reg out_ready=0;
    wire [63:0] pixels;
    reg [63:0] expected[$];
    int tested=0;
    int stalled=0;
    edrv32_rnd_blur_coeff u_coeff (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(1'b0), .valid_i(coeff_valid), .ready_o(coeff_ready),
        .radius_i(radius), .valid_o(coeff_out_valid), .ready_i(coeff_out_ready),
        .coefficient_o(coefficient)
    );
    edrv32_rnd_blur_math u_math (
        .clk_i(clk), .rst_n_i(rst_n), .valid_i(valid), .ready_o(ready),
        .sum_i(sums), .coefficient_i(coefficient), .valid_o(out_valid),
        .ready_i(out_ready), .pixel_o(pixels)
    );
    always @(posedge clk) begin
        reg [63:0] want;
        if(rst_n && out_valid && out_ready) begin
            if(expected.size()==0) $fatal(1,"unexpected output t=%0t",$time);
            want=expected.pop_front();
            if(pixels !== want)
                $fatal(1,"blur want=%h got=%h t=%0t",want,pixels,$time);
            tested++;
        end
    end
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        for(int r=0;r<32;r++) begin
            @(negedge clk);
            radius=5'(r);
            coeff_valid=1;
            do @(posedge clk); while(!coeff_ready);
            @(negedge clk);
            coeff_valid=0;
            while(!coeff_out_valid) @(negedge clk);
            if(int'(coefficient)!=(65536+r)/(2*r+1))
                $fatal(1,"coefficient R=%0d want=%0d got=%0d t=%0t",
                    r,(65536+r)/(2*r+1),coefficient,$time);
            for(int n=0;n<500;n++) begin
                reg [63:0] want;
                @(negedge clk);
                out_ready=$urandom_range(0,3)!=0;
                valid=1;
                for(int c=0;c<8;c++) begin
                    int s;
                    s=n==0 ? 0 : n==1 ? 255*(2*r+1) : int'($urandom_range(0,255*(2*r+1)));
                    sums[c*14+:14]=14'(s);
                    want[c*8+:8]=8'((s*((65536+r)/(2*r+1))+32768)>>16);
                end
                #1;
                while(!ready) begin
                    stalled++;
                    @(negedge clk);
                    out_ready=1;
                    #1;
                end
                expected.push_back(want);
                @(posedge clk);
            end
            @(negedge clk);
            valid=0;
            out_ready=1;
            while(expected.size()!=0) @(negedge clk);
            coeff_out_ready=1;
            @(negedge clk);
            coeff_out_ready=0;
        end
        if(tested!=16000 || stalled==0) $fatal(1,"coverage tested=%0d stalled=%0d",tested,stalled);
        $display("PASS blur 32 radii, 16000 two-pixel sums with backpressure");
        $finish;
    end
endmodule
