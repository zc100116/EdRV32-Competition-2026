// Self-checking gpu_unpack unit test.
module tb_gpu_unpack;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic unpack_valid_i = 0;
    logic unpack_ready_o;
    logic [255:0] unpack_command_i = 0;
    logic matrix_read_data_valid_i = 0;
    logic matrix_read_data_ready_o;
    logic [255:0] matrix_read_data_data_i = 0;
    logic [31:0] matrix_read_data_keep_i = 0;
    logic matrix_read_data_last_i = 0;
    logic vertex_read_data_valid_i = 0;
    logic vertex_read_data_ready_o;
    logic [255:0] vertex_read_data_data_i = 0;
    logic [31:0] vertex_read_data_keep_i = 0;
    logic vertex_read_data_last_i = 0;
    logic quad_read_data_valid_i = 0;
    logic quad_read_data_ready_o;
    logic [255:0] quad_read_data_data_i = 0;
    logic [31:0] quad_read_data_keep_i = 0;
    logic quad_read_data_last_i = 0;
    logic texture_read_data_valid_i = 0;
    logic texture_read_data_ready_o;
    logic [255:0] texture_read_data_data_i = 0;
    logic [31:0] texture_read_data_keep_i = 0;
    logic texture_read_data_last_i = 0;
    logic palette_read_data_valid_i = 0;
    logic palette_read_data_ready_o;
    logic [255:0] palette_read_data_data_i = 0;
    logic [31:0] palette_read_data_keep_i = 0;
    logic palette_read_data_last_i = 0;
    logic matrix_valid_o;
    logic matrix_ready_i = 0;
    logic [511:0] matrix_data_o;
    logic vertex_valid_o;
    logic vertex_ready_i = 0;
    logic [127:0] vertex_data_o;
    logic quad_record_valid_o;
    logic quad_record_ready_i = 0;
    logic [127:0] quad_record_data_o;
    logic texture_load_valid_o;
    logic texture_load_ready_i = 0;
    logic [17:0] texture_load_addr_o;
    logic [255:0] texture_load_data_o;
    logic [31:0] texture_load_keep_o;
    logic palette_load_valid_o;
    logic palette_load_ready_i = 0;
    logic [11:0] palette_load_idx_o;
    logic [19:0] palette_load_data_o;
    logic stop_i = 0;
    logic unit_done_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_unpack u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .unpack_valid_i(unpack_valid_i),
        .unpack_ready_o(unpack_ready_o),
        .unpack_command_i(unpack_command_i),
        .matrix_read_data_valid_i(matrix_read_data_valid_i),
        .matrix_read_data_ready_o(matrix_read_data_ready_o),
        .matrix_read_data_data_i(matrix_read_data_data_i),
        .matrix_read_data_keep_i(matrix_read_data_keep_i),
        .matrix_read_data_last_i(matrix_read_data_last_i),
        .vertex_read_data_valid_i(vertex_read_data_valid_i),
        .vertex_read_data_ready_o(vertex_read_data_ready_o),
        .vertex_read_data_data_i(vertex_read_data_data_i),
        .vertex_read_data_keep_i(vertex_read_data_keep_i),
        .vertex_read_data_last_i(vertex_read_data_last_i),
        .quad_read_data_valid_i(quad_read_data_valid_i),
        .quad_read_data_ready_o(quad_read_data_ready_o),
        .quad_read_data_data_i(quad_read_data_data_i),
        .quad_read_data_keep_i(quad_read_data_keep_i),
        .quad_read_data_last_i(quad_read_data_last_i),
        .texture_read_data_valid_i(texture_read_data_valid_i),
        .texture_read_data_ready_o(texture_read_data_ready_o),
        .texture_read_data_data_i(texture_read_data_data_i),
        .texture_read_data_keep_i(texture_read_data_keep_i),
        .texture_read_data_last_i(texture_read_data_last_i),
        .palette_read_data_valid_i(palette_read_data_valid_i),
        .palette_read_data_ready_o(palette_read_data_ready_o),
        .palette_read_data_data_i(palette_read_data_data_i),
        .palette_read_data_keep_i(palette_read_data_keep_i),
        .palette_read_data_last_i(palette_read_data_last_i),
        .matrix_valid_o(matrix_valid_o),
        .matrix_ready_i(matrix_ready_i),
        .matrix_data_o(matrix_data_o),
        .vertex_valid_o(vertex_valid_o),
        .vertex_ready_i(vertex_ready_i),
        .vertex_data_o(vertex_data_o),
        .quad_record_valid_o(quad_record_valid_o),
        .quad_record_ready_i(quad_record_ready_i),
        .quad_record_data_o(quad_record_data_o),
        .texture_load_valid_o(texture_load_valid_o),
        .texture_load_ready_i(texture_load_ready_i),
        .texture_load_addr_o(texture_load_addr_o),
        .texture_load_data_o(texture_load_data_o),
        .texture_load_keep_o(texture_load_keep_o),
        .palette_load_valid_o(palette_load_valid_o),
        .palette_load_ready_i(palette_load_ready_i),
        .palette_load_idx_o(palette_load_idx_o),
        .palette_load_data_o(palette_load_data_o),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o)
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
    int seen[5];
    int mode=0;
    int cycle=0;
    logic [255:0] p0,p1;
    bit active=0;
    always @(negedge clk_i) if(active) begin
        cycle++;
        matrix_ready_i=cycle%7!=0;vertex_ready_i=cycle%5!=0;
        quad_record_ready_i=cycle%3!=0;texture_load_ready_i=cycle%4!=0;
        palette_load_ready_i=cycle%6!=0;
    end
    always @(posedge clk_i) if(rst_n_i && active) begin
        if(matrix_valid_o && matrix_ready_i) begin
            if(matrix_data_o!=={p1,p0}) $fatal(1,"FAIL matrix order");seen[0]++;
        end
        if(vertex_valid_o && vertex_ready_i) begin
            if(vertex_data_o !== (seen[1]<2 ? p0[seen[1]*128+:128] : p1[127:0]))
                $fatal(1,"FAIL vertex split");seen[1]++;
        end
        if(quad_record_valid_o && quad_record_ready_i) begin
            if(quad_record_data_o !== (seen[2]<2 ? p0[seen[2]*128+:128] : p1[127:0]))
                $fatal(1,"FAIL quad split");seen[2]++;
        end
        if(texture_load_valid_o && texture_load_ready_i) begin
            if(texture_load_addr_o!==18'(196544+seen[3]*32)
                || texture_load_data_o!==(seen[3]==0?p0:p1)
                || texture_load_keep_o!==32'hffffffff) $fatal(1,"FAIL texture load");seen[3]++;
        end
        if(palette_load_valid_o && palette_load_ready_i) begin
            if(palette_load_idx_o!==12'(15*256+seen[4])
                || palette_load_data_o !== 20'(1000+seen[4])) $fatal(1,"FAIL palette split");
            seen[4]++;
        end
    end
    task start(input int opcode);
        @(negedge clk_i);unpack_command_i=0;unpack_command_i[7:0]=8'(opcode);
        unpack_command_i[35:32]=15;unpack_command_i[113:101]=13'(196544>>5);
        unpack_valid_i=1;
        do tick();while(!unpack_ready_o && unit_done_o);
        @(negedge clk_i);unpack_valid_i=0;
    endtask
    task feed_matrix(input logic [255:0] data,input logic [31:0] keep,input bit last);
        @(negedge clk_i);matrix_read_data_valid_i=1;matrix_read_data_data_i=data;
        matrix_read_data_keep_i=keep;matrix_read_data_last_i=last;
        do begin @(posedge clk_i); end while(!matrix_read_data_ready_o);
        @(negedge clk_i);matrix_read_data_valid_i=0;
    endtask
    task feed_vertex(input logic [255:0] data,input logic [31:0] keep,input bit last);
        @(negedge clk_i);vertex_read_data_valid_i=1;vertex_read_data_data_i=data;
        vertex_read_data_keep_i=keep;vertex_read_data_last_i=last;
        do begin @(posedge clk_i); end while(!vertex_read_data_ready_o);
        @(negedge clk_i);vertex_read_data_valid_i=0;
    endtask
    task feed_quad(input logic [255:0] data,input logic [31:0] keep,input bit last);
        @(negedge clk_i);quad_read_data_valid_i=1;quad_read_data_data_i=data;
        quad_read_data_keep_i=keep;quad_read_data_last_i=last;
        do begin @(posedge clk_i); end while(!quad_read_data_ready_o);
        @(negedge clk_i);quad_read_data_valid_i=0;
    endtask
    task feed_texture(input logic [255:0] data,input logic [31:0] keep,input bit last);
        @(negedge clk_i);texture_read_data_valid_i=1;texture_read_data_data_i=data;
        texture_read_data_keep_i=keep;texture_read_data_last_i=last;
        do begin @(posedge clk_i); end while(!texture_read_data_ready_o);
        @(negedge clk_i);texture_read_data_valid_i=0;
    endtask
    task feed_palette(input logic [255:0] data,input logic [31:0] keep,input bit last);
        @(negedge clk_i);palette_read_data_valid_i=1;palette_read_data_data_i=data;
        palette_read_data_keep_i=keep;palette_read_data_last_i=last;
        do begin @(posedge clk_i); end while(!palette_read_data_ready_o);
        @(negedge clk_i);palette_read_data_valid_i=0;
    endtask
    initial begin
        reset();active=1;
        p0=256'h123456789abcdef0_223456789abcdef0_323456789abcdef0_423456789abcdef0;
        p1=~p0;
        start('h01);feed_matrix(p0,-1,0);feed_matrix(p1,-1,1);wait(unit_done_o);tick();
        start('h20);feed_vertex(p0,-1,0);feed_vertex(p1,'hffff,1);wait(unit_done_o);tick();
        start('h21);feed_quad(p0,-1,0);feed_quad(p1,'hffff,1);wait(unit_done_o);tick();
        start('h30);feed_texture(p0,-1,0);feed_texture(p1,-1,1);wait(unit_done_o);tick();
        for(int k=0;k<8;k++) begin p0[k*32+:32]=32'(1000+k);p1[k*32+:32]=32'(1008+k);end
        start('h31);feed_palette(p0,-1,0);feed_palette(p1,'hfffff,1);wait(unit_done_o);tick();
        if(seen[0]!=1 || seen[1]!=3 || seen[2]!=3 || seen[3]!=2 || seen[4]!=13)
            $fatal(1,"FAIL unpack counts");
        start('h20);@(negedge clk_i);stop_i=1;tick();
        if(!unit_done_o || vertex_valid_o || !vertex_read_data_ready_o) $fatal(1,"FAIL unpack stop");
        $display("PASS gpu_unpack matrix/vertex/quad/texture/palette/tails/backpressure/stop");$finish;
    end
endmodule
