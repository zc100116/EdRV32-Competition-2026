// File: tb.sv
// Spec: geo-spec 2, 4, 5.
// Description: Independent formula-based unit checks.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = !clk;
    reg coord_clk_i;
    reg coord_rst_n_i;
    reg coord_start_i;
    reg coord_clear_i;
    reg [5:0] coord_width_i;
    reg [4:0] coord_height_i;
    reg [31:0] coord_x_i;
    reg [31:0] coord_y_i;
    reg [31:0] coord_a_i;
    reg [31:0] coord_b_i;
    reg [31:0] coord_c_i;
    reg [31:0] coord_d_i;
    wire coord_valid_o;
    reg coord_ready_i;
    wire [31:0] coord_x_o;
    wire [31:0] coord_y_o;
    wire coord_eol_o;
    wire coord_last_o;
    edrv32_geo_coords u_coord_ (
        .clk_i(coord_clk_i),
        .rst_n_i(coord_rst_n_i),
        .start_i(coord_start_i),
        .clear_i(coord_clear_i),
        .width_i(coord_width_i),
        .height_i(coord_height_i),
        .x_i(coord_x_i),
        .y_i(coord_y_i),
        .a_i(coord_a_i),
        .b_i(coord_b_i),
        .c_i(coord_c_i),
        .d_i(coord_d_i),
        .valid_o(coord_valid_o),
        .ready_i(coord_ready_i),
        .x_o(coord_x_o),
        .y_o(coord_y_o),
        .eol_o(coord_eol_o),
        .last_o(coord_last_o)
    );
    reg tile_clk_i;
    reg tile_rst_n_i;
    reg tile_start_i;
    reg tile_clear_i;
    reg [11:0] tile_width_i;
    reg [11:0] tile_height_i;
    reg [31:0] tile_a_i;
    reg [31:0] tile_b_i;
    reg [31:0] tile_tx_i;
    reg [31:0] tile_c_i;
    reg [31:0] tile_d_i;
    reg [31:0] tile_ty_i;
    wire tile_valid_o;
    reg tile_ready_i;
    wire [11:0] tile_u_o;
    wire [11:0] tile_v_o;
    wire [5:0] tile_width_o;
    wire [4:0] tile_height_o;
    wire [31:0] tile_x_o;
    wire [31:0] tile_y_o;
    wire tile_last_o;
    edrv32_geo_tiles u_tile_ (
        .clk_i(tile_clk_i),
        .rst_n_i(tile_rst_n_i),
        .start_i(tile_start_i),
        .clear_i(tile_clear_i),
        .width_i(tile_width_i),
        .height_i(tile_height_i),
        .a_i(tile_a_i),
        .b_i(tile_b_i),
        .tx_i(tile_tx_i),
        .c_i(tile_c_i),
        .d_i(tile_d_i),
        .ty_i(tile_ty_i),
        .valid_o(tile_valid_o),
        .ready_i(tile_ready_i),
        .u_o(tile_u_o),
        .v_o(tile_v_o),
        .width_o(tile_width_o),
        .height_o(tile_height_o),
        .x_o(tile_x_o),
        .y_o(tile_y_o),
        .last_o(tile_last_o)
    );
    integer u;
    integer v;
    integer count;
    integer width;
    integer height;
    integer trial;
    integer cycles;
    integer coverage [0:139263];
    integer actual_width;
    integer actual_height;
    integer expected_x;
    integer expected_y;
    task pulse_reset;
        begin
            coord_rst_n_i=0; tile_rst_n_i=0;
            repeat (2) @(negedge clk);
            coord_rst_n_i=1; tile_rst_n_i=1;
        end
    endtask
    initial begin

        coord_rst_n_i = 0;
        coord_start_i = 0;
        coord_clear_i = 0;
        coord_width_i = 0;
        coord_height_i = 0;
        coord_x_i = 0;
        coord_y_i = 0;
        coord_a_i = 0;
        coord_b_i = 0;
        coord_c_i = 0;
        coord_d_i = 0;
        coord_ready_i = 0;

        tile_rst_n_i = 0;
        tile_start_i = 0;
        tile_clear_i = 0;
        tile_width_i = 0;
        tile_height_i = 0;
        tile_a_i = 0;
        tile_b_i = 0;
        tile_tx_i = 0;
        tile_c_i = 0;
        tile_d_i = 0;
        tile_ty_i = 0;
        tile_ready_i = 0;

        pulse_reset();
        for(trial=0;trial<30;trial=trial+1) begin
            @(negedge clk);
            coord_width_i=6'($urandom_range(1,32));
            coord_height_i=5'($urandom_range(1,16));
            coord_x_i=32'((int'($urandom_range(0,1000))-500)*65536);
            coord_y_i=32'((int'($urandom_range(0,1000))-500)*65536);
            coord_a_i=32'(int'($urandom_range(0,131072))-65536);
            coord_b_i=32'(int'($urandom_range(0,131072))-65536);
            coord_c_i=32'(int'($urandom_range(0,131072))-65536);
            coord_d_i=32'(int'($urandom_range(0,131072))-65536);
            coord_start_i=1; coord_ready_i=0;
            @(negedge clk);coord_start_i=0;
            u=0;v=0;count=0;cycles=0;
            while(coord_valid_o) begin
                expected_x=$signed(coord_a_i)*u+$signed(coord_b_i)*v+$signed(coord_x_i);
                expected_y=$signed(coord_c_i)*u+$signed(coord_d_i)*v+$signed(coord_y_i);
                if(coord_x_o!==32'(expected_x) || coord_y_o!==32'(expected_y) ||
                    coord_eol_o!==(u==int'(coord_width_i)-1) ||
                    coord_last_o!==((u==int'(coord_width_i)-1)&&
                        (v==int'(coord_height_i)-1)))
                    $fatal(1,"FAIL coordinates trial=%d u=%d v=%d exp=%h,%h got=%h,%h",
                        trial,u,v,expected_x,expected_y,coord_x_o,coord_y_o);
                coord_ready_i=($urandom_range(0,3)!=0);
                if(coord_ready_i) begin
                    count=count+1;
                    if(u==int'(coord_width_i)-1) begin u=0;v=v+1;end
                    else u=u+1;
                end
                cycles=cycles+1;
                if(cycles>2000) $fatal(1,"FAIL coordinate timeout");
                @(negedge clk);
            end
            if(count!=int'(coord_width_i)*int'(coord_height_i))
                $fatal(1,"FAIL coordinate count");
        end
        for(trial=0;trial<10;trial=trial+1) begin
            width=(trial==0)?0:2+trial*8;
            height=(trial==1)?0:trial*5+1;
            if(trial==8) begin width=4094;height=17;end
            if(trial==9) begin width=34;height=4095;end
            for(u=0;u<139264;u=u+1) coverage[u]=0;
            @(negedge clk);
            tile_width_i=12'(width);tile_height_i=12'(height);
            tile_a_i=32'h00018000;tile_b_i=32'hffff6000;tile_tx_i=32'h00012abc;
            tile_c_i=32'h00004000;tile_d_i=32'h00020000;tile_ty_i=32'hfffa1000;
            tile_start_i=1;tile_ready_i=0;
            @(negedge clk);tile_start_i=0;count=0;
            while(tile_valid_o) begin
                actual_width=(width-int'(tile_u_o)<32)?width-int'(tile_u_o):32;
                actual_height=(height-int'(tile_v_o)<16)?height-int'(tile_v_o):16;
                expected_x=$signed(tile_tx_i)+$signed(tile_a_i)*int'(tile_u_o)+
                    $signed(tile_b_i)*int'(tile_v_o);
                expected_y=$signed(tile_ty_i)+$signed(tile_c_i)*int'(tile_u_o)+
                    $signed(tile_d_i)*int'(tile_v_o);
                if(tile_width_o!=6'(actual_width)||tile_height_o!=5'(actual_height)||
                    tile_x_o!==32'(expected_x)||tile_y_o!==32'(expected_y))
                    $fatal(1,"FAIL tile extent or origin");
                tile_ready_i=($urandom_range(0,3)!=0);
                if(tile_ready_i) begin
                    for(v=0;v<actual_height;v=v+1)
                        for(u=0;u<actual_width;u=u+1) begin
                            if(int'(tile_u_o)+u>=width || int'(tile_v_o)+v>=height)
                                $fatal(1,"FAIL block writes outside rectangle");
                            coverage[(int'(tile_v_o)+v)*width+int'(tile_u_o)+u]++;
                            count++;
                        end
                end
                @(negedge clk);
            end
            if(count!=width*height) $fatal(1,"FAIL rectangle coverage count");
            for(u=0;u<width*height;u=u+1)
                if(coverage[u]!=1) $fatal(1,"FAIL duplicate or missing rectangle pixel");
        end
        $display("PASS geo_coords exact recurrence, stalls, tile coverage and empty rectangles");
        $finish;
    end
    always @(*) begin
        coord_clk_i=clk;
        tile_clk_i=clk;
    end
endmodule
