// File: tb.sv
// Spec: geo-spec 2, 4, 5.
// Description: Independent formula-based unit checks.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = !clk;
    reg b_clk_i;
    reg b_rst_n_i;
    reg b_advance_i;
    reg b_clear_i;
    reg b_valid_i;
    reg b_eol_i;
    reg [15:0] b_p00_i;
    reg [15:0] b_p01_i;
    reg [15:0] b_p10_i;
    reg [15:0] b_p11_i;
    reg [7:0] b_fx_i;
    reg [7:0] b_fy_i;
    wire b_valid_o;
    wire b_eol_o;
    wire [15:0] b_pixel_o;
    edrv32_geo_bilinear u_b_ (
        .clk_i(b_clk_i),
        .rst_n_i(b_rst_n_i),
        .advance_i(b_advance_i),
        .clear_i(b_clear_i),
        .valid_i(b_valid_i),
        .eol_i(b_eol_i),
        .p00_i(b_p00_i),
        .p01_i(b_p01_i),
        .p10_i(b_p10_i),
        .p11_i(b_p11_i),
        .fx_i(b_fx_i),
        .fy_i(b_fy_i),
        .valid_o(b_valid_o),
        .eol_o(b_eol_o),
        .pixel_o(b_pixel_o)
    );
    integer trial;
    integer sent;
    integer received;
    reg [15:0] expected [0:2047];
    reg [2:0] valid_model;
    reg [2:0] eol_model;
    reg [15:0] pipeline [0:2];
    function automatic integer expand_channel(input reg [15:0] p, input integer ch);
        integer v;
        begin
            if(ch==0) begin v=int'(p[4:0]);expand_channel=(v<<3)|(v>>2);end
            else if(ch==1) begin v=int'(p[10:5]);expand_channel=(v<<2)|(v>>4);end
            else begin v=int'(p[15:11]);expand_channel=(v<<3)|(v>>2);end
        end
    endfunction
    function automatic [15:0] reference_pixel(input reg [15:0] p00,p01,p10,p11,
        input integer fx,fy);
        integer channel;
        integer value;
        reg [15:0] result;
        begin
            result=0;
            for(channel=0;channel<3;channel++) begin
                value=(expand_channel(p00,channel)*(256-fx)*(256-fy)+
                    expand_channel(p01,channel)*fx*(256-fy)+
                    expand_channel(p10,channel)*(256-fx)*fy+
                    expand_channel(p11,channel)*fx*fy+32768)>>16;
                if(channel==0) result[4:0]=5'(value>>3);
                else if(channel==1) result[10:5]=6'(value>>2);
                else result[15:11]=5'(value>>3);
            end
            reference_pixel=result;
        end
    endfunction
    initial begin

        b_rst_n_i = 0;
        b_advance_i = 0;
        b_clear_i = 0;
        b_valid_i = 0;
        b_eol_i = 0;
        b_p00_i = 0;
        b_p01_i = 0;
        b_p10_i = 0;
        b_p11_i = 0;
        b_fx_i = 0;
        b_fy_i = 0;
        b_rst_n_i=0;valid_model=0;eol_model=0;sent=0;received=0;
        repeat(2) @(negedge clk);
        b_rst_n_i=1;
        for(trial=0;trial<1300;trial++) begin
            b_advance_i=trial<1024 ? ($urandom_range(0,3)!=0) : 1;
            b_valid_i=trial<1024;
            b_eol_i=1'(trial);
            b_p00_i=16'($urandom); b_p01_i=16'($urandom);
            b_p10_i=16'($urandom); b_p11_i=16'($urandom);
            if(trial%16==0) begin
                b_p01_i=b_p00_i;b_p10_i=b_p00_i;b_p11_i=b_p00_i;
            end
            b_fx_i=(trial<256)?8'(trial):8'($urandom);
            b_fy_i=(trial<256)?8'(255-trial):8'($urandom);
            if(trial<4) begin b_fx_i=trial%2==0?0:255;b_fy_i=trial/2==0?0:255;end
            if(b_advance_i) begin
                if(valid_model[2]) begin
                    if(!b_valid_o || b_pixel_o!==pipeline[2] || b_eol_o!==eol_model[2])
                        $fatal(1,"FAIL interpolation exp=%h got=%h at %t",
                            pipeline[2],b_pixel_o,$time);
                    received++;
                end
                valid_model={valid_model[1:0],b_valid_i};
                eol_model={eol_model[1:0],b_eol_i};
                pipeline[2]=pipeline[1];
                pipeline[1]=pipeline[0];
                pipeline[0]=reference_pixel(b_p00_i,b_p01_i,b_p10_i,b_p11_i,
                    int'(b_fx_i),int'(b_fy_i));
                if(b_valid_i) sent++;
            end
            @(negedge clk);
        end
        if(sent!=received) $fatal(1,"FAIL interpolation count");
        $display("PASS geo_bilinear 8-bit weights, exact rounding and pipeline backpressure");
        $finish;
    end
    always @(*) b_clk_i=clk;
endmodule
