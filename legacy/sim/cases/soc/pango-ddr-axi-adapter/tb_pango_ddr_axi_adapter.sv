`timescale 1ns/1ps

module tb_pango_ddr_axi_adapter #(
    parameter MODEL_RANDOM_STALL = 1
);

    localparam ADDR_W = 32;
    localparam DATA_W = 256;
    localparam STRB_W = DATA_W / 8;
    localparam ID_W = 4;

    reg clk;
    reg rst_n;
    reg init_done;

    reg [ID_W-1:0] s_awid;
    reg [ADDR_W-1:0] s_awaddr;
    reg [7:0] s_awlen;
    reg [2:0] s_awsize;
    reg [1:0] s_awburst;
    reg s_awvalid;
    wire s_awready;
    reg [DATA_W-1:0] s_wdata;
    reg [STRB_W-1:0] s_wstrb;
    reg s_wlast;
    reg s_wvalid;
    wire s_wready;
    wire [ID_W-1:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    reg s_bready;

    reg [ID_W-1:0] s_arid;
    reg [ADDR_W-1:0] s_araddr;
    reg [7:0] s_arlen;
    reg [2:0] s_arsize;
    reg [1:0] s_arburst;
    reg s_arvalid;
    wire s_arready;
    wire [ID_W-1:0] s_rid;
    wire [DATA_W-1:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    reg s_rready;

    wire [27:0] ui_awaddr;
    wire [3:0] ui_awid;
    wire [3:0] ui_awlen;
    wire ui_awvalid;
    wire ui_awready;
    wire [DATA_W-1:0] ui_wdata;
    wire [STRB_W-1:0] ui_wstrb;
    wire ui_wready;
    wire [3:0] ui_wusero_id;
    wire ui_wusero_last;
    wire [27:0] ui_araddr;
    wire [3:0] ui_arid;
    wire [3:0] ui_arlen;
    wire ui_arvalid;
    wire ui_arready;
    wire [DATA_W-1:0] ui_rdata;
    wire [3:0] ui_rid;
    wire ui_rlast;
    wire ui_rvalid;
    wire ui_rerror;
    wire [31:0] model_write_count;
    wire [31:0] model_read_count;
    wire protocol_error;

    integer checks;
    integer failures;
    integer expected_aw_count;
    integer expected_ar_count;
    integer seen_aw_count;
    integer seen_ar_count;
    integer seen_b_count;
    reg [1:0] expected_bresp_r;
    reg [27:0] expected_aw_addr [0:31];
    reg [3:0] expected_aw_len [0:31];
    reg [27:0] expected_ar_addr [0:31];
    reg [3:0] expected_ar_len [0:31];

    reg ui_aw_stalled_r;
    reg [35:0] ui_aw_payload_r;
    reg ui_ar_stalled_r;
    reg [35:0] ui_ar_payload_r;
    reg axi_r_stalled_r;
    reg [ID_W+DATA_W+2:0] axi_r_payload_r;
    reg ui_write_monitor_armed_r;
    reg ui_write_monitor_started_r;
    integer ui_write_monitor_left_r;

    always #5 clk = ~clk;

    function automatic [DATA_W-1:0] beat_pattern;
        input [31:0] seed;
        input integer beat;
        integer lane;
        begin
            for (lane = 0; lane < 8; lane = lane + 1)
                beat_pattern[lane*32 +: 32] =
                    seed ^ beat[31:0] ^ (32'h0101_0101 * lane);
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

    task automatic add_expected_transaction;
        input write_not_read;
        input [ADDR_W-1:0] byte_addr;
        input integer beats;
        begin
            if (write_not_read) begin
                expected_aw_addr[expected_aw_count] = byte_addr >> 2;
                expected_aw_len[expected_aw_count] = beats - 1;
                expected_aw_count = expected_aw_count + 1;
            end else begin
                expected_ar_addr[expected_ar_count] = byte_addr >> 2;
                expected_ar_len[expected_ar_count] = beats - 1;
                expected_ar_count = expected_ar_count + 1;
            end
        end
    endtask

    task automatic axi_write;
        input [ID_W-1:0] id;
        input [ADDR_W-1:0] addr;
        input integer beats;
        input [31:0] seed;
        integer beat;
        integer guard;
        integer b_before;
        begin
            expected_bresp_r = 2'b00;
            add_expected_transaction(1'b1, addr, beats);
            b_before = seen_b_count;
            if (!MODEL_RANDOM_STALL) begin
                ui_write_monitor_armed_r = 1'b1;
                ui_write_monitor_started_r = 1'b0;
                ui_write_monitor_left_r = beats;
            end

            @(negedge clk);
            s_awid = id;
            s_awaddr = addr;
            s_awlen = beats - 1;
            s_awsize = 3'd5;
            s_awburst = 2'b01;
            s_awvalid = 1'b1;
            guard = 0;
            while (!s_awready && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 200, "AXI AW accepted");
            @(negedge clk);
            s_awvalid = 1'b0;

            for (beat = 0; beat < beats; beat = beat + 1) begin
                s_wdata = beat_pattern(seed, beat);
                s_wstrb = {STRB_W{1'b1}};
                s_wlast = (beat == beats-1);
                s_wvalid = 1'b1;
                guard = 0;
                while (!s_wready && guard < 500) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                check_true(guard < 500, "AXI W beat accepted");
                if (!MODEL_RANDOM_STALL && (beat != 0))
                    check_true(guard == 0,
                               "no adapter WREADY bubble inside an AXI burst");
                @(negedge clk);
            end
            s_wvalid = 1'b0;
            s_wlast = 1'b0;

            guard = 0;
            while ((seen_b_count == b_before) && guard < 2000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 2000, "AXI B response received");
            check_true(seen_b_count == b_before + 1,
                        "one AXI write produces exactly one B response");
        end
    endtask

    task automatic axi_write_error;
        input [ID_W-1:0] id;
        input [ADDR_W-1:0] addr;
        input integer beats;
        integer beat;
        integer guard;
        integer b_before;
        begin
            expected_bresp_r = 2'b11;
            b_before = seen_b_count;
            @(negedge clk);
            s_awid = id;
            s_awaddr = addr;
            s_awlen = beats - 1;
            s_awsize = 3'd5;
            s_awburst = 2'b01;
            s_awvalid = 1'b1;
            guard = 0;
            while (!s_awready && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 200, "overlength AXI AW accepted for DECERR");
            @(negedge clk);
            s_awvalid = 1'b0;

            for (beat = 0; beat < beats; beat = beat + 1) begin
                s_wdata = beat_pattern(32'he000_0000, beat);
                s_wstrb = {STRB_W{1'b1}};
                s_wlast = beat == beats-1;
                s_wvalid = 1'b1;
                guard = 0;
                while (!s_wready && guard < 500) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                check_true(guard < 500, "overlength AXI W beat drained");
                @(negedge clk);
            end
            s_wvalid = 1'b0;
            s_wlast = 1'b0;

            guard = 0;
            while ((seen_b_count == b_before) && guard < 2000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 2000, "overlength write receives DECERR B");
            check_true(seen_b_count == b_before + 1,
                       "overlength write produces exactly one B response");
        end
    endtask

    task automatic axi_read_check;
        input [ID_W-1:0] id;
        input [ADDR_W-1:0] addr;
        input integer beats;
        input [31:0] seed;
        input integer backpressure_cycles;
        integer beat;
        integer guard;
        begin
            add_expected_transaction(1'b0, addr, beats);

            @(negedge clk);
            s_arid = id;
            s_araddr = addr;
            s_arlen = beats - 1;
            s_arsize = 3'd5;
            s_arburst = 2'b01;
            s_arvalid = 1'b1;
            guard = 0;
            while (!s_arready && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 200, "AXI AR accepted");
            @(negedge clk);
            s_arvalid = 1'b0;
            s_rready = 1'b0;
            repeat (backpressure_cycles) @(negedge clk);
            s_rready = 1'b1;

            for (beat = 0; beat < beats; beat = beat + 1) begin
                guard = 0;
                while (!s_rvalid && guard < 2000) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                check_true(guard < 2000, "AXI R beat received");
                if ((backpressure_cycles >= 80) && (beat != 0))
                    check_true(guard == 0,
                               "prefetched AXI R data has no adapter bubble");
                check_true(s_rid == id, "AXI R ID is preserved");
                check_true(s_rresp == 2'b00, "AXI R response is OKAY");
                if (s_rdata != beat_pattern(seed, beat))
                    $display("RDATA_MISMATCH id=%0d beat=%0d got_lo=%08x expected_lo=%08x",
                             id, beat, s_rdata[31:0], seed ^ beat[31:0]);
                check_true(s_rdata == beat_pattern(seed, beat),
                           "AXI R data matches written data");
                check_true(s_rlast == (beat == beats-1),
                            "RLAST appears only on the final AXI beat");
                @(negedge clk);
            end
            s_rready = 1'b0;
        end
    endtask

    task automatic axi_read_error;
        input [ID_W-1:0] id;
        input [ADDR_W-1:0] addr;
        input integer beats;
        integer beat;
        integer guard;
        begin
            @(negedge clk);
            s_arid = id;
            s_araddr = addr;
            s_arlen = beats - 1;
            s_arsize = 3'd5;
            s_arburst = 2'b01;
            s_arvalid = 1'b1;
            guard = 0;
            while (!s_arready && guard < 200) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 200, "overlength AXI AR accepted for DECERR");
            @(negedge clk);
            s_arvalid = 1'b0;
            s_rready = 1'b1;
            for (beat = 0; beat < beats; beat = beat + 1) begin
                guard = 0;
                while (!s_rvalid && guard < 2000) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                check_true(guard < 2000, "overlength read receives DECERR beat");
                if (beat != 0)
                    check_true(guard == 0,
                               "DECERR R stream remains one beat per clock");
                check_true(s_rid == id, "DECERR read preserves AXI ID");
                check_true(s_rresp == 2'b11, "overlength read response is DECERR");
                check_true(s_rdata == {DATA_W{1'b0}},
                           "DECERR read data is constant zero");
                check_true(s_rlast == (beat == beats-1),
                           "DECERR RLAST appears on the requested final beat");
                @(negedge clk);
            end
            s_rready = 1'b0;
        end
    endtask

    task automatic axi_multi_stress;
        integer txn;
        integer beat;
        integer guard;
        integer b_before;
        integer total_beat;
        integer txn_beats;
        reg [31:0] txn_addr;
        reg [31:0] txn_seed;
        begin
            expected_bresp_r = 2'b00;
            b_before = seen_b_count;
            if (!MODEL_RANDOM_STALL) begin
                ui_write_monitor_armed_r = 1'b1;
                ui_write_monitor_started_r = 1'b0;
                ui_write_monitor_left_r = 25;
            end

            // Queue three AW transactions before presenting any W data.
            for (txn = 0; txn < 3; txn = txn + 1) begin
                txn_beats = (txn == 0) ? 16 : ((txn == 1) ? 8 : 1);
                txn_addr = 32'h0000_6000 + txn * 32'h0000_1000;
                add_expected_transaction(1'b1, txn_addr, txn_beats);
                @(negedge clk);
                s_awid = 4'd6 + txn;
                s_awaddr = txn_addr;
                s_awlen = txn_beats - 1;
                s_awsize = 3'd5;
                s_awburst = 2'b01;
                s_awvalid = 1'b1;
                guard = 0;
                while (!s_awready && guard < 500) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                check_true(guard < 500, "queued AXI AW accepted");
                @(negedge clk);
                s_awvalid = 1'b0;
            end

            // AXI4 W streams follow AW acceptance order.
            for (txn = 0; txn < 3; txn = txn + 1) begin
                txn_beats = (txn == 0) ? 16 : ((txn == 1) ? 8 : 1);
                txn_seed = 32'h6000_0000 + txn * 32'h1000_0000;
                for (beat = 0; beat < txn_beats; beat = beat + 1) begin
                    s_wdata = beat_pattern(txn_seed, beat);
                    s_wstrb = {STRB_W{1'b1}};
                    s_wlast = beat == txn_beats-1;
                    s_wvalid = 1'b1;
                    guard = 0;
                    while (!s_wready && guard < 1000) begin
                        @(negedge clk);
                        guard = guard + 1;
                    end
                    check_true(guard < 1000, "queued AXI W beat accepted");
                    @(negedge clk);
                end
            end
            s_wvalid = 1'b0;
            s_wlast = 1'b0;

            guard = 0;
            while ((seen_b_count != b_before + 3) && guard < 5000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 5000,
                       "three queued writes produce three ordered B responses");

            // Queue three reads. The UI model deliberately returns slot IDs
            // with different delays; AXI output must still follow AR order.
            for (txn = 0; txn < 3; txn = txn + 1) begin
                txn_beats = (txn == 0) ? 16 : ((txn == 1) ? 8 : 1);
                txn_addr = 32'h0000_6000 + txn * 32'h0000_1000;
                add_expected_transaction(1'b0, txn_addr, txn_beats);
                @(negedge clk);
                s_arid = 4'd6 + txn;
                s_araddr = txn_addr;
                s_arlen = txn_beats - 1;
                s_arsize = 3'd5;
                s_arburst = 2'b01;
                s_arvalid = 1'b1;
                guard = 0;
                while (!s_arready && guard < 500) begin
                    @(negedge clk);
                    guard = guard + 1;
                end
                check_true(guard < 500, "queued AXI AR accepted");
                @(negedge clk);
                s_arvalid = 1'b0;
            end

            s_rready = 1'b0;
            repeat (120) @(negedge clk);
            s_rready = 1'b1;
            total_beat = 0;
            for (txn = 0; txn < 3; txn = txn + 1) begin
                txn_beats = (txn == 0) ? 16 : ((txn == 1) ? 8 : 1);
                txn_seed = 32'h6000_0000 + txn * 32'h1000_0000;
                for (beat = 0; beat < txn_beats; beat = beat + 1) begin
                    guard = 0;
                    while (!s_rvalid && guard < 3000) begin
                        @(negedge clk);
                        guard = guard + 1;
                    end
                    check_true(guard < 3000, "queued AXI R beat received");
                    if (!MODEL_RANDOM_STALL && (total_beat != 0))
                        check_true(guard == 0,
                                   "prefetched requests have no R boundary bubble");
                    check_true(s_rid == 4'd6 + txn,
                               "queued AXI R responses preserve request order");
                    check_true(s_rresp == 2'b00,
                               "queued AXI R response is OKAY");
                    check_true(s_rdata == beat_pattern(txn_seed, beat),
                               "queued AXI R data matches written data");
                    check_true(s_rlast == (beat == txn_beats-1),
                               "queued AXI RLAST ends each transaction");
                    total_beat = total_beat + 1;
                    @(negedge clk);
                end
            end
            s_rready = 1'b0;
        end
    endtask

    edrv32_pango_ddr_axi_adapter u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .init_done_i(init_done),
        .s_awid_i(s_awid),
        .s_awaddr_i(s_awaddr),
        .s_awlen_i(s_awlen),
        .s_awsize_i(s_awsize),
        .s_awburst_i(s_awburst),
        .s_awvalid_i(s_awvalid),
        .s_awready_o(s_awready),
        .s_wdata_i(s_wdata),
        .s_wstrb_i(s_wstrb),
        .s_wlast_i(s_wlast),
        .s_wvalid_i(s_wvalid),
        .s_wready_o(s_wready),
        .s_bid_o(s_bid),
        .s_bresp_o(s_bresp),
        .s_bvalid_o(s_bvalid),
        .s_bready_i(s_bready),
        .s_arid_i(s_arid),
        .s_araddr_i(s_araddr),
        .s_arlen_i(s_arlen),
        .s_arsize_i(s_arsize),
        .s_arburst_i(s_arburst),
        .s_arvalid_i(s_arvalid),
        .s_arready_o(s_arready),
        .s_rid_o(s_rid),
        .s_rdata_o(s_rdata),
        .s_rresp_o(s_rresp),
        .s_rlast_o(s_rlast),
        .s_rvalid_o(s_rvalid),
        .s_rready_i(s_rready),
        .ui_awaddr_o(ui_awaddr),
        .ui_awid_o(ui_awid),
        .ui_awlen_o(ui_awlen),
        .ui_awvalid_o(ui_awvalid),
        .ui_awready_i(ui_awready),
        .ui_wdata_o(ui_wdata),
        .ui_wstrb_o(ui_wstrb),
        .ui_wready_i(ui_wready),
        .ui_wusero_id_i(ui_wusero_id),
        .ui_wusero_last_i(ui_wusero_last),
        .ui_araddr_o(ui_araddr),
        .ui_arid_o(ui_arid),
        .ui_arlen_o(ui_arlen),
        .ui_arvalid_o(ui_arvalid),
        .ui_arready_i(ui_arready),
        .ui_rdata_i(ui_rdata),
        .ui_rid_i(ui_rid),
        .ui_rlast_i(ui_rlast),
        .ui_rvalid_i(ui_rvalid),
        .protocol_error_o(protocol_error)
    );

    pango_ddr_ui_model #(
        .MEMORY_LINES(8192),
        .RANDOM_STALL(MODEL_RANDOM_STALL),
        .ALLOW_AW_DURING_W(1),
        .ALLOW_FIRST_W_WITH_AW(1),
        .REVERSE_READ_DELAY(1)
    ) u_ddr_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .init_done_i(init_done),
        .awvalid_i(ui_awvalid),
        .awready_o(ui_awready),
        .awaddr_i(ui_awaddr),
        .awlen_i(ui_awlen),
        .awid_i(ui_awid),
        .wdata_i(ui_wdata),
        .wstrb_i(ui_wstrb),
        .wready_o(ui_wready),
        .wusero_id_o(ui_wusero_id),
        .wusero_last_o(ui_wusero_last),
        .arvalid_i(ui_arvalid),
        .arready_o(ui_arready),
        .araddr_i(ui_araddr),
        .arlen_i(ui_arlen),
        .arid_i(ui_arid),
        .rvalid_o(ui_rvalid),
        .rdata_o(ui_rdata),
        .rid_o(ui_rid),
        .rlast_o(ui_rlast),
        .rerror_o(ui_rerror),
        .write_count_o(model_write_count),
        .read_count_o(model_read_count)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            seen_aw_count <= 0;
            seen_ar_count <= 0;
            seen_b_count <= 0;
            ui_aw_stalled_r <= 1'b0;
            ui_ar_stalled_r <= 1'b0;
            axi_r_stalled_r <= 1'b0;
            ui_write_monitor_armed_r <= 1'b0;
            ui_write_monitor_started_r <= 1'b0;
            ui_write_monitor_left_r <= 0;
        end else begin
            if (ui_awvalid && ui_awready) begin
                check_true(seen_aw_count < expected_aw_count,
                           "no unexpected UI AW child");
                check_true(ui_awaddr == expected_aw_addr[seen_aw_count],
                           "UI AW address uses 32-bit word units");
                check_true(ui_awlen == expected_aw_len[seen_aw_count],
                            "UI AW length matches the DDR AXI request");
                seen_aw_count <= seen_aw_count + 1;
            end
            if (ui_arvalid && ui_arready) begin
                check_true(seen_ar_count < expected_ar_count,
                           "no unexpected UI AR child");
                check_true(ui_araddr == expected_ar_addr[seen_ar_count],
                           "UI AR address uses 32-bit word units");
                check_true(ui_arlen == expected_ar_len[seen_ar_count],
                            "UI AR length matches the DDR AXI request");
                seen_ar_count <= seen_ar_count + 1;
            end
            if (s_bvalid && s_bready) begin
                check_true(s_bresp == expected_bresp_r,
                           "AXI B response matches request legality");
                seen_b_count <= seen_b_count + 1;
            end

            if (ui_aw_stalled_r)
                check_true({ui_awid, ui_awaddr, ui_awlen} == ui_aw_payload_r,
                           "UI AW payload stable while stalled");
            ui_aw_stalled_r <= ui_awvalid && !ui_awready;
            if (ui_awvalid && !ui_awready)
                ui_aw_payload_r <= {ui_awid, ui_awaddr, ui_awlen};

            if (ui_ar_stalled_r)
                check_true({ui_arid, ui_araddr, ui_arlen} == ui_ar_payload_r,
                           "UI AR payload stable while stalled");
            ui_ar_stalled_r <= ui_arvalid && !ui_arready;
            if (ui_arvalid && !ui_arready)
                ui_ar_payload_r <= {ui_arid, ui_araddr, ui_arlen};

            if (axi_r_stalled_r)
                check_true({s_rid, s_rdata, s_rresp, s_rlast} == axi_r_payload_r,
                           "AXI R payload stable while stalled");
            axi_r_stalled_r <= s_rvalid && !s_rready;
            if (s_rvalid && !s_rready)
                axi_r_payload_r <= {s_rid, s_rdata, s_rresp, s_rlast};

            if (!MODEL_RANDOM_STALL && ui_write_monitor_armed_r) begin
                if (ui_write_monitor_started_r)
                    check_true(ui_wready,
                               "no DDR UI write-data bubble inside a burst");
                else if (ui_wready)
                    ui_write_monitor_started_r <= 1'b1;

                if (ui_wready) begin
                    ui_write_monitor_left_r <= ui_write_monitor_left_r - 1;
                    if (ui_write_monitor_left_r == 1) begin
                        ui_write_monitor_armed_r <= 1'b0;
                        ui_write_monitor_started_r <= 1'b0;
                    end
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        init_done = 1'b0;
        s_awid = 0;
        s_awaddr = 0;
        s_awlen = 0;
        s_awsize = 3'd5;
        s_awburst = 2'b01;
        s_awvalid = 1'b0;
        s_wdata = 0;
        s_wstrb = 0;
        s_wlast = 1'b0;
        s_wvalid = 1'b0;
        s_bready = 1'b1;
        s_arid = 0;
        s_araddr = 0;
        s_arlen = 0;
        s_arsize = 3'd5;
        s_arburst = 2'b01;
        s_arvalid = 1'b0;
        s_rready = 1'b0;
        checks = 0;
        failures = 0;
        expected_aw_count = 0;
        expected_ar_count = 0;
        expected_bresp_r = 2'b00;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        #1;
        check_true(!s_awready && !s_arready,
                   "AXI requests remain blocked before DDR init_done");
        check_true(!ui_awvalid && !ui_arvalid,
                   "no UI request is issued before DDR init_done");
        init_done = 1'b1;

        axi_write(4'd1, 32'h0000_1000, 1, 32'h1000_0000);
        axi_read_check(4'd1, 32'h0000_1000, 1, 32'h1000_0000, 0);
        axi_write(4'd2, 32'h0000_2000, 8, 32'h2000_0000);
        axi_read_check(4'd2, 32'h0000_2000, 8, 32'h2000_0000, 3);
        axi_write(4'd3, 32'h0000_3000, 16, 32'h3000_0000);
        axi_read_check(4'd3, 32'h0000_3000, 16, 32'h3000_0000, 80);
        axi_multi_stress();
        axi_write_error(4'd4, 32'h0000_4000, 17);
        axi_read_error(4'd5, 32'h0000_5000, 17);
        repeat (10) @(posedge clk);
        $display("PANGO_DDR_AXI_ADAPTER_COUNTS aw=%0d/%0d ar=%0d/%0d b=%0d write=%0d read=%0d protocol_error=%0d",
                 seen_aw_count, expected_aw_count,
                 seen_ar_count, expected_ar_count, seen_b_count,
                 model_write_count, model_read_count, protocol_error);
        check_true(seen_aw_count == expected_aw_count,
                   "all expected UI AW children were issued");
        check_true(seen_ar_count == expected_ar_count,
                   "all expected UI AR children were issued");
        check_true(seen_aw_count == 6 && seen_ar_count == 6,
                    "every 1/8/16-beat request maps to one DDR UI command");
        check_true(seen_b_count == 7,
                   "six legal and one illegal writes each produce one B");
        check_true(model_write_count == 50,
                    "DDR UI received every write beat exactly once");
        check_true(model_read_count == 50,
                    "DDR UI returned every read beat exactly once");
        check_true(!ui_rerror, "DDR model did not inject a read error");
        check_true(protocol_error,
                   "overlength DDR AXI request sets the protocol diagnostic");

        if (failures == 0)
            $display("PANGO_DDR_AXI_ADAPTER_PASS checks=%0d commands=%0d beats=%0d random_stall=%0d",
                     checks, seen_aw_count, model_write_count,
                     MODEL_RANDOM_STALL);
        else
            $fatal(1, "PANGO_DDR_AXI_ADAPTER_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "Pango DDR AXI adapter timeout");
    end

endmodule
