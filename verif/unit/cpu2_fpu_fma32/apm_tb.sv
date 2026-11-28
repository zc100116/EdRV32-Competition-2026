// File: apm_tb.sv
// Spec: fpu-spec 5.2; FV16.
// Description: Independent full 48-bit product and four-enabled-edge reference.
// Clock domain: simulation clk_sys.
module apm_tb;
    reg clk;
    reg enable;
    reg [23:0] a;
    reg [23:0] b;
    wire [47:0] product;
    reg [47:0] expected [0:3];
    reg [3:0] valid;
    reg [31:0] random_r;
    integer checked;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    edrv32_apm_cpu2_u24xu24 u_dut (
        .clk_i(clk),
        .enable_i({6{enable}}),
        .a_i(a),
        .b_i(b),
        .product_o(product)
    );
    initial begin
        enable = 0;
        valid = 0;
        random_r = 32'hf0216;
        checked = 0;
        for (integer cycle = 0; cycle < 100016; cycle = cycle + 1) begin
            @(negedge clk);
            random_r = {random_r[30:0], random_r[31]^random_r[21]^random_r[1]^random_r[0]};
            enable = random_r[1:0] != 0;
            a = random_r[23:0];
            b = {random_r[7:0],random_r[31:16]};
            // First 16 enabled inputs cross zero, extrema, and partition boundaries.
            if (cycle < 16) begin
                enable = 1;
                case (cycle % 4)
                    0: a = 24'b0;
                    1: a = 24'hffffff;
                    2: a = 24'h800000;
                    default: a = 24'h010000;
                endcase
                case (cycle / 4)
                    0: b = 24'b0;
                    1: b = 24'hffffff;
                    2: b = 24'h800000;
                    default: b = 24'h00ffff;
                endcase
            end
            @(posedge clk);
            if (enable) begin
                for (integer j = 3; j > 0; j = j - 1) expected[j] = expected[j-1];
                expected[0] = {24'b0,a} * {24'b0,b};
                valid = {valid[2:0],1'b1};
            end
            #1;
            if (valid[3]) begin
                if (product !== expected[3]) begin
                    $fatal(1,"APM expected=%012h actual=%012h enable=%0d cycle=%0d",
                        expected[3],product,enable,cycle);
                end
                checked = checked + 1;
            end
        end
        $display("PASS APM full48 four-edge enabled chain: %0d checks",checked);
        $finish;
    end
endmodule
