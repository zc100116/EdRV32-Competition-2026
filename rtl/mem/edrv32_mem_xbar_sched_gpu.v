// File: edrv32_mem_xbar_sched_gpu.v
// Spec: gpu-soc-spec 6.2, 8.3.
// Description: Registered eligibility, urgent P0/P1, CPU, then P0/P1/P3/P4 round robin.
//              Each port alternates direction when both read and write are eligible.
// Clock: clk_mem.
module edrv32_mem_xbar_sched_gpu (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Capacity and credit masks precede transaction selection.
    input wire enable_i,
    input wire [9:0] candidates_i,
    output wire prepare_o,
    input wire [9:0] eligible_i,
    input wire [1:0] urgent_i,
    output reg grant_o,
    output reg [2:0] port_o,
    output reg write_o
);
    reg prepared_r;
    reg [1:0] urgent_r;
    reg [1:0] next_r;
    reg [4:0] last_write_r;
    wire [3:0] ready_w;
    reg [1:0] choice_w;
    reg rotate_w;
    assign prepare_o = enable_i && !prepared_r;
    assign ready_w = {|eligible_i[9:8], |eligible_i[7:6],
        |eligible_i[3:2], |eligible_i[1:0]};

    // Four ports: explicit cyclic priority masks, one transaction per rotating grant.
    always @(*) begin
        choice_w = next_r;
        case (next_r)
            2'd0: begin
                if (ready_w[0]) choice_w = 2'd0;
                else if (ready_w[1]) choice_w = 2'd1;
                else if (ready_w[2]) choice_w = 2'd2;
                else if (ready_w[3]) choice_w = 2'd3;
            end
            2'd1: begin
                if (ready_w[1]) choice_w = 2'd1;
                else if (ready_w[2]) choice_w = 2'd2;
                else if (ready_w[3]) choice_w = 2'd3;
                else if (ready_w[0]) choice_w = 2'd0;
            end
            2'd2: begin
                if (ready_w[2]) choice_w = 2'd2;
                else if (ready_w[3]) choice_w = 2'd3;
                else if (ready_w[0]) choice_w = 2'd0;
                else if (ready_w[1]) choice_w = 2'd1;
            end
            default: begin
                if (ready_w[3]) choice_w = 2'd3;
                else if (ready_w[0]) choice_w = 2'd0;
                else if (ready_w[1]) choice_w = 2'd1;
                else if (ready_w[2]) choice_w = 2'd2;
            end
        endcase
    end
    always @(*) begin
        grant_o = 1'b0;
        port_o = 3'd0;
        write_o = 1'b0;
        rotate_w = 1'b0;
        if (enable_i && prepared_r) begin
            if (urgent_r[0] && ready_w[0]) begin
                grant_o = 1'b1;
                port_o = 3'd0;
            end else if (urgent_r[1] && ready_w[1]) begin
                grant_o = 1'b1;
                port_o = 3'd1;
            end else if (|eligible_i[5:4]) begin
                grant_o = 1'b1;
                port_o = 3'd2;
            end else if (|ready_w) begin
                grant_o = 1'b1;
                rotate_w = 1'b1;
                case (choice_w)
                    2'd0: port_o = 3'd0;
                    2'd1: port_o = 3'd1;
                    2'd2: port_o = 3'd3;
                    default: port_o = 3'd4;
                endcase
            end
            write_o = eligible_i[{port_o, 1'b1}] &&
                (!eligible_i[{port_o, 1'b0}] || !last_write_r[port_o]);
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            prepared_r <= 1'b0;
            urgent_r <= 2'b0;
            next_r <= 2'd0;
            last_write_r <= 5'b11111;
        end else begin
            prepared_r <= prepare_o && |candidates_i;
            if (prepare_o) urgent_r <= urgent_i;
            if (grant_o) last_write_r[port_o] <= write_o;
            if (grant_o && rotate_w) next_r <= choice_w + 2'd1;
        end
    end
endmodule
