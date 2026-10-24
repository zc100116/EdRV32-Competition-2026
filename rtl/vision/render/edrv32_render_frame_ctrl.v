// ============================================================================
// File        : edrv32_render_frame_ctrl.v
// Description : APB submission and frame ownership for the 2D renderer.
// Notes       : Same clock domain as the command engine and DDR UI. A display
//               token is retired only after scanout has stopped using it.
// ============================================================================

module edrv32_render_frame_ctrl #(
    parameter [31:0] FRONT_BASE   = 32'h0300_0000,
    parameter [31:0] TARGET_BASE0 = 32'h0200_0000,
    parameter [31:0] TARGET_BASE1 = 32'h0220_0000,
    parameter [31:0] TARGET_BASE2 = 32'h0240_0000
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [31:0]  paddr_i,
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    input  wire [3:0]   pstrb_i,
    output wire         pready_o,
    output wire [31:0]  prdata_o,
    output wire         pslverr_o,
    output wire         irq_o,

    input  wire         base_valid_i,
    input  wire [1:0]   base_buffer_i,
    input  wire [31:0]  base_addr_i,
    input  wire [31:0]  base_stride_i,
    output wire         base_release_valid_o,
    output wire [1:0]   base_release_buffer_o,

    output wire         display_valid_o,
    input  wire         display_ready_i,
    output wire [2:0]   display_token_o,
    output wire [31:0]  display_base_o,
    input  wire         display_retire_valid_i,
    input  wire [2:0]   display_retire_token_i,

    output wire         draw_start_o,
    input  wire         draw_ready_i,
    output wire [31:0]  draw_list_base_o,
    output wire [15:0]  draw_list_count_o,
    input  wire         draw_done_i,
    input  wire         draw_error_i,

    output wire         compose_start_o,
    input  wire         compose_ready_i,
    output wire [31:0]  compose_base_o,
    output wire [31:0]  compose_base_stride_o,
    output wire [31:0]  compose_front_o,
    output wire [31:0]  compose_front_stride_o,
    output wire [31:0]  compose_target_o,
    output wire [31:0]  compose_target_stride_o,
    output wire [15:0]  compose_width_o,
    output wire [15:0]  compose_height_o,
    input  wire         compose_done_i,
    input  wire         compose_error_i
);

    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_DRAW    = 2'd1;
    localparam [1:0] ST_COMPOSE = 2'd2;

    localparam [7:0] REG_ID            = 8'h00;
    localparam [7:0] REG_VERSION       = 8'h04;
    localparam [7:0] REG_CONTROL       = 8'h08;
    localparam [7:0] REG_STATUS        = 8'h0c;
    localparam [7:0] REG_LIST_BASE     = 8'h10;
    localparam [7:0] REG_LIST_COUNT    = 8'h14;
    localparam [7:0] REG_FRONT_BASE    = 8'h18;
    localparam [7:0] REG_FRONT_STRIDE  = 8'h1c;
    localparam [7:0] REG_SIZE          = 8'h20;
    localparam [7:0] REG_TARGET_STRIDE = 8'h24;
    localparam [7:0] REG_COMMAND       = 8'h28;
    localparam [7:0] REG_IRQ_ENABLE    = 8'h2c;
    localparam [7:0] REG_IRQ_STATUS    = 8'h30;
    localparam [7:0] REG_DRAW_COUNT    = 8'h34;
    localparam [7:0] REG_FRAME_COUNT   = 8'h38;
    localparam [7:0] REG_DROP_COUNT    = 8'h3c;
    localparam [7:0] REG_ERROR_COUNT   = 8'h40;

    function [31:0] apply_strobe;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strobe;
        integer byte_index;
        begin
            apply_strobe = old_value;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1)
                if (strobe[byte_index])
                    apply_strobe[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
        end
    endfunction

    reg [1:0]  state_r;
    reg        front_enable_r;
    reg        hold_base_enable_r;
    reg        front_valid_r;
    reg [31:0] list_base_r;
    reg [15:0] list_count_r;
    reg [31:0] front_base_r;
    reg [31:0] front_stride_r;
    reg [15:0] width_r;
    reg [15:0] height_r;
    reg [31:0] target_stride_r;
    reg [3:0]  irq_enable_r;
    reg [3:0]  irq_status_r;
    reg [31:0] draw_count_r;
    reg [31:0] frame_count_r;
    reg [31:0] drop_count_r;
    reg [31:0] error_count_r;
    reg [31:0] prdata_r;

    reg        command_pending_r;
    reg [31:0] command_base_r;
    reg [15:0] command_count_r;

    reg        base_pending_r;
    reg [1:0]  pending_base_buffer_r;
    reg [31:0] pending_base_addr_r;
    reg [31:0] pending_base_stride_r;
    reg [1:0]  active_base_buffer_r;
    reg [31:0] active_base_addr_r;
    reg [31:0] active_base_stride_r;
    reg        active_from_held_r;
    reg [1:0]  active_target_buffer_r;
    reg [31:0] active_target_base_r;
    reg        held_base_valid_r;
    reg [1:0]  held_base_buffer_r;
    reg [31:0] held_base_addr_r;
    reg [31:0] held_base_stride_r;
    reg        recompose_pending_r;

    reg [2:0]  target_free_r;
    reg [1:0]  target_next_r;
    reg        publish_valid_r;
    reg [2:0]  publish_token_r;
    reg [31:0] publish_base_r;
    reg        release_overflow_r;
    reg [7:0]  release_queue_r;
    reg [2:0]  release_count_r;

    wire [7:0] offset_w = paddr_i[7:0];
    wire aligned_w = paddr_i[1:0] == 2'b00;
    wire local_slot_w = paddr_i[31:8] == 24'd0;
    wire implemented_w =
        (offset_w == REG_ID) ||
        (offset_w == REG_VERSION) ||
        (offset_w == REG_CONTROL) ||
        (offset_w == REG_STATUS) ||
        (offset_w == REG_LIST_BASE) ||
        (offset_w == REG_LIST_COUNT) ||
        (offset_w == REG_FRONT_BASE) ||
        (offset_w == REG_FRONT_STRIDE) ||
        (offset_w == REG_SIZE) ||
        (offset_w == REG_TARGET_STRIDE) ||
        (offset_w == REG_COMMAND) ||
        (offset_w == REG_IRQ_ENABLE) ||
        (offset_w == REG_IRQ_STATUS) ||
        (offset_w == REG_DRAW_COUNT) ||
        (offset_w == REG_FRAME_COUNT) ||
        (offset_w == REG_DROP_COUNT) ||
        (offset_w == REG_ERROR_COUNT);
    wire writable_w =
        (offset_w == REG_CONTROL) ||
        (offset_w == REG_LIST_BASE) ||
        (offset_w == REG_LIST_COUNT) ||
        (offset_w == REG_FRONT_BASE) ||
        (offset_w == REG_FRONT_STRIDE) ||
        (offset_w == REG_SIZE) ||
        (offset_w == REG_TARGET_STRIDE) ||
        (offset_w == REG_COMMAND) ||
        (offset_w == REG_IRQ_ENABLE) ||
        (offset_w == REG_IRQ_STATUS);
    wire access_w = psel_i && penable_i;
    wire legal_w = aligned_w && local_slot_w && implemented_w &&
                   (!pwrite_i || writable_w);
    wire commit_request_w = access_w && pwrite_i && legal_w &&
        (offset_w == REG_COMMAND) && pstrb_i[0] && pwdata_i[0];
    wire commit_busy_w = commit_request_w && command_pending_r;
    wire commit_invalid_w = commit_request_w &&
        ((list_count_r == 16'd0) || (list_base_r[5:0] != 6'd0));
    wire config_busy_w = access_w && pwrite_i &&
        ((offset_w == REG_FRONT_BASE) ||
         (offset_w == REG_FRONT_STRIDE) ||
         (offset_w == REG_SIZE) ||
         (offset_w == REG_TARGET_STRIDE) ||
         (offset_w == REG_CONTROL)) &&
        ((state_r != ST_IDLE) || command_pending_r);
    wire write_w = access_w && pwrite_i && legal_w &&
                   !commit_busy_w && !commit_invalid_w &&
                   !config_busy_w;
    wire config_write_w = write_w &&
        ((offset_w == REG_CONTROL) ||
         (offset_w == REG_FRONT_BASE) ||
         (offset_w == REG_FRONT_STRIDE) ||
         (offset_w == REG_SIZE) ||
         (offset_w == REG_TARGET_STRIDE));
    wire [31:0] control_merge_w = apply_strobe(
        {30'd0,hold_base_enable_r,front_enable_r},
        pwdata_i,pstrb_i);
    wire [31:0] list_count_merge_w = apply_strobe(
        {16'd0,list_count_r},pwdata_i,pstrb_i);
    wire [31:0] size_merge_w = apply_strobe(
        {height_r,width_r},pwdata_i,pstrb_i);
    wire [31:0] irq_enable_merge_w = apply_strobe(
        {28'd0,irq_enable_r},pwdata_i,pstrb_i);
    wire [31:0] write_mask_w = {
        {8{pstrb_i[3]}},{8{pstrb_i[2]}},
        {8{pstrb_i[1]}},{8{pstrb_i[0]}}
    };
    wire [3:0] irq_clear_w =
        (write_w && (offset_w == REG_IRQ_STATUS)) ?
        (pwdata_i[3:0] & write_mask_w[3:0]) : 4'd0;

    reg [1:0] selected_target_w;
    always @(*) begin
        selected_target_w = 2'd0;
        case (target_next_r)
            2'd0: selected_target_w = target_free_r[0] ? 2'd0 :
                (target_free_r[1] ? 2'd1 : 2'd2);
            2'd1: selected_target_w = target_free_r[1] ? 2'd1 :
                (target_free_r[2] ? 2'd2 : 2'd0);
            default: selected_target_w = target_free_r[2] ? 2'd2 :
                (target_free_r[0] ? 2'd0 : 2'd1);
        endcase
    end
    wire [31:0] selected_target_base_w = selected_target_w == 2'd0 ?
        TARGET_BASE0 : selected_target_w == 2'd1 ?
        TARGET_BASE1 : TARGET_BASE2;
    wire draw_fire_w = (state_r == ST_IDLE) && !publish_valid_r &&
                       command_pending_r && draw_ready_i;
    wire compose_pending_base_w = base_pending_r;
    wire compose_held_base_w = !base_pending_r &&
        hold_base_enable_r && held_base_valid_r &&
        recompose_pending_r;
    wire compose_fire_w = (state_r == ST_IDLE) && !publish_valid_r &&
        !command_pending_r &&
        (compose_pending_base_w || compose_held_base_w) &&
        front_enable_r &&
        front_valid_r && (|target_free_r) && compose_ready_i &&
        !config_write_w;
    wire bypass_fire_w = (state_r == ST_IDLE) && !publish_valid_r &&
        !command_pending_r && base_pending_r &&
        (!front_enable_r || !front_valid_r) && !config_write_w;
    wire consume_base_w =
        (compose_fire_w && compose_pending_base_w) || bypass_fire_w;
    wire stale_release_w = base_valid_i && base_pending_r &&
                           !consume_base_w;
    wire compose_release_w = (state_r == ST_COMPOSE) &&
        compose_done_i && !active_from_held_r &&
        (!hold_base_enable_r || compose_error_i);
    wire held_replace_release_w =
        (state_r == ST_COMPOSE) && compose_done_i &&
        !compose_error_i && !active_from_held_r &&
        hold_base_enable_r && held_base_valid_r &&
        (held_base_buffer_r != active_base_buffer_r);
    wire held_control_release_w = write_w &&
        (offset_w == REG_CONTROL) && held_base_valid_r &&
        (!control_merge_w[1] || !control_merge_w[0]);
    wire held_resize_release_w = write_w &&
        (offset_w == REG_SIZE) && held_base_valid_r;
    wire held_bypass_release_w = bypass_fire_w && held_base_valid_r;
    wire held_release_w = held_replace_release_w ||
        held_control_release_w || held_resize_release_w ||
        held_bypass_release_w;
    wire retire_base_w = display_retire_valid_i &&
                         !display_retire_token_i[2];
    wire retire_target_w = display_retire_valid_i &&
                           display_retire_token_i[2] &&
                           (display_retire_token_i[1:0] < 2'd3);
    wire draw_complete_w = (state_r == ST_DRAW) && draw_done_i;
    wire compose_complete_w = (state_r == ST_COMPOSE) &&
                              compose_done_i;
    wire publish_fire_w = publish_valid_r && display_ready_i;

    reg [7:0] release_queue_next_w;
    reg [2:0] release_count_next_w;
    reg       release_overflow_w;
    always @(*) begin
        release_queue_next_w = release_queue_r;
        release_count_next_w = release_count_r;
        release_overflow_w = 1'b0;
        if (release_count_r != 3'd0) begin
            release_queue_next_w = {2'b0,release_queue_r[7:2]};
            release_count_next_w = release_count_r - 3'd1;
        end
        if (compose_release_w) begin
            if (release_count_next_w < 3'd4) begin
                release_queue_next_w[release_count_next_w*2 +: 2] =
                    active_base_buffer_r;
                release_count_next_w = release_count_next_w + 3'd1;
            end else begin
                release_overflow_w = 1'b1;
            end
        end
        if (held_release_w) begin
            if (release_count_next_w < 3'd4) begin
                release_queue_next_w[release_count_next_w*2 +: 2] =
                    held_base_buffer_r;
                release_count_next_w = release_count_next_w + 3'd1;
            end else begin
                release_overflow_w = 1'b1;
            end
        end
        if (stale_release_w) begin
            if (release_count_next_w < 3'd4) begin
                release_queue_next_w[release_count_next_w*2 +: 2] =
                    pending_base_buffer_r;
                release_count_next_w = release_count_next_w + 3'd1;
            end else begin
                release_overflow_w = 1'b1;
            end
        end
        if (retire_base_w) begin
            if (release_count_next_w < 3'd4) begin
                release_queue_next_w[release_count_next_w*2 +: 2] =
                    display_retire_token_i[1:0];
                release_count_next_w = release_count_next_w + 3'd1;
            end else begin
                release_overflow_w = 1'b1;
            end
        end
    end

    wire [3:0] irq_event_w = {
        stale_release_w,
        (draw_complete_w && draw_error_i) ||
            (compose_complete_w && compose_error_i) ||
            release_overflow_w,
        publish_fire_w,
        draw_complete_w && !draw_error_i
    };
    wire [31:0] status_w = {
        18'd0,recompose_pending_r,held_base_valid_r,
        hold_base_enable_r,target_free_r,release_overflow_r,
        publish_valid_r,base_pending_r,command_pending_r,
        front_valid_r,front_enable_r,state_r
    };

    assign pready_o = 1'b1;
    assign prdata_o = prdata_r;
    assign pslverr_o = access_w &&
        (!legal_w || commit_busy_w || commit_invalid_w || config_busy_w);
    assign irq_o = |(irq_status_r & irq_enable_r);
    assign base_release_valid_o = release_count_r != 3'd0;
    assign base_release_buffer_o = release_queue_r[1:0];
    assign display_valid_o = publish_valid_r;
    assign display_token_o = publish_token_r;
    assign display_base_o = publish_base_r;
    assign draw_start_o = draw_fire_w;
    assign draw_list_base_o = command_base_r;
    assign draw_list_count_o = command_count_r;
    assign compose_start_o = compose_fire_w;
    assign compose_base_o = compose_pending_base_w ?
        pending_base_addr_r : held_base_addr_r;
    assign compose_base_stride_o = compose_pending_base_w ?
        pending_base_stride_r : held_base_stride_r;
    assign compose_front_o = front_base_r;
    assign compose_front_stride_o = front_stride_r;
    assign compose_target_o = selected_target_base_w;
    assign compose_target_stride_o = target_stride_r;
    assign compose_width_o = width_r;
    assign compose_height_o = height_r;

    always @(*) begin
        prdata_r = 32'd0;
        case (offset_w)
            REG_ID:            prdata_r = 32'h524e_4452;
            REG_VERSION:       prdata_r = 32'h0001_0001;
            REG_CONTROL:       prdata_r =
                {30'd0,hold_base_enable_r,front_enable_r};
            REG_STATUS:        prdata_r = status_w;
            REG_LIST_BASE:     prdata_r = list_base_r;
            REG_LIST_COUNT:    prdata_r = {16'd0,list_count_r};
            REG_FRONT_BASE:    prdata_r = front_base_r;
            REG_FRONT_STRIDE:  prdata_r = front_stride_r;
            REG_SIZE:          prdata_r = {height_r,width_r};
            REG_TARGET_STRIDE: prdata_r = target_stride_r;
            REG_COMMAND:       prdata_r = 32'd0;
            REG_IRQ_ENABLE:    prdata_r = {28'd0,irq_enable_r};
            REG_IRQ_STATUS:    prdata_r = {28'd0,irq_status_r};
            REG_DRAW_COUNT:    prdata_r = draw_count_r;
            REG_FRAME_COUNT:   prdata_r = frame_count_r;
            REG_DROP_COUNT:    prdata_r = drop_count_r;
            REG_ERROR_COUNT:   prdata_r = error_count_r;
            default:           prdata_r = 32'd0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            front_enable_r <= 1'b0;
            hold_base_enable_r <= 1'b0;
            front_valid_r <= 1'b0;
            list_base_r <= 32'd0;
            list_count_r <= 16'd0;
            front_base_r <= FRONT_BASE;
            front_stride_r <= 32'd5120;
            width_r <= 16'd1280;
            height_r <= 16'd720;
            target_stride_r <= 32'd2560;
            irq_enable_r <= 4'd0;
            draw_count_r <= 32'd0;
            frame_count_r <= 32'd0;
            drop_count_r <= 32'd0;
            error_count_r <= 32'd0;
            command_pending_r <= 1'b0;
            command_base_r <= 32'd0;
            command_count_r <= 16'd0;
            base_pending_r <= 1'b0;
            pending_base_buffer_r <= 2'd0;
            pending_base_addr_r <= 32'd0;
            pending_base_stride_r <= 32'd0;
            active_base_buffer_r <= 2'd0;
            active_base_addr_r <= 32'd0;
            active_base_stride_r <= 32'd0;
            active_from_held_r <= 1'b0;
            active_target_buffer_r <= 2'd0;
            active_target_base_r <= 32'd0;
            held_base_valid_r <= 1'b0;
            held_base_buffer_r <= 2'd0;
            held_base_addr_r <= 32'd0;
            held_base_stride_r <= 32'd0;
            recompose_pending_r <= 1'b0;
            target_free_r <= 3'b111;
            target_next_r <= 2'd0;
            publish_valid_r <= 1'b0;
            publish_token_r <= 3'd0;
            publish_base_r <= 32'd0;
            release_overflow_r <= 1'b0;
        end else begin
            if (write_w && (offset_w == REG_CONTROL)) begin
                front_enable_r <= control_merge_w[0];
                hold_base_enable_r <= control_merge_w[1];
            end
            if (held_control_release_w || held_resize_release_w ||
                held_bypass_release_w) begin
                held_base_valid_r <= 1'b0;
                recompose_pending_r <= 1'b0;
            end
            if (write_w && (offset_w == REG_LIST_BASE))
                list_base_r <= apply_strobe(
                    list_base_r,pwdata_i,pstrb_i);
            if (write_w && (offset_w == REG_LIST_COUNT))
                list_count_r <= list_count_merge_w[15:0];
            if (write_w && (offset_w == REG_FRONT_BASE)) begin
                front_base_r <= apply_strobe(
                    front_base_r,pwdata_i,pstrb_i);
                front_valid_r <= 1'b0;
            end
            if (write_w && (offset_w == REG_FRONT_STRIDE)) begin
                front_stride_r <= apply_strobe(
                    front_stride_r,pwdata_i,pstrb_i);
                front_valid_r <= 1'b0;
            end
            if (write_w && (offset_w == REG_SIZE)) begin
                width_r <= size_merge_w[15:0];
                height_r <= size_merge_w[31:16];
                front_valid_r <= 1'b0;
                recompose_pending_r <= 1'b0;
            end
            if (write_w && (offset_w == REG_TARGET_STRIDE))
                target_stride_r <= apply_strobe(
                    target_stride_r,pwdata_i,pstrb_i);
            if (write_w && (offset_w == REG_IRQ_ENABLE))
                irq_enable_r <= irq_enable_merge_w[3:0];
            if (commit_request_w && !commit_busy_w &&
                !commit_invalid_w) begin
                command_pending_r <= 1'b1;
                command_base_r <= list_base_r;
                command_count_r <= list_count_r;
            end
            if (draw_fire_w)
                command_pending_r <= 1'b0;

            if (consume_base_w) begin
                base_pending_r <= base_valid_i;
                if (base_valid_i) begin
                    pending_base_buffer_r <= base_buffer_i;
                    pending_base_addr_r <= base_addr_i;
                    pending_base_stride_r <= base_stride_i;
                end
            end else if (base_valid_i) begin
                base_pending_r <= 1'b1;
                pending_base_buffer_r <= base_buffer_i;
                pending_base_addr_r <= base_addr_i;
                pending_base_stride_r <= base_stride_i;
            end
            if (stale_release_w)
                drop_count_r <= drop_count_r + 32'd1;

            if (retire_target_w)
                target_free_r[display_retire_token_i[1:0]] <= 1'b1;
            if (publish_fire_w) begin
                publish_valid_r <= 1'b0;
                frame_count_r <= frame_count_r + 32'd1;
            end
            if (bypass_fire_w) begin
                publish_valid_r <= 1'b1;
                publish_token_r <= {1'b0,pending_base_buffer_r};
                publish_base_r <= pending_base_addr_r;
                recompose_pending_r <= 1'b0;
            end

            case (state_r)
                ST_IDLE: begin
                    if (draw_fire_w) begin
                        state_r <= ST_DRAW;
                    end else if (compose_fire_w) begin
                        state_r <= ST_COMPOSE;
                        active_from_held_r <= compose_held_base_w;
                        active_base_buffer_r <= compose_pending_base_w ?
                            pending_base_buffer_r : held_base_buffer_r;
                        active_base_addr_r <= compose_pending_base_w ?
                            pending_base_addr_r : held_base_addr_r;
                        active_base_stride_r <= compose_pending_base_w ?
                            pending_base_stride_r : held_base_stride_r;
                        active_target_buffer_r <= selected_target_w;
                        active_target_base_r <= selected_target_base_w;
                        recompose_pending_r <= 1'b0;
                        target_free_r[selected_target_w] <= 1'b0;
                        target_next_r <= selected_target_w == 2'd2 ?
                            2'd0 : selected_target_w + 2'd1;
                    end
                end
                ST_DRAW: begin
                    if (draw_done_i) begin
                        state_r <= ST_IDLE;
                        if (draw_error_i) begin
                            front_valid_r <= 1'b0;
                            recompose_pending_r <= 1'b0;
                            error_count_r <= error_count_r + 32'd1;
                        end else begin
                            front_valid_r <= 1'b1;
                            if (hold_base_enable_r && held_base_valid_r)
                                recompose_pending_r <= 1'b1;
                            draw_count_r <= draw_count_r + 32'd1;
                        end
                    end
                end
                ST_COMPOSE: begin
                    if (compose_done_i) begin
                        state_r <= ST_IDLE;
                        if (compose_error_i) begin
                            target_free_r[active_target_buffer_r] <= 1'b1;
                            error_count_r <= error_count_r + 32'd1;
                        end else begin
                            publish_valid_r <= 1'b1;
                            publish_token_r <=
                                {1'b1,active_target_buffer_r};
                            publish_base_r <= active_target_base_r;
                            if (hold_base_enable_r &&
                                !active_from_held_r) begin
                                held_base_valid_r <= 1'b1;
                                held_base_buffer_r <=
                                    active_base_buffer_r;
                                held_base_addr_r <=
                                    active_base_addr_r;
                                held_base_stride_r <=
                                    active_base_stride_r;
                            end
                        end
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
            if (release_overflow_w)
                release_overflow_r <= 1'b1;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            release_queue_r <= 8'd0;
            release_count_r <= 3'd0;
            irq_status_r <= 4'd0;
        end else begin
            release_queue_r <= release_queue_next_w;
            release_count_r <= release_count_next_w;
            irq_status_r <= (irq_status_r & ~irq_clear_w) | irq_event_w;
        end
    end

endmodule
