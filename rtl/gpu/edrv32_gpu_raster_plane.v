// File: edrv32_gpu_raster_plane.v
// Spec: gpu-spec 2.13.7; microarch 4.6, 4.10.
// Description: Two interleaved group accumulators and two carry stages.
//              Same-phase forwarding closes the two-cycle feedback recurrence.
// Clock domain: clk_gpu.
// WIDTH values are fixed by gpu-spec v0.4 2.13.7 (62/66/58), or edge width 40.
module edrv32_gpu_raster_plane #(
    parameter WIDTH = 66
) (
    // Clock and pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Row initialization and ordered group issue.
    input wire load_i,
    input wire issue_i,
    input wire reuse_i,
    input wire [2*WIDTH-1:0] seed_i,
    input wire [WIDTH-1:0] delta_i,
    output wire [WIDTH-1:0] plane_o
);
    wire [WIDTH-1:0] phase_w [0:1];
    reg phase_idx_r;
    reg phase_pipe_0_r;
    reg phase_pipe_1_r;
    reg [1:0] write_valid_r;
    reg [WIDTH-1:0] original_0_r;
    reg [WIDTH-1:0] original_1_r;
    wire [WIDTH-1:0] selected_w;
    wire [WIDTH-1:0] next_w;
    assign selected_w = write_valid_r[1] && phase_idx_r == phase_pipe_1_r ?
        next_w : phase_w[phase_idx_r];
    assign plane_o = original_1_r;
    edrv32_gpu_raster_add #(
        .WIDTH(WIDTH)
    ) u_add (
        .clk_i(clk_i),
        .en_i(en_i),
        .a_i(selected_w),
        .b_i(delta_i),
        .sum_o(next_w)
    );
    always @(posedge clk_i) begin
        if (en_i) begin
            phase_pipe_0_r <= phase_idx_r;
            phase_pipe_1_r <= phase_pipe_0_r;
            write_valid_r <= {write_valid_r[0], issue_i && reuse_i};
            original_0_r <= selected_w;
            original_1_r <= original_0_r;
            if (issue_i) begin
                phase_idx_r <= phase_idx_r + 1'b1;
            end
            if (load_i) begin
                phase_idx_r <= 0;
                write_valid_r <= 0;
            end
        end
    end
    genvar phase;
    generate
        // Two phase registers, each with a load/feedback selector and one whole-register write.
        for (phase = 0; phase < 2; phase = phase + 1) begin : g_phase
            reg [WIDTH-1:0] value_r;
            assign phase_w[phase] = value_r;
            always @(posedge clk_i) begin
                if (en_i && (load_i || (write_valid_r[1] && phase_pipe_1_r == phase)))
                    value_r <= load_i ? seed_i[phase*WIDTH +: WIDTH] : next_w;
            end
        end
    endgenerate
endmodule
