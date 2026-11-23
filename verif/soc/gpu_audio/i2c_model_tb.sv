// File: i2c_model_tb.sv
// Spec: gpu-soc-testplan ST-12 I2C recording model.
// Description: Check start/ACK/stop and recorded register bytes before SoC integration.
// Clock domain: observation clk_i; bit-banged external SCL.
`timescale 1ns/1ps
/* verilator lint_off BLKSEQ */
module i2c_model_tb;
    bit clk_i;
    initial clk_i = 0;
    always #4 clk_i = !clk_i;
    bit rst_n_i;
    bit scl_i;
    bit master_sda;
    wire sda_oe_o;
    wire sda_i = master_sda && !sda_oe_o;
    wire write_valid_o;
    wire [7:0] register_o;
    wire [7:0] value_o;
    integer write_count_o;
    integer observed;
    i2c_rx_model u_model (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .scl_i(scl_i),
        .sda_i(sda_i),
        .sda_oe_o(sda_oe_o),
        .write_valid_o(write_valid_o),
        .register_o(register_o),
        .value_o(value_o),
        .write_count_o(write_count_o)
    );
    task automatic settle;
        // 125 MHz observation clock: 625 cycles gives a 5 us I2C half-period.
        repeat (625) @(negedge clk_i);
    endtask
    task automatic send_byte(input bit [7:0] value);
        for (int i = 7; i >= 0; i--) begin
            scl_i = 0;
            master_sda = value[i];
            settle();
            scl_i = 1;
            settle();
        end
        scl_i = 0;
        master_sda = 1;
        settle();
        scl_i = 1;
        settle();
        if (sda_i) $fatal(1, "FAIL missing ACK byte=%h time=%0t", value, $time);
        scl_i = 0;
        settle();
    endtask
    task automatic write_register(input bit [7:0] address, input bit [7:0] value);
        master_sda = 0;
        settle();
        send_byte(8'h12);
        send_byte(address);
        send_byte(value);
        master_sda = 0;
        settle();
        scl_i = 1;
        settle();
        master_sda = 1;
        settle();
    endtask
    always @(negedge clk_i) begin
        if (write_valid_o) begin
            if ((observed == 0 && {register_o, value_o} != 16'h0204) ||
                (observed == 1 && {register_o, value_o} != 16'h1130))
                $fatal(1, "FAIL recorded I2C actual=%h time=%0t", {register_o, value_o}, $time);
            observed++;
        end
    end
    initial begin
        rst_n_i = 0;
        scl_i = 1;
        master_sda = 1;
        observed = 0;
        settle();
        rst_n_i = 1;
        settle();
        write_register(8'h02, 8'h04);
        write_register(8'h11, 8'h30);
        if (write_count_o != 2 || observed != 2)
            $fatal(1, "FAIL writes expected=2 actual=%0d observed=%0d", write_count_o, observed);
        $display("PASS I2C recording model writes=2");
        $finish;
    end
endmodule
