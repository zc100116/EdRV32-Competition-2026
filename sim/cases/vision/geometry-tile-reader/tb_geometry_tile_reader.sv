`timescale 1ns/1ps

module tb_geometry_tile_reader;
    reg clk;
    reg rst_n;
    reg req_valid;
    wire req_ready;
    reg [11:0] req_tile_x;
    reg [11:0] req_tile_y;
    wire row_valid;
    reg row_ready;
    wire [3:0] row_index;
    wire [255:0] row_data;
    wire done;
    wire error;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [3:0] arqos;
    wire arvalid;
    reg arready;
    reg [3:0] rid;
    reg [255:0] rdata;
    reg [1:0] rresp;
    reg rlast;
    reg rvalid;
    wire rready;

    reg [15:0] pending_r;
    reg [31:0] address_r [0:15];
    reg [15:0] seen_rows_r;
    integer checks;
    integer failures;
    integer cycle_count;
    integer selected_i;
    integer row_count;
    integer guard;

    always #5 clk = ~clk;

    function automatic [255:0] row_pattern;
        input [3:0] id_i;
        input [31:0] addr_i;
        integer lane_i;
        begin
            for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1)
                row_pattern[lane_i*32 +: 32] =
                    addr_i ^ {28'b0, id_i} ^ lane_i;
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("CHECK_FAIL time=%0t %0s", $time, message);
            end
        end
    endtask

    edrv32_geometry_axi_tile_reader u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready),
        .req_surface_base_i(32'h0000_2000), .req_stride_i(32'd64),
        .req_src_width_i(16'd30), .req_src_height_i(16'd23),
        .req_tile_x_i(req_tile_x), .req_tile_y_i(req_tile_y),
        .row_valid_o(row_valid), .row_ready_i(row_ready),
        .row_index_o(row_index), .row_data_o(row_data),
        .done_o(done), .error_o(error),
        .m_arid_o(arid), .m_araddr_o(araddr), .m_arlen_o(arlen),
        .m_arsize_o(arsize), .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata), .m_rresp_i(rresp),
        .m_rlast_i(rlast), .m_rvalid_i(rvalid), .m_rready_o(rready)
    );

    always @(negedge clk) begin
        if (!rst_n) begin
            arready = 1'b0;
            row_ready = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;
            arready = (cycle_count % 5) != 1;
            row_ready = ((cycle_count % 7) != 2) &&
                        ((cycle_count % 7) != 3);
        end
    end

    always @(*) begin
        selected_i = -1;
        for (integer select_i = 15; select_i >= 0; select_i = select_i - 1)
            if ((selected_i < 0) && pending_r[select_i])
                selected_i = select_i;
        rvalid = selected_i >= 0;
        rid = selected_i >= 0 ? selected_i[3:0] : 4'b0;
        rdata = selected_i >= 0 ?
            row_pattern(selected_i[3:0], address_r[selected_i]) : 256'b0;
        rresp = 2'b00;
        rlast = 1'b1;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pending_r <= 16'b0;
        end else begin
            if (arvalid && arready) begin
                pending_r[arid] <= 1'b1;
                address_r[arid] <= araddr;
                check_true(arlen == 0 && arsize == 3'd5 && arburst == 2'b01,
                           "tile row uses one aligned full-width AXI beat");
                check_true(araddr == 32'h0000_2420 + ({28'b0, arid} << 6),
                           "tile row address includes base, tile and stride");
            end
            if (rvalid && rready)
                pending_r[rid] <= 1'b0;

            if (row_valid && row_ready) begin
                check_true(!seen_rows_r[row_index],
                           "each tile row is emitted once");
                seen_rows_r[row_index] <= 1'b1;
                row_count <= row_count + 1;
                if (row_index < 7)
                    check_true(row_data == row_pattern(
                        row_index, address_r[row_index]),
                        "returned AXI row keeps RID/data association");
                else
                    check_true(row_data == 0,
                               "partial bottom tile is zero completed");
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_tile_x = 12'b0;
        req_tile_y = 12'b0;
        arready = 1'b0;
        row_ready = 1'b0;
        pending_r = 16'b0;
        seen_rows_r = 16'b0;
        row_count = 0;
        cycle_count = 0;
        checks = 0;
        failures = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        req_tile_x = 12'd1;
        req_tile_y = 12'd1;
        req_valid = 1'b1;
        while (!req_ready)
            @(negedge clk);
        @(negedge clk);
        req_valid = 1'b0;

        guard = 0;
        while (!done && guard < 2000) begin
            @(negedge clk);
            guard = guard + 1;
        end
        check_true(guard < 2000 && !error,
                   "partial out-of-order tile request completes");
        check_true(row_count == 16 && seen_rows_r == 16'hffff,
                   "all sixteen tile rows are emitted");

        @(negedge clk);
        req_tile_x = 12'd0;
        req_tile_y = 12'd2;
        req_valid = 1'b1;
        @(negedge clk);
        req_valid = 1'b0;
        #1;
        check_true(done && error && req_ready,
                   "out-of-range tile request returns error completion");

        if (failures == 0)
            $display("GEOMETRY_TILE_READER_PASS checks=%0d", checks);
        else
            $fatal(1, "GEOMETRY_TILE_READER_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Geometry tile reader timeout");
    end

endmodule
