// File: tb_npu_operator.sv
// Spec: npu-spec 2, 5; npu-testplan OP and SQ.
// Description: Isolated operator plus DMA, independent sparse memory and reference images.
// Clock: clk_npu (single domain; boundary CDC is tested by NB).
`timescale 1ns/1ps
module tb_npu_operator;
    parameter bit NONCONV = 0;
    bit clk = 0;
    bit rst_n = 0;
    bit start = 0;
    bit stop = 0;
    bit cancel = 0;
    logic [31:0] meta [0:20];
    wire [511:0] desc;
    wire [31:0] in_addr = meta[16];
    wire [31:0] out_addr = meta[17];
    wire [31:0] unused_residual_addr = meta[18];
    wire [31:0] unused_weight_addr = meta[19];
    wire [31:0] unused_quant_addr = meta[20];
    edrv32_axi256_if bus();
    wire [31:0] unused_checker_errors;
    npu_axi256_mem u_memory (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus),
        .errors_o(unused_checker_errors)
    );
    always #4 clk = !clk;
    always @(posedge clk) begin
        if (rst_n && (read_error || write_error)) $fatal(1, "FAIL unexpected AXI error");
    end
    for (genvar g = 0; g < 16; g++) begin : g_descriptor
        assign desc[32*g+:32] = meta[g];
    end
    wire  read_req_valid;
    wire  read_req_ready;
    wire [31:0] read_req_addr;
    wire [4:0] read_req_beats;
    wire [31:0] read_req_tag;
    wire  read_data_valid;
    wire  read_data_ready;
    wire [255:0] read_data;
    wire [31:0] read_data_tag;
    wire [3:0] read_data_index;
    wire  read_data_last;
    wire  write_req_valid;
    wire  write_req_ready;
    wire [31:0] write_req_addr;
    wire [4:0] write_req_beats;
    wire  write_data_valid;
    wire  write_data_ready;
    wire [255:0] write_data;
    wire  write_stream_idle;
    wire  done;
    wire  unused_writer_idle;
    wire  unused_mac_beat;
    wire  unused_input_wait;
    wire  unused_model_wait;
    wire  unused_active;
    wire  read_idle;
    wire  read_error;
    wire  unused_read_beat;
    wire  write_idle;
    wire  write_error;
    wire  unused_write_beat;
    wire  unused_write_response_wait;
    wire unused_cls_valid;
    wire [255:0] unused_cls_data;
    wire [1:0] unused_cls_head;
    wire [11:0] unused_cls_row;
    wire [10:0] unused_cls_pair;
    wire [2:0] unused_cls_block;
    wire unused_cls_plane;

    generate if (!NONCONV) begin : g_conv
    edrv32_npu_conv u_conv (
        .clk_i(clk),
        .rst_n_i({4{rst_n}}),
        .start_i({4{start}}),
        .stop_i(stop),
        .cancel_i({4{cancel}}),
        .desc_i(desc),
        .in_addr_i(in_addr),
        .out_addr_i(out_addr),
        .residual_addr_i(unused_residual_addr),
        .weight_addr_i(unused_weight_addr),
        .quant_addr_i(unused_quant_addr),
        .post_enable_i(1'b0),
        .raw_cls_write_i(1'b0),
        .cls_valid_o(unused_cls_valid),
        .cls_data_o(unused_cls_data),
        .cls_head_o(unused_cls_head),
        .cls_row_o(unused_cls_row),
        .cls_pair_o(unused_cls_pair),
        .cls_block_o(unused_cls_block),
        .cls_plane_o(unused_cls_plane),
        .read_req_valid_o(read_req_valid),
        .read_req_ready_i(read_req_ready),
        .read_req_addr_o(read_req_addr),
        .read_req_beats_o(read_req_beats),
        .read_req_tag_o(read_req_tag),
        .read_data_valid_i(read_data_valid),
        .read_data_ready_o(read_data_ready),
        .read_data_i(read_data),
        .read_data_tag_i(read_data_tag),
        .read_data_index_i(read_data_index),
        .read_data_last_i(read_data_last),
        .write_req_valid_o(write_req_valid),
        .write_req_ready_i(write_req_ready),
        .write_req_addr_o(write_req_addr),
        .write_req_beats_o(write_req_beats),
        .write_data_valid_o(write_data_valid),
        .write_data_ready_i(write_data_ready),
        .write_data_o(write_data),
        .write_stream_idle_i(write_stream_idle),
        .done_o(done),
        .writer_idle_o(unused_writer_idle),
        .mac_beat_o(unused_mac_beat),
        .input_wait_o(unused_input_wait),
        .model_wait_o(unused_model_wait)
    );
    end else begin : g_nonconv
    edrv32_npu_nonconv u_nonconv (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .start_i(start),
        .stop_i(stop),
        .cancel_i(cancel),
        .desc_i(desc),
        .in_addr_i(in_addr),
        .out_addr_i(out_addr),
        .read_req_valid_o(read_req_valid),
        .read_req_ready_i(read_req_ready),
        .read_req_addr_o(read_req_addr),
        .read_req_beats_o(read_req_beats),
        .read_req_tag_o(read_req_tag),
        .read_data_valid_i(read_data_valid),
        .read_data_ready_o(read_data_ready),
        .read_data_i(read_data),
        .read_data_tag_i(read_data_tag),
        .read_data_index_i(read_data_index),
        .read_data_last_i(read_data_last),
        .write_req_valid_o(write_req_valid),
        .write_req_ready_i(write_req_ready),
        .write_req_addr_o(write_req_addr),
        .write_req_beats_o(write_req_beats),
        .write_data_valid_o(write_data_valid),
        .write_data_ready_i(write_data_ready),
        .write_data_o(write_data),
        .write_stream_idle_i(write_stream_idle),
        .done_o(done),
        .writer_idle_o(unused_writer_idle),
        .active_o(unused_active)
    );
    int row_samples;
    bit sampling;
    always @(posedge clk) begin
        if (rst_n && !u_nonconv.upsample_r) begin
            if (u_nonconv.state_r == 5) begin
                row_samples = 0;
                sampling = 1;
            end else if (sampling) begin
                if (row_samples < int'(u_nonconv.in_w_w)*25) begin
                    if (u_nonconv.state_r != 6)
                        $fatal(1, "FAIL POOL sample bubble at sample=%0d time=%0t",
                            row_samples, $time);
                    row_samples++;
                end else begin
                    sampling = 0;
                end
            end
        end
    end
    always @(posedge clk) begin
        if (rst_n) begin
            if (u_nonconv.plane_wr_en_w && u_nonconv.plane_rd_en_w
                && (u_nonconv.plane_wr_addr_w == u_nonconv.unused_sample_addr_w[8:0]))
                $fatal(1, "FAIL plane scratch simultaneous same-address read/write");
            if (u_nonconv.row_wr_en_w && u_nonconv.row_rd_en_w
                && (u_nonconv.row_wr_addr_w == u_nonconv.row_rd_addr_w))
                $fatal(1, "FAIL row scratch simultaneous same-address read/write");
        end
    end
    end endgenerate
    edrv32_npu_read_dma u_read_dma (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .stop_i(stop),
        .req_valid_i(read_req_valid),
        .req_ready_o(read_req_ready),
        .req_addr_i(read_req_addr),
        .req_beats_i(read_req_beats),
        .req_tag_i(read_req_tag),
        .data_valid_o(read_data_valid),
        .data_ready_i(read_data_ready),
        .data_o(read_data),
        .data_tag_o(read_data_tag),
        .data_index_o(read_data_index),
        .data_last_o(read_data_last),
        .axi_arid_o(bus.arid),
        .axi_araddr_o(bus.araddr),
        .axi_arlen_o(bus.arlen),
        .axi_arvalid_o(bus.arvalid),
        .axi_arready_i(bus.arready),
        .axi_rid_i(bus.rid),
        .axi_rdata_i(bus.rdata),
        .axi_rresp_i(bus.rresp),
        .axi_rlast_i(bus.rlast),
        .axi_rvalid_i(bus.rvalid),
        .axi_rready_o(bus.rready),
        .idle_o(read_idle),
        .error_o(read_error),
        .beat_o(unused_read_beat)
    );
    edrv32_npu_write_dma u_write_dma (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .stop_i(stop),
        .req_valid_i(write_req_valid),
        .req_ready_o(write_req_ready),
        .req_addr_i(write_req_addr),
        .req_beats_i(write_req_beats),
        .data_valid_i(write_data_valid),
        .data_ready_o(write_data_ready),
        .data_i(write_data),
        .data_strb_i(32'hffffffff),
        .stream_idle_o(write_stream_idle),
        .axi_awid_o(bus.awid),
        .axi_awaddr_o(bus.awaddr),
        .axi_awlen_o(bus.awlen),
        .axi_awvalid_o(bus.awvalid),
        .axi_awready_i(bus.awready),
        .axi_wdata_o(bus.wdata),
        .axi_wstrb_o(bus.wstrb),
        .axi_wlast_o(bus.wlast),
        .axi_wvalid_o(bus.wvalid),
        .axi_wready_i(bus.wready),
        .axi_bid_i(bus.bid),
        .axi_bresp_i(bus.bresp),
        .axi_bvalid_i(bus.bvalid),
        .axi_bready_o(bus.bready),
        .idle_o(write_idle),
        .error_o(write_error),
        .beat_o(unused_write_beat),
        .response_wait_o(unused_write_response_wait)
    );

    initial begin : run
        string path;
        string file_name;
        string unused_region;
        int fd;
        int status;
        longint unsigned expected_reads;
        longint unsigned expected_writes;
        int unsigned iw;
        int unsigned ih;
        int unsigned ow;
        int unsigned oh;
        int unsigned cin;
        int unsigned blocks;
        int unsigned planes;
        int unsigned terms;
        int unsigned input_rows;
        bit [31:0] address;
        bit [31:0] size;
        bit [31:0] ref_beat;
        bit [255:0] ref_data;
        byte unsigned expected [bit [31:0]];
        string word;
        if (!$value$plusargs("CASE_DIR=%s", path)) $fatal(1, "FAIL missing CASE_DIR");
        $readmemh({path, "/operator_meta.hex"}, meta);
        foreach (meta[n]) if ($isunknown(meta[n])) $fatal(1, "FAIL meta %0d", n);
        for (int k = 0; k < 6; k++) begin
            case (k)
                0: file_name = "model";
                1: file_name = "desc";
                2: file_name = "input";
                3: file_name = "work";
                4: file_name = "output";
                5: file_name = "state";
                default: file_name = "";
            endcase
            fd = $fopen({path, "/mem_", file_name, ".hex"}, "r");
            if (fd != 0) begin
                $fclose(fd);
                u_memory.load_hex({path, "/mem_", file_name, ".hex"});
            end
        end
        fd = $fopen({path, "/ref_out.hex"}, "r");
        if (fd == 0) $fatal(1, "FAIL missing reference");
        while ($fscanf(fd, "%s", word) == 1) begin
            if (word.substr(0, 0) == "@") begin
                status = $sscanf(word.substr(1, word.len()-1), "%h", ref_beat);
            end else begin
                status = $sscanf(word, "%h", ref_data);
                for (int b = 0; b < 32; b++) expected[ref_beat*32+32'(b)] = ref_data[b*8+:8];
                ref_beat++;
            end
            if (status != 1) $fatal(1, "FAIL reference format");
        end
        $fclose(fd);
        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        wait (done);
        wait (read_idle && write_idle);
        @(negedge clk);
        fd = $fopen({path, "/check.txt"}, "r");
        if (fd == 0) $fatal(1, "FAIL missing check regions");
        while ($fscanf(fd, "%s %h %h", unused_region, address, size) == 3) begin
            for (bit [31:0] b = 0; b < size; b++) begin
                if (u_memory.peek(address+b) != expected[address+b]) begin
                    $fatal(1, "FAIL addr=%08x expected=%02x actual=%02x time=%0t",
                        address+b, expected[address+b], u_memory.peek(address+b), $time);
                end
            end
        end
        $fclose(fd);
        if (u_memory.read_outstanding != 0 || u_memory.write_outstanding != 0)
            $fatal(1, "FAIL transactions left at fence");
        iw = meta[8] & 4095;
        ih = meta[8] >> 16 & 4095;
        ow = meta[9] & 4095;
        oh = meta[9] >> 16 & 4095;
        cin = meta[10] & 63;
        blocks = meta[10] >> 8 & 15;
        if (NONCONV) begin
            // Both serial operators read each source C16 beat once.
            expected_reads = 64'(cin)*(64'(iw)/64'd2)*64'(ih);
            planes = cin;
        end else begin
            terms = meta[0][4] ? 9 : 1;
            if (!meta[0][8]) terms *= 2*cin;
            planes = 2*blocks-int'(meta[0][9]);
            input_rows = meta[0][4] ? ih : oh;
            // Derive weights from geometry, independently of K_COUNT/BLOCK_BYTES.
            expected_reads = 64'(8)*64'(terms)*64'(blocks);
            if (meta[0][9] && !meta[0][8]) expected_reads -= 64'(4)*64'(terms);
            expected_reads += 64'(8)*64'(blocks)*(meta[0][6] ? 2 : 1);
            expected_reads += 64'(cin)*(64'(iw)/(meta[0][8] ? 64'd8 : 64'd2))*64'(input_rows);
            if (meta[0][7]) expected_reads += 64'(planes)*(64'(ow)/64'd2)*64'(oh);
        end
        expected_writes = 64'(planes)*(64'(ow)/64'd2)*64'(oh);
        if (u_memory.read_beats != expected_reads || u_memory.write_beats != expected_writes)
            $fatal(1, "FAIL exact DMA traffic expected R/W=%0d/%0d actual=%0d/%0d",
                expected_reads, expected_writes, u_memory.read_beats, u_memory.write_beats);
        $display("PASS isolated operator NONCONV=%0d read=%0d write=%0d",
            NONCONV, u_memory.read_beats, u_memory.write_beats);
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1, "FAIL operator timeout");
    end
endmodule
