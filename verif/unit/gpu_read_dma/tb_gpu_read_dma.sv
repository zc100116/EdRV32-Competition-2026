// Self-checking gpu_read_dma unit test.
module tb_gpu_read_dma;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic command_read_req_valid_i = 0;
    logic command_read_req_ready_o;
    logic [31:0] command_read_req_addr_i = 0;
    logic [31:0] command_read_req_bytes_i = 0;
    logic command_read_data_valid_o;
    logic command_read_data_ready_i = 0;
    logic [255:0] command_read_data_data_o;
    logic [31:0] command_read_data_keep_o;
    logic command_read_data_last_o;
    logic command_read_done_o;
    logic matrix_read_req_valid_i = 0;
    logic matrix_read_req_ready_o;
    logic [31:0] matrix_read_req_addr_i = 0;
    logic [31:0] matrix_read_req_bytes_i = 0;
    logic matrix_read_data_valid_o;
    logic matrix_read_data_ready_i = 0;
    logic [255:0] matrix_read_data_data_o;
    logic [31:0] matrix_read_data_keep_o;
    logic matrix_read_data_last_o;
    logic matrix_read_done_o;
    logic vertex_read_req_valid_i = 0;
    logic vertex_read_req_ready_o;
    logic [31:0] vertex_read_req_addr_i = 0;
    logic [31:0] vertex_read_req_bytes_i = 0;
    logic vertex_read_data_valid_o;
    logic vertex_read_data_ready_i = 0;
    logic [255:0] vertex_read_data_data_o;
    logic [31:0] vertex_read_data_keep_o;
    logic vertex_read_data_last_o;
    logic vertex_read_done_o;
    logic quad_read_req_valid_i = 0;
    logic quad_read_req_ready_o;
    logic [31:0] quad_read_req_addr_i = 0;
    logic [31:0] quad_read_req_bytes_i = 0;
    logic quad_read_data_valid_o;
    logic quad_read_data_ready_i = 0;
    logic [255:0] quad_read_data_data_o;
    logic [31:0] quad_read_data_keep_o;
    logic quad_read_data_last_o;
    logic quad_read_done_o;
    logic object_read_req_valid_i = 0;
    logic object_read_req_ready_o;
    logic [31:0] object_read_req_addr_i = 0;
    logic [31:0] object_read_req_bytes_i = 0;
    logic object_read_data_valid_o;
    logic object_read_data_ready_i = 0;
    logic [255:0] object_read_data_data_o;
    logic [31:0] object_read_data_keep_o;
    logic object_read_data_last_o;
    logic object_read_done_o;
    logic texture_read_req_valid_i = 0;
    logic texture_read_req_ready_o;
    logic [31:0] texture_read_req_addr_i = 0;
    logic [31:0] texture_read_req_bytes_i = 0;
    logic texture_read_data_valid_o;
    logic texture_read_data_ready_i = 0;
    logic [255:0] texture_read_data_data_o;
    logic [31:0] texture_read_data_keep_o;
    logic texture_read_data_last_o;
    logic texture_read_done_o;
    logic palette_read_req_valid_i = 0;
    logic palette_read_req_ready_o;
    logic [31:0] palette_read_req_addr_i = 0;
    logic [31:0] palette_read_req_bytes_i = 0;
    logic palette_read_data_valid_o;
    logic palette_read_data_ready_i = 0;
    logic [255:0] palette_read_data_data_o;
    logic [31:0] palette_read_data_keep_o;
    logic palette_read_data_last_o;
    logic palette_read_done_o;
    logic m_axi_arid_o;
    logic [31:0] m_axi_araddr_o;
    logic [3:0] m_axi_arlen_o;
    logic m_axi_arvalid_o;
    logic m_axi_arready_i = 0;
    logic m_axi_rid_i = 0;
    logic [255:0] m_axi_rdata_i = 0;
    logic [1:0] m_axi_rresp_i = 0;
    logic m_axi_rlast_i = 0;
    logic m_axi_rvalid_i = 0;
    logic m_axi_rready_o;
    logic start_i = 0;
    logic stop_i = 0;
    logic dma_idle_o;
    logic dma_error_o;
    logic perf_read_wait_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_read_dma u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .command_read_req_valid_i(command_read_req_valid_i),
        .command_read_req_ready_o(command_read_req_ready_o),
        .command_read_req_addr_i(command_read_req_addr_i),
        .command_read_req_bytes_i(command_read_req_bytes_i),
        .command_read_data_valid_o(command_read_data_valid_o),
        .command_read_data_ready_i(command_read_data_ready_i),
        .command_read_data_data_o(command_read_data_data_o),
        .command_read_data_keep_o(command_read_data_keep_o),
        .command_read_data_last_o(command_read_data_last_o),
        .command_read_done_o(command_read_done_o),
        .matrix_read_req_valid_i(matrix_read_req_valid_i),
        .matrix_read_req_ready_o(matrix_read_req_ready_o),
        .matrix_read_req_addr_i(matrix_read_req_addr_i),
        .matrix_read_req_bytes_i(matrix_read_req_bytes_i),
        .matrix_read_data_valid_o(matrix_read_data_valid_o),
        .matrix_read_data_ready_i(matrix_read_data_ready_i),
        .matrix_read_data_data_o(matrix_read_data_data_o),
        .matrix_read_data_keep_o(matrix_read_data_keep_o),
        .matrix_read_data_last_o(matrix_read_data_last_o),
        .matrix_read_done_o(matrix_read_done_o),
        .vertex_read_req_valid_i(vertex_read_req_valid_i),
        .vertex_read_req_ready_o(vertex_read_req_ready_o),
        .vertex_read_req_addr_i(vertex_read_req_addr_i),
        .vertex_read_req_bytes_i(vertex_read_req_bytes_i),
        .vertex_read_data_valid_o(vertex_read_data_valid_o),
        .vertex_read_data_ready_i(vertex_read_data_ready_i),
        .vertex_read_data_data_o(vertex_read_data_data_o),
        .vertex_read_data_keep_o(vertex_read_data_keep_o),
        .vertex_read_data_last_o(vertex_read_data_last_o),
        .vertex_read_done_o(vertex_read_done_o),
        .quad_read_req_valid_i(quad_read_req_valid_i),
        .quad_read_req_ready_o(quad_read_req_ready_o),
        .quad_read_req_addr_i(quad_read_req_addr_i),
        .quad_read_req_bytes_i(quad_read_req_bytes_i),
        .quad_read_data_valid_o(quad_read_data_valid_o),
        .quad_read_data_ready_i(quad_read_data_ready_i),
        .quad_read_data_data_o(quad_read_data_data_o),
        .quad_read_data_keep_o(quad_read_data_keep_o),
        .quad_read_data_last_o(quad_read_data_last_o),
        .quad_read_done_o(quad_read_done_o),
        .object_read_req_valid_i(object_read_req_valid_i),
        .object_read_req_ready_o(object_read_req_ready_o),
        .object_read_req_addr_i(object_read_req_addr_i),
        .object_read_req_bytes_i(object_read_req_bytes_i),
        .object_read_data_valid_o(object_read_data_valid_o),
        .object_read_data_ready_i(object_read_data_ready_i),
        .object_read_data_data_o(object_read_data_data_o),
        .object_read_data_keep_o(object_read_data_keep_o),
        .object_read_data_last_o(object_read_data_last_o),
        .object_read_done_o(object_read_done_o),
        .texture_read_req_valid_i(texture_read_req_valid_i),
        .texture_read_req_ready_o(texture_read_req_ready_o),
        .texture_read_req_addr_i(texture_read_req_addr_i),
        .texture_read_req_bytes_i(texture_read_req_bytes_i),
        .texture_read_data_valid_o(texture_read_data_valid_o),
        .texture_read_data_ready_i(texture_read_data_ready_i),
        .texture_read_data_data_o(texture_read_data_data_o),
        .texture_read_data_keep_o(texture_read_data_keep_o),
        .texture_read_data_last_o(texture_read_data_last_o),
        .texture_read_done_o(texture_read_done_o),
        .palette_read_req_valid_i(palette_read_req_valid_i),
        .palette_read_req_ready_o(palette_read_req_ready_o),
        .palette_read_req_addr_i(palette_read_req_addr_i),
        .palette_read_req_bytes_i(palette_read_req_bytes_i),
        .palette_read_data_valid_o(palette_read_data_valid_o),
        .palette_read_data_ready_i(palette_read_data_ready_i),
        .palette_read_data_data_o(palette_read_data_data_o),
        .palette_read_data_keep_o(palette_read_data_keep_o),
        .palette_read_data_last_o(palette_read_data_last_o),
        .palette_read_done_o(palette_read_done_o),
        .m_axi_arid_o(m_axi_arid_o),
        .m_axi_araddr_o(m_axi_araddr_o),
        .m_axi_arlen_o(m_axi_arlen_o),
        .m_axi_arvalid_o(m_axi_arvalid_o),
        .m_axi_arready_i(m_axi_arready_i),
        .m_axi_rid_i(m_axi_rid_i),
        .m_axi_rdata_i(m_axi_rdata_i),
        .m_axi_rresp_i(m_axi_rresp_i),
        .m_axi_rlast_i(m_axi_rlast_i),
        .m_axi_rvalid_i(m_axi_rvalid_i),
        .m_axi_rready_o(m_axi_rready_o),
        .start_i(start_i),
        .stop_i(stop_i),
        .dma_idle_o(dma_idle_o),
        .dma_error_o(dma_error_o),
        .perf_read_wait_o(perf_read_wait_o)
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
    int base[7];
    int bytes_count[7];
    int received[7];
    int qa[256];
    int qn[256];
    int qhead=0;
    int qtail=0;
    int rb=0;
    int cycles=0;
    int outstanding=0;
    int peak=0;
    int completions=0;
    bit run_bfm=0;
    bit inject=0;
    function [7:0] pattern(input int addr);
        return 8'(addr ^ (addr>>8) ^ (addr>>16));
    endfunction
    task check_data(input int c, input logic [255:0] data,
                    input logic [31:0] keep, input bit last);
        int a;
        bit expected_keep;
        a=(base[c]&~31)+32*received[c];
        for (int j=0;j<32;j++) begin
            expected_keep=(a+j>=base[c] && a+j<base[c]+bytes_count[c]);
            if (keep[j] !== expected_keep || data[j*8+:8] !== pattern(a+j))
                $fatal(1,"FAIL read client %0d beat %0d byte %0d",c,received[c],j);
        end
        if (last !== (a+32>=base[c]+bytes_count[c])) $fatal(1,"FAIL read last");
        received[c]++;
    endtask
    always @(negedge clk_i) begin
        if (run_bfm) begin
            cycles++;
            m_axi_arready_i=(cycles%5!=0);
            m_axi_rvalid_i=qhead<qtail && cycles%4!=0;
            m_axi_rresp_i=(inject && qhead==4 && rb==0) ? 2 : 0;
            m_axi_rlast_i=qhead<qtail && rb+1==qn[qhead];
            for(int j=0;j<32;j++) m_axi_rdata_i[j*8+:8]=pattern(qa[qhead]+32*rb+j);
            command_read_data_ready_i=cycles>100 && cycles%7!=0;
            matrix_read_data_ready_i=cycles>100 && cycles%7!=0;
            vertex_read_data_ready_i=cycles>100 && cycles%7!=0;
            quad_read_data_ready_i=cycles>100 && cycles%7!=0;
            object_read_data_ready_i=cycles>100 && cycles%7!=0;
            texture_read_data_ready_i=cycles>100 && cycles%7!=0;
            palette_read_data_ready_i=cycles>100 && cycles%7!=0;
        end
    end
    always @(posedge clk_i) begin
        if (rst_n_i && run_bfm) begin
            if (m_axi_arvalid_o && m_axi_arready_i) begin
                if (m_axi_araddr_o[4:0]!=0 || int'(m_axi_araddr_o[11:0])
                    +32*(int'(m_axi_arlen_o)+1)>4096 || m_axi_arid_o)
                    $fatal(1,"FAIL read burst geometry");
                qa[qtail]=int'(m_axi_araddr_o); qn[qtail]=int'(m_axi_arlen_o)+1;
                qtail++; outstanding++;
                if(outstanding>peak) peak=outstanding;
                if(outstanding>4) $fatal(1,"FAIL read outstanding");
            end
            if (m_axi_rvalid_i && m_axi_rready_o) begin
                rb++;
                if(rb==qn[qhead]) begin qhead++; rb=0; outstanding--; end
            end
            if (command_read_data_valid_o && command_read_data_ready_i)
                check_data(0,command_read_data_data_o,command_read_data_keep_o,command_read_data_last_o);
            if (command_read_done_o) completions++;
            if (matrix_read_data_valid_o && matrix_read_data_ready_i)
                check_data(1,matrix_read_data_data_o,matrix_read_data_keep_o,matrix_read_data_last_o);
            if (matrix_read_done_o) completions++;
            if (vertex_read_data_valid_o && vertex_read_data_ready_i)
                check_data(2,vertex_read_data_data_o,vertex_read_data_keep_o,vertex_read_data_last_o);
            if (vertex_read_done_o) completions++;
            if (quad_read_data_valid_o && quad_read_data_ready_i)
                check_data(3,quad_read_data_data_o,quad_read_data_keep_o,quad_read_data_last_o);
            if (quad_read_done_o) completions++;
            if (object_read_data_valid_o && object_read_data_ready_i)
                check_data(4,object_read_data_data_o,object_read_data_keep_o,object_read_data_last_o);
            if (object_read_done_o) completions++;
            if (texture_read_data_valid_o && texture_read_data_ready_i)
                check_data(5,texture_read_data_data_o,texture_read_data_keep_o,texture_read_data_last_o);
            if (texture_read_done_o) completions++;
            if (palette_read_data_valid_o && palette_read_data_ready_i)
                check_data(6,palette_read_data_data_o,palette_read_data_keep_o,palette_read_data_last_o);
            if (palette_read_done_o) completions++;
        end
    end
    initial begin
        reset();
        for(int i=0;i<7;i++) begin base[i]=i*65536+'hfe3; bytes_count[i]=1300+i*17; end
        @(negedge clk_i); run_bfm=1; inject=1;
        command_read_req_valid_i=1; command_read_req_addr_i=32'(base[0]);
        command_read_req_bytes_i=32'(bytes_count[0]);
        matrix_read_req_valid_i=1; matrix_read_req_addr_i=32'(base[1]);
        matrix_read_req_bytes_i=32'(bytes_count[1]);
        vertex_read_req_valid_i=1; vertex_read_req_addr_i=32'(base[2]);
        vertex_read_req_bytes_i=32'(bytes_count[2]);
        quad_read_req_valid_i=1; quad_read_req_addr_i=32'(base[3]);
        quad_read_req_bytes_i=32'(bytes_count[3]);
        object_read_req_valid_i=1; object_read_req_addr_i=32'(base[4]);
        object_read_req_bytes_i=32'(bytes_count[4]);
        texture_read_req_valid_i=1; texture_read_req_addr_i=32'(base[5]);
        texture_read_req_bytes_i=32'(bytes_count[5]);
        palette_read_req_valid_i=1; palette_read_req_addr_i=32'(base[6]);
        palette_read_req_bytes_i=32'(bytes_count[6]);
        tick(); @(negedge clk_i);
        command_read_req_valid_i=0;
        matrix_read_req_valid_i=0;
        vertex_read_req_valid_i=0;
        quad_read_req_valid_i=0;
        object_read_req_valid_i=0;
        texture_read_req_valid_i=0;
        palette_read_req_valid_i=0;
        wait(completions==7); tick();
        if (!dma_idle_o || !dma_error_o || peak!=4) $fatal(1,"FAIL read drain/error/peak %0d",peak);
        @(negedge clk_i); start_i=1; inject=0; tick();
        @(negedge clk_i); start_i=0;
        base[0]='h200ffb; bytes_count[0]=1700; received[0]=0;
        command_read_req_valid_i=1; command_read_req_addr_i=32'(base[0]);
        command_read_req_bytes_i=32'(bytes_count[0]); tick();
        @(negedge clk_i); command_read_req_valid_i=0; stop_i=1;
        wait(completions==8); tick();
        if (!dma_idle_o || dma_error_o || command_read_req_ready_o)
            $fatal(1,"FAIL read ABORT drain");
        $display("PASS gpu_read_dma 7 clients align/4KiB/16beat/keep/error/ABORT peak=%0d",peak);
        $finish;
    end
endmodule
