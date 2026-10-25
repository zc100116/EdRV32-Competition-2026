// ============================================================================
// File        : edrv32_render_fifo.v
// Description : 256-bit render FIFO with a registered IP read prefetch.
// Notes       : The public read port is first-word fall-through. The Pango
//               FIFO's synchronous read data is held in two local registers.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_render_fifo #(
    parameter integer DEPTH = 32,
    parameter integer COUNT_W = $clog2(DEPTH) + 1
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,
    input  wire                 flush_i,
    input  wire                 push_i,
    input  wire [255:0]         write_data_i,
    input  wire                 pop_i,
    output wire [255:0]         read_data_o,
    output wire                 full_o,
    output wire                 empty_o,
    output wire [COUNT_W-1:0]   count_o
);

    reg [COUNT_W-1:0] count_r;
    reg [255:0] head_r;
    reg [255:0] next_r;
    reg [1:0] local_count_r;
    reg raw_pending_r;

    wire [255:0] raw_data_w;
    reg [6:0] raw_count_r;
    reg [5:0] raw_write_addr_r;
    reg [5:0] raw_read_addr_r;
    wire raw_empty_w = raw_count_r == 7'd0;
    wire push_w = push_i && !full_o && !flush_i;
    wire pop_w = pop_i && !empty_o && !flush_i;
    wire [2:0] after_return_w =
        {1'b0, local_count_r} - {2'b0, pop_w} +
        {2'b0, raw_pending_r};
    wire raw_read_w = rst_n_i && !flush_i && !raw_empty_w &&
        (after_return_w < 3'd2);

    assign read_data_o = head_r;
    assign full_o = count_r == DEPTH[COUNT_W-1:0];
    assign empty_o = local_count_r == 2'd0;
    assign count_o = count_r;

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    render_fifo_ram u_ram (
        .wr_data(write_data_i),
        .wr_addr(raw_write_addr_r),
        .wr_en(push_w),
        .wr_clk(clk_i),
        .wr_rst(~rst_n_i),
        .rd_addr(raw_read_addr_r),
        .rd_data(raw_data_w),
        .rd_clk(clk_i),
        .rd_clk_en(raw_read_w),
        .rd_rst(~rst_n_i)
    );
`else
    reg [255:0] sim_memory_r [0:63];
    reg [255:0] sim_raw_data_r;

    always @(posedge clk_i) begin
        if (push_w)
            sim_memory_r[raw_write_addr_r] <= write_data_i;
        if (raw_read_w)
            sim_raw_data_r <= sim_memory_r[raw_read_addr_r];
    end

    assign raw_data_w = sim_raw_data_r;
`endif

    generate
        if (DEPTH != 32 && DEPTH != 64) begin : gen_bad_depth
            edrv32_render_fifo_depth_must_be_32_or_64 u_bad_depth ();
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_r <= {COUNT_W{1'b0}};
            raw_count_r <= 7'd0;
            raw_write_addr_r <= 6'd0;
            raw_read_addr_r <= 6'd0;
            local_count_r <= 2'd0;
            raw_pending_r <= 1'b0;
        end else if (flush_i) begin
            count_r <= {COUNT_W{1'b0}};
            raw_count_r <= 7'd0;
            raw_write_addr_r <= 6'd0;
            raw_read_addr_r <= 6'd0;
            local_count_r <= 2'd0;
            raw_pending_r <= 1'b0;
        end else begin
            raw_pending_r <= raw_read_w;
            if (push_w)
                raw_write_addr_r <= raw_write_addr_r + 1'b1;
            if (raw_read_w)
                raw_read_addr_r <= raw_read_addr_r + 1'b1;
            case ({push_w, raw_read_w})
                2'b10: raw_count_r <= raw_count_r + 1'b1;
                2'b01: raw_count_r <= raw_count_r - 1'b1;
                default: begin end
            endcase
            case ({push_w, pop_w})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: begin end
            endcase
            case ({pop_w, raw_pending_r})
                2'b01: begin
                    if (local_count_r == 2'd0)
                        head_r <= raw_data_w;
                    else
                        next_r <= raw_data_w;
                    local_count_r <= local_count_r + 1'b1;
                end
                2'b10: begin
                    if (local_count_r == 2'd2)
                        head_r <= next_r;
                    local_count_r <= local_count_r - 1'b1;
                end
                2'b11: begin
                    if (local_count_r == 2'd1)
                        head_r <= raw_data_w;
                    else begin
                        head_r <= next_r;
                        next_r <= raw_data_w;
                    end
                end
                default: begin end
            endcase
        end
    end

endmodule
