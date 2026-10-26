// File: edrv32_mem_xbar_sched.v
// Spec: mem-subsys-spec 2.2; edrv32-soc-spec 6.4.2-6.4.5; task M-R2b.
// Description: Registered affordability stage followed by mask-only priority selection.
// Urgent, latency, rotating starvation and DRR share transaction grants. Batching
// only chooses the DRR direction. Token buckets reset full at 32 beats.
// Clock: clk_mem.
module edrv32_mem_xbar_sched (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Preparation pulse also registers the top-level eligibility mask.
    input wire enable_i,
    input wire [13:0] candidates_i,
    output wire prepare_o,
    input wire [13:0] eligible_i,
    input wire [69:0] beats_i,
    input wire [13:0] starved_i,
    input wire [1:0] urgent_i,
    output reg grant_o,
    output reg [2:0] port_o,
    output reg write_o,
    output reg urgent_o,
    output wire dir_switch_o,

    // Runtime configuration, with exact implemented register widths.
    input wire [7:0] urg_max_i,
    input wire [7:0] dir_batch_i,
    input wire [27:0] weight_i,
    input wire [62:0] rate_i
);
    reg prepared_r;
    reg [13:0] funded_r;
    reg [13:0] deficit_enough_r;
    reg [6:0] weighted_r;
    reg [1:0] urgent_allowed_r;
    reg preferred_r;
    reg [13:0] tokens_r [0:1];
    reg [7:0] deficit_r [0:6];
    reg [7:0] urgent_cnt_r [0:1];
    reg urgent_turn_r;
    reg [2:0] round_ptr_r;
    reg [2:0] starve_ptr_r;
    reg dir_valid_r;
    reg dir_write_r;
    reg [7:0] dir_cnt_r;
    wire [6:0] starve_ports_w;
    wire [6:0] drr_read_w;
    wire [6:0] drr_write_w;
    wire [13:0] starve_w;
    wire [1:0] rt_w;
    wire [1:0] lat_w;
    reg drr_w;
    reg starvation_w;
    reg [6:0] drr_ports_w;
    wire refill_w;
    wire [3:0] grant_queue_w;
    wire [4:0] grant_beats_w;
    reg [14:0] token_sum_w [0:1];
    integer update_idx;
    integer token_idx;
    genvar p;

    function [2:0] first7;
        input [6:0] mask_i;
        input [2:0] turn_i;
        reg [13:0] unused_doubled_w;
        reg [6:0] rotated_w;
        reg [2:0] offset_w;
        reg [3:0] index_w;
        begin
            unused_doubled_w = {mask_i, mask_i} >> turn_i;
            rotated_w = unused_doubled_w[6:0];
            if (rotated_w[0]) offset_w = 3'd0;
            else if (rotated_w[1]) offset_w = 3'd1;
            else if (rotated_w[2]) offset_w = 3'd2;
            else if (rotated_w[3]) offset_w = 3'd3;
            else if (rotated_w[4]) offset_w = 3'd4;
            else if (rotated_w[5]) offset_w = 3'd5;
            else offset_w = rotated_w[6] ? 3'd6 : 3'd0;
            index_w = {1'b0, turn_i} + {1'b0, offset_w};
            first7 = index_w >= 4'd7 ? index_w[2:0] - 3'd7 : index_w[2:0];
        end
    endfunction

    assign prepare_o = enable_i && !prepared_r;
    assign grant_queue_w = {port_o, write_o};
    assign grant_beats_w = beats_i[grant_queue_w*5 +: 5];
    assign dir_switch_o = grant_o && dir_valid_r && write_o != dir_write_r;
    assign starve_w = eligible_i & starved_i;
    assign rt_w = {eligible_i[3], eligible_i[0]} & urgent_allowed_r;
    assign lat_w = eligible_i[5:4] & funded_r[5:4];
    assign refill_w = enable_i && prepared_r && !grant_o;

    generate
        for (p = 0; p < 7; p = p + 1) begin : g_masks
            assign starve_ports_w[p] = |starve_w[p*2 +: 2];
            assign drr_read_w[p] = eligible_i[p*2] && funded_r[p*2] &&
                deficit_enough_r[p*2] && weighted_r[p] && p != 2;
            assign drr_write_w[p] = eligible_i[p*2+1] && funded_r[p*2+1] &&
                deficit_enough_r[p*2+1] && weighted_r[p] && p != 2;
        end
    endgenerate

    // Only small masks and registered preference state enter grant selection.
    always @(*) begin
        grant_o = 1'b0;
        port_o = 3'b0;
        write_o = 1'b0;
        urgent_o = 1'b0;
        drr_w = 1'b0;
        starvation_w = 1'b0;
        drr_ports_w = preferred_r ? drr_write_w : drr_read_w;
        if (drr_ports_w == 0) begin
            drr_ports_w = preferred_r ? drr_read_w : drr_write_w;
        end
        if (enable_i && prepared_r) begin
            if (|rt_w) begin
                grant_o = 1'b1;
                urgent_o = 1'b1;
                write_o = rt_w[urgent_turn_r] ? urgent_turn_r : !urgent_turn_r;
                port_o = {2'b0, write_o};
            end else if (|lat_w) begin
                grant_o = 1'b1;
                port_o = 3'd2;
                write_o = lat_w[preferred_r] ? preferred_r : !preferred_r;
            end else if (|starve_ports_w) begin
                grant_o = 1'b1;
                starvation_w = 1'b1;
                port_o = first7(starve_ports_w, starve_ptr_r);
                write_o = starve_w[{port_o, preferred_r}] ? preferred_r : !preferred_r;
            end else if (|drr_ports_w) begin
                grant_o = 1'b1;
                drr_w = 1'b1;
                port_o = first7(drr_ports_w, round_ptr_r);
                write_o = preferred_r ? drr_write_w[port_o] : !drr_read_w[port_o];
            end
        end
    end

    always @(*) begin
        for (token_idx = 0; token_idx < 2; token_idx = token_idx + 1) begin
            token_sum_w[token_idx] = {1'b0, tokens_r[token_idx]} +
                {6'b0, rate_i[(token_idx == 0 ? 2 : 6)*9 +: 9]};
            if (grant_o && port_o == (token_idx == 0 ? 3'd2 : 3'd6)) begin
                if (token_sum_w[token_idx] >= {2'b0, grant_beats_w, 8'b0}) begin
                    token_sum_w[token_idx] = token_sum_w[token_idx] -
                        {2'b0, grant_beats_w, 8'b0};
                end else begin
                    // Rule 3 bypasses an empty bucket and consumes its remainder.
                    token_sum_w[token_idx] = 15'b0;
                end
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            prepared_r <= 1'b0;
            funded_r <= 14'b0;
            deficit_enough_r <= 14'b0;
            weighted_r <= 7'b0;
            urgent_allowed_r <= 2'b0;
            preferred_r <= 1'b0;
            urgent_turn_r <= 1'b0;
            round_ptr_r <= 3'b0;
            starve_ptr_r <= 3'b0;
            dir_valid_r <= 1'b0;
            dir_write_r <= 1'b0;
            dir_cnt_r <= 8'b0;
            urgent_cnt_r[0] <= 8'b0;
            urgent_cnt_r[1] <= 8'b0;
            tokens_r[0] <= 14'd8192;
            tokens_r[1] <= 14'd8192;
            for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                deficit_r[update_idx] <= 8'b0;
            end
        end else begin
            prepared_r <= prepare_o && |candidates_i;
            for (update_idx = 0; update_idx < 2; update_idx = update_idx + 1) begin
                tokens_r[update_idx] <= token_sum_w[update_idx] > 15'd8192 ?
                    14'd8192 : token_sum_w[update_idx][13:0];
                if (!urgent_i[update_idx] ||
                    (grant_o && port_o != {2'b0, update_idx[0]})) begin
                    urgent_cnt_r[update_idx] <= 8'b0;
                end
            end
            if (prepare_o) begin
                preferred_r <= dir_valid_r && dir_cnt_r < dir_batch_i ?
                    dir_write_r : !dir_write_r;
                urgent_allowed_r <= urgent_i &
                    {urgent_cnt_r[1] < urg_max_i, urgent_cnt_r[0] < urg_max_i};
                for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                    weighted_r[update_idx] <= weight_i[update_idx*4 +: 4] != 0;
                    funded_r[update_idx*2] <= (update_idx != 2 && update_idx != 6) ||
                        tokens_r[update_idx == 2 ? 0 : 1] >=
                        {1'b0, beats_i[update_idx*10 +: 5], 8'b0};
                    funded_r[update_idx*2+1] <= (update_idx != 2 && update_idx != 6) ||
                        tokens_r[update_idx == 2 ? 0 : 1] >=
                        {1'b0, beats_i[update_idx*10+5 +: 5], 8'b0};
                    deficit_enough_r[update_idx*2] <= deficit_r[update_idx] >=
                        {3'b0, beats_i[update_idx*10 +: 5]};
                    deficit_enough_r[update_idx*2+1] <= deficit_r[update_idx] >=
                        {3'b0, beats_i[update_idx*10+5 +: 5]};
                end
            end
            for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                if (refill_w && update_idx != 2 &&
                    (|(eligible_i[update_idx*2 +: 2] & funded_r[update_idx*2 +: 2]))) begin
                    deficit_r[update_idx] <= deficit_r[update_idx] +
                        {weight_i[update_idx*4 +: 4], 4'b0};
                end
                if (grant_o && drr_w && port_o == update_idx[2:0]) begin
                    deficit_r[update_idx] <= deficit_r[update_idx] - {3'b0, grant_beats_w};
                end
            end
            if (grant_o && drr_w) round_ptr_r <= port_o;
            if (grant_o && starvation_w) begin
                starve_ptr_r <= port_o == 3'd6 ? 3'd0 : port_o + 3'd1;
            end
            if (grant_o && urgent_o) begin
                urgent_cnt_r[port_o[0]] <= urgent_cnt_r[port_o[0]] + 8'd1;
                urgent_turn_r <= !port_o[0];
            end
            if (grant_o) begin
                dir_valid_r <= 1'b1;
                dir_write_r <= write_o;
                if (!dir_valid_r || write_o != dir_write_r) dir_cnt_r <= 8'd1;
                else if (dir_cnt_r != 8'hff) dir_cnt_r <= dir_cnt_r + 8'd1;
            end
        end
    end
endmodule
