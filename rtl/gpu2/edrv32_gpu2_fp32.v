// File: edrv32_gpu2_fp32.v
// Spec: gpu-v2-spec 2.4, architecture M-8 native vec4 and staged DP.
// Description: Four shared two-APM multipliers, vec4 MUL/FMA12 and independent DP16 tree.
// Clock domain: clk_gpu. Separate completion ports preserve the independent adder resources.
module edrv32_gpu2_fp32 (
    // Clock and reset of control state only.
    input wire clk_i,
    input wire rst_n_i,

    // One native vec4 request per edge: 0 MUL, 1 FMA, 2 DP3, 3 DP4.
    input wire req_valid_i,
    output reg req_ready_o,
    input wire [1:0] req_op_i,
    input wire [127:0] req_a_i,
    input wire [127:0] req_b_i,
    input wire [127:0] req_c_i,

    // Independent vector and scalar completion queues, each held through backpressure.
    output wire vec_valid_o,
    input wire vec_ready_i,
    output wire [127:0] vec_data_o,
    output wire dp_valid_o,
    input wire dp_ready_i,
    output wire [31:0] dp_data_o
);
    // DP16 needs more than 16 registered credits for uninterrupted II1 startup.
    // Pair the existing 16-word macros; eight/sixteen-sink bank-select leaves add no edge.
    (* keep = "true", syn_preserve = 1 *) reg [7:0] vec_read_bank_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] dp_read_bank_r;
    wire [4:0] vec_rd_next_w;
    wire [4:0] dp_rd_next_w;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] vec_wr_addr_r;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] vec_rd_addr_r;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] dp_wr_addr_r;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] dp_rd_addr_r;
    wire [4:0] vec_wr_next_w;
    wire [4:0] dp_wr_next_w;
    wire accept_w;
    wire vec_pop_w;
    wire dp_pop_w;
    wire vec_push_w;
    wire dp_push_w;
    reg [10:0] vec_valid_r;
    reg [14:0] dp_valid_r;
    reg [5:0] outstanding_r;
    wire [5:0] outstanding_next_w;
    reg [5:0] vec_count_r;
    reg [5:0] dp_count_r;
    reg [4:0] vec_wr_r;
    reg [4:0] vec_rd_r;
    reg [4:0] dp_wr_r;
    reg [4:0] dp_rd_r;
    assign vec_rd_next_w = vec_rd_r + {4'b0, vec_pop_w};
    assign dp_rd_next_w = dp_rd_r + {4'b0, dp_pop_w};
    assign vec_wr_next_w = vec_wr_r + {4'b0, vec_push_w};
    assign dp_wr_next_w = dp_wr_r + {4'b0, dp_push_w};
    assign accept_w = req_valid_i && req_ready_o;
    assign vec_pop_w = vec_valid_o && vec_ready_i;
    assign dp_pop_w = dp_valid_o && dp_ready_i;
    assign outstanding_next_w = outstanding_r + {5'b0, accept_w}
        - {5'b0, vec_pop_w} - {5'b0, dp_pop_w};
    // The queue write is the last arithmetic boundary, not an added waiting edge.
    assign vec_push_w = vec_valid_r[10];
    assign dp_push_w = dp_valid_r[14];
    assign vec_valid_o = vec_count_r != 0;
    assign dp_valid_o = dp_count_r != 0;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            vec_valid_r <= 11'b0;
            dp_valid_r <= 15'b0;
            outstanding_r <= 6'b0;
            req_ready_o <= 1'b1;
            vec_read_bank_r <= 8'b0;
            vec_wr_addr_r <= 32'b0;
            vec_rd_addr_r <= 32'b0;
            dp_wr_addr_r <= 8'b0;
            dp_rd_addr_r <= 8'b0;
            dp_read_bank_r <= 2'b0;
            vec_count_r <= 6'b0;
            dp_count_r <= 6'b0;
            vec_wr_r <= 5'b0;
            vec_rd_r <= 5'b0;
            dp_wr_r <= 5'b0;
            dp_rd_r <= 5'b0;
        end else begin
            vec_valid_r <= {vec_valid_r[9:0], accept_w && !req_op_i[1]};
            dp_valid_r <= {dp_valid_r[13:0], accept_w && req_op_i[1]};
            outstanding_r <= outstanding_next_w;
            vec_read_bank_r <= {8{vec_rd_next_w[4]}};
            vec_wr_addr_r <= {8{vec_wr_next_w[3:0]}};
            vec_rd_addr_r <= {8{vec_rd_next_w[3:0]}};
            dp_wr_addr_r <= {2{dp_wr_next_w[3:0]}};
            dp_rd_addr_r <= {2{dp_rd_next_w[3:0]}};
            dp_read_bank_r <= {2{dp_rd_next_w[4]}};
            req_ready_o <= outstanding_next_w < 6'd32;
            vec_count_r <= vec_count_r + {5'b0, vec_push_w} - {5'b0, vec_pop_w};
            dp_count_r <= dp_count_r + {5'b0, dp_push_w} - {5'b0, dp_pop_w};
            vec_wr_r <= vec_wr_next_w;
            vec_rd_r <= vec_rd_next_w;
            dp_wr_r <= dp_wr_next_w;
            dp_rd_r <= dp_rd_next_w;
        end
    end
    wire [127:0] products_w;
    genvar lane;
    genvar queue_bank;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            wire [31:0] b_w;
            wire [31:0] product_w;
            wire [31:0] fused_w;
            reg [31:0] s11_vec_r;
            // DP3's fourth product is +0, irrespective of the unused operands.
            wire [31:0] a_w;
            assign a_w = lane == 3 && req_op_i == 2'd2
                ? 32'b0 : req_a_i[lane*32 +: 32];
            assign b_w = lane == 3 && req_op_i == 2'd2
                ? 32'b0 : req_b_i[lane*32 +: 32];
            edrv32_gpu2_fp32_scalar u_scalar (
                .clk_i(clk_i),
                .mul_i(req_op_i != 2'd1),
                .a_i(a_w),
                .b_i(b_w),
                .c_i(req_c_i[lane*32 +: 32]),
                .product_o(product_w),
                .result_o(fused_w)
            );
            always @(posedge clk_i) begin
                s11_vec_r <= fused_w;
            end
            assign products_w[lane*32 +: 32] = product_w;
            wire [63:0] queue_data_w;
            for (queue_bank = 0; queue_bank < 2; queue_bank = queue_bank+1) begin : g_queue
                localparam BANK = queue_bank;
                edrv32_ram_gpu2_queue u_vec_queue (
                    .clk_i(clk_i),
                    .wr_en_i(vec_push_w && vec_wr_r[4] == BANK),
                    .wr_addr_i(vec_wr_addr_r[(lane*2+queue_bank)*4 +: 4]),
                    .wr_data_i(s11_vec_r),
                    .rd_addr_i(vec_rd_addr_r[(lane*2+queue_bank)*4 +: 4]),
                    .rd_data_o(queue_data_w[queue_bank*32 +: 32])
                );
            end
            assign vec_data_o[lane*32 +: 16] = vec_read_bank_r[lane*2]
                ? queue_data_w[47:32] : queue_data_w[15:0];
            assign vec_data_o[lane*32+16 +: 16] = vec_read_bank_r[lane*2+1]
                ? queue_data_w[63:48] : queue_data_w[31:16];
        end
    endgenerate
    wire [31:0] s10_pair01_w;
    wire [31:0] s10_pair23_w;
    wire [31:0] unused_pair01_rounded_w;
    wire [31:0] unused_pair23_rounded_w;
    wire [31:0] dp_rounded_w;
    wire [31:0] unused_dp_registered_w;
    // Three independent FP32 adders; no sharing with the following vec4 FMA.
    edrv32_gpu2_fp32_add u_pair01 (
        .clk_i(clk_i),
        .a_i(products_w[31:0]),
        .b_i(products_w[63:32]),
        .rounded_o(unused_pair01_rounded_w),
        .result_o(s10_pair01_w)
    );
    edrv32_gpu2_fp32_add u_pair23 (
        .clk_i(clk_i),
        .a_i(products_w[95:64]),
        .b_i(products_w[127:96]),
        .rounded_o(unused_pair23_rounded_w),
        .result_o(s10_pair23_w)
    );
    edrv32_gpu2_fp32_add u_dp (
        .clk_i(clk_i),
        .a_i(s10_pair01_w),
        .b_i(s10_pair23_w),
        .rounded_o(dp_rounded_w),
        .result_o(unused_dp_registered_w)
    );
    wire [63:0] dp_queue_data_w;
    genvar dp_bank;
    generate
        for (dp_bank = 0; dp_bank < 2; dp_bank = dp_bank+1) begin : g_dp_queue
            localparam BANK = dp_bank;
            edrv32_ram_gpu2_queue u_dp_queue (
                .clk_i(clk_i),
                .wr_en_i(dp_push_w && dp_wr_r[4] == BANK),
                .wr_addr_i(dp_wr_addr_r[dp_bank*4 +: 4]),
                .wr_data_i(dp_rounded_w),
                .rd_addr_i(dp_rd_addr_r[dp_bank*4 +: 4]),
                .rd_data_o(dp_queue_data_w[dp_bank*32 +: 32])
            );
        end
    endgenerate
    assign dp_data_o[15:0] = dp_read_bank_r[0] ? dp_queue_data_w[47:32] : dp_queue_data_w[15:0];
    assign dp_data_o[31:16] = dp_read_bank_r[1] ? dp_queue_data_w[63:48] : dp_queue_data_w[31:16];
endmodule
