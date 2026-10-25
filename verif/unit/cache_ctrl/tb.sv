// File: cache_ctrl/tb.sv
// Spec: cache-spec; cache-testplan 2.2.
// Description: Self-checking directed cache unit tests.
// Clock domain: clk_sys (PMA is combinational).
module tb;
    logic [31:0] apb_prdata_o;
    logic maint_req_valid_o;
    logic [2:0] maint_cmd_o;
    logic [31:0] maint_addr_o;
    logic [31:0] maint_size_o;

    logic clk_i = 0;
    logic rst_n_i = 0;
    logic [11:0] apb_paddr_i = 0;
    logic apb_psel_i = 0;
    logic apb_penable_i = 0;
    logic apb_pwrite_i = 0;
    logic [31:0] apb_pwdata_i = 0;
    logic [3:0] apb_pstrb_i = 0;
    logic apb_pready_o;
    logic apb_pslverr_o;
    logic maint_req_ready_i = 0;
    logic maint_busy_i = 0;
    logic wb_err_i = 0;
    logic [31:0] wb_err_addr_i = 0;
    logic irq_o;
    always #5 clk_i = ~clk_i;
    edrv32_cache_ctrl dut (
        .apb_prdata_o(apb_prdata_o),
        .maint_req_valid_o(maint_req_valid_o),
        .maint_cmd_o(maint_cmd_o),
        .maint_addr_o(maint_addr_o),
        .maint_size_o(maint_size_o),

        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_pslverr_o(apb_pslverr_o),
        .maint_req_ready_i(maint_req_ready_i),
        .maint_busy_i(maint_busy_i),
        .wb_err_i(wb_err_i),
        .wb_err_addr_i(wb_err_addr_i),
        .irq_o(irq_o)
    );
    task automatic tick;
        @(posedge clk_i); #1;
    endtask
    task automatic step;
        @(negedge clk_i); #1;
    endtask
    initial begin
        #200000;
        $fatal(1, "FAIL timeout");
    end
    task automatic read_check(input logic [11:0] addr, input logic [31:0] expected);
        step(); apb_paddr_i = addr; apb_psel_i = 1; apb_penable_i = 1;
        apb_pwrite_i = 0; #1;
        if (apb_prdata_o !== expected || !apb_pready_o || apb_pslverr_o)
            $fatal(1, "FAIL ctrl %h expected %h got %h", addr, expected, apb_prdata_o);
        tick(); step(); apb_psel_i = 0; apb_penable_i = 0;
    endtask
    task automatic write_reg(input logic [11:0] addr, input logic [31:0] data,
                             input logic [3:0] mask = 4'hf);
        step(); apb_paddr_i = addr; apb_pwdata_i = data; apb_pstrb_i = mask;
        apb_psel_i = 1; apb_penable_i = 1; apb_pwrite_i = 1;
        tick(); step(); apb_psel_i = 0; apb_penable_i = 0;
    endtask
    initial begin
        tick(); step(); rst_n_i = 1;
        read_check(12'h000, 32'h00050001);
        read_check(12'h008, 0); read_check(12'h00c, 0); read_check(12'h010, 0);
        read_check(12'h014, 0); read_check(12'h020, 0); read_check(12'h024, 0);
        read_check(12'h028, 0); read_check(12'h004, 0); read_check(12'hffc, 0);
        write_reg(12'h000, 32'hffffffff); read_check(12'h000, 32'h00050001);
        write_reg(12'h004, 32'hffffffff); read_check(12'h004, 0);
        write_reg(12'h020, 32'h10000003); write_reg(12'h024, 32'h41);
        read_check(12'h020, 32'h10000003); read_check(12'h024, 32'h41);
        write_reg(12'h020, 32'h00005500, 4'b0010); read_check(12'h020, 32'h10005503);
        write_reg(12'h028, 5);
        if (maint_req_valid_o) $fatal(1, "FAIL invalid command");
        write_reg(12'h028, 3);
        if (!maint_req_valid_o || maint_cmd_o != 3 || maint_addr_o != 32'h10005503 ||
            maint_size_o != 32'h41) $fatal(1, "FAIL command snapshot");
        read_check(12'h008, 1);
        write_reg(12'h028, 1);
        if (maint_cmd_o != 3) $fatal(1, "FAIL pending busy command");
        step(); maint_req_ready_i = 1; maint_busy_i = 1; tick();
        step(); maint_req_ready_i = 0;
        write_reg(12'h028, 4);
        if (maint_req_valid_o) $fatal(1, "FAIL busy command");
        read_check(12'h008, 1);
        step(); maint_busy_i = 0; wb_err_i = 1; wb_err_addr_i = 32'h80000120;
        tick(); step(); wb_err_i = 0;
        read_check(12'h010, 2); read_check(12'h014, 32'h80000120);
        if (irq_o) $fatal(1, "FAIL disabled irq");
        write_reg(12'h00c, 32'hffffffff); read_check(12'h00c, 2);
        if (!irq_o) $fatal(1, "FAIL enabled irq");
        write_reg(12'h010, 1); read_check(12'h010, 2);
        write_reg(12'h010, 2); read_check(12'h010, 0);
        if (irq_o) $fatal(1, "FAIL cleared irq");
        // A newly arriving error wins over software clearing the old status.
        step(); apb_paddr_i = 12'h010; apb_pwdata_i = 2; apb_pstrb_i = 4'hf;
        apb_psel_i = 1; apb_penable_i = 1; apb_pwrite_i = 1;
        wb_err_i = 1; wb_err_addr_i = 32'h800003e0;
        tick(); step(); apb_psel_i = 0; apb_penable_i = 0; wb_err_i = 0;
        read_check(12'h010, 2); read_check(12'h014, 32'h800003e0);
        if (!irq_o) $fatal(1, "FAIL concurrent new error must win RW1C");
        write_reg(12'h010, 2); read_check(12'h010, 0);
        for (int cmd = 1; cmd <= 4; cmd++) begin
            write_reg(12'h028, 32'(cmd));
            if (!maint_req_valid_o || maint_cmd_o != 3'(cmd)) $fatal(1, "FAIL cmd");
            step(); maint_req_ready_i = 1; tick(); step(); maint_req_ready_i = 0;
        end
        $display("PASS cache_ctrl"); $finish;
    end
endmodule
