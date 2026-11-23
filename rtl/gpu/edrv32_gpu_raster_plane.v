// File: edrv32_gpu_raster_plane.v
// Spec: gpu-spec 2.13.7; microarch 4.6, 4.10.
// Description: Four interleaved group accumulators and four 20-bit carry slices.
//              Same-phase forwarding closes the four-cycle feedback recurrence.
// Clock domain: clk_gpu.
module edrv32_gpu_raster_plane (
    // Clock and pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Row initialization and ordered group issue.
    input wire load_i,
    input wire issue_i,
    input wire reuse_i,
    input wire [279:0] seed_i,
    input wire [69:0] delta_i,
    output wire [69:0] plane_o
);
    reg [69:0] phase_r [0:3];
    reg [1:0] phase_idx_r;
    reg [1:0] phase_pipe_r [0:3];
    reg [3:0] write_valid_r;
    reg [69:0] original_r [0:3];
    wire [69:0] selected_w;
    wire [69:0] next_w;
    assign selected_w = write_valid_r[3] && phase_idx_r == phase_pipe_r[3] ?
        next_w : phase_r[phase_idx_r];
    assign plane_o = original_r[3];
    edrv32_gpu_raster_add u_add (
        .clk_i(clk_i),
        .en_i(en_i),
        .a_i(selected_w),
        .b_i(delta_i),
        .sum_o(next_w)
    );
    always @(posedge clk_i) begin
        if (en_i) begin
            phase_pipe_r[0] <= phase_idx_r;
            phase_pipe_r[1] <= phase_pipe_r[0];
            phase_pipe_r[2] <= phase_pipe_r[1];
            phase_pipe_r[3] <= phase_pipe_r[2];
            write_valid_r <= {write_valid_r[2:0], issue_i && reuse_i};
            original_r[0] <= selected_w;
            original_r[1] <= original_r[0];
            original_r[2] <= original_r[1];
            original_r[3] <= original_r[2];
            if (issue_i) begin
                phase_idx_r <= phase_idx_r + 1'b1;
            end
            if (write_valid_r[3]) begin
                phase_r[phase_pipe_r[3]] <= next_w;
            end
            if (load_i) begin
                phase_idx_r <= 0;
                write_valid_r <= 0;
                phase_r[0] <= seed_i[0 +: 70];
                phase_r[1] <= seed_i[70 +: 70];
                phase_r[2] <= seed_i[140 +: 70];
                phase_r[3] <= seed_i[210 +: 70];
            end
        end
    end
endmodule
