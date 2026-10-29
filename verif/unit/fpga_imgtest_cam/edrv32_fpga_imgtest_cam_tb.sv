// File: edrv32_fpga_imgtest_cam_tb.sv
// Spec: Task B3-9; design b2-software 3.2; vin-spec 2.1/2.10.
// Description: Decode both SCCB pins against the software table at actual clock divisors.
// Clock domain: synthetic clk_mem, 125 MHz.
module edrv32_fpga_imgtest_cam_tb;
    /* verilator lint_off BLKSEQ */
    reg clk = 0;
    always #4 clk = !clk;
    reg rst_n = 0;
    wire [1:0] scl;
    wire [1:0] sda;
    wire cam_rst_n;
    wire [1:0] done;
    reg [23:0] expected [0:243];
    string table_path;
    edrv32_fpga_imgtest_cam_init u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .scl_o(scl),
        .sda_o(sda),
        .cam_rst_n_o(cam_rst_n),
        .done_o(done)
    );
    genvar c;
    generate
        for(c=0;c<2;c++) begin : g_sensor
            reg last_scl = 1;
            reg last_sda = 1;
            bit active = 0;
            int bits_seen = 0;
            reg [31:0] shift = 0;
            int transactions = 0;
            always @(negedge clk) begin
                if (scl[c] && last_scl && !sda[c] && last_sda) begin
                    if (!cam_rst_n || $time < 21840000)
                        $fatal(1,"camera started before reset/settle delay time=%t",$time);
                    if (active) $fatal(1,"unexpected restart camera=%0d",c);
                    active=1; bits_seen=0; shift=0;
                end
                if (active && scl[c] && !last_scl && bits_seen<36) begin
                    if (bits_seen%9 != 8) shift={shift[30:0],sda[c]};
                    else if (!sda[c]) $fatal(1,"SCCB ninth bit not released");
                    bits_seen++;
                end
                if (scl[c] && last_scl && sda[c] && !last_sda && active) begin
                    if(bits_seen != 36 || shift !== {8'h78,expected[transactions]})
                        $fatal(1,"camera=%0d transaction=%0d bits=%0d got=%h expected=%h",
                            c,transactions,bits_seen,shift,{8'h78,expected[transactions]});
                    active=0;
                    transactions++;
                end
                last_scl=scl[c]; last_sda=sda[c];
            end
        end
    endgenerate
    initial begin
        if(!$value$plusargs("CAM_TABLE=%s",table_path)) $fatal(1,"missing CAM_TABLE");
        $readmemh(table_path,expected);
        repeat(4) @(negedge clk);
        rst_n=1;
        repeat(787499) @(negedge clk);
        if(cam_rst_n) $fatal(1,"reset released too early");
        repeat(2) @(negedge clk);
        if(!cam_rst_n) $fatal(1,"reset was not released");
        wait(done==3); @(negedge clk);
        if(g_sensor[0].transactions!=244 || g_sensor[1].transactions!=244)
            $fatal(1,"camera table lengths %0d/%0d",g_sensor[0].transactions,g_sensor[1].transactions);
        $display("PASS fpga_imgtest_cam 244 software-identical RGB565 720p writes per camera");
        $finish;
    end
    initial begin
        #240000000;
        $fatal(1,"camera init timeout done=%b",done);
    end
endmodule
