// File: edrv32_gpu_list_pack.v
// Spec: gpu-spec 2.9, 5; gpu-microarch 4.5.
// Description: Ordered object writeback and capacity-limited hit/free list tail packing.
// Only list entries within MAX are written; object owns visible counts and overflow.
// Clock: clk_gpu.
module edrv32_gpu_list_pack (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Command and previously captured register configuration.
    input wire pack_valid_i,
    output wire pack_ready_o,
    input wire [255:0] pack_command_i,
    input wire [31:0] object_cfg_hit_base_i,
    input wire [23:0] object_cfg_hit_max_i,
    input wire [31:0] object_cfg_free_base_i,
    input wire [23:0] object_cfg_free_max_i,

    // Ordered object updates and events.
    input wire object_update_valid_i,
    output wire object_update_ready_o,
    input wire [23:0] object_update_idx_i,
    input wire [255:0] object_update_data_i,
    input wire object_event_valid_i,
    output wire object_event_ready_o,
    input wire [23:0] object_event_idx_i,
    input wire [7:0] object_event_hit_i,
    input wire object_event_free_i,

    // Independent write clients.
    output wire object_write_req_valid_o,
    input wire object_write_req_ready_i,
    output wire [31:0] object_write_req_addr_o,
    output wire [31:0] object_write_req_bytes_o,
    output wire object_write_data_valid_o,
    input wire object_write_data_ready_i,
    output wire [255:0] object_write_data_data_o,
    output wire [31:0] object_write_data_keep_o,
    output wire object_write_data_last_o,
    input wire object_write_done_i,
    output wire hit_write_req_valid_o,
    input wire hit_write_req_ready_i,
    output wire [31:0] hit_write_req_addr_o,
    output wire [31:0] hit_write_req_bytes_o,
    output wire hit_write_data_valid_o,
    input wire hit_write_data_ready_i,
    output wire [255:0] hit_write_data_data_o,
    output wire [31:0] hit_write_data_keep_o,
    output wire hit_write_data_last_o,
    input wire hit_write_done_i,
    output wire free_write_req_valid_o,
    input wire free_write_req_ready_i,
    output wire [31:0] free_write_req_addr_o,
    output wire [31:0] free_write_req_bytes_o,
    output wire free_write_data_valid_o,
    input wire free_write_data_ready_i,
    output wire [255:0] free_write_data_data_o,
    output wire [31:0] free_write_data_keep_o,
    output wire free_write_data_last_o,
    input wire free_write_done_i,

    // Finish follows object unit_done; stop retains data for accepted DMA requests.
    input wire finish_i,
    input wire stop_i,
    output wire unit_done_o
);
    reg busy_r;
    reg done_r;
    reg step_r;
    reg [31:0] object_base_r;
    reg [31:0] hit_base_r;
    reg [31:0] free_base_r;
    reg [23:0] hit_max_r;
    reg [23:0] free_max_r;
    reg [23:0] hit_count_r;
    reg [23:0] free_count_r;
    reg [255:0] hit_pack_r;
    reg [255:0] free_pack_r;
    reg [3:0] hit_items_r;
    reg [3:0] free_items_r;
    reg [23:0] event_idx_r [0:1];
    reg [7:0] event_hit_r [0:1];
    reg event_free_r [0:1];
    reg event_head_r;
    reg event_tail_r;
    reg [1:0] event_count_r;
    reg [3:0] event_target_r;
    wire event_push_w;
    wire event_pop_w;
    wire process_hit_w;
    wire process_free_w;
    wire hit_flush_w;
    wire free_flush_w;
    wire [2:0] queue_push_w;
    wire [2:0] queue_pop_w;
    wire [2:0] req_ready_w;
    wire [2:0] data_ready_w;
    wire [2:0] write_done_w;
    reg [255:0] data_r [0:5];
    reg [31:0] addr_r [0:5];
    reg [5:0] bytes_r [0:5];
    reg [2:0] head_r;
    reg [2:0] tail_r;
    reg [1:0] count_r [0:2];
    reg [1:0] write_state_r [0:2];
    wire unused_command_w;
    assign unused_command_w = ^{pack_command_i[255:96], pack_command_i[68:33],
        pack_command_i[31:0]};
    assign pack_ready_o = !busy_r;
    assign unit_done_o = done_r;
    assign object_update_ready_o = stop_i || (busy_r && count_r[0] < 2);
    assign object_event_ready_o = stop_i || (busy_r && event_count_r < 2);
    assign event_push_w = object_event_valid_i && object_event_ready_o && !stop_i;
    assign event_pop_w = event_count_r != 0 && event_target_r == 4'd9;
    assign process_hit_w = event_count_r != 0 && event_target_r < 4'd8
        && hit_items_r < 4'd8 && !stop_i;
    assign process_free_w = event_count_r != 0 && event_target_r == 4'd8
        && free_items_r < 4'd8 && !stop_i;
    assign hit_flush_w = hit_items_r != 0 && count_r[1] < 2 && !stop_i
        && (hit_items_r == 4'd8 || (finish_i && event_count_r == 0));
    assign free_flush_w = free_items_r != 0 && count_r[2] < 2 && !stop_i
        && (free_items_r == 4'd8 || (finish_i && event_count_r == 0));
    assign queue_push_w[0] = object_update_valid_i && object_update_ready_o && !stop_i;
    assign queue_push_w[1] = hit_flush_w;
    assign queue_push_w[2] = free_flush_w;
    assign req_ready_w[0] = object_write_req_ready_i;
    assign data_ready_w[0] = object_write_data_ready_i;
    assign write_done_w[0] = object_write_done_i;
    assign object_write_req_valid_o = count_r[0] != 0 && write_state_r[0] == 0 && !stop_i;
    assign object_write_req_addr_o = addr_r[0+{31'b0, head_r[0]}];
    assign object_write_req_bytes_o = {26'b0, bytes_r[0+{31'b0, head_r[0]}]};
    assign object_write_data_valid_o = write_state_r[0] == 1;
    assign object_write_data_data_o = data_r[0+{31'b0, head_r[0]}];
    assign object_write_data_keep_o = 32'hffffffff
        >> (6'd32 - bytes_r[0+{31'b0, head_r[0]}]);
    assign object_write_data_last_o = 1'b1;
    assign queue_pop_w[0] = write_state_r[0] == 1 && data_ready_w[0];
    assign req_ready_w[1] = hit_write_req_ready_i;
    assign data_ready_w[1] = hit_write_data_ready_i;
    assign write_done_w[1] = hit_write_done_i;
    assign hit_write_req_valid_o = count_r[1] != 0 && write_state_r[1] == 0 && !stop_i;
    assign hit_write_req_addr_o = addr_r[2+{31'b0, head_r[1]}];
    assign hit_write_req_bytes_o = {26'b0, bytes_r[2+{31'b0, head_r[1]}]};
    assign hit_write_data_valid_o = write_state_r[1] == 1;
    assign hit_write_data_data_o = data_r[2+{31'b0, head_r[1]}];
    assign hit_write_data_keep_o = 32'hffffffff
        >> (6'd32 - bytes_r[2+{31'b0, head_r[1]}]);
    assign hit_write_data_last_o = 1'b1;
    assign queue_pop_w[1] = write_state_r[1] == 1 && data_ready_w[1];
    assign req_ready_w[2] = free_write_req_ready_i;
    assign data_ready_w[2] = free_write_data_ready_i;
    assign write_done_w[2] = free_write_done_i;
    assign free_write_req_valid_o = count_r[2] != 0 && write_state_r[2] == 0 && !stop_i;
    assign free_write_req_addr_o = addr_r[4+{31'b0, head_r[2]}];
    assign free_write_req_bytes_o = {26'b0, bytes_r[4+{31'b0, head_r[2]}]};
    assign free_write_data_valid_o = write_state_r[2] == 1;
    assign free_write_data_data_o = data_r[4+{31'b0, head_r[2]}];
    assign free_write_data_keep_o = 32'hffffffff
        >> (6'd32 - bytes_r[4+{31'b0, head_r[2]}]);
    assign free_write_data_last_o = 1'b1;
    assign queue_pop_w[2] = write_state_r[2] == 1 && data_ready_w[2];

    always @(posedge clk_i) begin
        if (pack_valid_i && pack_ready_o) begin
            step_r <= pack_command_i[32];
            object_base_r <= {pack_command_i[95:69], 5'b0};
            hit_base_r <= object_cfg_hit_base_i;
            free_base_r <= object_cfg_free_base_i;
            hit_max_r <= object_cfg_hit_max_i;
            free_max_r <= object_cfg_free_max_i;
        end
        if (event_push_w) begin
            event_idx_r[event_tail_r] <= object_event_idx_i;
            event_hit_r[event_tail_r] <= object_event_hit_i;
            event_free_r[event_tail_r] <= object_event_free_i;
        end
        if (queue_push_w[0]) begin
            data_r[{31'b0, tail_r[0]}] <= object_update_data_i;
            addr_r[{31'b0, tail_r[0]}] <= object_base_r
                + {3'b0, object_update_idx_i, 5'b0};
            bytes_r[{31'b0, tail_r[0]}] <= 6'd32;
        end
        if (process_hit_w && event_hit_r[event_head_r][event_target_r[2:0]]
            && hit_count_r < hit_max_r)
            hit_pack_r[hit_items_r[2:0]*32 +: 32] <=
                {5'b0, event_target_r[2:0], event_idx_r[event_head_r]};
        if (process_free_w && event_free_r[event_head_r] && free_count_r < free_max_r)
            free_pack_r[free_items_r[2:0]*32 +: 32] <= {8'b0, event_idx_r[event_head_r]};
        if (hit_flush_w) begin
            data_r[2+{31'b0, tail_r[1]}] <= hit_pack_r;
            addr_r[2+{31'b0, tail_r[1]}] <= hit_base_r
                + {6'b0, (hit_count_r - {20'b0, hit_items_r}), 2'b0};
            bytes_r[2+{31'b0, tail_r[1]}] <= {hit_items_r, 2'b0};
        end
        if (free_flush_w) begin
            data_r[4+{31'b0, tail_r[2]}] <= free_pack_r;
            addr_r[4+{31'b0, tail_r[2]}] <= free_base_r
                + {6'b0, (free_count_r - {20'b0, free_items_r}), 2'b0};
            bytes_r[4+{31'b0, tail_r[2]}] <= {free_items_r, 2'b0};
        end
    end

    genvar c;
    generate
        for (c = 0; c < 3; c = c + 1) begin : g_writer
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    head_r[c] <= 1'b0;
                    tail_r[c] <= 1'b0;
                    count_r[c] <= 2'b0;
                    write_state_r[c] <= 2'b0;
                end else if (pack_valid_i && pack_ready_o) begin
                    head_r[c] <= 1'b0;
                    tail_r[c] <= 1'b0;
                    count_r[c] <= 2'b0;
                    write_state_r[c] <= 2'b0;
                end else begin
                    if (queue_push_w[c]) tail_r[c] <= !tail_r[c];
                    if (queue_pop_w[c]) head_r[c] <= !head_r[c];
                    case ({queue_push_w[c], queue_pop_w[c]})
                        2'b10: count_r[c] <= count_r[c] + 2'd1;
                        2'b01: count_r[c] <= count_r[c] - 2'd1;
                        default: begin end
                    endcase
                    begin
                        case (write_state_r[c])
                            2'd0: begin
                                if (stop_i) count_r[c] <= 2'b0;
                                else if (count_r[c] != 0 && req_ready_w[c])
                                    write_state_r[c] <= 2'd1;
                            end
                            2'd1: if (data_ready_w[c]) write_state_r[c] <= 2'd2;
                            2'd2: if (write_done_w[c]) write_state_r[c] <= 2'd0;
                            default: begin end
                        endcase
                    end
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            done_r <= 1'b1;
            hit_count_r <= 24'b0;
            free_count_r <= 24'b0;
            hit_items_r <= 4'b0;
            free_items_r <= 4'b0;
            event_head_r <= 1'b0;
            event_tail_r <= 1'b0;
            event_count_r <= 2'b0;
            event_target_r <= 4'b0;
        end else begin
            if (pack_valid_i && pack_ready_o) begin
                event_head_r <= 1'b0;
                event_tail_r <= 1'b0;
                event_count_r <= 2'b0;
                event_target_r <= 4'b0;
                busy_r <= 1'b1;
                done_r <= 1'b0;
                hit_count_r <= 24'b0;
                free_count_r <= 24'b0;
                hit_items_r <= 4'b0;
                free_items_r <= 4'b0;
            end
            if (event_push_w) event_tail_r <= !event_tail_r;
            if (event_pop_w) begin
                event_head_r <= !event_head_r;
                event_target_r <= 4'b0;
            end
            begin
                case ({event_push_w, event_pop_w})
                    2'b10: event_count_r <= event_count_r + 2'd1;
                    2'b01: event_count_r <= event_count_r - 2'd1;
                    default: begin end
                endcase
            end
            if (process_hit_w) begin
                event_target_r <= event_target_r + 4'd1;
                if (step_r && event_hit_r[event_head_r][event_target_r[2:0]]
                    && hit_count_r < hit_max_r) begin
                    hit_count_r <= hit_count_r + 24'd1;
                    hit_items_r <= hit_items_r + 4'd1;
                end
            end
            if (process_free_w) begin
                event_target_r <= event_target_r + 4'd1;
                if (step_r && event_free_r[event_head_r] && free_count_r < free_max_r) begin
                    free_count_r <= free_count_r + 24'd1;
                    free_items_r <= free_items_r + 4'd1;
                end
            end
            if (hit_flush_w) hit_items_r <= 4'b0;
            if (free_flush_w) free_items_r <= 4'b0;
            if (stop_i) begin
                event_count_r <= 2'b0;
                hit_items_r <= 4'b0;
                free_items_r <= 4'b0;
            end
            if (busy_r && (finish_i || stop_i) && event_count_r == 0
                && hit_items_r == 0 && free_items_r == 0
                && count_r[0] == 0 && count_r[1] == 0 && count_r[2] == 0
                && write_state_r[0] == 0 && write_state_r[1] == 0 && write_state_r[2] == 0) begin
                busy_r <= 1'b0;
                done_r <= 1'b1;
            end
        end
    end
endmodule
