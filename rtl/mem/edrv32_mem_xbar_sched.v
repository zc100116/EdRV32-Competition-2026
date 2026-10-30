// File: edrv32_mem_xbar_sched.v
// Spec: mem-subsys-spec 2.2; edrv32-soc-spec 6.4.2-6.4.5; task M-R2b.
// Description: Registered affordability stage followed by mask-only priority selection.
// Urgent, latency, rotating starvation and DRR share transaction grants. Batching
// only chooses the DRR direction. Token buckets reset full at 32 beats.
// M-I1 confirmed: queued nonzero-weight heads retain round credit under capacity
// or token stalls. Refill only an insufficient deficit; its maximum is 15+240=255.
// Start a round only with a capacity/token-ready DRR head; idle capacity never refills.
// Clock: clk_mem.
module edrv32_mem_xbar_sched (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Preparation pulse also registers the top-level eligibility mask.
    input wire enable_i,
    input wire [13:0] candidates_i,
    input wire [13:0] queued_i,
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
    // X-F1 path 4: cached rotation masks and per-direction accounting precede selection.
    wire unused_rate_w;
    assign unused_rate_w = &{rate_i[53:27], rate_i[17:0]};
    reg prepared_r;
    reg [13:0] funded_r;
    reg [13:0] queued_r;
    reg [13:0] deficit_enough_r;
    reg [6:0] weighted_r;
    reg [1:0] urgent_allowed_r;
    reg preferred_r;
    reg [13:0] tokens_r [0:1];
    reg [7:0] deficit_r [0:6];
    reg [7:0] urgent_cnt_r [0:1];
    reg urgent_turn_r;
    reg [6:0] round_mask_r;
    reg [6:0] starve_mask_r;
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
    wire [6:0] drr_eligible_w;
    wire [13:0] token_next_w [0:1];
    integer update_idx;
    genvar p;

    function [13:0] token_bound;
        input [7:0] whole_i;
        input [7:0] fraction_i;
        begin
            token_bound = whole_i[7] ? 14'b0 :
                whole_i >= 8'd32 ? 14'd8192 : {whole_i[5:0], fraction_i};
        end
    endfunction

    assign prepare_o = enable_i && !prepared_r;
    assign dir_switch_o = grant_o && dir_valid_r && write_o != dir_write_r;
    assign starve_w = eligible_i & starved_i;
    assign rt_w = {|eligible_i[3:2], eligible_i[0]} & urgent_allowed_r;
    assign lat_w = eligible_i[5:4] & funded_r[5:4];
    assign refill_w = enable_i && prepared_r && |drr_eligible_w &&
        !(|rt_w || |lat_w || |starve_ports_w || |drr_read_w || |drr_write_w);

    generate
        for (p = 0; p < 7; p = p + 1) begin : g_masks
            assign drr_eligible_w[p] = (|(eligible_i[p*2 +: 2] &
                funded_r[p*2 +: 2])) && weighted_r[p] && p != 2;
            assign starve_ports_w[p] = |starve_w[p*2 +: 2];
            assign drr_read_w[p] = eligible_i[p*2] && funded_r[p*2] &&
                deficit_enough_r[p*2] && weighted_r[p] && p != 2;
            assign drr_write_w[p] = eligible_i[p*2+1] && funded_r[p*2+1] &&
                deficit_enough_r[p*2+1] && weighted_r[p] && p != 2;
        end
    endgenerate

    function [2:0] first7;
        input [6:0] mask_i;
        input [6:0] priority_i;
        reg [6:0] choice_w;
        begin
            choice_w = |(mask_i & priority_i) ? mask_i & priority_i : mask_i;
            if (choice_w[0]) first7 = 3'd0;
            else if (choice_w[1]) first7 = 3'd1;
            else if (choice_w[2]) first7 = 3'd2;
            else if (choice_w[3]) first7 = 3'd3;
            else if (choice_w[4]) first7 = 3'd4;
            else if (choice_w[5]) first7 = 3'd5;
            else first7 = choice_w[6] ? 3'd6 : 3'd0;
        end
    endfunction

    wire [2:0] rt_port_w;
    wire [2:0] starve_port_w;
    wire [2:0] drr_port_w;
    wire drr_write_select_w;
    assign rt_port_w = {2'b0, rt_w[urgent_turn_r] ? urgent_turn_r : !urgent_turn_r};
    assign starve_port_w = first7(starve_ports_w, starve_mask_r);
    // Both direction priorities are evaluated before direction/class selection.
    assign drr_write_select_w = preferred_r ? |drr_write_w : !(|drr_read_w);
    assign drr_port_w = drr_write_select_w ? first7(drr_write_w, round_mask_r) :
        first7(drr_read_w, round_mask_r);
    always @(*) begin
        drr_ports_w = preferred_r ? drr_write_w : drr_read_w;
        if (drr_ports_w == 0) begin
            drr_ports_w = preferred_r ? drr_read_w : drr_write_w;
        end
    end
    // Only small masks and registered preference state enter grant selection.
    always @(*) begin
        grant_o = 1'b0;
        port_o = 3'b0;
        write_o = 1'b0;
        urgent_o = 1'b0;
        drr_w = 1'b0;
        starvation_w = 1'b0;
        if (enable_i && prepared_r) begin
            if (|rt_w) begin
                grant_o = 1'b1;
                urgent_o = 1'b1;
                port_o = rt_port_w;
                write_o = eligible_i[{rt_port_w, preferred_r}] ?
                    preferred_r : !preferred_r;
            end else if (|lat_w) begin
                grant_o = 1'b1;
                port_o = 3'd2;
                write_o = lat_w[preferred_r] ? preferred_r : !preferred_r;
            end else if (|starve_ports_w) begin
                grant_o = 1'b1;
                starvation_w = 1'b1;
                port_o = starve_port_w;
                write_o = starve_w[{starve_port_w, preferred_r}] ?
                    preferred_r : !preferred_r;
            end else if (|drr_ports_w) begin
                grant_o = 1'b1;
                drr_w = 1'b1;
                port_o = drr_port_w;
                write_o = drr_write_select_w;
            end
        end
    end

    // X-F1 path 4: token arithmetic precedes grant selection, for both directions.
    // Rule 3 can consume an empty bucket; saturate each candidate before the final mux.
    generate
        for (p = 0; p < 2; p = p + 1) begin : g_token_next
            localparam PORT = p == 0 ? 2 : 6;
            wire [8:0] fraction_w;
            wire [7:0] idle_base_w;
            wire [7:0] read_base_w;
            wire [7:0] write_base_w;
            wire [13:0] idle_w;
            wire [13:0] read_w;
            wire [13:0] write_w;
            assign fraction_w = {1'b0, tokens_r[p][7:0]} +
                {1'b0, rate_i[PORT*9 +: 8]};
            assign idle_base_w = {2'b0, tokens_r[p][13:8]} +
                {7'b0, rate_i[PORT*9+8]};
            assign read_base_w = idle_base_w - {3'b0, beats_i[PORT*10 +: 5]};
            assign write_base_w = idle_base_w - {3'b0, beats_i[PORT*10+5 +: 5]};
            // The fractional carry selects already bounded whole-beat candidates.
            assign idle_w = fraction_w[8] ?
                token_bound(idle_base_w + 8'd1, fraction_w[7:0]) :
                token_bound(idle_base_w, fraction_w[7:0]);
            assign read_w = fraction_w[8] ?
                token_bound(read_base_w + 8'd1, fraction_w[7:0]) :
                token_bound(read_base_w, fraction_w[7:0]);
            assign write_w = fraction_w[8] ?
                token_bound(write_base_w + 8'd1, fraction_w[7:0]) :
                token_bound(write_base_w, fraction_w[7:0]);
            assign token_next_w[p] = grant_o && port_o == PORT ?
                (write_o ? write_w : read_w) : idle_w;
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            prepared_r <= 1'b0;
            funded_r <= 14'b0;
            queued_r <= 14'b0;
            deficit_enough_r <= 14'b0;
            weighted_r <= 7'b0;
            urgent_allowed_r <= 2'b0;
            preferred_r <= 1'b0;
            urgent_turn_r <= 1'b0;
            round_mask_r <= 7'h7f;
            starve_mask_r <= 7'h7f;
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
                tokens_r[update_idx] <= token_next_w[update_idx];
                if (!urgent_i[update_idx] ||
                    (grant_o && port_o != {2'b0, update_idx[0]})) begin
                    urgent_cnt_r[update_idx] <= 8'b0;
                end
            end
            if (prepare_o) begin
                queued_r <= queued_i;
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
                if (refill_w && update_idx != 2 && weighted_r[update_idx] &&
                    (|(queued_r[update_idx*2 +: 2] &
                        ~deficit_enough_r[update_idx*2 +: 2]))) begin
                    deficit_r[update_idx] <= deficit_r[update_idx] +
                        {weight_i[update_idx*4 +: 4], 4'b0};
                end
                if (grant_o && drr_w && port_o == update_idx[2:0]) begin
                    deficit_r[update_idx] <= write_o ?
                        deficit_r[update_idx] - {3'b0, beats_i[update_idx*10+5 +: 5]} :
                        deficit_r[update_idx] - {3'b0, beats_i[update_idx*10 +: 5]};
                end
            end
            if (grant_o && drr_w) round_mask_r <= 7'h7f << port_o;
            if (grant_o && starvation_w) begin
                starve_mask_r <= port_o == 3'd6 ? 7'h7f : (7'h7f << (port_o + 3'd1));
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
