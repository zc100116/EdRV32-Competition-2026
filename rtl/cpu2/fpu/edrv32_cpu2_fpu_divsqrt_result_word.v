// File: edrv32_cpu2_fpu_divsqrt_result_word.v
// Spec: fpu-spec 5.3; cpu-v2-spec 5.1 regional control copies.
// Description: Sixteen-bit held result word with local copies of packet selectors.
//              Metadata is copied at preparation/encoding, without extending latency.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_divsqrt_result_word (
    // Clock and local control reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire capture_next_i,
    input wire encode_next_i,
    input wire pack_next_i,

    // Metadata and candidate words from the precision-specific datapath.
    input wire special_i,
    input wire overflow_i,
    input wire infinity_i,
    input wire [15:0] special_data_i,
    input wire [15:0] finite_data_i,
    input wire [15:0] infinity_data_i,
    input wire [15:0] maximum_data_i,
    output reg [15:0] result_o
);
    (* keep = "true", syn_preserve = 1 *) reg capture_r;
    (* keep = "true", syn_preserve = 1 *) reg encode_r;
    (* keep = "true", syn_preserve = 1 *) reg pack_r;
    (* keep = "true", syn_preserve = 1 *) reg special_r;
    (* keep = "true", syn_preserve = 1 *) reg overflow_r;
    (* keep = "true", syn_preserve = 1 *) reg infinity_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capture_r <= 1'b0;
            encode_r <= 1'b0;
            pack_r <= 1'b0;
        end else begin
            capture_r <= capture_next_i;
            encode_r <= encode_next_i;
            pack_r <= pack_next_i;
        end
    end
    always @(posedge clk_i) begin
        if (capture_r) special_r <= special_i;
        if (encode_r) begin
            overflow_r <= overflow_i;
            infinity_r <= infinity_i;
        end
    end
    always @(posedge clk_i) begin
        if (pack_r) begin
            result_o <= special_r ? special_data_i : overflow_r
                ? (infinity_r ? infinity_data_i : maximum_data_i) : finite_data_i;
        end
    end
endmodule
