// File: edrv32_mem_xbar_sched.v
// Spec: mem-subsys-spec 2.2; edrv32-soc-spec 6.4.2-6.4.5.
// Description: Shared transaction scheduler: urgent, latency, starvation, then DRR.
// Read/write batching only applies to DRR. Tokens use 1/256-beat fixed point.
// Buckets reset full (32 beats). Any other port grant resets an RT urgent streak.
// Clock: clk_mem.
module edrv32_mem_xbar_sched (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Eligible head transactions, indexed by 2*port + write.
    input wire enable_i,
    input wire [13:0] eligible_i,
    input wire [69:0] beats_i,
    input wire [447:0] wait_i,
    input wire [1:0] urgent_i,
    output reg grant_o,
    output reg [2:0] port_o,
    output reg write_o,
    output reg urgent_o,
    output wire dir_switch_o,

    // Runtime configuration.
    input wire [31:0] urg_max_i,
    input wire [31:0] starve_cyc_i,
    input wire [31:0] dir_batch_i,
    input wire [223:0] weight_i,
    input wire [223:0] rate_i
);
    reg [13:0] tokens_r [0:6];
    reg [36:0] deficit_r [0:6];
    reg [31:0] urgent_cnt_r [0:1];
    reg urgent_turn_r;
    reg [2:0] round_ptr_r;
    reg dir_valid_r;
    reg dir_write_r;
    reg [31:0] dir_cnt_r;
    reg [13:0] funded_w;
    reg refill_w;
    reg drr_w;
    reg latency_w;
    reg preferred_w;
    reg [31:0] oldest_w;
    reg [33:0] token_sum_w;
    reg [33:0] token_next_w [0:6];
    integer p;
    integer d;
    integer step;
    integer candidate;
    integer urgent_port;
    integer update_idx;
    integer token_idx;

    assign dir_switch_o = grant_o && dir_valid_r && write_o != dir_write_r;

    always @(*) begin
        funded_w = 14'b0;
        grant_o = 1'b0;
        port_o = 3'b0;
        write_o = 1'b0;
        urgent_o = 1'b0;
        refill_w = 1'b0;
        drr_w = 1'b0;
        latency_w = 1'b0;
        preferred_w = dir_valid_r && dir_cnt_r < dir_batch_i ?
                        dir_write_r : !dir_write_r;
        oldest_w = 32'b0;
        candidate = 0;
        urgent_port = 0;
        for (p = 0; p < 7; p = p + 1) begin
            for (d = 0; d < 2; d = d + 1) begin
                funded_w[p*2+d] = eligible_i[p*2+d] &&
                    ((p != 2 && p != 6) ||
                        {24'b0, tokens_r[p]} >= {25'b0, beats_i[(p*2+d)*5 +: 5], 8'b0});
            end
        end
        if (enable_i) begin
            // RT tie-break rotates between P0-read and P1-write.
            for (step = 0; step < 2; step = step + 1) begin
                urgent_port = (int_unsigned(urgent_turn_r) + step) % 2;
                if (!grant_o && urgent_i[urgent_port] &&
                    urgent_cnt_r[urgent_port] < urg_max_i &&
                    eligible_i[urgent_port*3]) begin
                    grant_o = 1'b1;
                    port_o = urgent_port == 0 ? 3'd0 : 3'd1;
                    write_o = urgent_port != 0;
                    urgent_o = 1'b1;
                end
            end
            // P2 has no DRR weight; tokens qualify its low-latency grants.
            for (step = 0; step < 2; step = step + 1) begin
                candidate = preferred_w ? 5-step : 4+step;
                if (!grant_o && funded_w[candidate]) begin
                    grant_o = 1'b1;
                    latency_w = 1'b1;
                    port_o = 3'd2;
                    write_o = candidate == 5;
                end
            end
            for (p = 0; p < 7; p = p + 1) begin
                for (d = 0; d < 2; d = d + 1) begin
                    if (!urgent_o && !latency_w &&
                        eligible_i[p*2+d] && wait_i[(p*2+d)*32 +: 32] > starve_cyc_i &&
                        (!grant_o || wait_i[(p*2+d)*32 +: 32] > oldest_w)) begin
                        grant_o = 1'b1;
                        port_o = p[2:0];
                        write_o = d != 0;
                        oldest_w = wait_i[(p*2+d)*32 +: 32];
                    end
                end
            end
            if (!grant_o) begin
                for (d = 0; d < 2; d = d + 1) begin
                    for (step = 0; step < 7; step = step + 1) begin
                        candidate = {29'b0, round_ptr_r} + step;
                        if (candidate >= 7) begin
                            candidate = candidate - 7;
                        end
                        if (!grant_o && candidate != 2 &&
                            weight_i[candidate*32 +: 32] != 0 &&
                            funded_w[candidate*2+int_unsigned(preferred_w ^ (d != 0))] &&
                            deficit_r[candidate] >=
                            {32'b0,
                                beats_i[(candidate*2+int_unsigned(preferred_w ^ (d != 0)))*5 +: 5]})
                        begin
                            grant_o = 1'b1;
                            port_o = candidate[2:0];
                            write_o = preferred_w ^ (d != 0);
                            drr_w = 1'b1;
                        end
                    end
                end
                refill_w = !grant_o;
            end
        end
    end

    // A Verilog-2001 sized conversion keeps loop-index arithmetic unsigned and explicit.
    function integer int_unsigned;
        input value_i;
        begin
            int_unsigned = value_i ? 1 : 0;
        end
    endfunction

    always @(*) begin
        token_sum_w = 34'b0;
        for (token_idx = 0; token_idx < 7; token_idx = token_idx + 1) begin
            token_next_w[token_idx] = {20'b0, tokens_r[token_idx]};
            if (token_idx == 2 || token_idx == 6) begin
                token_sum_w = {20'b0, tokens_r[token_idx]} +
                                {2'b0, rate_i[token_idx*32 +: 32]};
                if (grant_o && {29'b0, port_o} == token_idx) begin
                    // Starvation grants bypass tokens. They consume all remaining tokens.
                    if (token_sum_w >=
                        {21'b0, beats_i[(token_idx*2+int_unsigned(write_o))*5 +: 5], 8'b0}) begin
                        token_sum_w = token_sum_w -
                            {21'b0, beats_i[(token_idx*2+int_unsigned(write_o))*5 +: 5], 8'b0};
                    end else begin
                        token_sum_w = 34'b0;
                    end
                end
                token_next_w[token_idx] = token_sum_w > 34'd8192 ? 34'd8192 : token_sum_w;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            urgent_turn_r <= 1'b0;
            round_ptr_r <= 3'b0;
            dir_valid_r <= 1'b0;
            dir_write_r <= 1'b0;
            dir_cnt_r <= 32'b0;
            urgent_cnt_r[0] <= 32'b0;
            urgent_cnt_r[1] <= 32'b0;
            for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                tokens_r[update_idx] <= 14'd8192;
                deficit_r[update_idx] <= 37'b0;
            end
        end else begin
            for (update_idx = 0; update_idx < 7; update_idx = update_idx + 1) begin
                tokens_r[update_idx] <= token_next_w[update_idx][13:0];
                if (refill_w && update_idx != 2 &&
                    (funded_w[update_idx*2] || funded_w[update_idx*2+1])) begin
                    deficit_r[update_idx] <= deficit_r[update_idx] +
                                            {1'b0, weight_i[update_idx*32 +: 32], 4'b0};
                end
                if (grant_o && drr_w && {29'b0, port_o} == update_idx) begin
                    deficit_r[update_idx] <= deficit_r[update_idx] -
                        {32'b0, beats_i[(update_idx*2+int_unsigned(write_o))*5 +: 5]};
                    round_ptr_r <= port_o;
                end
            end
            if (!urgent_i[0] || (grant_o && port_o != 3'd0)) begin
                urgent_cnt_r[0] <= 32'b0;
            end
            if (!urgent_i[1] || (grant_o && port_o != 3'd1)) begin
                urgent_cnt_r[1] <= 32'b0;
            end
            if (grant_o && urgent_o) begin
                urgent_cnt_r[port_o[0]] <= urgent_cnt_r[port_o[0]] + 32'd1;
                urgent_turn_r <= !port_o[0];
            end
            if (grant_o) begin
                dir_valid_r <= 1'b1;
                dir_write_r <= write_o;
                if (!dir_valid_r || write_o != dir_write_r) begin
                    dir_cnt_r <= 32'd1;
                end else if (dir_cnt_r != 32'hffff_ffff) begin
                    dir_cnt_r <= dir_cnt_r + 32'd1;
                end
            end
        end
    end
endmodule
