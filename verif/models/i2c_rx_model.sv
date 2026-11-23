// File: i2c_rx_model.sv
// Spec: gpu-soc-testplan ST-12; ES8156 datasheet rev 5 I2C interface.
// Description: ACK 0x12 write transactions and record 8-bit register/value pairs.
//              Clocked pin observation; SDA output is open-drain enable only.
// Clock domain: observation clk_sys; external I2C SCL.
`timescale 1ns/1ps
module i2c_rx_model (
    input logic clk_i,
    input logic rst_n_i,
    input logic scl_i,
    input logic sda_i,
    output logic sda_oe_o,
    output logic write_valid_o,
    output logic [7:0] register_o,
    output logic [7:0] value_o,
    output integer write_count_o
);
    logic old_scl;
    logic old_sda;
    logic active;
    logic selected;
    logic [6:0] shift;
    wire [7:0] byte_value = {shift, sda_i};
    integer bit_count;
    integer byte_count;

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            old_scl <= 1;
            old_sda <= 1;
            active <= 0;
            selected <= 0;
            shift <= 0;
            bit_count <= 0;
            byte_count <= 0;
            sda_oe_o <= 0;
            write_valid_o <= 0;
            register_o <= 0;
            value_o <= 0;
            write_count_o <= 0;
        end else begin
            old_scl <= scl_i;
            old_sda <= sda_i;
            write_valid_o <= 0;
            if (scl_i && old_scl && old_sda && !sda_i) begin
                active <= 1;
                selected <= 0;
                bit_count <= 0;
                byte_count <= 0;
            end else if (scl_i && old_scl && !old_sda && sda_i) begin
                active <= 0;
                sda_oe_o <= 0;
            end else if (active) begin
                if (scl_i && !old_scl) begin
                    if (bit_count < 8) begin
                        shift <= {shift[5:0], sda_i};
                        bit_count <= bit_count + 1;
                        if (bit_count == 7) begin
                            case (byte_count)
                                0: selected <= byte_value == 8'h12;
                                1: register_o <= byte_value;
                                2: begin
                                    if (selected) begin
                                        value_o <= byte_value;
                                        write_valid_o <= 1;
                                        write_count_o <= write_count_o + 1;
                                    end
                                end
                                default: begin end
                            endcase
                            byte_count <= byte_count + 1;
                        end
                    end else begin
                        bit_count <= 9;
                    end
                end
                if (!scl_i && old_scl) begin
                    if (bit_count == 8) begin
                        sda_oe_o <= selected;
                    end else if (bit_count == 9) begin
                        sda_oe_o <= 0;
                        bit_count <= 0;
                    end
                end
            end
        end
    end
endmodule
