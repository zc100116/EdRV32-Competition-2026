// File: edrv32_sync_fifo.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Synchronous ready/valid FIFO with unreset storage.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_sync_fifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Producer input.
    input wire valid_i,
    output wire ready_o,
    input wire [WIDTH-1:0] data_i,

    // Consumer output.
    output wire valid_o,
    input wire ready_i,
    output wire [WIDTH-1:0] data_o
);
    localparam PTR_WIDTH = $clog2(DEPTH);
    localparam [PTR_WIDTH:0] DEPTH_COUNT = DEPTH[PTR_WIDTH:0];
    reg [WIDTH-1:0] memory_r [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] write_ptr_r;
    reg [PTR_WIDTH-1:0] read_ptr_r;
    reg [PTR_WIDTH:0] count_r;
    wire write_w;
    wire read_w;

    assign ready_o = (count_r != DEPTH_COUNT);
    assign valid_o = (count_r != 0);
    assign data_o = memory_r[read_ptr_r];
    assign write_w = valid_i && ready_o;
    assign read_w = valid_o && ready_i;

    always @(posedge clk_i) begin
        if (write_w) begin
            memory_r[write_ptr_r] <= data_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_ptr_r <= {PTR_WIDTH{1'b0}};
            read_ptr_r <= {PTR_WIDTH{1'b0}};
            count_r <= {(PTR_WIDTH+1){1'b0}};
        end else begin
            if (write_w) begin
                write_ptr_r <= write_ptr_r + 1'b1;
            end
            if (read_w) begin
                read_ptr_r <= read_ptr_r + 1'b1;
            end
            case ({write_w, read_w})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: count_r <= count_r;
            endcase
        end
    end
endmodule
