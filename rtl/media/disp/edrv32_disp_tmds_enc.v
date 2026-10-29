// File: edrv32_disp_tmds_enc.v
// Spec: disp-spec 2.2.
// Description: Legacy TMDS transition minimization and running disparity algorithm.
//              Three preparation stages precede the registered channel symbol.
// Clock domain: clk_pix (clk_i).
module edrv32_disp_tmds_enc (
    // Clock and reset.
    input  wire       clk_i,
    input  wire       rst_n_i,

    // Channel data and blanking controls.
    input  wire [7:0] data_i,
    input  wire       control0_i,
    input  wire       control1_i,
    input  wire       de_i,

    // Registered parallel channel symbol.
    output wire [9:0] symbol_o
);

    localparam [9:0] CONTROL_00 = 10'b1101010100;
    localparam [9:0] CONTROL_01 = 10'b0010101011;
    localparam [9:0] CONTROL_10 = 10'b0101010100;
    localparam [9:0] CONTROL_11 = 10'b1010101011;

    reg [3:0] data_ones_r;
    reg [7:0] data_r;
    reg de_stage1_r;
    reg control0_stage1_r;
    reg control1_stage1_r;

    wire use_xnor_w = (data_ones_r > 4) ||
        ((data_ones_r == 4) && !data_r[0]);
    reg [8:0] transition_w;
    integer bit_idx;

    always @(*) begin
        transition_w = 9'd0;
        transition_w[0] = data_r[0];
        for (bit_idx = 1; bit_idx < 8; bit_idx = bit_idx + 1) begin
            transition_w[bit_idx] = use_xnor_w
                ? ~(transition_w[bit_idx-1] ^ data_r[bit_idx])
                : (transition_w[bit_idx-1] ^ data_r[bit_idx]);
        end
        transition_w[8] = !use_xnor_w;
    end

    // Register transition minimization before its population count.
    reg [8:0] transition_stage2_r;
    reg de_stage3_r;
    reg control0_stage3_r;
    reg control1_stage3_r;
    wire [3:0] transition_ones_w;
    reg transition_balanced_r;
    reg transition_positive_r;
    reg transition_negative_r;
    reg [3:0] transition_ones_r;
    reg [3:0] transition_zeros_r;
    reg [8:0] transition_r;
    reg de_stage2_r;
    reg control0_stage2_r;
    reg control1_stage2_r;

    reg signed [4:0] disparity_r;
    reg [9:0] symbol_r;

    wire disparity_balanced_w = (disparity_r == 0) ||
        transition_balanced_r;
    wire invert_transition_w =
        (!disparity_r[4] && transition_positive_r) ||
        (disparity_r[4] && transition_negative_r);

    assign transition_ones_w = {3'b0, transition_stage2_r[0]} +
        {3'b0, transition_stage2_r[1]} + {3'b0, transition_stage2_r[2]} +
        {3'b0, transition_stage2_r[3]} + {3'b0, transition_stage2_r[4]} +
        {3'b0, transition_stage2_r[5]} + {3'b0, transition_stage2_r[6]} +
        {3'b0, transition_stage2_r[7]};

    assign symbol_o = symbol_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            de_stage1_r <= 1'b0;
            de_stage2_r <= 1'b0;
            de_stage3_r <= 1'b0;
        end else begin
            de_stage1_r <= de_i;
            de_stage2_r <= de_stage1_r;
            de_stage3_r <= de_stage2_r;
        end
    end

    always @(posedge clk_i) begin
        data_ones_r <= {3'b0, data_i[0]} + {3'b0, data_i[1]} +
            {3'b0, data_i[2]} + {3'b0, data_i[3]} + {3'b0, data_i[4]} +
            {3'b0, data_i[5]} + {3'b0, data_i[6]} + {3'b0, data_i[7]};
        data_r <= data_i;
        control0_stage1_r <= control0_i;
        control1_stage1_r <= control1_i;
        transition_ones_r <= transition_ones_w;
        transition_zeros_r <= 4'd8 - transition_ones_w;
        // These predicates depend only on the symbol, so prepare them before feedback.
        transition_balanced_r <= transition_ones_w == 4'd4;
        transition_positive_r <= transition_ones_w > 4'd4;
        transition_negative_r <= transition_ones_w < 4'd4;
        transition_stage2_r <= transition_w;
        transition_r <= transition_stage2_r;
        control0_stage2_r <= control0_stage1_r;
        control1_stage2_r <= control1_stage1_r;
        control0_stage3_r <= control0_stage2_r;
        control1_stage3_r <= control1_stage2_r;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            disparity_r <= 5'sd0;
        end else if (!de_stage3_r) begin
            disparity_r <= 5'sd0;
        end else if (disparity_balanced_w) begin
            disparity_r <= !transition_r[8]
                ? disparity_r + {1'b0, transition_zeros_r} - {1'b0, transition_ones_r}
                : disparity_r + {1'b0, transition_ones_r} - {1'b0, transition_zeros_r};
        end else if (invert_transition_w) begin
            disparity_r <= disparity_r + {3'b0, transition_r[8], 1'b0} +
                {1'b0, transition_zeros_r} - {1'b0, transition_ones_r};
        end else begin
            disparity_r <= disparity_r - {3'b0, !transition_r[8], 1'b0} +
                {1'b0, transition_ones_r} - {1'b0, transition_zeros_r};
        end
    end

    always @(posedge clk_i) begin
        if (!de_stage3_r) begin
            case ({control1_stage3_r, control0_stage3_r})
                2'b00: symbol_r <= CONTROL_00;
                2'b01: symbol_r <= CONTROL_01;
                2'b10: symbol_r <= CONTROL_10;
                default: symbol_r <= CONTROL_11;
            endcase
        end else if (disparity_balanced_w) begin
            symbol_r[9] <= !transition_r[8];
            symbol_r[8] <= transition_r[8];
            symbol_r[7:0] <= transition_r[8]
                ? transition_r[7:0] : ~transition_r[7:0];
        end else if (invert_transition_w) begin
            symbol_r <= {1'b1, transition_r[8], ~transition_r[7:0]};
        end else begin
            symbol_r <= {1'b0, transition_r[8], transition_r[7:0]};
        end
    end

endmodule
