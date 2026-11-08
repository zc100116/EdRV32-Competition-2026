// File: tb.sv
// Spec: npu-testplan PP-04; npu-spec 5.6.
// Description: Full-width integer DFL oracle, peak difference 255 and exact half rounding.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb;
    bit clk = 0;
    always #2.5 clk = !clk;
    bit rst_n = 0;
    bit start = 0;
    logic [127:0] bin_values = 0;
    wire done;
    wire [11:0] distance;
    wire exp_en;
    wire [7:0] exp_addr;
    logic [31:0] exp_array;
    logic [31:0] exp_data;
    bit half_mode = 0;
    bit saw255 = 0;
    function automatic int unsigned weight(input int delta);
        if (half_mode) begin
            case (delta)
                0: return 1048576;
                1: return 1044480;
                2: return 4096;
                default: return 0;
            endcase
        end
        return delta < 21 ? 1048576 >> delta : 0;
    endfunction
    always @(posedge clk) begin
        if (exp_en) begin
            exp_array <= weight(int'(exp_addr));
            if (exp_addr == 255) saw255 <= 1;
        end
        exp_data <= exp_array;
    end
    edrv32_npu_post_dfl dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(1'b0),
        .start_i(start),
        .bins_i(bin_values),
        .done_o(done),
        .distance_o(distance),
        .exp_en_o(exp_en),
        .exp_addr_o(exp_addr),
        .exp_data_i(exp_data)
    );
    task automatic tick;
        @(negedge clk);
    endtask
    task automatic run_case(input int number);
        int peak;
        longint unsigned den;
        longint unsigned num;
        longint unsigned expected;
        int cycles;
        peak = -128;
        den = 0;
        num = 0;
        for (int n = 0; n < 16; n++)
            if (int'($signed(bin_values[8*n+:8])) > peak) peak = int'($signed(bin_values[8*n+:8]));
        for (int n = 0; n < 16; n++) begin
            den += 64'(weight(peak - int'($signed(bin_values[8*n+:8]))));
            num += 64'(n) * 64'(weight(peak - int'($signed(bin_values[8*n+:8]))));
        end
        expected = (num*256 + den/2)/den;
        start = 1;
        tick;
        start = 0;
        cycles = 0;
        while (!done) begin
            tick;
            cycles++;
            if (cycles > 100) $fatal(1, "FAIL DFL timeout case=%0d", number);
        end
        if (64'(distance) != expected)
            $fatal(1, "FAIL DFL case=%0d expected=%0d got=%0d den=%0d num=%0d time=%0t",
                number, expected, distance, den, num, $time);
        if (number == 0 && (den != 16777216 || num != 125829120))
            $fatal(1, "FAIL full-width stimulus");
        if (half_mode && ((num*256)%den != den/2 || expected != 129))
            $fatal(1, "FAIL half-point stimulus");
        $display("DFL case=%0d cycles=%0d distance=%0d", number, cycles, distance);
        tick;
    endtask
    initial begin
        repeat (3) tick;
        rst_n = 1;
        run_case(0);
        bin_values = {16{8'h80}};
        bin_values[7:0] = 127;
        run_case(1);
        bin_values = {16{8'h80}};
        bin_values[127:120] = 127;
        run_case(2);
        half_mode = 1;
        bin_values = {16{8'h80}};
        bin_values[7:0] = 127;
        bin_values[15:8] = 126;
        bin_values[23:16] = 125;
        run_case(3);
        half_mode = 0;
        for (int c = 4; c < 84; c++) begin
            for (int n = 0; n < 16; n++) bin_values[8*n+:8] = 8'($urandom);
            run_case(c);
        end
        if (!saw255) $fatal(1, "FAIL difference 255 not exercised");
        $display("PASS DFL full-width, difference255, half-point, random");
        $finish;
    end
endmodule
