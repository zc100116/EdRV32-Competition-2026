// ============================================================================
// File        : spi_flash_jedec_model.sv
// Author      : Edward ZC
// Description : Minimal mode-0 SPI Flash model for JEDEC-ID command 0x9F.
// Notes       : Read-only diagnostic model; it intentionally implements no
//               erase/program operations and returns C8 40 18.
// ============================================================================
module spi_flash_jedec_model (
    input  wire cs_n_i,
    input  wire sclk_i,
    input  wire mosi_i,
    output reg  miso_o,
    output reg  command_seen_o,
    output reg  protocol_error_o
);
    localparam [7:0] JEDEC_COMMAND = 8'h9f;
    localparam [23:0] JEDEC_ID = 24'hc8_40_18;

    reg [7:0] command_r;
    reg [5:0] input_bits_r;
    reg [5:0] output_bits_r;

    initial begin
        miso_o = 1'b1;
        command_seen_o = 1'b0;
        protocol_error_o = 1'b0;
        command_r = 8'b0;
        input_bits_r = 6'b0;
        output_bits_r = 6'b0;
    end

    always @(negedge cs_n_i) begin
        command_r = 8'b0;
        input_bits_r = 6'b0;
        output_bits_r = 6'b0;
        miso_o = 1'b1;
    end

    // SPI mode 0: slave samples MOSI on the rising edge.
    always @(posedge sclk_i) begin
        if (!cs_n_i) begin
            if (input_bits_r < 8) begin
                command_r = {command_r[6:0], mosi_i};
                input_bits_r = input_bits_r + 1'b1;
                if (input_bits_r == 8) begin
                    if (command_r == JEDEC_COMMAND)
                        command_seen_o = 1'b1;
                    else
                        protocol_error_o = 1'b1;
                end
            end else if (output_bits_r < 24) begin
                output_bits_r = output_bits_r + 1'b1;
            end
        end
    end

    // Change MISO on the falling edge so it is stable at the next rising edge.
    always @(negedge sclk_i) begin
        if (!cs_n_i && input_bits_r >= 8 && output_bits_r < 24)
            miso_o = JEDEC_ID[23-output_bits_r];
    end

    always @(posedge cs_n_i) begin
        if (input_bits_r != 0 && (input_bits_r != 8 || output_bits_r != 24))
            protocol_error_o = 1'b1;
        miso_o = 1'b1;
    end
endmodule
