// Self-checking gpu_command unit test.
module tb_gpu_command;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic start_i = 0;
    logic abort_i = 0;
    logic soft_rst_i = 0;
    logic enable_i = 0;
    logic [31:0] desc_base_i = 0;
    logic [15:0] desc_count_i = 0;
    logic wide_i = 0;
    logic busy_o;
    logic done_o;
    logic error_o;
    logic [31:0] err_code_o;
    logic command_read_req_valid_o;
    logic command_read_req_ready_i = 0;
    logic [31:0] command_read_req_addr_o;
    logic [31:0] command_read_req_bytes_o;
    logic matrix_read_req_valid_o;
    logic matrix_read_req_ready_i = 0;
    logic [31:0] matrix_read_req_addr_o;
    logic [31:0] matrix_read_req_bytes_o;
    logic vertex_read_req_valid_o;
    logic vertex_read_req_ready_i = 0;
    logic [31:0] vertex_read_req_addr_o;
    logic [31:0] vertex_read_req_bytes_o;
    logic quad_read_req_valid_o;
    logic quad_read_req_ready_i = 0;
    logic [31:0] quad_read_req_addr_o;
    logic [31:0] quad_read_req_bytes_o;
    logic object_read_req_valid_o;
    logic object_read_req_ready_i = 0;
    logic [31:0] object_read_req_addr_o;
    logic [31:0] object_read_req_bytes_o;
    logic texture_read_req_valid_o;
    logic texture_read_req_ready_i = 0;
    logic [31:0] texture_read_req_addr_o;
    logic [31:0] texture_read_req_bytes_o;
    logic palette_read_req_valid_o;
    logic palette_read_req_ready_i = 0;
    logic [31:0] palette_read_req_addr_o;
    logic [31:0] palette_read_req_bytes_o;
    logic command_read_data_valid_i = 0;
    logic command_read_data_ready_o;
    logic [255:0] command_read_data_data_i = 0;
    logic [31:0] command_read_data_keep_i = 0;
    logic command_read_data_last_i = 0;
    logic object_read_done_i = 0;
    logic read_dma_idle_i = 0;
    logic write_dma_idle_i = 0;
    logic read_dma_error_i = 0;
    logic write_dma_error_i = 0;
    logic dma_start_o;
    logic unpack_valid_o;
    logic unpack_ready_i = 0;
    logic [255:0] unpack_command_o;
    logic unpack_done_i = 0;
    logic matrix_valid_i = 0;
    logic matrix_ready_o;
    logic [511:0] matrix_data_i = 0;
    logic geometry_cfg_valid_o;
    logic geometry_cfg_ready_i = 0;
    logic [511:0] geometry_cfg_matrix_o;
    logic [95:0] geometry_cfg_light_o;
    logic [255:0] geometry_cfg_target_o;
    logic [255:0] geometry_cfg_pixel_o;
    logic geometry_cfg_wide_o;
    logic raster_render_state_valid_o;
    logic raster_render_state_ready_i = 0;
    logic [255:0] raster_render_state_tex_o;
    logic [255:0] raster_render_state_pixel_o;
    logic [255:0] raster_render_state_target_o;
    logic raster_render_state_wide_o;
    logic texture_render_state_valid_o;
    logic texture_render_state_ready_i = 0;
    logic [255:0] texture_render_state_tex_o;
    logic [255:0] texture_render_state_pixel_o;
    logic [255:0] texture_render_state_target_o;
    logic texture_render_state_wide_o;
    logic pixel_render_state_valid_o;
    logic pixel_render_state_ready_i = 0;
    logic [255:0] pixel_render_state_tex_o;
    logic [255:0] pixel_render_state_pixel_o;
    logic [255:0] pixel_render_state_target_o;
    logic pixel_render_state_wide_o;
    logic geometry_draw_valid_o;
    logic geometry_draw_ready_i = 0;
    logic [255:0] geometry_draw_command_o;
    logic raster_draw_valid_o;
    logic raster_draw_ready_i = 0;
    logic [255:0] raster_draw_command_o;
    logic quad_draw_valid_o;
    logic quad_draw_ready_i = 0;
    logic [255:0] quad_draw_command_o;
    logic object_draw_valid_o;
    logic object_draw_ready_i = 0;
    logic [255:0] object_draw_command_o;
    logic clear_valid_o;
    logic clear_ready_i = 0;
    logic [255:0] clear_command_o;
    logic [255:0] clear_target_o;
    logic clear_wide_o;
    logic resolve_valid_o;
    logic resolve_ready_i = 0;
    logic [255:0] resolve_command_o;
    logic [255:0] resolve_target_o;
    logic resolve_wide_o;
    logic palette_prepare_valid_o;
    logic palette_prepare_ready_i = 0;
    logic [3:0] palette_prepare_group_o;
    logic palette_prepared_valid_i = 0;
    logic palette_prepared_ready_o;
    logic object_cfg_request_o;
    logic object_cfg_done_i = 0;
    logic pack_valid_o;
    logic pack_ready_i = 0;
    logic [255:0] pack_command_o;
    logic pack_done_i = 0;
    logic object_publish_o;
    logic object_published_i = 0;
    logic geometry_finish_o;
    logic geometry_unit_done_i = 0;
    logic setup_finish_o;
    logic setup_unit_done_i = 0;
    logic raster_finish_o;
    logic raster_unit_done_i = 0;
    logic quad_finish_o;
    logic quad_unit_done_i = 0;
    logic perspective_finish_o;
    logic perspective_unit_done_i = 0;
    logic object_finish_o;
    logic object_unit_done_i = 0;
    logic texture_finish_o;
    logic texture_unit_done_i = 0;
    logic pixel_finish_o;
    logic pixel_unit_done_i = 0;
    logic target_finish_o;
    logic target_unit_done_i = 0;
    logic resolve_finish_o;
    logic resolve_unit_done_i = 0;
    logic stop_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_command u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .start_i(start_i),
        .abort_i(abort_i),
        .soft_rst_i(soft_rst_i),
        .enable_i(enable_i),
        .desc_base_i(desc_base_i),
        .desc_count_i(desc_count_i),
        .wide_i(wide_i),
        .busy_o(busy_o),
        .done_o(done_o),
        .error_o(error_o),
        .err_code_o(err_code_o),
        .command_read_req_valid_o(command_read_req_valid_o),
        .command_read_req_ready_i(command_read_req_ready_i),
        .command_read_req_addr_o(command_read_req_addr_o),
        .command_read_req_bytes_o(command_read_req_bytes_o),
        .matrix_read_req_valid_o(matrix_read_req_valid_o),
        .matrix_read_req_ready_i(matrix_read_req_ready_i),
        .matrix_read_req_addr_o(matrix_read_req_addr_o),
        .matrix_read_req_bytes_o(matrix_read_req_bytes_o),
        .vertex_read_req_valid_o(vertex_read_req_valid_o),
        .vertex_read_req_ready_i(vertex_read_req_ready_i),
        .vertex_read_req_addr_o(vertex_read_req_addr_o),
        .vertex_read_req_bytes_o(vertex_read_req_bytes_o),
        .quad_read_req_valid_o(quad_read_req_valid_o),
        .quad_read_req_ready_i(quad_read_req_ready_i),
        .quad_read_req_addr_o(quad_read_req_addr_o),
        .quad_read_req_bytes_o(quad_read_req_bytes_o),
        .object_read_req_valid_o(object_read_req_valid_o),
        .object_read_req_ready_i(object_read_req_ready_i),
        .object_read_req_addr_o(object_read_req_addr_o),
        .object_read_req_bytes_o(object_read_req_bytes_o),
        .texture_read_req_valid_o(texture_read_req_valid_o),
        .texture_read_req_ready_i(texture_read_req_ready_i),
        .texture_read_req_addr_o(texture_read_req_addr_o),
        .texture_read_req_bytes_o(texture_read_req_bytes_o),
        .palette_read_req_valid_o(palette_read_req_valid_o),
        .palette_read_req_ready_i(palette_read_req_ready_i),
        .palette_read_req_addr_o(palette_read_req_addr_o),
        .palette_read_req_bytes_o(palette_read_req_bytes_o),
        .command_read_data_valid_i(command_read_data_valid_i),
        .command_read_data_ready_o(command_read_data_ready_o),
        .command_read_data_data_i(command_read_data_data_i),
        .command_read_data_keep_i(command_read_data_keep_i),
        .command_read_data_last_i(command_read_data_last_i),
        .object_read_done_i(object_read_done_i),
        .read_dma_idle_i(read_dma_idle_i),
        .write_dma_idle_i(write_dma_idle_i),
        .read_dma_error_i(read_dma_error_i),
        .write_dma_error_i(write_dma_error_i),
        .dma_start_o(dma_start_o),
        .unpack_valid_o(unpack_valid_o),
        .unpack_ready_i(unpack_ready_i),
        .unpack_command_o(unpack_command_o),
        .unpack_done_i(unpack_done_i),
        .matrix_valid_i(matrix_valid_i),
        .matrix_ready_o(matrix_ready_o),
        .matrix_data_i(matrix_data_i),
        .geometry_cfg_valid_o(geometry_cfg_valid_o),
        .geometry_cfg_ready_i(geometry_cfg_ready_i),
        .geometry_cfg_matrix_o(geometry_cfg_matrix_o),
        .geometry_cfg_light_o(geometry_cfg_light_o),
        .geometry_cfg_target_o(geometry_cfg_target_o),
        .geometry_cfg_pixel_o(geometry_cfg_pixel_o),
        .geometry_cfg_wide_o(geometry_cfg_wide_o),
        .raster_render_state_valid_o(raster_render_state_valid_o),
        .raster_render_state_ready_i(raster_render_state_ready_i),
        .raster_render_state_tex_o(raster_render_state_tex_o),
        .raster_render_state_pixel_o(raster_render_state_pixel_o),
        .raster_render_state_target_o(raster_render_state_target_o),
        .raster_render_state_wide_o(raster_render_state_wide_o),
        .texture_render_state_valid_o(texture_render_state_valid_o),
        .texture_render_state_ready_i(texture_render_state_ready_i),
        .texture_render_state_tex_o(texture_render_state_tex_o),
        .texture_render_state_pixel_o(texture_render_state_pixel_o),
        .texture_render_state_target_o(texture_render_state_target_o),
        .texture_render_state_wide_o(texture_render_state_wide_o),
        .pixel_render_state_valid_o(pixel_render_state_valid_o),
        .pixel_render_state_ready_i(pixel_render_state_ready_i),
        .pixel_render_state_tex_o(pixel_render_state_tex_o),
        .pixel_render_state_pixel_o(pixel_render_state_pixel_o),
        .pixel_render_state_target_o(pixel_render_state_target_o),
        .pixel_render_state_wide_o(pixel_render_state_wide_o),
        .geometry_draw_valid_o(geometry_draw_valid_o),
        .geometry_draw_ready_i(geometry_draw_ready_i),
        .geometry_draw_command_o(geometry_draw_command_o),
        .raster_draw_valid_o(raster_draw_valid_o),
        .raster_draw_ready_i(raster_draw_ready_i),
        .raster_draw_command_o(raster_draw_command_o),
        .quad_draw_valid_o(quad_draw_valid_o),
        .quad_draw_ready_i(quad_draw_ready_i),
        .quad_draw_command_o(quad_draw_command_o),
        .object_draw_valid_o(object_draw_valid_o),
        .object_draw_ready_i(object_draw_ready_i),
        .object_draw_command_o(object_draw_command_o),
        .clear_valid_o(clear_valid_o),
        .clear_ready_i(clear_ready_i),
        .clear_command_o(clear_command_o),
        .clear_target_o(clear_target_o),
        .clear_wide_o(clear_wide_o),
        .resolve_valid_o(resolve_valid_o),
        .resolve_ready_i(resolve_ready_i),
        .resolve_command_o(resolve_command_o),
        .resolve_target_o(resolve_target_o),
        .resolve_wide_o(resolve_wide_o),
        .palette_prepare_valid_o(palette_prepare_valid_o),
        .palette_prepare_ready_i(palette_prepare_ready_i),
        .palette_prepare_group_o(palette_prepare_group_o),
        .palette_prepared_valid_i(palette_prepared_valid_i),
        .palette_prepared_ready_o(palette_prepared_ready_o),
        .object_cfg_request_o(object_cfg_request_o),
        .object_cfg_done_i(object_cfg_done_i),
        .pack_valid_o(pack_valid_o),
        .pack_ready_i(pack_ready_i),
        .pack_command_o(pack_command_o),
        .pack_done_i(pack_done_i),
        .object_publish_o(object_publish_o),
        .object_published_i(object_published_i),
        .geometry_finish_o(geometry_finish_o),
        .geometry_unit_done_i(geometry_unit_done_i),
        .setup_finish_o(setup_finish_o),
        .setup_unit_done_i(setup_unit_done_i),
        .raster_finish_o(raster_finish_o),
        .raster_unit_done_i(raster_unit_done_i),
        .quad_finish_o(quad_finish_o),
        .quad_unit_done_i(quad_unit_done_i),
        .perspective_finish_o(perspective_finish_o),
        .perspective_unit_done_i(perspective_unit_done_i),
        .object_finish_o(object_finish_o),
        .object_unit_done_i(object_unit_done_i),
        .texture_finish_o(texture_finish_o),
        .texture_unit_done_i(texture_unit_done_i),
        .pixel_finish_o(pixel_finish_o),
        .pixel_unit_done_i(pixel_unit_done_i),
        .target_finish_o(target_finish_o),
        .target_unit_done_i(target_unit_done_i),
        .resolve_finish_o(resolve_finish_o),
        .resolve_unit_done_i(resolve_unit_done_i),
        .stop_o(stop_o)
    );
    task tick;
        @(posedge clk_i); #1;
    endtask
    task reset;
        rst_n_i = 0;
        repeat (3) tick();
        @(negedge clk_i); rst_n_i = 1;
    endtask
    initial begin
        #2000000; $fatal(1, "FAIL timeout");
    end
    logic [255:0] program_data[64];
    int feed_count=0;
    int feed_index=0;
    int data_delay=0;
    int write_delay=0;
    int request_count[7];
    int done_count=0,error_count=0;
    int resolve_count=0,draw_count=0;
    int unit_delay[10];
    int cycles=0;
    bit model_run=0;
    bit matrix_pending=0;
    bit matrix_taken=0;
    logic [255:0] expected_tex;
    logic [255:0] expected_pixel;
    logic [255:0] expected_target;
    logic [511:0] expected_matrix;
    logic [95:0] expected_light;
    function int footprint(input int lw,input int lh,input int format);
        int w,h,bx,by,total;
        w=1<<lw;h=1<<lh;total=0;
        for(int k=0;k<9;k++) begin
            bx=format==2?w:(w+1)/2;
            by=format==0?(h+1)/2:h;
            total+=8*((bx+1)/2)*((by+1)/2);
            if(w>1)w/=2;if(h>1)h/=2;
        end
        return total;
    endfunction
    task fill_program;
        for(int i=0;i<64;i++) program_data[i]=0;
        program_data[0][7:0]='h01; program_data[0][95:69]=27'('h4000>>5);
        program_data[1][7:0]='h02; program_data[1][79:32]=48'h123456789abc;
        program_data[1][119:96]=24'h123456; program_data[1][151:128]=24'habcdef;
        program_data[2][7:0]='h03; program_data[2][67:64]=3;
        program_data[2][71:68]=3; program_data[2][77:74]=1;
        program_data[2][81:78]=2; program_data[2][83:82]=1;
        program_data[3][7:0]='h04; program_data[3][34:32]=7;
        program_data[4][7:0]='h05; program_data[4][191:32]=160'h123456789abcdef0123456789abcdef012345678;
        program_data[5][7:0]='h10;
        program_data[6][7:0]='h20; program_data[6][119:96]=1;
        program_data[7][7:0]='h21; program_data[7][119:96]=1;
        program_data[8][7:0]='h22; program_data[8][119:96]=2; program_data[8][33:32]=3;
        program_data[9][7:0]='h30; program_data[9][146:133]=2;
        program_data[10][7:0]='h31; program_data[10][104:96]=13;
        program_data[11][7:0]='h40;
        expected_tex=program_data[2]; expected_pixel=program_data[3];
        expected_target=program_data[4];
        expected_light={24'habcdef,24'h123456,48'h123456789abc};
        for(int i=0;i<16;i++) expected_matrix[i*32+:32]=32'(i*12345+7);
    endtask
    always @(negedge clk_i) begin
        if(model_run) begin
            cycles++;
            command_read_req_ready_i=1;
            command_read_data_valid_i=feed_count>0 && cycles%5!=0;
            command_read_data_data_i=program_data[feed_index];
            command_read_data_keep_i=-1;
            command_read_data_last_i=feed_count==1;
            read_dma_idle_i=feed_count==0 && data_delay==0;
            if(data_delay>0) data_delay--;
            object_read_done_i=0;
            if(data_delay==1) begin
                unpack_done_i=1;
                if(matrix_pending) matrix_valid_i=1;
                object_read_done_i=1;
            end
            if(matrix_taken) begin matrix_valid_i=0;matrix_pending=0;matrix_taken=0;end
            matrix_data_i=expected_matrix;
            if(write_delay>0) write_delay--;
            write_dma_idle_i=write_delay==0;
            object_cfg_done_i=object_cfg_request_o;
            palette_prepared_valid_i=palette_prepared_ready_o;
            object_published_i=object_publish_o;
            matrix_read_req_ready_i=1;
            vertex_read_req_ready_i=1;
            quad_read_req_ready_i=1;
            object_read_req_ready_i=1;
            texture_read_req_ready_i=1;
            palette_read_req_ready_i=1;
            unpack_ready_i=cycles%7!=0;
            geometry_cfg_ready_i=cycles%7!=0;
            raster_render_state_ready_i=cycles%7!=0;
            texture_render_state_ready_i=cycles%7!=0;
            pixel_render_state_ready_i=cycles%7!=0;
            geometry_draw_ready_i=cycles%7!=0;
            raster_draw_ready_i=cycles%7!=0;
            quad_draw_ready_i=cycles%7!=0;
            object_draw_ready_i=cycles%7!=0;
            clear_ready_i=cycles%7!=0;
            resolve_ready_i=cycles%7!=0;
            palette_prepare_ready_i=cycles%7!=0;
            pack_ready_i=cycles%7!=0;
            if(!geometry_finish_o) begin geometry_unit_done_i=0;unit_delay[0]=3;end
            else if(unit_delay[0]>0) unit_delay[0]--;
            else geometry_unit_done_i=1;
            if(!setup_finish_o) begin setup_unit_done_i=0;unit_delay[1]=3;end
            else if(unit_delay[1]>0) unit_delay[1]--;
            else setup_unit_done_i=1;
            if(!raster_finish_o) begin raster_unit_done_i=0;unit_delay[2]=3;end
            else if(unit_delay[2]>0) unit_delay[2]--;
            else raster_unit_done_i=1;
            if(!quad_finish_o) begin quad_unit_done_i=0;unit_delay[3]=3;end
            else if(unit_delay[3]>0) unit_delay[3]--;
            else quad_unit_done_i=1;
            if(!perspective_finish_o) begin perspective_unit_done_i=0;unit_delay[4]=3;end
            else if(unit_delay[4]>0) unit_delay[4]--;
            else perspective_unit_done_i=1;
            if(!object_finish_o) begin object_unit_done_i=0;unit_delay[5]=3;end
            else if(unit_delay[5]>0) unit_delay[5]--;
            else object_unit_done_i=1;
            if(!texture_finish_o) begin texture_unit_done_i=0;unit_delay[6]=3;end
            else if(unit_delay[6]>0) unit_delay[6]--;
            else texture_unit_done_i=1;
            if(!pixel_finish_o) begin pixel_unit_done_i=0;unit_delay[7]=3;end
            else if(unit_delay[7]>0) unit_delay[7]--;
            else pixel_unit_done_i=1;
            if(!target_finish_o) begin target_unit_done_i=0;unit_delay[8]=3;end
            else if(unit_delay[8]>0) unit_delay[8]--;
            else target_unit_done_i=1;
            if(!resolve_finish_o) begin resolve_unit_done_i=0;unit_delay[9]=3;end
            else if(unit_delay[9]>0) unit_delay[9]--;
            else resolve_unit_done_i=1;
            pack_done_i=object_unit_done_i;
        end
    end
    always @(posedge clk_i) begin
        if(rst_n_i && model_run) begin
            if(command_read_req_valid_o && command_read_req_ready_i) begin
                feed_count=int'(command_read_req_bytes_o)>>5;
                feed_index=(int'(command_read_req_addr_o)-'h1000)>>5;
                if(command_read_req_addr_o[4:0]!=0 || command_read_req_bytes_o>512
                    || command_read_req_addr_o<'h1000 || command_read_req_addr_o>'h17e0)
                    $fatal(1,"FAIL DESC snapshot/reserved prefetch");
            end
            if(command_read_data_valid_i && command_read_data_ready_o) begin
                feed_count--; feed_index++;
            end
            if(unpack_valid_o && unpack_ready_i) unpack_done_i=0;
            if(matrix_valid_i && matrix_ready_o) matrix_taken=1;
            if(matrix_read_req_valid_o && matrix_read_req_ready_i) begin
                request_count[1]++; data_delay=9;
                matrix_pending=1;
            end
            if(vertex_read_req_valid_o && vertex_read_req_ready_i) begin
                request_count[2]++; data_delay=9;
                if(vertex_read_req_bytes_o!=48) $fatal(1,"FAIL triangle bytes");
            end
            if(quad_read_req_valid_o && quad_read_req_ready_i) begin
                request_count[3]++; data_delay=9;
                if(quad_read_req_bytes_o!=16) $fatal(1,"FAIL quad bytes");
            end
            if(object_read_req_valid_o && object_read_req_ready_i) begin
                request_count[4]++; data_delay=9;
                if(object_read_req_bytes_o!=64) $fatal(1,"FAIL object bytes");
                write_delay=25;
            end
            if(texture_read_req_valid_o && texture_read_req_ready_i) begin
                request_count[5]++; data_delay=9;
            end
            if(palette_read_req_valid_o && palette_read_req_ready_i) begin
                request_count[6]++; data_delay=9;
            end
            if(geometry_cfg_valid_o && geometry_cfg_ready_i) begin
                if(geometry_cfg_matrix_o!==expected_matrix || geometry_cfg_light_o!==expected_light
                    || geometry_cfg_target_o!==expected_target || geometry_cfg_pixel_o!==expected_pixel
                    || geometry_cfg_wide_o) $fatal(1,"FAIL geometry snapshot");
            end
            if(raster_render_state_valid_o && raster_render_state_ready_i) begin
                if(raster_render_state_tex_o!==expected_tex || raster_render_state_pixel_o!==expected_pixel
                    || raster_render_state_target_o!==expected_target || raster_render_state_wide_o)
                    $fatal(1,"FAIL raster snapshot");
            end
            if(texture_render_state_valid_o && texture_render_state_ready_i) begin
                if(texture_render_state_tex_o!==expected_tex || texture_render_state_pixel_o!==expected_pixel
                    || texture_render_state_target_o!==expected_target || texture_render_state_wide_o)
                    $fatal(1,"FAIL texture snapshot");
            end
            if(pixel_render_state_valid_o && pixel_render_state_ready_i) begin
                if(pixel_render_state_tex_o!==expected_tex || pixel_render_state_pixel_o!==expected_pixel
                    || pixel_render_state_target_o!==expected_target || pixel_render_state_wide_o)
                    $fatal(1,"FAIL pixel snapshot");
            end
            if(resolve_valid_o && resolve_ready_i) begin resolve_count++;write_delay=35;end
            if(geometry_draw_valid_o && geometry_draw_ready_i) draw_count++;
            if(palette_prepare_valid_o && palette_prepare_ready_i && palette_prepare_group_o!=2)
                $fatal(1,"FAIL palette group");
            if(object_publish_o && !write_dma_idle_i) $fatal(1,"FAIL early object publish");
            if(done_o) begin
                if(!read_dma_idle_i || !write_dma_idle_i) $fatal(1,"FAIL early DONE");
                done_count++;
            end
            if(error_o) error_count++;
        end
    end
    task launch(input int n);
        @(negedge clk_i); desc_base_i='h1000;desc_count_i=16'(n);wide_i=0;
        enable_i=1;start_i=1;
        tick(); @(negedge clk_i);start_i=0;wide_i=1;desc_base_i=-1;desc_count_i=0;
    endtask
    task wait_idle;
        wait(!busy_o); repeat(3) tick();
    endtask
    task expect_error(input int code);
        int old_error;
        old_error=error_count; launch(1);wait_idle();
        if(error_count!=old_error+1 || err_code_o!=32'(code))
            $fatal(1,"FAIL error expected=%0d actual=%0d count=%0d",code,err_code_o,error_count);
    endtask
    initial begin
        reset(); model_run=1;fill_program();unpack_done_i=1;
        launch(12);wait_idle();
        if(done_count!=1 || error_count!=0 || resolve_count!=1 || draw_count!=1)
            $fatal(1,"FAIL all opcode sequence done=%0d error=%0d",done_count,error_count);
        for(int i=1;i<7;i++) if(request_count[i]!=1) $fatal(1,"FAIL decoded client %0d",i);
        program_data[0]=0;program_data[0][7:0]='hff;expect_error(1);
        program_data[0]=expected_tex;program_data[0][49:37]=13'(196608>>5);expect_error(3);
        program_data[0]=0;program_data[0][7:0]='h30;
        program_data[0][113:101]=13'(196576>>5);program_data[0][146:133]=2;expect_error(4);
        program_data[0][146:133]=1;launch(1);wait_idle();
        if(done_count!=2) $fatal(1,"FAIL exact TEX_LOAD boundary");
        program_data[0]=0;program_data[0][7:0]='h40;
        launch(1);wait(resolve_valid_o && resolve_ready_i);tick();
        @(negedge clk_i);abort_i=1;tick();@(negedge clk_i);abort_i=0;
        wait_idle();if(done_count!=2 || error_count!=3) $fatal(1,"FAIL ABORT event");
        launch(1);wait(resolve_valid_o && resolve_ready_i);tick();
        @(negedge clk_i);read_dma_error_i=1;tick();
        @(negedge clk_i);read_dma_error_i=0;wait_idle();
        if(error_count!=4 || err_code_o!=2) $fatal(1,"FAIL AXI error");
        for(int i=0;i<40;i++) begin program_data[i]=0;program_data[i][7:0]='h02;end
        launch(40);wait_idle();if(done_count!=3) $fatal(1,"FAIL multi-interval prefetch");
        launch(0);wait_idle();if(done_count!=4) $fatal(1,"FAIL empty list");
        for(int fmt=0;fmt<3;fmt++) begin
            for(int lw=3;lw<=8;lw++) begin
                for(int lh=3;lh<=8;lh++) begin
                    int offset,old_done;
                    offset=((196608-footprint(lw,lh,fmt))/32)*32;
                    program_data[0]=0;program_data[0][7:0]='h03;
                    program_data[0][67:64]=4'(lw);program_data[0][71:68]=4'(lh);
                    program_data[0][73:72]=2'(fmt);program_data[0][77:74]=9;
                    program_data[0][49:37]=13'(offset>>5);
                    old_done=done_count;launch(1);wait_idle();
                    if(done_count!=old_done+1) $fatal(1,"FAIL padded mip boundary");
                    program_data[0][49:37]=13'((offset+32)>>5);expect_error(3);
                end
            end
        end
        $display("PASS gpu_command all opcodes/snapshots/errors1-4/drain/DONE/ABORT");$finish;
    end
endmodule
