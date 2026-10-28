// File: tmds_rx_model.sv
// Spec: DISP 2.2; DVI 1.0 sections 3.2, 3.3 (Figure 3-5).
// Description: Decode parallel DVI symbols independently of the transmitter.
//              Collect active pixels between VS rising edges in frame_pixels.
// Clock domain: clk_pix_i.
`timescale 1ns/1ps
module tmds_rx_model (
    // Pixel clock and reset.
    input logic clk_pix_i,
    input logic rst_n_i,
    // Parallel DVI lanes, B in the least significant ten bits.
    input logic [29:0] sym_i,
    output logic hs_o,
    output logic vs_o,
    output logic de_o,
    output logic [23:0] rgb_o,
    output int frame_count_o,
    output int frame_pixel_count_o
);
    logic hs_hold;
    logic vs_hold;
    logic vs_previous;
    logic [1:0] control;
    logic is_control;
    logic [23:0] active_pixels[$];
    logic [23:0] frame_pixels[$];

    function automatic int control_value(input logic [9:0] symbol_i);
        case (symbol_i)
            10'b1101010100: return 0;
            10'b0010101011: return 1;
            10'b0101010100: return 2;
            10'b1010101011: return 3;
            default: return -1;
        endcase
    endfunction

    function automatic logic [7:0] decode(input logic [9:0] symbol_i);
        logic [7:0] transition_word;
        logic [7:0] value;
        transition_word = symbol_i[7:0] ^ {8{symbol_i[9]}};
        value[0] = transition_word[0];
        for (int i = 1; i < 8; i++)
            value[i] = transition_word[i] ^ transition_word[i-1] ^ !symbol_i[8];
        return value;
    endfunction

    always_comb begin
        is_control = control_value(sym_i[9:0]) >= 0;
        control = 2'(control_value(sym_i[9:0]));
        de_o = !is_control;
        hs_o = is_control ? control[0] : hs_hold;
        vs_o = is_control ? control[1] : vs_hold;
        rgb_o = {decode(sym_i[29:20]), decode(sym_i[19:10]), decode(sym_i[9:0])};
        if (is_control) rgb_o = 0;
    end

    always @(posedge clk_pix_i) begin
        if (!rst_n_i) begin
            hs_hold = 0;
            vs_hold = 0;
            vs_previous = 0;
            frame_count_o = 0;
            frame_pixel_count_o = 0;
            active_pixels.delete();
            frame_pixels.delete();
        end else begin
            if (is_control) begin
                if (control_value(sym_i[19:10]) != 0 ||
                    control_value(sym_i[29:20]) != 0)
                    $fatal(1, "FAIL TMDS controls expected=G/R CTL00 actual=%h time=%0t",
                            sym_i, $time);
                hs_hold = control[0];
                vs_hold = control[1];
            end
            if (de_o) active_pixels.push_back(rgb_o);
            if (vs_o && !vs_previous) begin
                frame_pixels = active_pixels;
                frame_pixel_count_o = active_pixels.size();
                frame_count_o++;
                active_pixels.delete();
            end
            vs_previous = vs_o;
        end
    end
endmodule
