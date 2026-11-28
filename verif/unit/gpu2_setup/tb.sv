// G-P03 self-check: only public operands/results and Python integer expectations.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg valid = 0;
    wire norm_valid;
    wire product_valid;
    wire relocate_valid;
    wire [47:0] norm_m_out;
    wire [9:0] norm_e_out;
    wire [81:0] product_out;
    wire [59:0] relocated_out;
    reg [81:0] mantissa_i;
    reg [81:0] rows_mantissa_i [0:9999];
    reg [9:0] exponent_i;
    reg [9:0] rows_exponent_i [0:9999];
    reg [47:0] rows_norm_m [0:9999];
    reg [9:0] rows_norm_e [0:9999];
    reg [48:0] a_i;
    reg [48:0] rows_a_i [0:9999];
    reg [32:0] b_i;
    reg [32:0] rows_b_i [0:9999];
    reg [81:0] rows_product [0:9999];
    reg [47:0] start_i;
    reg [47:0] rows_start_i [0:9999];
    reg [47:0] gx_i;
    reg [47:0] rows_gx_i [0:9999];
    reg [47:0] gy_i;
    reg [47:0] rows_gy_i [0:9999];
    reg [4:0] tile_x_i;
    reg [4:0] rows_tile_x_i [0:9999];
    reg [3:0] tile_y_i;
    reg [3:0] rows_tile_y_i [0:9999];
    reg [59:0] rows_relocated [0:9999];
    edrv32_gpu2_setup_probe dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(valid),
        .mantissa_i(mantissa_i),
        .exponent_i(exponent_i),
        .a_i(a_i),
        .b_i(b_i),
        .start_i(start_i),
        .gx_i(gx_i),
        .gy_i(gy_i),
        .tile_x_i(tile_x_i),
        .tile_y_i(tile_y_i),
        .norm_valid_o(norm_valid),
        .mantissa_o(norm_m_out),
        .exponent_o(norm_e_out),
        .product_valid_o(product_valid),
        .product_o(product_out),
        .relocate_valid_o(relocate_valid),
        .start_o(relocated_out)
    );
    integer fd;
    integer got;
    integer count = 0;
    integer issued = 0;
    integer norms = 0;
    integer products = 0;
    integer relocations = 0;
    integer cycle = 0;
    reg [5:0] history = 0;
    initial begin
        fd = $fopen("build/gpu2/setup/vectors.txt", "r");
        if (fd == 0) $fatal(1, "FAIL missing vectors");
        while (!$feof(fd)) begin
            got = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                rows_mantissa_i[count],
                rows_exponent_i[count],
                rows_norm_m[count],
                rows_norm_e[count],
                rows_a_i[count],
                rows_b_i[count],
                rows_product[count],
                rows_start_i[count],
                rows_gx_i[count],
                rows_gy_i[count],
                rows_tile_x_i[count],
                rows_tile_y_i[count],
                rows_relocated[count]);
            if (got != 13) $fatal(1, "FAIL vector parse %0d", count);
            count = count+1;
        end
        $fclose(fd);
        repeat (3) @(negedge clk);
        rst_n = 1;
        while (issued < count || products < count) begin
            valid = issued < count && cycle % 13 != 7;
            mantissa_i = rows_mantissa_i[issued < count ? issued : count-1];
            exponent_i = rows_exponent_i[issued < count ? issued : count-1];
            a_i = rows_a_i[issued < count ? issued : count-1];
            b_i = rows_b_i[issued < count ? issued : count-1];
            start_i = rows_start_i[issued < count ? issued : count-1];
            gx_i = rows_gx_i[issued < count ? issued : count-1];
            gy_i = rows_gy_i[issued < count ? issued : count-1];
            tile_x_i = rows_tile_x_i[issued < count ? issued : count-1];
            tile_y_i = rows_tile_y_i[issued < count ? issued : count-1];
            if (valid) issued = issued+1;
            @(posedge clk);
            history = {history[4:0], valid};
            #1;
            if (norm_valid !== history[1] || product_valid !== history[5] ||
                relocate_valid !== history[3]) $fatal(1, "FAIL valid latency cycle %0d", cycle);
            if (norm_valid) begin
                if (norm_m_out !== rows_norm_m[norms] || norm_e_out !== rows_norm_e[norms])
                    $fatal(1, "FAIL N48 row=%0d expected=%h/%h actual=%h/%h time=%0t",
                        norms, rows_norm_m[norms], rows_norm_e[norms], norm_m_out, norm_e_out, $time);
                norms = norms+1;
            end
            if (product_valid) begin
                if (product_out !== rows_product[products])
                    $fatal(1, "FAIL product row=%0d expected=%h actual=%h time=%0t",
                        products, rows_product[products], product_out, $time);
                products = products+1;
            end
            if (relocate_valid) begin
                if (relocated_out !== rows_relocated[relocations])
                    $fatal(1, "FAIL relocation row=%0d expected=%h actual=%h time=%0t",
                        relocations, rows_relocated[relocations], relocated_out, $time);
                relocations = relocations+1;
            end
            cycle = cycle+1;
            @(negedge clk);
        end
        if (norms != count || relocations != count) $fatal(1, "FAIL missing results");
        $display("PASS setup: %0d vectors, N48=2 product=6 relocation=4 clocks II1", count);
        $finish;
    end
endmodule
