`timescale 1ns/1ps
`include "edrv32_uop.vh"
module tb_if2_dual_missing;
    localparam [31:0] BASE=32'h80000000;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg block_valid=0;
    wire block_ready;
    reg [31:0] block_addr,block_data;
    reg block_error;
    reg [1:0] block_epoch;
    reg ready=0,second_ready=0;
    reg redirect=0;
    reg [31:0] redirect_target=BASE;
    reg [1:0] redirect_epoch=0;
    wire first_valid,second_window_valid,first_accept,second_accept;
    wire valid,second_valid;
    wire [2:0] consume_halfwords;
    wire [15:0] halfword0;
    wire [15:0] second_halfword0;
    wire [15:0] halfword1;
    wire [15:0] second_halfword1;
    wire  halfword1_valid;
    wire  second_halfword1_valid;
    wire [31:0] pc;
    wire [31:0] second_pc;
    wire  halfword0_error;
    wire  second_halfword0_error;
    wire  halfword1_error;
    wire  second_halfword1_error;
    wire [`EDRV32_EPOCH_W-1:0] epoch;
    wire [`EDRV32_EPOCH_W-1:0] second_epoch;
    wire  predicted_taken;
    wire  second_predicted_taken;
    wire [31:0] predicted_target;
    wire [31:0] second_predicted_target;
    wire [1:0] predictor_meta;
    wire [1:0] second_predictor_meta;
    wire [31:0] out_pc;
    wire [31:0] out_second_pc;
    wire [31:0] out_instr;
    wire [31:0] out_second_instr;
    wire [31:0] out_raw_instr;
    wire [31:0] out_second_raw_instr;
    wire  out_is_compressed;
    wire  out_second_is_compressed;
    wire  out_fetch_fault;
    wire  out_second_fetch_fault;
    wire  out_compressed_illegal;
    wire  out_second_compressed_illegal;
    wire [`EDRV32_EPOCH_W-1:0] out_epoch;
    wire [`EDRV32_EPOCH_W-1:0] out_second_epoch;
    wire  out_predicted_taken;
    wire  out_second_predicted_taken;
    wire [31:0] out_predicted_target;
    wire [31:0] out_second_predicted_target;
    wire [1:0] out_predictor_meta;
    wire [1:0] out_second_predictor_meta;
    edrv32_if2_stage #(.RESET_PC(BASE),.DUAL_WINDOW(1)) u_if2 (
        .clk_i(clk),.rst_n_i(rst_n),
        .block_valid_i(block_valid),.block_ready_o(block_ready),
        .block_addr_i(block_addr),.block_data_i(block_data),
        .block_error_i(block_error),.block_epoch_i(block_epoch),
        .block_predicted_taken0_i(1'b0),.block_predicted_target0_i(block_addr+32'h80),
        .block_predictor_meta0_i(block_addr[3:2]),
        .block_predicted_taken1_i(1'b0),.block_predicted_target1_i(block_addr+32'h82),
        .block_predictor_meta1_i(~block_addr[3:2]),
        .preview_valid_i(1'b0),.preview_addr_i(32'd0),.preview_epoch_i(2'd0),
        .preview_target0_i(32'd0),.preview_target1_i(32'd0),
        .window_valid_o(first_valid),.window_ready_i(first_accept),
        .second_window_valid_o(second_window_valid),.second_window_accept_i(second_accept),
        .halfword0_o(halfword0),.second_halfword0_o(second_halfword0),
        .halfword1_o(halfword1),.second_halfword1_o(second_halfword1),
        .halfword1_valid_o(halfword1_valid),.second_halfword1_valid_o(second_halfword1_valid),
        .window_pc_o(pc),.second_window_pc_o(second_pc),
        .halfword0_error_o(halfword0_error),.second_halfword0_error_o(second_halfword0_error),
        .halfword1_error_o(halfword1_error),.second_halfword1_error_o(second_halfword1_error),
        .window_epoch_o(epoch),.second_window_epoch_o(second_epoch),
        .window_predicted_taken_o(predicted_taken),.second_window_predicted_taken_o(second_predicted_taken),
        .window_predicted_target_o(predicted_target),.second_window_predicted_target_o(second_predicted_target),
        .window_predictor_meta_o(predictor_meta),.second_window_predictor_meta_o(second_predictor_meta),
        .prediction_redirect_valid_o(),.prediction_redirect_target_o(),
        .prediction_redirect_fast_o(),.prediction_redirect_fast_slot1_o(),
        .prediction_redirect_fire_i(1'b0),.prediction_redirect_epoch_i(2'd0),
        .hpm_consume_halfwords_o(consume_halfwords),
        .redirect_fire_i(redirect),.redirect_target_i(redirect_target),
        .redirect_epoch_i(redirect_epoch),.kill_i(redirect)
    );
    assign first_accept=ready;
    assign second_accept=second_ready;
    task automatic send;
        input [31:0] address,data;
        begin
            @(negedge clk);block_valid=1;block_addr=address;block_data=data;
            do @(posedge clk);while(!block_ready);
            @(negedge clk);block_valid=0;
        end
    endtask
    always @(posedge clk)if(rst_n)begin
        if(^{u_if2.window_count_r,u_if2.count_r,u_if2.consume_pc_r,
             u_if2.second_capture_w,u_if2.candidate_accept_w,block_ready}===1'bx)
            $fatal(1,"invalid B payload contaminated IF2 control");
    end
    initial begin
        block_addr=BASE;block_data=0;block_error=0;block_epoch=0;
        repeat(3)@(negedge clk);rst_n=1;
        send(BASE,32'h00010001);send(BASE+4,32'h00010001);
        if(u_if2.window_count_r!==4||u_if2.count_r!==0)$fatal(1,"window fill failed");
        // Direct ingress is full. Only two FIFO locations are written here.
        send(BASE+8,32'h00100093);
        if(u_if2.count_r!==2)$fatal(1,"single 32-bit FIFO ingress failed");
        ready=1;second_ready=1;
        @(posedge clk);@(negedge clk);
        if(u_if2.window_count_r!==2||u_if2.count_r!==2)$fatal(1,"local capacity setup failed");
        if(u_if2.candidate_accept_w!==1||u_if2.second_capture_w!==0||consume_halfwords!==2)
            $fatal(1,"missing B was treated as a second instruction");
        @(posedge clk);@(negedge clk);
        if(u_if2.window_count_r!==1||u_if2.count_r!==0||pc!==BASE+8||halfword0!==16'h0093||halfword1!==16'h0010)
            $fatal(1,"single instruction capture corrupted window/FIFO state");
        @(posedge clk);@(negedge clk);
        if(first_valid!==0||second_window_valid!==0)$fatal(1,"ghost window after drain");
        $display("PASS: IF2 absent B with uninitialized FIFO payload stays single capture");$finish;
    end
endmodule
