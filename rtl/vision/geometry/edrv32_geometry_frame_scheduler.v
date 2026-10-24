// ============================================================================
// File        : edrv32_geometry_frame_scheduler.v
// Description : Low-latency source/target ownership for Geometry display.
// Notes       : Geometry owns one active source frame and at most one pending
//               source frame.  A newer arrival replaces a stale pending frame
//               so overload cannot grow into seconds of display latency.
// ============================================================================

module edrv32_geometry_frame_scheduler #(
    parameter [31:0] TARGET_BASE0 = 32'h0200_0000,
    parameter [31:0] TARGET_BASE1 = 32'h0220_0000,
    parameter [31:0] TARGET_BASE2 = 32'h0240_0000
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire [4:0]   mode_i,
    input  wire         source_valid_i,
    input  wire [1:0]   source_buffer_i,
    input  wire [31:0]  source_base_i,
    output wire         source_release_valid_o,
    output wire [1:0]   source_release_buffer_o,
    input  wire         target_release_valid_i,
    input  wire [1:0]   target_release_buffer_i,
    output wire         display_valid_o,
    output wire [1:0]   display_buffer_o,
    output wire [31:0]  display_base_o,
    input  wire         geometry_ready_i,
    output wire         geometry_start_o,
    output wire [31:0]  geometry_source_base_o,
    output wire [31:0]  geometry_target_base_o,
    output wire [4:0]   geometry_mode_o,
    input  wire         geometry_done_i,
    input  wire         geometry_error_i,
    output wire         overflow_error_o,
    output wire [31:0]  replaced_frame_count_o
);

    reg pending_valid_r;
    reg [1:0] pending_buffer_r;
    reg [31:0] pending_base_r;

    reg [2:0] target_free_r;
    reg [1:0] target_next_r;
    reg active_r;
    reg [1:0] active_source_buffer_r;
    reg [1:0] active_target_buffer_r;
    reg [31:0] active_source_base_r;
    reg [31:0] active_target_base_r;
    reg [4:0] active_mode_r;

    reg source_release_valid_r;
    reg [1:0] source_release_buffer_r;
    reg deferred_release_valid_r;
    reg [1:0] deferred_release_buffer_r;
    reg display_valid_r;
    reg [1:0] display_buffer_r;
    reg [31:0] display_base_r;
    reg geometry_start_r;
    reg overflow_error_r;
    reg [31:0] replaced_frame_count_r;

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

    wire can_start_w = !active_r && pending_valid_r &&
        (|target_free_r) && geometry_ready_i;
    wire replace_pending_w = source_valid_i && pending_valid_r &&
        !can_start_w;
    wire geometry_complete_w = active_r && geometry_done_i;

    assign source_release_valid_o = source_release_valid_r;
    assign source_release_buffer_o = source_release_buffer_r;
    assign display_valid_o = display_valid_r;
    assign display_buffer_o = display_buffer_r;
    assign display_base_o = display_base_r;
    assign geometry_start_o = geometry_start_r;
    assign geometry_source_base_o = active_source_base_r;
    assign geometry_target_base_o = active_target_base_r;
    assign geometry_mode_o = active_mode_r;
    assign overflow_error_o = overflow_error_r;
    assign replaced_frame_count_o = replaced_frame_count_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pending_valid_r <= 1'b0;
            pending_buffer_r <= 2'b0;
            pending_base_r <= 32'b0;
            target_free_r <= 3'b111;
            target_next_r <= 2'b0;
            active_r <= 1'b0;
            active_source_buffer_r <= 2'b0;
            active_target_buffer_r <= 2'b0;
            active_source_base_r <= 32'b0;
            active_target_base_r <= 32'b0;
            active_mode_r <= 5'b0;
            source_release_valid_r <= 1'b0;
            source_release_buffer_r <= 2'b0;
            deferred_release_valid_r <= 1'b0;
            deferred_release_buffer_r <= 2'b0;
            display_valid_r <= 1'b0;
            display_buffer_r <= 2'b0;
            display_base_r <= 32'b0;
            geometry_start_r <= 1'b0;
            overflow_error_r <= 1'b0;
            replaced_frame_count_r <= 32'b0;
        end else begin
            source_release_valid_r <= 1'b0;
            display_valid_r <= 1'b0;
            geometry_start_r <= 1'b0;
            if (replace_pending_w)
                replaced_frame_count_r <= replaced_frame_count_r + 1'b1;

            // The active source release has priority.  A simultaneous stale
            // pending release is retained for the following clock.
            if (geometry_complete_w) begin
                source_release_valid_r <= 1'b1;
                source_release_buffer_r <= active_source_buffer_r;
                if (deferred_release_valid_r)
                    overflow_error_r <= 1'b1;
                if (replace_pending_w) begin
                    deferred_release_valid_r <= 1'b1;
                    deferred_release_buffer_r <= pending_buffer_r;
                end
            end else if (deferred_release_valid_r) begin
                source_release_valid_r <= 1'b1;
                source_release_buffer_r <= deferred_release_buffer_r;
                if (replace_pending_w) begin
                    deferred_release_valid_r <= 1'b1;
                    deferred_release_buffer_r <= pending_buffer_r;
                end else begin
                    deferred_release_valid_r <= 1'b0;
                end
            end else if (replace_pending_w) begin
                source_release_valid_r <= 1'b1;
                source_release_buffer_r <= pending_buffer_r;
            end

            if (target_release_valid_i && (target_release_buffer_i < 3))
                target_free_r[target_release_buffer_i] <= 1'b1;

            if (can_start_w) begin
                active_r <= 1'b1;
                active_source_buffer_r <= pending_buffer_r;
                active_source_base_r <= pending_base_r;
                active_target_buffer_r <= selected_target_w;
                active_target_base_r <= selected_target_w == 0 ? TARGET_BASE0 :
                    (selected_target_w == 1 ? TARGET_BASE1 : TARGET_BASE2);
                active_mode_r <= mode_i;
                target_free_r[selected_target_w] <= 1'b0;
                target_next_r <= selected_target_w == 2 ?
                    2'd0 : selected_target_w + 1'b1;
                geometry_start_r <= 1'b1;
                pending_valid_r <= source_valid_i;
                if (source_valid_i) begin
                    pending_buffer_r <= source_buffer_i;
                    pending_base_r <= source_base_i;
                end
            end else if (source_valid_i) begin
                pending_valid_r <= 1'b1;
                pending_buffer_r <= source_buffer_i;
                pending_base_r <= source_base_i;
            end

            if (geometry_complete_w) begin
                active_r <= 1'b0;
                if (geometry_error_i) begin
                    target_free_r[active_target_buffer_r] <= 1'b1;
                end else begin
                    display_valid_r <= 1'b1;
                    display_buffer_r <= active_target_buffer_r;
                    display_base_r <= active_target_base_r;
                end
            end
        end
    end

endmodule
