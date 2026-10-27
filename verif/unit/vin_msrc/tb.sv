// File: tb.sv
// Spec: vin 2.3, 2.5, 5.3, 6.
// Description: Row/address oracle checks reserved unthrottled reads and stalled unpacking.
// Clock domain: clk_mem.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit start = 0;
    bit abort_request = 0;
    bit [31:0] base = 'h10000;
    bit [15:0] stride = 2592;
    bit [10:0] width = 1280;
    bit [11:0] height = 8;
    wire valid;
    bit ready = 0;
    wire [31:0] data;
    wire sof;
    wire eol;
    wire eof;
    wire [31:0] frame_id;
    wire [10:0] out_width;
    wire [11:0] out_height;
    wire arid;
    wire [31:0] araddr;
    wire [3:0] arlen;
    wire arvalid;
    bit arready;
    bit [255:0] rdata;
    bit [1:0] rresp;
    bit rlast;
    bit rvalid;
    wire rready;
    wire busy;
    wire done;
    wire error;
    wire cfg_error;
    wire frame;
    typedef struct packed {int addr; int beats;} burst_t;
    burst_t returns[$];
    burst_t returning;
    int return_pos;
    int cycles;
    int outputs;
    int expected_width = 1280;
    int expected_height = 8;
    int expected_stride = 2592;
    int expected_base = 'h10000;
    int expected_id;
    int read_row;
    int read_beats;
    int done_count;
    int error_count;
    int cfg_count;
    int frame_count;
    bit checking = 1;
    bit read_error = 0;
    bit hold_returns = 0;
    edrv32_vin_msrc u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .start_i(start),
        .abort_i(abort_request),
        .base_i(base),
        .stride_i(stride),
        .width_i(width),
        .height_i(height),
        .valid_o(valid),
        .ready_i(ready),
        .data_o(data),
        .sof_o(sof),
        .eol_o(eol),
        .eof_o(eof),
        .frame_id_o(frame_id),
        .width_o(out_width),
        .height_o(out_height),
        .p1_arid_o(arid),
        .p1_araddr_o(araddr),
        .p1_arlen_o(arlen),
        .p1_arvalid_o(arvalid),
        .p1_arready_i(arready),
        .p1_rdata_i(rdata),
        .p1_rresp_i(rresp),
        .p1_rlast_i(rlast),
        .p1_rvalid_i(rvalid),
        .p1_rready_o(rready),
        .p1_rid_i(1'b0),
        .busy_o(busy),
        .done_o(done),
        .error_o(error),
        .cfg_error_o(cfg_error),
        .frame_o(frame)
    );

    function automatic bit [31:0] pattern(input int addr);
        return 32'(addr) ^ 32'hb00caffe;
    endfunction
    always @(negedge clk) begin
        cycles++;
        arready = cycles % 5 != 0;
        rvalid = !hold_returns && returns.size() != 0 && cycles % 7 != 0;
        rresp = read_error ? 2'b10 : 2'b00;
        rlast = 0;
        if (rvalid) begin
            returning = returns[0];
            for (int w = 0; w < 8; w++)
                rdata[w*32 +: 32] = pattern(returning.addr + return_pos*32 + w*4);
            rlast = return_pos == returning.beats-1;
        end
    end
    always @(posedge clk) begin
        burst_t burst;
        int want_addr;
        int want_beats;
        int words_per_row;
        int row;
        int word_no;
        bit [31:0] want;
        if (rst_n) begin
            if (!rready) $fatal(1, "FAIL R backpressured t=%0t",$time);
            if (done) done_count++;
            if (error) error_count++;
            if (cfg_error) cfg_count++;
            if (frame) frame_count++;
            if (arvalid && arready) begin
                burst.addr = int'(araddr);
                burst.beats = int'(arlen)+1;
                returns.push_back(burst);
                if (checking) begin
                    want_addr = expected_base + read_row*expected_stride + read_beats*32;
                    want_beats = (expected_width*2+31)/32-read_beats;
                    if (want_beats > 16) want_beats = 16;
                    if (want_beats > (4096-(want_addr%4096))/32)
                        want_beats = (4096-(want_addr%4096))/32;
                    if (arid || int'(araddr) != want_addr || int'(arlen)+1 != want_beats)
                        $fatal(1,"FAIL AR want=%h/%0d got=%h/%0d",want_addr,want_beats,
                            araddr,int'(arlen)+1);
                    read_beats += want_beats;
                    if (read_beats == (expected_width*2+31)/32) begin
                        read_beats = 0;
                        read_row++;
                    end
                end
            end
            if (rvalid && rready) begin
                return_pos++;
                if (rlast) begin
                    burst = returns.pop_front();
                    return_pos = 0;
                end
            end
            if (valid && ready && checking) begin
                words_per_row = expected_width/2;
                row = outputs/words_per_row;
                word_no = outputs%words_per_row;
                want = pattern(expected_base + row*expected_stride + word_no*4);
                if (data !== want || sof !== (outputs == 0) ||
                    eol !== (word_no == words_per_row-1) ||
                    eof !== (outputs == words_per_row*expected_height-1) ||
                    frame_id !== 32'(expected_id))
                    $fatal(1,"FAIL pixel n=%0d want=%h got=%h flags=%b%b%b id=%0d",
                        outputs,want,data,sof,eol,eof,frame_id);
                outputs++;
            end
        end
    end
    task automatic launch;
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
    endtask
    task automatic idle;
        do @(negedge clk); while (busy);
        repeat (3) @(negedge clk);
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        launch();
        // Let the input buffer fill while output is stalled; START while busy is ignored.
        repeat (1000) @(negedge clk);
        if (done_count != 0 || read_row > 3) $fatal(1,"FAIL reserved row capacity");
        launch();
        base = 'h20000;
        width = 18;
        height = 3;
        stride = 64;
        ready = 1;
        idle();
        if (outputs != 5120 || done_count != 1 || frame_count != 1)
            $fatal(1,"FAIL first frame outputs=%0d done=%0d",outputs,done_count);
        expected_base = int'(base);
        expected_width = int'(width);
        expected_height = int'(height);
        expected_stride = int'(stride);
        expected_id = 1;
        read_row = 0;
        read_beats = 0;
        outputs = 0;
        read_error = 1;
        launch();
        idle();
        if (outputs != 27 || done_count != 2 || frame_count != 2 || error_count != 3)
            $fatal(1,"FAIL tail/error outputs=%0d done=%0d errors=%0d",
                outputs,done_count,error_count);
        read_error = 0;
        width = 0;
        launch();
        repeat (3) @(negedge clk);
        if (busy || cfg_count != 1) $fatal(1,"FAIL invalid memory size");
        width = 1280;
        height = 8;
        checking = 0;
        hold_returns = 1;
        launch();
        repeat (20) @(negedge clk);
        abort_request = 1;
        @(negedge clk);
        abort_request = 0;
        hold_returns = 0;
        idle();
        if (returns.size() != 0 || done_count != 2)
            $fatal(1,"FAIL ABORT left reads or signaled done");
        $display("PASS vin_msrc");
        $finish;
    end
    initial begin #10000000; $fatal(1,"FAIL timeout"); end
endmodule
