// File: edrv32_cpu2_tage_update.v
// Spec: cpu-v2-spec 5.4.
// Description: One branch update from current rows and the saved prediction token.
// Saturate the matching provider and allocate at most one longer row, short to long.
// Clock domain: clk_sys.
module edrv32_cpu2_tage_update (
    // Saved prediction token and current training rows.
    input wire [63:0] rows_i,
    input wire [39:0] tags_i,
    input wire [2:0] provider_i,
    input wire prediction_i,
    input wire alternate_i,
    input wire taken_i,
    input wire [1:0] base_i,
    output wire [1:0] base_o,
    output wire [63:0] rows_o,
    output wire [3:0] write_o
);
    wire [3:0] free_w;
    wire [3:0] allocate_w;
    function [2:0] counter3;
        input [2:0] old_i;
        input up_i;
        begin
            counter3 = up_i ? ((old_i == 3'd7) ? old_i : old_i + 3'd1) :
                ((old_i == 3'd0) ? old_i : old_i - 3'd1);
        end
    endfunction
    function [1:0] counter2;
        input [1:0] old_i;
        input up_i;
        begin
            counter2 = up_i ? ((old_i == 2'd3) ? old_i : old_i + 2'd1) :
                ((old_i == 2'd0) ? old_i : old_i - 2'd1);
        end
    endfunction
    assign base_o = counter2(base_i, taken_i);
    genvar table_num;
    generate
        for (table_num = 0; table_num < 4; table_num = table_num + 1) begin : g_update
            localparam [2:0] PROVIDER = table_num + 1;
            wire [15:0] row_w;
            wire [9:0] tag_w;
            wire provider_hit_w;
            wire pressure_w;
            wire prior_allocation_w;
            assign row_w = rows_i[16*table_num +: 16];
            assign tag_w = tags_i[10*table_num +: 10];
            assign free_w[table_num] = (PROVIDER > provider_i) &&
                (!row_w[15] || (row_w[1:0] == 2'd0));
            if (table_num == 0) begin : g_first
                assign prior_allocation_w = 1'b0;
            end else begin : g_rest
                assign prior_allocation_w = |free_w[table_num-1:0];
            end
            assign allocate_w[table_num] = (prediction_i != taken_i) &&
                free_w[table_num] && !prior_allocation_w;
            assign provider_hit_w = (PROVIDER == provider_i) && row_w[15] &&
                (row_w[14:5] == tag_w);
            assign pressure_w = (prediction_i != taken_i) && (PROVIDER > provider_i) &&
                !free_w[table_num] && !prior_allocation_w;
            assign write_o[table_num] = provider_hit_w || pressure_w || allocate_w[table_num];
            assign rows_o[16*table_num +: 16] = allocate_w[table_num] ?
                {1'b1, tag_w, (taken_i ? 3'd4 : 3'd3), 2'd0} :
                provider_hit_w ? {row_w[15:5], counter3(row_w[4:2], taken_i),
                    ((prediction_i != alternate_i) ?
                        counter2(row_w[1:0], prediction_i == taken_i) : row_w[1:0])} :
                pressure_w ? {row_w[15:2], row_w[1:0] - 2'd1} : row_w;
        end
    endgenerate
endmodule
