// G-P04 public-port trace compares both RAM mappings against the same reference.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [0:0] rf_wr_en_i;
    reg [8:0] rf_wr_addr_i;
    reg [127:0] rf_wr_data_i;
    reg [2:0] rf_rd_en_i;
    reg [26:0] rf_rd_addr_i;
    reg [0:0] const_wr_en_i;
    reg [6:0] const_wr_addr_i;
    reg [127:0] const_wr_data_i;
    reg [1:0] const_rd_en_i;
    reg [13:0] const_rd_addr_i;
    reg [0:0] program_wr_en_i;
    reg [9:0] program_wr_addr_i;
    reg [159:0] program_wr_data_i;
    reg [0:0] program_rd_en_i;
    reg [9:0] program_rd_addr_i;
    reg [71:0] setup_wr_en_i;
    reg [287:0] setup_wr_addr_i;
    reg [6623:0] setup_wr_data_i;
    reg [71:0] setup_rd_en_i;
    reg [287:0] setup_rd_addr_i;
    wire [383:0] drm_rf_rd_data_o;
    wire [383:0] lut_rf_rd_data_o;
    reg [383:0] expected_rf_rd_data_o;
    wire [255:0] drm_const_rd_data_o;
    wire [255:0] lut_const_rd_data_o;
    reg [255:0] expected_const_rd_data_o;
    wire [159:0] drm_program_rd_data_o;
    wire [159:0] lut_program_rd_data_o;
    reg [159:0] expected_program_rd_data_o;
    wire [6623:0] drm_setup_rd_data_o;
    wire [6623:0] lut_setup_rd_data_o;
    reg [6623:0] expected_setup_rd_data_o;
    reg [77:0] known;
    edrv32_gpu2_banks_drm u_drm (
        .clk_i(clk),
        .rf_wr_en_i(rf_wr_en_i),
        .rf_wr_addr_i(rf_wr_addr_i),
        .rf_wr_data_i(rf_wr_data_i),
        .rf_rd_en_i(rf_rd_en_i),
        .rf_rd_addr_i(rf_rd_addr_i),
        .const_wr_en_i(const_wr_en_i),
        .const_wr_addr_i(const_wr_addr_i),
        .const_wr_data_i(const_wr_data_i),
        .const_rd_en_i(const_rd_en_i),
        .const_rd_addr_i(const_rd_addr_i),
        .program_wr_en_i(program_wr_en_i),
        .program_wr_addr_i(program_wr_addr_i),
        .program_wr_data_i(program_wr_data_i),
        .program_rd_en_i(program_rd_en_i),
        .program_rd_addr_i(program_rd_addr_i),
        .setup_wr_en_i(setup_wr_en_i),
        .setup_wr_addr_i(setup_wr_addr_i),
        .setup_wr_data_i(setup_wr_data_i),
        .setup_rd_en_i(setup_rd_en_i),
        .setup_rd_addr_i(setup_rd_addr_i),
        .rf_rd_data_o(drm_rf_rd_data_o),
        .const_rd_data_o(drm_const_rd_data_o),
        .program_rd_data_o(drm_program_rd_data_o),
        .setup_rd_data_o(drm_setup_rd_data_o)
    );
    edrv32_gpu2_banks_lutram u_lutram (
        .clk_i(clk),
        .rf_wr_en_i(rf_wr_en_i),
        .rf_wr_addr_i(rf_wr_addr_i),
        .rf_wr_data_i(rf_wr_data_i),
        .rf_rd_en_i(rf_rd_en_i),
        .rf_rd_addr_i(rf_rd_addr_i),
        .const_wr_en_i(const_wr_en_i),
        .const_wr_addr_i(const_wr_addr_i),
        .const_wr_data_i(const_wr_data_i),
        .const_rd_en_i(const_rd_en_i),
        .const_rd_addr_i(const_rd_addr_i),
        .program_wr_en_i(program_wr_en_i),
        .program_wr_addr_i(program_wr_addr_i),
        .program_wr_data_i(program_wr_data_i),
        .program_rd_en_i(program_rd_en_i),
        .program_rd_addr_i(program_rd_addr_i),
        .setup_wr_en_i(setup_wr_en_i),
        .setup_wr_addr_i(setup_wr_addr_i),
        .setup_wr_data_i(setup_wr_data_i),
        .setup_rd_en_i(setup_rd_en_i),
        .setup_rd_addr_i(setup_rd_addr_i),
        .rf_rd_data_o(lut_rf_rd_data_o),
        .const_rd_data_o(lut_const_rd_data_o),
        .program_rd_data_o(lut_program_rd_data_o),
        .setup_rd_data_o(lut_setup_rd_data_o)
    );
    integer fd;
    integer got;
    integer cycle = 0;
    integer checks = 0;
    integer bank;
    initial begin
        fd = $fopen("build/gpu2/banks/trace.txt", "r");
        if (fd == 0) $fatal(1, "FAIL missing trace");
        while (!$feof(fd)) begin
            @(negedge clk);
            got = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                rf_wr_en_i,
                rf_wr_addr_i,
                rf_wr_data_i,
                rf_rd_en_i,
                rf_rd_addr_i,
                const_wr_en_i,
                const_wr_addr_i,
                const_wr_data_i,
                const_rd_en_i,
                const_rd_addr_i,
                program_wr_en_i,
                program_wr_addr_i,
                program_wr_data_i,
                program_rd_en_i,
                program_rd_addr_i,
                setup_wr_en_i,
                setup_wr_addr_i,
                setup_wr_data_i,
                setup_rd_en_i,
                setup_rd_addr_i,
                known,
                expected_rf_rd_data_o,
                expected_const_rd_data_o,
                expected_program_rd_data_o,
                expected_setup_rd_data_o);
            if (got != 25) $fatal(1, "FAIL trace parse cycle %0d", cycle);
            @(posedge clk);
            #1;
            for (bank = 0; bank < 3; bank = bank+1) begin
                if (known[bank+0]) begin
                    if (drm_rf_rd_data_o[bank*128 +: 128] !==
                        expected_rf_rd_data_o[bank*128 +: 128] ||
                        lut_rf_rd_data_o[bank*128 +: 128] !==
                        expected_rf_rd_data_o[bank*128 +: 128])
                        $fatal(1, "FAIL rf_rd_data_o cycle=%0d bank=%0d exp=%h drm=%h lut=%h t=%0t",
                            cycle, bank, expected_rf_rd_data_o[bank*128 +: 128],
                            drm_rf_rd_data_o[bank*128 +: 128],
                            lut_rf_rd_data_o[bank*128 +: 128], $time);
                    checks = checks+1;
                end
            end
            for (bank = 0; bank < 2; bank = bank+1) begin
                if (known[bank+3]) begin
                    if (drm_const_rd_data_o[bank*128 +: 128] !==
                        expected_const_rd_data_o[bank*128 +: 128] ||
                        lut_const_rd_data_o[bank*128 +: 128] !==
                        expected_const_rd_data_o[bank*128 +: 128])
                        $fatal(1, "FAIL const_rd_data_o cycle=%0d bank=%0d exp=%h drm=%h lut=%h t=%0t",
                            cycle, bank, expected_const_rd_data_o[bank*128 +: 128],
                            drm_const_rd_data_o[bank*128 +: 128],
                            lut_const_rd_data_o[bank*128 +: 128], $time);
                    checks = checks+1;
                end
            end
            for (bank = 0; bank < 1; bank = bank+1) begin
                if (known[bank+5]) begin
                    if (drm_program_rd_data_o[bank*160 +: 160] !==
                        expected_program_rd_data_o[bank*160 +: 160] ||
                        lut_program_rd_data_o[bank*160 +: 160] !==
                        expected_program_rd_data_o[bank*160 +: 160])
                        $fatal(1, "FAIL program_rd_data_o cycle=%0d bank=%0d exp=%h drm=%h lut=%h t=%0t",
                            cycle, bank, expected_program_rd_data_o[bank*160 +: 160],
                            drm_program_rd_data_o[bank*160 +: 160],
                            lut_program_rd_data_o[bank*160 +: 160], $time);
                    checks = checks+1;
                end
            end
            for (bank = 0; bank < 72; bank = bank+1) begin
                if (known[bank+6]) begin
                    if (drm_setup_rd_data_o[bank*92 +: 92] !==
                        expected_setup_rd_data_o[bank*92 +: 92] ||
                        lut_setup_rd_data_o[bank*92 +: 92] !==
                        expected_setup_rd_data_o[bank*92 +: 92])
                        $fatal(1, "FAIL setup_rd_data_o cycle=%0d bank=%0d exp=%h drm=%h lut=%h t=%0t",
                            cycle, bank, expected_setup_rd_data_o[bank*92 +: 92],
                            drm_setup_rd_data_o[bank*92 +: 92],
                            lut_setup_rd_data_o[bank*92 +: 92], $time);
                    checks = checks+1;
                end
            end
            cycle = cycle+1;
        end
        $fclose(fd);
        if (cycle != 3072 || checks < 200000) $fatal(1, "FAIL trace coverage %0d", checks);
        $display("PASS banks: %0d clocks, %0d comparisons per mapping, latency=2 II1", cycle,
            checks);
        $finish;
    end
endmodule
