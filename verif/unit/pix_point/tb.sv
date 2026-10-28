// File: tb.sv
// Spec: pix-spec 2.1-2.3, 2.5; unit arithmetic boundaries.
// Description: Independent integer point-operation expectations, both Gamma banks.
// Clock: clk_mem model.
module tb;
    bit clk=0;
    always #4 clk=~clk;
    bit rst_n=0;
    bit advance=1;
    bit clear=0;
    bit valid=0;
    logic [31:0] source;
    bit bc_en=0;
    bit gamma_en=0;
    bit gamma_bank=0;
    logic [8:0] contrast=256;
    logic [8:0] brightness=0;
    bit gamma_wr=0;
    logic [8:0] gamma_addr;
    logic [7:0] gamma_data;
    wire valid1;
    wire [47:0] data1;
    wire sof1;
    wire eol1;
    wire eof1;
    logic [47:0] source2;
    bit gray_en=0;
    bit bin_en=0;
    bit inv_en=0;
    logic [7:0] thresh=128;
    wire valid2;
    wire [31:0] data2;
    wire sof2;
    wire eol2;
    wire eof2;
    int contrasts[4]='{0,128,256,511};
    int brights[4]='{-256,-1,0,255};
    `include "pix_ref.svh"

    edrv32_pix_point1 dut1 (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(valid),
        .data_i(source),
        .sof_i(1'b1),
        .eol_i(1'b1),
        .eof_i(1'b1),
        .valid_o(valid1),
        .data_o(data1),
        .sof_o(sof1),
        .eol_o(eol1),
        .eof_o(eof1),
        .advance_i(advance),
        .clear_i(clear),
        .bc_en_i(bc_en),
        .gamma_en_i(gamma_en),
        .gamma_bank_i(gamma_bank),
        .contrast_i(contrast),
        .brightness_i(brightness),
        .gamma_wr_i(gamma_wr),
        .gamma_addr_i(gamma_addr),
        .gamma_data_i(gamma_data)
    );
    edrv32_pix_point2 dut2 (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(valid),
        .data_i(source2),
        .sof_i(1'b1),
        .eol_i(1'b1),
        .eof_i(1'b1),
        .valid_o(valid2),
        .data_o(data2),
        .sof_o(sof2),
        .eol_o(eol2),
        .eof_o(eof2),
        .advance_i(advance),
        .clear_i(clear),
        .gray_en_i(gray_en),
        .bin_en_i(bin_en),
        .inv_en_i(inv_en),
        .thresh_i(thresh)
    );

    function automatic logic [23:0] expand_ref(input logic [15:0] p);
        return {p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
    endfunction
    function automatic logic [7:0] gamma_ref(input int bank, input int value);
        return bank==0 ? 8'(255-value) : 8'((value*value+127)/255);
    endfunction
    function automatic logic [47:0] ref1(input logic [31:0] pair);
        logic [47:0] result;
        int value;
        for (int lane=0; lane<2; lane++) begin
            result[lane*24 +: 24] = expand_ref(pair[lane*16 +: 16]);
            for (int c=0; c<3; c++) begin
                value=int'(result[lane*24+c*8 +: 8]);
                if (bc_en) value=clamp_ref((((value-128)*int'(contrast)) >>> 8)
                    +128+int'($signed(brightness)));
                if (gamma_en) value=int'(gamma_ref(int'(gamma_bank),value));
                result[lane*24+c*8 +: 8] = 8'(value);
            end
        end
        return result;
    endfunction
    function automatic logic [31:0] ref2(input logic [47:0] pair);
        logic [23:0] rgb;
        logic [31:0] result;
        int y;
        for (int lane=0; lane<2; lane++) begin
            rgb=pair[lane*24 +: 24];
            y=gray_ref(rgb);
            if (gray_en) rgb={8'(y),8'(y),8'(y)};
            // Recompute Y from the preceding step, independently of the RTL simplification.
            y=gray_ref(rgb);
            if (bin_en) rgb=y>=int'(thresh) ? 24'hffffff : 24'd0;
            if (inv_en) rgb=24'hffffff-rgb;
            result[lane*16 +: 16]={rgb[23:19],rgb[15:10],rgb[7:3]};
        end
        return result;
    endfunction
    task automatic check1;
        logic [47:0] expected;
        expected=ref1(source);
        @(posedge clk); #1;
        if (!valid1 || data1!==expected || !sof1 || !eol1 || !eof1)
            $fatal(1,"FAIL point1 t=%0t in=%h bc=%h/%h gamma=%b/%b exp=%h got=%h",
                $time,source,contrast,brightness,gamma_en,gamma_bank,expected,data1);
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        for (int bank=0; bank<2; bank++) begin
            for (int n=0; n<256; n++) begin
                @(negedge clk);
                gamma_wr=1;
                gamma_addr=9'(bank*256+n);
                gamma_data=gamma_ref(bank,n);
            end
        end
        @(negedge clk); gamma_wr=0; valid=1;
        for (int mode=0; mode<3; mode++) begin
            bc_en=mode!=0;
            gamma_en=mode==2;
            for (int bank=0; bank<2; bank++) begin
                gamma_bank=1'(bank);
                foreach(contrasts[c]) begin
                    foreach(brights[b]) begin
                        contrast=9'(contrasts[c]); brightness=9'(brights[b]);
                        for (int n=0; n<256; n++) begin
                            source={16'(n*253+17),16'(n*257)};
                            check1();
                            @(negedge clk);
                        end
                    end
                end
            end
        end
        for (int mode=0; mode<8; mode++) begin
            {inv_en,bin_en,gray_en}=3'(mode);
            for (int t=0; t<3; t++) begin
                thresh=t==0 ? 0 : (t==1 ? 128 : 255);
                for (int n=0; n<260; n++) begin
                    source2={8'(255-n),8'(n),8'(n*37),8'(n),8'(n*3),8'(255-n)};
                    case (n)
                        256: source2=48'd0;
                        257: source2=48'hffffffffffff;
                        258: source2=48'h8080807f7f7f;
                        259: source2=48'hfffffffefefe;
                        default: begin end
                    endcase
                    @(posedge clk); #1;
                    if (!valid2 || data2!==ref2(source2) || !sof2 || !eol2 || !eof2)
                        $fatal(1,"FAIL point2 t=%0t mode=%0d thresh=%0d exp=%h got=%h",
                            $time,mode,thresh,ref2(source2),data2);
                    @(negedge clk);
                end
            end
        end
        advance=0;
        begin
            logic [79:0] held;
            held={data1,data2};
            repeat(3) begin
                source=~source; source2=~source2;
                @(posedge clk); #1;
                if ({data1,data2}!==held) $fatal(1,"FAIL point stall t=%0t",$time);
                @(negedge clk);
            end
        end
        clear=1;
        @(posedge clk); #1;
        if (valid1 || valid2) $fatal(1,"FAIL clear t=%0t",$time);
        $display("PASS pix_point: formulas, saturation, banks, order, freeze and clear");
        $finish;
    end
endmodule
