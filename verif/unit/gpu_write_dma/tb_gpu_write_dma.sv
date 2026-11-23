// Self-checking gpu_write_dma unit test.
module tb_gpu_write_dma;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic object_write_req_valid_i = 0;
    logic object_write_req_ready_o;
    logic [31:0] object_write_req_addr_i = 0;
    logic [31:0] object_write_req_bytes_i = 0;
    logic object_write_data_valid_i = 0;
    logic object_write_data_ready_o;
    logic [255:0] object_write_data_data_i = 0;
    logic [31:0] object_write_data_keep_i = 0;
    logic object_write_data_last_i = 0;
    logic object_write_done_o;
    logic hit_write_req_valid_i = 0;
    logic hit_write_req_ready_o;
    logic [31:0] hit_write_req_addr_i = 0;
    logic [31:0] hit_write_req_bytes_i = 0;
    logic hit_write_data_valid_i = 0;
    logic hit_write_data_ready_o;
    logic [255:0] hit_write_data_data_i = 0;
    logic [31:0] hit_write_data_keep_i = 0;
    logic hit_write_data_last_i = 0;
    logic hit_write_done_o;
    logic free_write_req_valid_i = 0;
    logic free_write_req_ready_o;
    logic [31:0] free_write_req_addr_i = 0;
    logic [31:0] free_write_req_bytes_i = 0;
    logic free_write_data_valid_i = 0;
    logic free_write_data_ready_o;
    logic [255:0] free_write_data_data_i = 0;
    logic [31:0] free_write_data_keep_i = 0;
    logic free_write_data_last_i = 0;
    logic free_write_done_o;
    logic resolve_write_req_valid_i = 0;
    logic resolve_write_req_ready_o;
    logic [31:0] resolve_write_req_addr_i = 0;
    logic [31:0] resolve_write_req_bytes_i = 0;
    logic resolve_write_data_valid_i = 0;
    logic resolve_write_data_ready_o;
    logic [255:0] resolve_write_data_data_i = 0;
    logic [31:0] resolve_write_data_keep_i = 0;
    logic resolve_write_data_last_i = 0;
    logic resolve_write_done_o;
    logic m_axi_awid_o;
    logic [31:0] m_axi_awaddr_o;
    logic [3:0] m_axi_awlen_o;
    logic m_axi_awvalid_o;
    logic m_axi_awready_i = 0;
    logic [255:0] m_axi_wdata_o;
    logic [31:0] m_axi_wstrb_o;
    logic m_axi_wlast_o;
    logic m_axi_wvalid_o;
    logic m_axi_wready_i = 0;
    logic m_axi_bid_i = 0;
    logic [1:0] m_axi_bresp_i = 0;
    logic m_axi_bvalid_i = 0;
    logic m_axi_bready_o;
    logic start_i = 0;
    logic stop_i = 0;
    logic dma_idle_o;
    logic dma_error_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_write_dma u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .object_write_req_valid_i(object_write_req_valid_i),
        .object_write_req_ready_o(object_write_req_ready_o),
        .object_write_req_addr_i(object_write_req_addr_i),
        .object_write_req_bytes_i(object_write_req_bytes_i),
        .object_write_data_valid_i(object_write_data_valid_i),
        .object_write_data_ready_o(object_write_data_ready_o),
        .object_write_data_data_i(object_write_data_data_i),
        .object_write_data_keep_i(object_write_data_keep_i),
        .object_write_data_last_i(object_write_data_last_i),
        .object_write_done_o(object_write_done_o),
        .hit_write_req_valid_i(hit_write_req_valid_i),
        .hit_write_req_ready_o(hit_write_req_ready_o),
        .hit_write_req_addr_i(hit_write_req_addr_i),
        .hit_write_req_bytes_i(hit_write_req_bytes_i),
        .hit_write_data_valid_i(hit_write_data_valid_i),
        .hit_write_data_ready_o(hit_write_data_ready_o),
        .hit_write_data_data_i(hit_write_data_data_i),
        .hit_write_data_keep_i(hit_write_data_keep_i),
        .hit_write_data_last_i(hit_write_data_last_i),
        .hit_write_done_o(hit_write_done_o),
        .free_write_req_valid_i(free_write_req_valid_i),
        .free_write_req_ready_o(free_write_req_ready_o),
        .free_write_req_addr_i(free_write_req_addr_i),
        .free_write_req_bytes_i(free_write_req_bytes_i),
        .free_write_data_valid_i(free_write_data_valid_i),
        .free_write_data_ready_o(free_write_data_ready_o),
        .free_write_data_data_i(free_write_data_data_i),
        .free_write_data_keep_i(free_write_data_keep_i),
        .free_write_data_last_i(free_write_data_last_i),
        .free_write_done_o(free_write_done_o),
        .resolve_write_req_valid_i(resolve_write_req_valid_i),
        .resolve_write_req_ready_o(resolve_write_req_ready_o),
        .resolve_write_req_addr_i(resolve_write_req_addr_i),
        .resolve_write_req_bytes_i(resolve_write_req_bytes_i),
        .resolve_write_data_valid_i(resolve_write_data_valid_i),
        .resolve_write_data_ready_o(resolve_write_data_ready_o),
        .resolve_write_data_data_i(resolve_write_data_data_i),
        .resolve_write_data_keep_i(resolve_write_data_keep_i),
        .resolve_write_data_last_i(resolve_write_data_last_i),
        .resolve_write_done_o(resolve_write_done_o),
        .m_axi_awid_o(m_axi_awid_o),
        .m_axi_awaddr_o(m_axi_awaddr_o),
        .m_axi_awlen_o(m_axi_awlen_o),
        .m_axi_awvalid_o(m_axi_awvalid_o),
        .m_axi_awready_i(m_axi_awready_i),
        .m_axi_wdata_o(m_axi_wdata_o),
        .m_axi_wstrb_o(m_axi_wstrb_o),
        .m_axi_wlast_o(m_axi_wlast_o),
        .m_axi_wvalid_o(m_axi_wvalid_o),
        .m_axi_wready_i(m_axi_wready_i),
        .m_axi_bid_i(m_axi_bid_i),
        .m_axi_bresp_i(m_axi_bresp_i),
        .m_axi_bvalid_i(m_axi_bvalid_i),
        .m_axi_bready_o(m_axi_bready_o),
        .start_i(start_i),
        .stop_i(stop_i),
        .dma_idle_o(dma_idle_o),
        .dma_error_o(dma_error_o)
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
    int base[4];
    int bytes_count[4];
    int supplied[4];
    int qa[256];
    int qn[256];
    int wc[4];
    int qhead=0;
    int qtail=0;
    int bhead=0;
    int wb=0;
    int cycles=0;
    int outstanding=0;
    int peak=0;
    int completions=0;
    bit run_bfm=0;
    bit inject=0;
    function [7:0] pattern(input int addr);
        return 8'(addr ^ (addr>>8) ^ (addr>>16));
    endfunction
    always @(negedge clk_i) begin
        if (run_bfm) begin
            cycles++;
            m_axi_awready_i=cycles%5!=0;
            m_axi_wready_i=cycles%7!=0;
            m_axi_bvalid_i=bhead<qhead && cycles>120 && cycles%4!=0;
            m_axi_bresp_i=inject && bhead==3 ? 2 : 0;
            object_write_data_valid_i=cycles%3!=0;
            object_write_data_keep_i=32'hf7ffffff;
            object_write_data_last_i=((base[0]&~31)+32*(supplied[0]+1)>=base[0]+bytes_count[0]);
            for(int j=0;j<32;j++) object_write_data_data_i[j*8+:8]=
                pattern((base[0]&~31)+32*supplied[0]+j);
            hit_write_data_valid_i=cycles%3!=0;
            hit_write_data_keep_i=32'hf7ffffff;
            hit_write_data_last_i=((base[1]&~31)+32*(supplied[1]+1)>=base[1]+bytes_count[1]);
            for(int j=0;j<32;j++) hit_write_data_data_i[j*8+:8]=
                pattern((base[1]&~31)+32*supplied[1]+j);
            free_write_data_valid_i=cycles%3!=0;
            free_write_data_keep_i=32'hf7ffffff;
            free_write_data_last_i=((base[2]&~31)+32*(supplied[2]+1)>=base[2]+bytes_count[2]);
            for(int j=0;j<32;j++) free_write_data_data_i[j*8+:8]=
                pattern((base[2]&~31)+32*supplied[2]+j);
            resolve_write_data_valid_i=cycles%3!=0;
            resolve_write_data_keep_i=32'hf7ffffff;
            resolve_write_data_last_i=((base[3]&~31)+32*(supplied[3]+1)>=base[3]+bytes_count[3]);
            for(int j=0;j<32;j++) resolve_write_data_data_i[j*8+:8]=
                pattern((base[3]&~31)+32*supplied[3]+j);
        end
    end
    always @(posedge clk_i) begin
        if (rst_n_i && run_bfm) begin
            if(object_write_data_valid_i && object_write_data_ready_o) supplied[0]++;
            if(object_write_done_o) completions++;
            if(hit_write_data_valid_i && hit_write_data_ready_o) supplied[1]++;
            if(hit_write_done_o) completions++;
            if(free_write_data_valid_i && free_write_data_ready_o) supplied[2]++;
            if(free_write_done_o) completions++;
            if(resolve_write_data_valid_i && resolve_write_data_ready_o) supplied[3]++;
            if(resolve_write_done_o) completions++;
            if (m_axi_awvalid_o && m_axi_awready_i) begin
                if(m_axi_awaddr_o[4:0]!=0 || int'(m_axi_awaddr_o[11:0])
                    +32*(int'(m_axi_awlen_o)+1)>4096 || m_axi_awid_o)
                    $fatal(1,"FAIL write burst geometry");
                qa[qtail]=int'(m_axi_awaddr_o); qn[qtail]=int'(m_axi_awlen_o)+1;
                qtail++; outstanding++;
                if(outstanding>peak) peak=outstanding;
                if(outstanding>2) $fatal(1,"FAIL write outstanding");
            end
            if(m_axi_wvalid_o && m_axi_wready_i) begin
                int a;
                int c;
                bit k;
                a=qa[qhead]+32*wb; c=(a>>16)&3;
                if(qhead>=qtail) $fatal(1,"FAIL W before AW");
                for(int j=0;j<32;j++) begin
                    k=(a+j>=base[c] && a+j<base[c]+bytes_count[c] && j!=27);
                    if(m_axi_wstrb_o[j]!==k || m_axi_wdata_o[j*8+:8]!==pattern(a+j))
                        $fatal(1,"FAIL W client %0d beat %0d byte %0d",c,wb,j);
                end
                if(m_axi_wlast_o !== (wb+1==qn[qhead])) $fatal(1,"FAIL WLAST");
                wb++;
                if(wb==qn[qhead]) begin qhead++; wb=0; end
            end
            if(m_axi_bvalid_i && m_axi_bready_o) begin bhead++; outstanding--; end
        end
    end
    initial begin
        reset();
        for(int i=0;i<4;i++) begin base[i]=i*65536+'hfe3; bytes_count[i]=1300+i*17; end
        @(negedge clk_i); run_bfm=1; inject=1;
        object_write_req_valid_i=1; object_write_req_addr_i=32'(base[0]);
        object_write_req_bytes_i=32'(bytes_count[0]);
        hit_write_req_valid_i=1; hit_write_req_addr_i=32'(base[1]);
        hit_write_req_bytes_i=32'(bytes_count[1]);
        free_write_req_valid_i=1; free_write_req_addr_i=32'(base[2]);
        free_write_req_bytes_i=32'(bytes_count[2]);
        resolve_write_req_valid_i=1; resolve_write_req_addr_i=32'(base[3]);
        resolve_write_req_bytes_i=32'(bytes_count[3]);
        tick(); @(negedge clk_i);
        object_write_req_valid_i=0;
        hit_write_req_valid_i=0;
        free_write_req_valid_i=0;
        resolve_write_req_valid_i=0;
        wait(completions==4); tick();
        if(!dma_idle_o || !dma_error_o || peak!=2) $fatal(1,"FAIL write drain/error/peak %0d",peak);
        @(negedge clk_i); start_i=1; inject=0; tick();
        @(negedge clk_i); start_i=0;
        base[0]='h40ffb; bytes_count[0]=1700; supplied[0]=0;
        object_write_req_valid_i=1; object_write_req_addr_i=32'(base[0]);
        object_write_req_bytes_i=32'(bytes_count[0]); tick();
        @(negedge clk_i); object_write_req_valid_i=0; stop_i=1;
        wait(completions==5); tick();
        if(!dma_idle_o || dma_error_o || object_write_req_ready_o)
            $fatal(1,"FAIL write ABORT drain");
        $display("PASS gpu_write_dma 4 clients align/4KiB/16beat/WSTRB/error/ABORT peak=%0d",peak);
        $finish;
    end
endmodule
