// File: drm_collision_check.sv
// Spec: gpu-v2-spec 2.4 storage; fpga/ip/README.md DRM SDP same-address rule.
// Description: Same-edge write/read of one address through the generated DRM IPs
//              must return the old word; the next read returns the new word.
// Clock: single clk.
module drm_collision_check;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    reg clk = 0;
    always #5 clk = ~clk;
    reg wr_en = 0;
    reg rd_en = 0;
    reg [9:0] addr = 10'd5;
    reg [71:0] wr_data = 0;
    wire [71:0] rd72;
    wire [35:0] rd36;
    wire [31:0] rd_scratch;
    integer errors = 0;
    edrv32_ram_gpu2_sdp72 u_sdp72 (
        .clk_i(clk), .wr_en_i(wr_en), .wr_addr_i(addr[8:0]), .wr_data_i(wr_data),
        .rd_en_i(rd_en), .rd_addr_i(addr[8:0]), .rd_data_o(rd72)
    );
    edrv32_ram_gpu2_sdp36 u_sdp36 (
        .clk_i(clk), .wr_en_i(wr_en), .wr_addr_i(addr), .wr_data_i(wr_data[35:0]),
        .rd_en_i(rd_en), .rd_addr_i(addr), .rd_data_o(rd36)
    );
    edrv32_ram_gpu2_sfu_scratch u_scratch (
        .clk_i(clk), .wr_en_i(wr_en), .wr_addr_i(addr[4:0]), .wr_data_i(wr_data[31:0]),
        .rd_addr_i(addr[4:0]), .rd_data_o(rd_scratch)
    );
    // sdp72/sdp36 rely on the DRM returning the old word; the scratch wrapper
    // forwards the written word itself, so its interface returns the new word.
    task expect_words(input [71:0] value, input [31:0] scratch_value,
                      input [8*24-1:0] label_text);
        if (rd72 !== value) begin
            $display("FAIL sdp72 %0s expected %h actual %h at %0t", label_text, value, rd72, $time);
            errors = errors + 1;
        end
        if (rd36 !== value[35:0]) begin
            $display("FAIL sdp36 %0s expected %h actual %h at %0t", label_text, value[35:0], rd36, $time);
            errors = errors + 1;
        end
        if (rd_scratch !== scratch_value) begin
            $display("FAIL scratch %0s expected %h actual %h at %0t", label_text, scratch_value,
                     rd_scratch, $time);
            errors = errors + 1;
        end
    endtask
    initial begin
        repeat (4) @(posedge clk);
        // Write the old word A.
        @(negedge clk); wr_en = 1; wr_data = 72'hA1_A2A3A4A5_A6A7A8A9;
        // Same edge: write new word B and read the same address.
        @(negedge clk); wr_data = 72'hB1_B2B3B4B5_B6B7B8B9; rd_en = 1;
        @(negedge clk); wr_en = 0;
        expect_words(72'hA1_A2A3A4A5_A6A7A8A9, 32'hB6B7B8B9, "same-edge");
        // Following read returns B.
        @(negedge clk); rd_en = 0;
        expect_words(72'hB1_B2B3B4B5_B6B7B8B9, 32'hB6B7B8B9, "next read");
        if (errors == 0) $display("PASS drm_collision");
        else $display("FAIL drm_collision errors=%0d", errors);
        $finish;
    end
endmodule
