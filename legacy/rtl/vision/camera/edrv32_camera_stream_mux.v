// ============================================================================
// File        : edrv32_camera_stream_mux.v
// Description : Frame-boundary selector for two packed camera streams.
// Notes       : The unselected input is drained so a source change always waits
//               for a fresh SOF and never splices two cameras into one frame.
// ============================================================================

module edrv32_camera_stream_mux (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         select_i,

    input  wire [257:0] cam0_data_i,
    input  wire         cam0_valid_i,
    output wire         cam0_ready_o,

    input  wire [257:0] cam1_data_i,
    input  wire         cam1_valid_i,
    output wire         cam1_ready_o,

    output wire [257:0] stream_data_o,
    output wire         stream_valid_o,
    input  wire         stream_ready_i,
    output wire         active_camera_o,
    output wire         error_o
);

    reg in_frame_r;
    reg active_camera_r;
    reg error_r;

    reg cam0_ready_w;
    reg cam1_ready_w;
    reg [257:0] stream_data_w;
    reg stream_valid_w;

    always @(*) begin
        cam0_ready_w = 1'b0;
        cam1_ready_w = 1'b0;
        stream_data_w = 258'b0;
        stream_valid_w = 1'b0;

        if (in_frame_r) begin
            if (active_camera_r) begin
                cam0_ready_w = 1'b1;
                cam1_ready_w = stream_ready_i;
                stream_data_w = cam1_data_i;
                stream_valid_w = cam1_valid_i;
            end else begin
                cam0_ready_w = stream_ready_i;
                cam1_ready_w = 1'b1;
                stream_data_w = cam0_data_i;
                stream_valid_w = cam0_valid_i;
            end
        end else if (select_i) begin
            cam0_ready_w = 1'b1;
            if (cam1_valid_i && cam1_data_i[257]) begin
                cam1_ready_w = stream_ready_i;
                stream_data_w = cam1_data_i;
                stream_valid_w = 1'b1;
            end else begin
                cam1_ready_w = 1'b1;
            end
        end else begin
            cam1_ready_w = 1'b1;
            if (cam0_valid_i && cam0_data_i[257]) begin
                cam0_ready_w = stream_ready_i;
                stream_data_w = cam0_data_i;
                stream_valid_w = 1'b1;
            end else begin
                cam0_ready_w = 1'b1;
            end
        end
    end

    assign cam0_ready_o = cam0_ready_w;
    assign cam1_ready_o = cam1_ready_w;
    assign stream_data_o = stream_data_w;
    assign stream_valid_o = stream_valid_w;
    assign active_camera_o = active_camera_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            in_frame_r <= 1'b0;
            active_camera_r <= 1'b0;
            error_r <= 1'b0;
        end else if (stream_valid_w && stream_ready_i) begin
            if (!in_frame_r) begin
                active_camera_r <= select_i;
                in_frame_r <= !stream_data_w[256];
            end else begin
                if (stream_data_w[257])
                    error_r <= 1'b1;
                if (stream_data_w[256])
                    in_frame_r <= 1'b0;
            end
        end
    end

endmodule
