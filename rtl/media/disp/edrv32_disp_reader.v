// File: edrv32_disp_reader.v
// Spec: disp-spec 2.4-2.6, 4.3, 5.2.
// Description: Latch frames and issue ordered L0/L1 line descriptors with reserved space.
//              Row addresses accumulate strides; descriptor outputs are registered.
// Clock domain: clk_mem (clk_i).
module edrv32_disp_reader (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Frame configuration and FIFO accounting.
    input wire frame_req_i,
    input wire soft_clear_i,
    input wire [31:0] next_base_i,
    input wire [31:0] stride_i,
    input wire [31:0] l0_scroll_i,
    input wire [1:0] layer_ctrl_i,
    input wire [31:0] l1_next_base_i,
    input wire [31:0] l1_stride_i,
    input wire [31:0] l1_pos_i,
    input wire [31:0] l1_size_i,
    input wire [9:0] read_cnt_i,
    input wire [9:0] read1_cnt_i,
    input wire write_i,

    // One line is outstanding at a time; its layer owns every returned beat.
    output wire desc_valid_o,
    input wire desc_ready_i,
    output reg [31:0] desc_base_o,
    output reg [31:0] desc_stride_o,
    output reg [15:0] desc_width_bytes_o,
    output wire [11:0] desc_height_o,
    output reg write_layer_o,
    input wire done_i,

    // Frame status and performance events.
    output wire frame_start_o,
    output wire busy_o,
    output wire urgent_o,
    output wire delayed_req_o,
    output wire [31:0] req_cnt_o,
    output wire fifo_pending_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_SCROLL = 3'd1;
    localparam [2:0] S_PICK = 3'd2;
    localparam [2:0] S_WAIT = 3'd3;
    localparam [2:0] S_DESC = 3'd4;
    localparam [2:0] S_RUN = 3'd5;
    localparam [2:0] S_NEXT = 3'd6;
    reg [2:0] state_r;
    reg [9:0] line_r;
    reg [11:0] scroll_rows_r;
    reg [1:0] layer_ctrl_r;
    reg [10:0] l1_y_end_r;
    reg [9:0] l1_y_r;
    reg [7:0] l1_beats_r;
    reg [6:0] l0_beats_r;
    reg [9:0] l0_limit_r;
    reg [9:0] l1_limit_r;
    reg [31:0] pending_cnt_r;
    reg [31:0] req_cnt_r;
    reg [9:0] write_cnt_r;
    reg [9:0] write1_cnt_r;
    reg [9:0] admission_used_r;
    reg [9:0] admission_used1_r;
    reg [31:0] line_base_r;
    reg [31:0] stride_r;
    reg [31:0] l1_line_base_r;
    reg [31:0] l1_stride_r;
    wire [9:0] used_w;
    wire [9:0] used1_w;
    wire l1_row_w;
    wire active_w;
    wire space_w;
    wire [40:0] unused_cfg_w;

    assign unused_cfg_w = {l0_scroll_i[31:28], l0_scroll_i[15], l1_pos_i[31:26],
        l1_pos_i[15:0], l1_size_i[31:26], l1_size_i[15:11], l1_size_i[2:0]};

    assign used_w = write_cnt_r - read_cnt_i;
    assign used1_w = write1_cnt_r - read1_cnt_i;
    assign active_w = state_r != S_IDLE;
    assign l1_row_w = layer_ctrl_r[1] && line_r >= l1_y_r &&
        {1'b0, line_r} < l1_y_end_r;
    assign frame_start_o = !active_w && (pending_cnt_r != 32'd0 || frame_req_i);
    assign busy_o = active_w || pending_cnt_r != 32'd0 || frame_req_i;
    assign urgent_o = active_w && ((layer_ctrl_r[0] && used_w < 10'd81) ||
        (l1_row_w && used1_w < {2'd0, l1_beats_r}));
    assign delayed_req_o = frame_req_i && active_w;
    assign req_cnt_o = req_cnt_r;
    assign fifo_pending_o = used_w != 10'd0 || used1_w != 10'd0;
    // No following descriptor is offered until DONE, hence no unreturned reservation
    // remains at S_WAIT. Admission reserves the entire next line through S_RUN.
    assign space_w = write_layer_o ? admission_used1_r <= l1_limit_r :
        admission_used_r <= l0_limit_r;

    // Break Gray decode/subtraction from the admission comparator. S_PICK separates
    // a previous DONE from S_WAIT, so its final write is included before admission.
    // While waiting there are no incoming writes; delayed read credit is conservative.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            admission_used_r <= 10'd0;
            admission_used1_r <= 10'd0;
        end else begin
            admission_used_r <= used_w;
            admission_used1_r <= used1_w;
        end
    end
    assign desc_valid_o = state_r == S_DESC;
    assign desc_height_o = 12'd1;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            line_r <= 10'd0;
            scroll_rows_r <= 12'd0;
            layer_ctrl_r <= 2'd0;
            l1_y_r <= 10'd0;
            l1_y_end_r <= 11'd0;
            l1_beats_r <= 8'd0;
            l0_beats_r <= 7'd80;
            l0_limit_r <= 10'd432;
            l1_limit_r <= 10'd512;
            pending_cnt_r <= 32'd0;
            req_cnt_r <= 32'd0;
            write_cnt_r <= 10'd0;
            write1_cnt_r <= 10'd0;
            write_layer_o <= 1'b0;
        end else begin
            if (soft_clear_i) begin
                req_cnt_r <= 32'd0;
            end else if (frame_req_i) begin
                req_cnt_r <= req_cnt_r + 32'd1;
            end
            if (write_i && !write_layer_o) begin
                write_cnt_r <= write_cnt_r + 10'd1;
            end
            if (write_i && write_layer_o) begin
                write1_cnt_r <= write1_cnt_r + 10'd1;
            end
            if (frame_req_i != frame_start_o) begin
                pending_cnt_r <= frame_req_i ? pending_cnt_r + 32'd1 : pending_cnt_r - 32'd1;
            end
            case (state_r)
                S_IDLE: begin
                    if (frame_start_o) begin
                        state_r <= S_SCROLL;
                        line_r <= 10'd0;
                        scroll_rows_r <= layer_ctrl_i[0] ? l0_scroll_i[27:16] : 12'd0;
                        layer_ctrl_r <= layer_ctrl_i;
                        l1_y_r <= l1_pos_i[25:16];
                        l1_y_end_r <= {1'b0, l1_pos_i[25:16]} +
                            {1'b0, l1_size_i[25:16]};
                        l1_beats_r <= l1_size_i[10:3];
                        l0_beats_r <= l0_scroll_i[3:0] == 4'd0 ? 7'd80 : 7'd81;
                        l0_limit_r <= l0_scroll_i[3:0] == 4'd0 ? 10'd432 : 10'd431;
                        l1_limit_r <= 10'd512 - {2'd0, l1_size_i[10:3]};
                        write_layer_o <= 1'b0;
                    end
                end
                S_SCROLL: begin
                    if (scroll_rows_r == 12'd0) begin
                        state_r <= S_PICK;
                    end else begin
                        scroll_rows_r <= scroll_rows_r - 12'd1;
                    end
                end
                S_PICK: begin
                    if ((!write_layer_o && layer_ctrl_r[0]) ||
                        (write_layer_o && l1_row_w)) begin
                        state_r <= S_WAIT;
                    end else if (!write_layer_o) begin
                        write_layer_o <= 1'b1;
                    end else begin
                        state_r <= S_NEXT;
                    end
                end
                S_WAIT: begin
                    if (space_w) begin
                        state_r <= S_DESC;
                    end
                end
                S_DESC: begin
                    if (desc_ready_i) begin
                        state_r <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (done_i) begin
                        if (!write_layer_o && l1_row_w) begin
                            write_layer_o <= 1'b1;
                            state_r <= S_PICK;
                        end else if (line_r == 10'd719) begin
                            state_r <= S_IDLE;
                        end else begin
                            state_r <= S_NEXT;
                        end
                    end
                end
                S_NEXT: begin
                    write_layer_o <= 1'b0;
                    if (line_r == 10'd719) begin
                        state_r <= S_IDLE;
                    end else begin
                        line_r <= line_r + 10'd1;
                        state_r <= S_PICK;
                    end
                end
                default: begin end
            endcase
        end
    end

    // spec 2.5: repeated row addition also forms SCROLL_Y*STRIDE during prefetch.
    // At most 4095 additions fit comfortably within the 30-line blanking interval.
    always @(posedge clk_i) begin
        if (frame_start_o) begin
            line_base_r <= next_base_i + {16'd0, l0_scroll_i[14:4], 5'd0};
            stride_r <= stride_i;
            l1_line_base_r <= l1_next_base_i;
            l1_stride_r <= l1_stride_i;
        end else begin
            if ((state_r == S_SCROLL && scroll_rows_r != 12'd0) || state_r == S_NEXT) begin
                line_base_r <= line_base_r + stride_r;
            end
            if (state_r == S_NEXT && l1_row_w) begin
                l1_line_base_r <= l1_line_base_r + l1_stride_r;
            end
        end
        if (state_r == S_PICK) begin
            desc_base_o <= write_layer_o ? l1_line_base_r : line_base_r;
            desc_stride_o <= write_layer_o ? l1_stride_r : stride_r;
            desc_width_bytes_o <= write_layer_o ? {3'd0, l1_beats_r, 5'd0} :
                {4'd0, l0_beats_r, 5'd0};
        end
    end
endmodule
