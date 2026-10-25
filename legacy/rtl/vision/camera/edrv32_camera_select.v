// ============================================================================
// File        : edrv32_camera_select.v
// Description : Debounced active-low pushbutton toggling left/right selection.
// ============================================================================

module edrv32_camera_select #(
    parameter integer DEBOUNCE_CYCLES = 540000,
    parameter integer COUNT_W = (DEBOUNCE_CYCLES <= 1) ? 1 :
        $clog2(DEBOUNCE_CYCLES + 1)
) (
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire button_n_i,
    output wire select_o
);

    reg button_meta_r;
    reg button_sync_r;
    reg [COUNT_W-1:0] stable_count_r;
    reg pressed_r;
    reg select_r;

    assign select_o = select_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            button_meta_r <= 1'b1;
            button_sync_r <= 1'b1;
        end else begin
            button_meta_r <= button_n_i;
            button_sync_r <= button_meta_r;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            stable_count_r <= {COUNT_W{1'b0}};
            pressed_r <= 1'b0;
            select_r <= 1'b0;
        end else if (!button_sync_r) begin
            if (stable_count_r < DEBOUNCE_CYCLES[COUNT_W-1:0])
                stable_count_r <= stable_count_r + 1'b1;
            if ((stable_count_r == DEBOUNCE_CYCLES - 1) && !pressed_r) begin
                pressed_r <= 1'b1;
                select_r <= ~select_r;
            end
        end else begin
            stable_count_r <= {COUNT_W{1'b0}};
            pressed_r <= 1'b0;
        end
    end

endmodule
