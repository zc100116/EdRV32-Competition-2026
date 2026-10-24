`timescale 1ns/1ps

module tb_geometry_rot15_stress;
    reg clk;
    reg rst_n;
    reg start;
    reg [15:0] width;
    reg [15:0] height;
    reg [15:0] image_width;
    reg [15:0] image_height;
    reg [8:0] angle;
    wire ready;
    wire pixel_valid;
    reg pixel_ready;
    wire [15:0] pixel_data;
    wire [15:0] pixel_x;
    wire [15:0] pixel_y;
    wire pixel_sof;
    wire pixel_eol;
    wire pixel_eof;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [3:0] arqos;
    wire arvalid;
    wire arready;
    wire [3:0] rid;
    wire [255:0] rdata;
    wire [1:0] rresp;
    wire rlast;
    wire rvalid;
    wire rready;
    wire busy;
    wire done;
    wire error;

    reg read_active_r;
    reg [7:0] read_beats_left_r;
    reg [3:0] read_id_r;
    integer cycles;
    integer pixels;
    integer commands;
    integer beats;
    integer guard;
    integer requested_width;
    integer requested_height;
    integer requested_image_width;
    integer requested_image_height;
    integer requested_angle;
    integer stall_enable;
    integer switch_enable;
    integer run_index;
    integer cycle_start;
    integer command_start;
    integer beat_start;
    integer expected_x;
    integer expected_y;

    always #4 clk = ~clk;

    assign arready = !read_active_r &&
        (!stall_enable || (cycles % 7 != 3));
    assign rid = read_id_r;
    assign rdata = 256'b0;
    assign rresp = 2'b00;
    assign rlast = read_beats_left_r == 8'd1;
    assign rvalid = read_active_r &&
        (!stall_enable || (cycles % 11 < 8));

    edrv32_geometry_block_engine u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(start), .cfg_ready_o(ready),
        .cfg_surface_base_i(32'h0),
        .cfg_surface_stride_i({15'b0, width, 1'b0}),
        .cfg_src_width_i(width), .cfg_src_height_i(height),
        .cfg_crop_x_i(16'd0), .cfg_crop_y_i(16'd0),
        .cfg_crop_width_i(width), .cfg_crop_height_i(height),
        .cfg_dst_width_i(width), .cfg_dst_height_i(height),
        .cfg_image_width_i(image_width),
        .cfg_image_height_i(image_height),
        .cfg_angle_i(angle), .cfg_flip_x_i(1'b0),
        .cfg_flip_y_i(1'b0), .cfg_fill_pixel_i(16'h0000),
        .pixel_valid_o(pixel_valid), .pixel_ready_i(pixel_ready),
        .pixel_data_o(pixel_data),
        .pixel_dst_x_o(pixel_x), .pixel_dst_y_o(pixel_y),
        .pixel_sof_o(pixel_sof), .pixel_eol_o(pixel_eol),
        .pixel_eof_o(pixel_eof),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready),
        .busy_o(busy), .done_o(done), .error_o(error),
        .profile_phase_o()
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            read_active_r <= 1'b0;
            read_beats_left_r <= 8'b0;
            read_id_r <= 4'b0;
            cycles <= 0;
            pixels <= 0;
            commands <= 0;
            beats <= 0;
        end else begin
            cycles <= cycles + 1;
            if (arvalid && arready) begin
                if (araddr[4:0] != 0 || arsize != 3'd5 ||
                    arburst != 2'b01 ||
                    araddr[11:5] + arlen + 1 > 128)
                    $fatal(1, "Illegal source AR address=%h len=%0d",
                           araddr, arlen);
                read_active_r <= 1'b1;
                read_beats_left_r <= arlen + 1'b1;
                read_id_r <= arid;
                commands <= commands + 1;
                beats <= beats + arlen + 1;
            end
            if (rvalid && rready) begin
                read_beats_left_r <= read_beats_left_r - 1'b1;
                if (rlast)
                    read_active_r <= 1'b0;
            end
            if (pixel_valid && pixel_ready) begin
                expected_x = pixels % width;
                expected_y = pixels / width;
                if (pixel_x != expected_x || pixel_y != expected_y ||
                    pixel_sof != (pixels == 0) ||
                    pixel_eol != (expected_x == width - 1) ||
                    pixel_eof != (pixels == width*height - 1))
                    $fatal(1, "Raster mismatch at pixel %0d", pixels);
                pixels <= pixels + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        pixel_ready = 1'b1;
        stall_enable = 0;
        requested_width = 128;
        requested_height = 80;
        requested_image_width = 0;
        requested_image_height = 0;
        requested_angle = 15;
        switch_enable = 0;
        if ($value$plusargs("WIDTH=%d", requested_width)) begin end
        if ($value$plusargs("HEIGHT=%d", requested_height)) begin end
        if ($value$plusargs("IMAGE_WIDTH=%d", requested_image_width)) begin end
        if ($value$plusargs("IMAGE_HEIGHT=%d", requested_image_height)) begin end
        if ($value$plusargs("ANGLE=%d", requested_angle)) begin end
        if ($value$plusargs("STALL=%d", stall_enable)) begin end
        if ($value$plusargs("SWITCH=%d", switch_enable)) begin end
        width = requested_width;
        height = requested_height;
        image_width = requested_image_width == 0 ?
            requested_width : requested_image_width;
        image_height = requested_image_height == 0 ?
            requested_height : requested_image_height;
        angle = 9'd0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        for (run_index = 0; run_index < (switch_enable ? 2 : 1);
             run_index = run_index + 1) begin
            @(negedge clk);
            while (!ready)
                @(negedge clk);
            angle = ((switch_enable == 0) || (run_index == 1)) ?
                requested_angle : 9'd0;
            pixels = 0;
            cycle_start = cycles;
            command_start = commands;
            beat_start = beats;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            guard = 0;
            while (!done && guard < 15000000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!done || error || pixels != width*height)
                $fatal(1,
                       "GEOMETRY_STRESS_FAIL angle=%0d done=%b error=%b pixels=%0d expected=%0d state=%0d block=(%0d,%0d) cycles=%0d",
                       angle, done, error, pixels, width*height,
                       u_dut.state_r, u_dut.block_x_r, u_dut.band_y_r,
                       cycles - cycle_start);
            $display("GEOMETRY_STRESS_PASS size=%0dx%0d image=%0dx%0d angle=%0d stall=%0d cycles=%0d pixels=%0d ar=%0d beats=%0d",
                     width, height, image_width, image_height,
                     angle, stall_enable,
                     cycles - cycle_start, pixels,
                     commands - command_start, beats - beat_start);
        end
        $finish;
    end
endmodule
