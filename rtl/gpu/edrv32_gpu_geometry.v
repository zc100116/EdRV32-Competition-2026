// File: edrv32_gpu_geometry.v
// Spec: gpu-spec 2.4, 2.12; GPU microarchitecture 4.2, 4.3.
// Description: Draw-scoped configuration, ordered transform/clip/project, fan triangulation and culling.
//              Every interstage stream reserves two slots; done waits for complete output drain.
// Clock domain: clk_gpu.
module edrv32_gpu_geometry (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Configuration snapshot, followed by one draw command.
    input wire geometry_cfg_valid_i,
    output wire geometry_cfg_ready_o,
    input wire [511:0] geometry_cfg_matrix_i,
    input wire [95:0] geometry_cfg_light_i,
    input wire [255:0] geometry_cfg_target_i,
    input wire [255:0] geometry_cfg_pixel_i,
    input wire geometry_cfg_wide_i,
    input wire draw_valid_i,
    output wire draw_ready_o,
    input wire [255:0] draw_command_i,

    // Packed vertex stream.
    input wire vertex_valid_i,
    output wire vertex_ready_o,
    input wire [127:0] vertex_data_i,

    // Screen triangle replacement boundary.
    output wire screen_triangle_valid_o,
    input wire screen_triangle_ready_i,
    output wire [50:0] screen_triangle_x_o,
    output wire [50:0] screen_triangle_y_o,
    output wire [47:0] screen_triangle_depth_o,
    output wire [104:0] screen_triangle_q_o,
    output wire [152:0] screen_triangle_uq_o,
    output wire [152:0] screen_triangle_vq_o,
    output wire [215:0] screen_triangle_color_o,

    // Command lifetime and performance event.
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,
    output wire perf_vertex_o
);
    wire [511:0] matrix_w;
    wire [791:0] triangle_data_w;
    wire [263:0] project_input_data_w;
    reg [95:0] light_r;
    reg [255:0] unused_target_r;
    reg [255:0] unused_pixel_r;
    reg unused_wide_r;
    wire [255:0] unused_draw_w;
    reg configured_r;
    reg active_r;
    reg [25:0] remaining_r;
    wire transform_input_valid_w;
    wire transform_input_ready_w;
    wire transform_valid_w;
    wire transform_ready_w;
    wire [263:0] transform_data_w;
    wire transform_idle_w;
    reg [1:0] assembly_count_r;
    reg [1:0] triangle_count_r;
    reg triangle_read_r;
    reg triangle_write_r;
    wire triangle_push_w;
    wire triangle_pop_w;
    wire clip_ready_w;
    wire polygon_valid_w;
    wire polygon_ready_w;
    wire [2111:0] polygon_data_w;
    wire [3:0] polygon_count_w;
    wire clip_idle_w;
    reg sending_r;
    reg send_phase_r;
    reg [3:0] send_count_r;
    reg [2:0] send_index_r;
    wire project_input_valid_w;
    wire project_input_ready_w;
    wire project_valid_w;
    wire project_ready_w;
    wire [258:0] project_data_w;
    wire project_idle_w;
    reg [3:0] counts_r [0:15];
    reg [4:0] counts_count_r;
    reg [3:0] counts_read_r;
    reg [3:0] counts_write_r;
    wire polygon_accept_w;
    wire polygon_complete_w;
    reg [2:0] screen_index_r;
    reg screen_write_bank_r;
    reg screen_read_bank_r;
    reg [1:0] screen_count_r;
    wire [3:0] counts_head_w;
    wire [2:0] counts_even_index_w;
    reg [3:0] counts_even_cache_r;
    reg [3:0] counts_odd_cache_r;
    assign counts_even_index_w = counts_read_r[3:1] + {2'b0, counts_read_r[0]};
    assign counts_head_w = counts_read_r[0] ? counts_odd_cache_r : counts_even_cache_r;
    always @(posedge clk_i) begin
        counts_even_cache_r <= counts_r[{counts_even_index_w, 1'b0}];
        counts_odd_cache_r <= counts_r[{counts_read_r[3:1], 1'b1}];
    end
    reg [3:0] screen_counts_r [0:1];
    wire [3:0] next_screen_count_w;
    assign next_screen_count_w = screen_read_bank_r ? screen_counts_r[0] : screen_counts_r[1];
    wire fan_last_w;
    assign fan_last_w = fan_advance_w && {1'b0, fan_index_r} + 4'd2 == fan_count_r;
    reg fan_r;
    reg [2:0] fan_index_r;
    reg [3:0] fan_count_r;
    wire signed [17:0] fan_x_w [0:2];
    wire signed [17:0] fan_y_w [0:2];
    reg signed [17:0] fan_dx_w [0:1];
    reg signed [17:0] fan_dy_w [0:1];
    wire [35:0] fan_delta_x_w;
    wire [35:0] fan_delta_y_w;
    wire [71:0] fan_product_w;
    reg fan_keep_r;
    reg fan_negative_r;
    reg [2:0] fan_wait_r;
    wire fan_keep_w;
    wire fan_advance_w;
    reg [1:0] output_count_r;
    reg output_read_r;
    reg output_write_r;
    wire output_push_w;
    wire output_pop_w;
    wire drained_w;

    assign unused_draw_w = draw_command_i;
    assign geometry_cfg_ready_o = !active_r && !stop_i;
    assign draw_ready_o = configured_r && !active_r && !stop_i;
    assign transform_input_valid_w = active_r && remaining_r != 0 && vertex_valid_i;
    assign vertex_ready_o = active_r && remaining_r != 0 && transform_input_ready_w;
    assign perf_vertex_o = vertex_valid_i && vertex_ready_o;
    assign transform_ready_w = triangle_count_r != 2 && !stop_i;
    assign triangle_push_w = transform_valid_w && transform_ready_w && assembly_count_r == 2;
    assign triangle_pop_w = triangle_count_r != 0 && clip_ready_w;
    assign polygon_ready_w = !sending_r && counts_count_r != 16 && !stop_i;
    assign polygon_accept_w = polygon_valid_w && polygon_ready_w;
    assign project_input_valid_w = sending_r && !send_phase_r && !stop_i;
    assign project_ready_w = screen_count_r != 2 && counts_count_r != 0 && !stop_i;
    assign polygon_complete_w = project_valid_w && project_ready_w
        && {1'b0, screen_index_r} + 4'd1 == counts_head_w;
    assign fan_keep_w = fan_keep_r;
    assign fan_advance_w = fan_r && fan_wait_r == 0 && (!fan_keep_w || output_count_r != 2) &&
            !stop_i;
    assign output_push_w = fan_advance_w && fan_keep_w;
    assign screen_triangle_valid_o = output_count_r != 0;
    assign output_pop_w = screen_triangle_valid_o && screen_triangle_ready_i;
    assign drained_w = remaining_r == 0 && transform_idle_w && assembly_count_r == 0
        && triangle_count_r == 0 && clip_idle_w && !sending_r && counts_count_r == 0
        && project_idle_w && !fan_r && screen_count_r == 0 && output_count_r == 0 &&
            screen_index_r == 0;
    edrv32_gpu_transform u_transform (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .vertex_valid_i(transform_input_valid_w),
        .vertex_ready_o(transform_input_ready_w),
        .vertex_data_i(vertex_data_i),
        .matrix_i(matrix_w),
        .light_i(light_r),
        .transformed_valid_o(transform_valid_w),
        .transformed_ready_i(transform_ready_w),
        .transformed_data_o(transform_data_w),
        .stop_i(stop_i),
        .idle_o(transform_idle_w)
    );

    edrv32_gpu_clip u_clip (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .triangle_valid_i(triangle_count_r != 0),
        .triangle_ready_o(clip_ready_w),
        .triangle_data_i(triangle_data_w),
        .polygon_valid_o(polygon_valid_w),
        .polygon_ready_i(polygon_ready_w),
        .polygon_data_o(polygon_data_w),
        .polygon_count_o(polygon_count_w),
        .stop_i(stop_i),
        .idle_o(clip_idle_w)
    );

    edrv32_gpu_project u_project (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clipped_valid_i(project_input_valid_w),
        .clipped_ready_o(project_input_ready_w),
        .clipped_data_i(project_input_data_w),
        .viewport_i(unused_target_r[191:128]),
        .projected_valid_o(project_valid_w),
        .projected_ready_i(project_ready_w),
        .projected_data_o(project_data_w),
        .stop_i(stop_i),
        .idle_o(project_idle_w)
    );

    // Configuration: sixteen independent 32-bit registers, packed only at the port.
    // Assembly/clip/project queues: nine fields per vertex; no internal record mux.
    genvar field_g;
    genvar vertex_g;
    genvar matrix_g;
    generate
        for (matrix_g = 0; matrix_g < 16; matrix_g = matrix_g + 1) begin : g_matrix
            reg [31:0] data_r;
            assign matrix_w[matrix_g * 32 +: 32] = data_r;
            always @(posedge clk_i) begin
                if (geometry_cfg_valid_i && geometry_cfg_ready_o)
                    data_r <= geometry_cfg_matrix_i[matrix_g * 32 +: 32];
            end
        end
        for (field_g = 0; field_g < 9; field_g = field_g + 1) begin : g_clipped_field
            localparam WIDTH = field_g < 4 ? 40 : (field_g < 6 ? 16 : 24);
            localparam OFFSET = field_g < 4 ? field_g * 40
                : (field_g < 6 ? 160 + (field_g - 4) * 16 : 192 + (field_g - 6) * 24);
            // Each field owns its accept decode; preserved state prevents PDS merging.
            (* keep = "true", syn_preserve = 1 *) reg polygon_sending_r;
            (* keep = "true", syn_preserve = 1 *) reg [4:0] polygon_counts_count_r;
            (* keep = "true", syn_preserve = 1 *) wire polygon_accept_region_w;
            assign polygon_accept_region_w = polygon_valid_w && !polygon_sending_r
                && polygon_counts_count_r != 16 && !stop_i;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    polygon_sending_r <= 1'b0;
                    polygon_counts_count_r <= 5'd0;
                end else if (stop_i) begin
                    polygon_sending_r <= 1'b0;
                    polygon_counts_count_r <= 5'd0;
                end else begin
                    if (project_input_valid_w && project_input_ready_w
                        && {1'b0, send_index_r} + 4'd1 == send_count_r)
                        polygon_sending_r <= 1'b0;
                    if (polygon_accept_region_w) polygon_sending_r <= 1'b1;
                    case ({polygon_accept_region_w, polygon_complete_w})
                        2'b10: polygon_counts_count_r <= polygon_counts_count_r + 5'd1;
                        2'b01: polygon_counts_count_r <= polygon_counts_count_r - 5'd1;
                        default: polygon_counts_count_r <= polygon_counts_count_r;
                    endcase
                end
            end
            wire [WIDTH*8-1:0] polygon_w;
            reg [WIDTH-1:0] selected_polygon_w;
            assign project_input_data_w[OFFSET +: WIDTH] = selected_polygon_w;
            always @(*) begin
                selected_polygon_w = 0;
                case (send_index_r)
                    3'd0: selected_polygon_w = polygon_w[WIDTH*0 +: WIDTH];
                    3'd1: selected_polygon_w = polygon_w[WIDTH*1 +: WIDTH];
                    3'd2: selected_polygon_w = polygon_w[WIDTH*2 +: WIDTH];
                    3'd3: selected_polygon_w = polygon_w[WIDTH*3 +: WIDTH];
                    3'd4: selected_polygon_w = polygon_w[WIDTH*4 +: WIDTH];
                    3'd5: selected_polygon_w = polygon_w[WIDTH*5 +: WIDTH];
                    3'd6: selected_polygon_w = polygon_w[WIDTH*6 +: WIDTH];
                    3'd7: selected_polygon_w = polygon_w[WIDTH*7 +: WIDTH];
                    default: selected_polygon_w = 0;
                endcase
            end
            for (vertex_g = 0; vertex_g < 8; vertex_g = vertex_g + 1) begin : g_polygon
                reg [WIDTH-1:0] data_r;
                assign polygon_w[WIDTH*vertex_g +: WIDTH] = data_r;
                always @(posedge clk_i) begin
                    if (polygon_accept_region_w)
                        data_r <= polygon_data_w[vertex_g * 264 + OFFSET +: WIDTH];
                end
            end
            for (vertex_g = 0; vertex_g < 3; vertex_g = vertex_g + 1) begin : g_triangle
                wire [WIDTH-1:0] push_data_w;
                reg [WIDTH-1:0] data_r [0:1];
                if (vertex_g < 2) begin : g_assembly
                    reg [WIDTH-1:0] assembly_r;
                    always @(posedge clk_i) begin
                        if (transform_valid_w && transform_ready_w && assembly_count_r == vertex_g)
                            assembly_r <= transform_data_w[OFFSET +: WIDTH];
                    end
                    assign push_data_w = assembly_r;
                end else begin : g_last
                    assign push_data_w = transform_data_w[OFFSET +: WIDTH];
                end
                assign triangle_data_w[vertex_g * 264 + OFFSET +: WIDTH] = data_r[triangle_read_r];
                always @(posedge clk_i) begin
                    if (triangle_push_w) data_r[triangle_write_r] <= push_data_w;
                end
            end
        end
        // Seven projected fields; each has one 8-entry screen array and a 2-slot output FIFO.
        for (field_g = 0; field_g < 7; field_g = field_g + 1) begin : g_screen_field
            localparam WIDTH = field_g < 2 ? 17 : (field_g == 2 ? 16
                : (field_g == 3 ? 35 : (field_g < 6 ? 51 : 72)));
            localparam OFFSET = field_g == 0 ? 0 : (field_g == 1 ? 17
                : (field_g == 2 ? 34 : (field_g == 3 ? 50
                : (field_g == 4 ? 85 : (field_g == 5 ? 136 : 187)))));
            wire [71:0] unused_screen_data_w [0:2];
            wire [11:0] screen_address_w;
            assign screen_address_w = {screen_read_bank_r, next_index_w,
                screen_read_bank_r, fan_index_r, screen_read_bank_r, 3'b0};
            genvar screen_port;
            for (screen_port = 0; screen_port < 3;
                screen_port = screen_port + 1) begin : g_screen_port
                edrv32_ram_gpu_table u_screen (
                    .clk_i(clk_i),
                    .wr_en_i(project_valid_w && project_ready_w),
                    .wr_addr_i({2'b0, screen_write_bank_r, screen_index_r}),
                    .wr_data_i({{(72-WIDTH){1'b0}}, project_data_w[OFFSET +: WIDTH]}),
                    .rd_addr_i({2'b0, screen_address_w[screen_port*4 +: 4]}),
                    .rd_data_o(unused_screen_data_w[screen_port])
                );
            end
            wire [WIDTH*3-1:0] fan_w;
            wire [71:0] unused_screen_read2_w;
            wire [WIDTH-1:0] screen_read2_w;
            assign unused_screen_read2_w = unused_screen_data_w[2];
            assign screen_read2_w = unused_screen_read2_w[WIDTH-1:0];
            wire [71:0] unused_screen_read1_w;
            wire [WIDTH-1:0] screen_read1_w;
            assign unused_screen_read1_w = unused_screen_data_w[1];
            assign screen_read1_w = unused_screen_read1_w[WIDTH-1:0];
            wire [71:0] unused_screen_read0_w;
            wire [WIDTH-1:0] screen_read0_w;
            assign unused_screen_read0_w = unused_screen_data_w[0];
            assign screen_read0_w = unused_screen_read0_w[WIDTH-1:0];
            wire [2:0] next_index_w;
            wire [WIDTH*3-1:0] ordered_w;
            wire [WIDTH*3-1:0] output_w;
            reg [WIDTH*3-1:0] output_r [0:1];
            assign next_index_w = fan_index_r + 3'd1;
            assign fan_w[WIDTH*0 +: WIDTH] = screen_read0_w;
            assign fan_w[WIDTH*1 +: WIDTH] = screen_read1_w;
            assign fan_w[WIDTH*2 +: WIDTH] = screen_read2_w;
            assign ordered_w = !fan_negative_r
                ? {fan_w[WIDTH*2 +: WIDTH], fan_w[WIDTH*1 +: WIDTH], fan_w[WIDTH*0 +: WIDTH]}
                : {fan_w[WIDTH*1 +: WIDTH], fan_w[WIDTH*2 +: WIDTH], fan_w[WIDTH*0 +: WIDTH]};
            assign output_w = output_r[output_read_r];
            if (field_g == 0) begin : g_x
                assign screen_triangle_x_o = output_w;
                for (vertex_g = 0; vertex_g < 3; vertex_g = vertex_g + 1) begin : g_vertex
                    assign fan_x_w[vertex_g] = {fan_w[WIDTH*vertex_g+16],
                        fan_w[WIDTH*vertex_g +: WIDTH]};
                end
            end else if (field_g == 1) begin : g_y
                assign screen_triangle_y_o = output_w;
                for (vertex_g = 0; vertex_g < 3; vertex_g = vertex_g + 1) begin : g_vertex
                    assign fan_y_w[vertex_g] = {fan_w[WIDTH*vertex_g+16],
                        fan_w[WIDTH*vertex_g +: WIDTH]};
                end
            end else if (field_g == 2) begin : g_depth
                assign screen_triangle_depth_o = output_w;
            end else if (field_g == 3) begin : g_q
                assign screen_triangle_q_o = output_w;
            end else if (field_g == 4) begin : g_uq
                assign screen_triangle_uq_o = output_w;
            end else if (field_g == 5) begin : g_vq
                assign screen_triangle_vq_o = output_w;
            end else begin : g_color
                assign screen_triangle_color_o = output_w;
            end
            always @(posedge clk_i) begin
                if (output_push_w) output_r[output_write_r] <= ordered_w;
            end
        end
    endgenerate

    // Existing fan stage: four s18 subtractors, two 18x18 multipliers, one s37 subtractor.
    always @(*) begin
        fan_dx_w[0] = fan_x_w[1] - fan_x_w[0];
        fan_dx_w[1] = fan_x_w[2] - fan_x_w[0];
        fan_dy_w[0] = fan_y_w[1] - fan_y_w[0];
        fan_dy_w[1] = fan_y_w[2] - fan_y_w[0];
    end
    // Two registered 18x18 APM paths; signed 36-bit comparisons replace the s37 area sum.
    genvar fan_axis;
    generate
        for (fan_axis = 0; fan_axis < 2; fan_axis = fan_axis + 1) begin : g_fan_product
            reg signed [17:0] dx_r;
            reg signed [17:0] dy_r;
            reg signed [35:0] product_0_r;
            reg signed [35:0] product_1_r;
            reg signed [35:0] product_2_r;
            wire signed [17:0] multiply_x_w;
            wire signed [17:0] multiply_y_w;
            assign fan_delta_x_w[fan_axis*18 +: 18] = dx_r;
            assign fan_delta_y_w[fan_axis*18 +: 18] = dy_r;
            assign fan_product_w[fan_axis*36 +: 36] = product_2_r;
            assign multiply_x_w = fan_axis == 0 ?
                fan_delta_x_w[0 +: 18] : fan_delta_y_w[0 +: 18];
            assign multiply_y_w = fan_axis == 0 ?
                fan_delta_y_w[18 +: 18] : fan_delta_x_w[18 +: 18];
            always @(posedge clk_i) begin
                dx_r <= fan_dx_w[fan_axis];
                dy_r <= fan_dy_w[fan_axis];
                product_0_r <= multiply_x_w * multiply_y_w;
                product_1_r <= product_0_r;
                product_2_r <= product_1_r;
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        fan_keep_r <= fan_product_w[0 +: 36] != fan_product_w[36 +: 36] &&
            !(unused_pixel_r[36:35] == 1 &&
                $signed(fan_product_w[0 +: 36]) > $signed(fan_product_w[36 +: 36])) &&
            !(unused_pixel_r[36:35] == 2 &&
                $signed(fan_product_w[0 +: 36]) < $signed(fan_product_w[36 +: 36]));
        fan_negative_r <= $signed(fan_product_w[0 +: 36]) < $signed(fan_product_w[36 +: 36]);
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            configured_r <= 1'b0;
            active_r <= 1'b0;
            remaining_r <= 26'd0;
            assembly_count_r <= 2'd0;
            triangle_count_r <= 2'd0;
            triangle_read_r <= 1'b0;
            triangle_write_r <= 1'b0;
            sending_r <= 1'b0;
            send_phase_r <= 1'b0;
            send_count_r <= 4'd0;
            send_index_r <= 3'd0;
            counts_count_r <= 5'd0;
            counts_read_r <= 4'd0;
            counts_write_r <= 4'd0;
            screen_index_r <= 3'd0;
            screen_write_bank_r <= 0;
            screen_read_bank_r <= 0;
            screen_count_r <= 0;
            fan_r <= 1'b0;
            fan_wait_r <= 0;
            fan_index_r <= 3'd0;
            fan_count_r <= 4'd0;
            output_count_r <= 2'd0;
            output_read_r <= 1'b0;
            output_write_r <= 1'b0;
            unit_done_o <= 1'b0;
        end else if (stop_i) begin
            configured_r <= 1'b0;
            active_r <= 1'b0;
            remaining_r <= 26'd0;
            assembly_count_r <= 2'd0;
            triangle_count_r <= 2'd0;
            triangle_read_r <= 1'b0;
            triangle_write_r <= 1'b0;
            sending_r <= 1'b0;
            send_phase_r <= 1'b0;
            counts_count_r <= 5'd0;
            counts_read_r <= 4'd0;
            counts_write_r <= 4'd0;
            screen_index_r <= 3'd0;
            screen_write_bank_r <= 0;
            screen_read_bank_r <= 0;
            screen_count_r <= 0;
            fan_r <= 1'b0;
            fan_wait_r <= 0;
            output_count_r <= 2'd0;
            output_read_r <= 1'b0;
            output_write_r <= 1'b0;
            unit_done_o <= finish_i;
        end else begin
            if (fan_wait_r != 0) fan_wait_r <= fan_wait_r - 1'b1;
            if (!finish_i) unit_done_o <= 1'b0;
            else if (drained_w) begin
                unit_done_o <= 1'b1;
                active_r <= 1'b0;
            end
            if (geometry_cfg_valid_i && geometry_cfg_ready_o) configured_r <= 1'b1;
            if (draw_valid_i && draw_ready_o) begin
                remaining_r <= {2'd0, unused_draw_w[119:96]}
                    + ({2'd0, unused_draw_w[119:96]} << 1);
                active_r <= 1'b1;
                configured_r <= 1'b0;
            end else if (perf_vertex_o) remaining_r <= remaining_r - 26'd1;
            if (transform_valid_w && transform_ready_w) begin
                if (assembly_count_r == 2) assembly_count_r <= 2'd0;
                else assembly_count_r <= assembly_count_r + 2'd1;
            end
            if (triangle_push_w) triangle_write_r <= !triangle_write_r;
            if (triangle_pop_w) triangle_read_r <= !triangle_read_r;
            begin
                case ({triangle_push_w, triangle_pop_w})
                    2'b10: triangle_count_r <= triangle_count_r + 2'd1;
                    2'b01: triangle_count_r <= triangle_count_r - 2'd1;
                    default: triangle_count_r <= triangle_count_r;
                endcase
            end
            if (send_phase_r) send_phase_r <= 1'b0;
            if (project_input_valid_w && project_input_ready_w) begin
                send_phase_r <= 1'b1;
                if ({1'b0, send_index_r} + 4'd1 == send_count_r) sending_r <= 1'b0;
                else send_index_r <= send_index_r + 3'd1;
            end
            if (polygon_accept_w) begin
                sending_r <= 1'b1;
                send_index_r <= 3'd0;
                send_count_r <= polygon_count_w;
                counts_write_r <= counts_write_r + 4'd1;
            end
            if (polygon_complete_w) counts_read_r <= counts_read_r + 4'd1;
            begin
                case ({polygon_accept_w, polygon_complete_w})
                    2'b10: counts_count_r <= counts_count_r + 5'd1;
                    2'b01: counts_count_r <= counts_count_r - 5'd1;
                    default: counts_count_r <= counts_count_r;
                endcase
            end
            if (project_valid_w && project_ready_w) begin
                if (polygon_complete_w) screen_index_r <= 0;
                else screen_index_r <= screen_index_r + 1'b1;
            end
            if (polygon_complete_w) screen_write_bank_r <= !screen_write_bank_r;
            if (fan_last_w) screen_read_bank_r <= !screen_read_bank_r;
            begin
                case ({polygon_complete_w, fan_last_w})
                2'b10: screen_count_r <= screen_count_r + 1'b1;
                2'b01: screen_count_r <= screen_count_r - 1'b1;
                    default: screen_count_r <= screen_count_r;
                endcase
            end
            if (!fan_r && (screen_count_r != 0 || polygon_complete_w)) begin
                fan_r <= 1;
                fan_wait_r <= 5;
                fan_index_r <= 1;
                fan_count_r <= screen_count_r != 0 ? screen_counts_r[screen_read_bank_r]
                    : counts_head_w;
            end
            if (fan_advance_w) begin
                fan_wait_r <= 5;
                if (fan_last_w) begin
                    fan_r <= screen_count_r > 1 || polygon_complete_w;
                    fan_index_r <= 1;
                    fan_count_r <= screen_count_r > 1 ?
                        next_screen_count_w : counts_head_w;
                end else fan_index_r <= fan_index_r + 1'b1;
            end
            if (output_push_w) output_write_r <= !output_write_r;
            if (output_pop_w) output_read_r <= !output_read_r;
            begin
                case ({output_push_w, output_pop_w})
                    2'b10: output_count_r <= output_count_r + 2'd1;
                    2'b01: output_count_r <= output_count_r - 2'd1;
                    default: output_count_r <= output_count_r;
                endcase
            end
        end
    end

    always @(posedge clk_i) begin
        if (geometry_cfg_valid_i && geometry_cfg_ready_o) begin
            light_r <= geometry_cfg_light_i;
            unused_target_r <= geometry_cfg_target_i;
            unused_pixel_r <= geometry_cfg_pixel_i;
            unused_wide_r <= geometry_cfg_wide_i;
        end
        if (polygon_accept_w) counts_r[counts_write_r] <= polygon_count_w;
        if (polygon_complete_w)
            screen_counts_r[screen_write_bank_r] <= counts_head_w;
    end
endmodule
