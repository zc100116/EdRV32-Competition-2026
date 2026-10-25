// File: edrv32_cdc_handshake.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Transfer held payloads using a request/acknowledge toggle.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_cdc_handshake #(
    parameter WIDTH = 32
) (
    // Clock domains and their resets.
    input wire clk_src_i,
    input wire rst_src_n_i,
    input wire clk_dst_i,
    input wire rst_dst_n_i,

    // Source ready/valid input.
    input wire valid_i,
    output wire ready_o,
    input wire [WIDTH-1:0] data_i,

    // Destination ready/valid output.
    output wire valid_o,
    input wire ready_i,
    output wire [WIDTH-1:0] data_o
);
    reg req_r;
    reg ack_r;
    reg [WIDTH-1:0] data_r;
    wire req_w;
    wire ack_w;

    assign ready_o = (req_r == ack_w);
    assign valid_o = (req_w != ack_r);
    // Payload remains stable until the acknowledgement returns to the source.
    assign data_o = data_r;

    always @(posedge clk_src_i or negedge rst_src_n_i) begin
        if (!rst_src_n_i) begin
            req_r <= 1'b0;
        end else if (valid_i && ready_o) begin
            req_r <= ~req_r;
        end
    end

    always @(posedge clk_src_i) begin
        if (valid_i && ready_o) begin
            data_r <= data_i;
        end
    end

    always @(posedge clk_dst_i or negedge rst_dst_n_i) begin
        if (!rst_dst_n_i) begin
            ack_r <= 1'b0;
        end else if (valid_o && ready_i) begin
            ack_r <= req_w;
        end
    end

    edrv32_cdc_sync_bit u_req (
        // Destination domain.
        .clk_i(clk_dst_i),
        .rst_n_i(rst_dst_n_i),

        // Request toggle.
        .bit_i(req_r),
        .bit_o(req_w)
    );

    edrv32_cdc_sync_bit u_ack (
        // Source domain.
        .clk_i(clk_src_i),
        .rst_n_i(rst_src_n_i),

        // Acknowledgement toggle.
        .bit_i(ack_r),
        .bit_o(ack_w)
    );
endmodule
