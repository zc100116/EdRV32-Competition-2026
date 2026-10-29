// File: tb.sv
// Spec: disp-spec 2.2.
// Description: Independent serial TMDS reference, with emitted-symbol disparity update.
// Clock domain: test pixel clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [7:0] data = 0;
    reg [1:0] control = 0;
    reg de = 0;
    wire [9:0] symbol;
    reg [9:0] expected [0:3];
    int balance = 0;
    int compared = 0;
    bit positive = 0;
    bit negative = 0;
    edrv32_disp_tmds_enc dut (
        .clk_i(clk), .rst_n_i(rst_n), .data_i(data), .control0_i(control[0]),
        .control1_i(control[1]), .de_i(de), .symbol_o(symbol)
    );
    function automatic [9:0] reference_encode(input [7:0] value, input bit valid_data,
                                            input [1:0] controls);
        bit [8:0] q;
        bit xnor_mode;
        bit invert;
        bit [9:0] result;
        int ones;
        if (!valid_data) begin
            balance = 0;
            case (controls)
                0: result = 10'b1101010100;
                1: result = 10'b0010101011;
                2: result = 10'b0101010100;
                3: result = 10'b1010101011;
            endcase
        end else begin
            ones = $countones(value);
            xnor_mode = ones > 4 || (ones == 4 && value[0] == 0);
            q[0] = value[0];
            for (int bit_index = 1; bit_index < 8; bit_index++)
                q[bit_index] = q[bit_index-1] ^ value[bit_index] ^ xnor_mode;
            q[8] = !xnor_mode;
            ones = $countones(q[7:0]);
            if (balance == 0 || ones == 4)
                invert = !q[8];
            else
                invert = (balance > 0 && ones > 4) || (balance < 0 && ones < 4);
            result = {invert, q[8], q[7:0] ^ {8{invert}}};
            balance += 2*$countones(result)-10;
            positive |= balance > 0;
            negative |= balance < 0;
        end
        return result;
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            balance = 0;
            expected[0] = 10'b1101010100;
            expected[1] = 10'b1101010100;
            expected[2] = 10'b1101010100;
            expected[3] = 10'b1101010100;
        end else begin
            expected[3] = expected[2];
            expected[2] = expected[1];
            expected[1] = expected[0];
            expected[0] = reference_encode(data, de, control);
            #1;
            if (symbol !== expected[3])
                $fatal(1, "FAIL symbol=%010b expected=%010b cycle=%0d",
                       symbol, expected[3], compared);
            compared++;
        end
    end
    task automatic drive(input bit active, input [7:0] value, input [1:0] controls);
        @(negedge clk);
        de = active;
        data = value;
        control = controls;
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (int pass = 0; pass < 8; pass++) begin
            drive(0, 0, 2'(pass));
            for (int value = 0; value < 256; value++)
                drive(1, 8'(pass[0] ? 255-value : value), 0);
        end
        repeat (20000) drive($urandom_range(0,15) != 0, 8'($urandom), 2'($urandom));
        repeat (5) drive(0, 0, 0);
        if (!positive || !negative || compared < 22000)
            $fatal(1, "FAIL disparity sign coverage or symbol count");
        $display("PASS tmds_enc: %0d symbols, all bytes/controls, both disparity signs", compared);
        $finish;
    end
endmodule
