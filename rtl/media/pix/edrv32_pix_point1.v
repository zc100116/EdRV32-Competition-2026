// File: edrv32_pix_point1.v
// Spec: pix-spec 2.1-2.3, 2.6.
// Description: Consume registered centered RGB888 operands; apply contrast, bias and Gamma.
// Six asynchronous table read ports provide both RGB888 pixels each cycle.
// Clock: clk_mem.
module edrv32_pix_point1 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Input stream.
    input wire valid_i,
    input wire [47:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,

    // Output stream.
    output wire valid_o,
    output reg [47:0] data_o,
    output wire sof_o,
    output wire eol_o,
    output wire eof_o,

    // Pipeline and frame configuration.
    input wire [6:0] advance_i,
    input wire clear_i,
    input wire bc_en_i,
    input wire gamma_en_i,
    input wire gamma_bank_i,
    input wire [8:0] contrast_i,
    input wire [9:0] bias_i,
    input wire gamma_wr_i,
    input wire [8:0] gamma_addr_i,
    input wire [7:0] gamma_data_i
);
    reg [3:0] valid_r;
    reg [3:0] sof_r;
    reg [3:0] eol_r;
    reg [3:0] eof_r;
    reg [2:0] config_r [0:2];
    reg [47:0] rgb_r [0:1];

    assign valid_o = valid_r[3];
    assign sof_o = sof_r[3];
    assign eol_o = eol_r[3];
    assign eof_o = eof_r[3];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 4'd0;
        end else if (clear_i) begin
            valid_r <= 4'd0;
        end else if (advance_i[0]) begin
            valid_r <= {valid_r[2:0], valid_i};
        end
    end

    always @(posedge clk_i) begin
        if (advance_i[0]) begin
            sof_r <= {sof_r[2:0], sof_i};
            eol_r <= {eol_r[2:0], eol_i};
            eof_r <= {eof_r[2:0], eof_i};
            config_r[0] <= {gamma_bank_i, gamma_en_i, bc_en_i};
            rgb_r[0] <= expanded_w;
            config_r[1] <= config_r[0];
            config_r[2] <= config_r[1];
            rgb_r[1] <= rgb_r[0];
        end
    end

    reg [7:0] gamma_r [0:511];
    wire [47:0] expanded_w;
    reg signed [9:0] bias_r;
    genvar channel;

    // spec pix 2.3: writes remain independent of stream stalls and reset.
    always @(posedge clk_i) begin
        if (gamma_wr_i) begin
            gamma_r[gamma_addr_i] <= gamma_data_i;
        end
        if (advance_i[0]) begin
            bias_r <= $signed(bias_i);
        end
    end

    assign expanded_w = data_i ^ 48'h808080808080;

    generate
        for (channel = 0; channel < 6; channel = channel + 1) begin : g_channel
            reg signed [17:0] s2_unused_product_r;
            reg signed [10:0] s3_adjusted_r;
            reg [7:0] s4_corrected_r;
            always @(posedge clk_i) begin
                if (advance_i[channel+1]) begin
                    // The top-level input slot is the dedicated APM operand register.
                    s2_unused_product_r <= $signed(data_i[channel*8 +: 8])
                        * $signed({1'b0, contrast_i});
                    s3_adjusted_r <= $signed({s2_unused_product_r[17],
                        s2_unused_product_r[17:8]})
                        + $signed({bias_r[9], bias_r});
                    s4_corrected_r <= !config_r[1][0] ? rgb_r[1][channel*8 +: 8]
                        : (s3_adjusted_r[10] ? 8'd0
                        : (|s3_adjusted_r[9:8] ? 8'd255 : s3_adjusted_r[7:0]));
                    data_o[channel*8 +: 8] <= config_r[2][1]
                        ? gamma_r[{config_r[2][2], s4_corrected_r}] : s4_corrected_r;
                end
            end
        end
    endgenerate
endmodule
