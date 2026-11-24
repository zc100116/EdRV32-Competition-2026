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
    wire [69:0] phase_w [0:3];
    reg [1:0] phase_idx_r;
    reg [1:0] phase_pipe_0_r;
    reg [1:0] phase_pipe_1_r;
    reg [1:0] phase_pipe_2_r;
    reg [1:0] phase_pipe_3_r;
    reg [3:0] write_valid_r;
    reg [69:0] original_0_r;
    reg [69:0] original_1_r;
    reg [69:0] original_2_r;
    reg [69:0] original_3_r;
    wire [69:0] selected_w;
    wire [69:0] next_w;
    assign selected_w = write_valid_r[3] && phase_idx_r == phase_pipe_3_r ?
        next_w : phase_w[phase_idx_r];
    assign plane_o = original_3_r;
    edrv32_gpu_raster_add u_add (
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
            phase_pipe_2_r <= phase_pipe_1_r;
            phase_pipe_3_r <= phase_pipe_2_r;
            write_valid_r <= {write_valid_r[2:0], issue_i && reuse_i};
            original_0_r <= selected_w;
            original_1_r <= original_0_r;
            original_2_r <= original_1_r;
            original_3_r <= original_2_r;
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
        // Four phase registers, each with a load/feedback selector and one whole-register write.
        for (phase = 0; phase < 4; phase = phase + 1) begin : g_phase
            reg [69:0] value_r;
            assign phase_w[phase] = value_r;
            always @(posedge clk_i) begin
                if (en_i && (load_i || (write_valid_r[3] && phase_pipe_3_r == phase)))
                    value_r <= load_i ? seed_i[phase*70 +: 70] : next_w;
            end
        end
    endgenerate
endmodule
