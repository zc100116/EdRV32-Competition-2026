// File: edrv32_apb_async_bridge.v
// Spec: sys-subsys-spec 2.3, 3.2, 5.
// Description: One outstanding APB transfer; CDC request and response use common handshakes.
//              Held request and response payloads cross through common CDC primitives.
// Clock domain: clk_s_i and clk_m_i.
module edrv32_apb_async_bridge (
    // Source and destination clocks and resets.
    input wire clk_s_i,
    input wire rst_s_n_i,
    input wire clk_m_i,
    input wire rst_m_n_i,

    // s_apb interface.
    input wire [15:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire [31:0] s_apb_prdata_o,
    output wire s_apb_pready_o,
    output wire s_apb_pslverr_o,

    // m_apb interface.
    output wire [15:0] m_apb_paddr_o,
    output wire m_apb_psel_o,
    output wire m_apb_penable_o,
    output wire m_apb_pwrite_o,
    output wire [31:0] m_apb_pwdata_o,
    output wire [3:0] m_apb_pstrb_o,
    input wire [31:0] m_apb_prdata_i,
    input wire m_apb_pready_i,
    input wire m_apb_pslverr_i
);
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_WAIT = 2'd1;
    localparam [1:0] S_DONE = 2'd2;
    localparam [1:0] S_MASTER_IDLE = 2'd0;
    localparam [1:0] S_MASTER_SETUP = 2'd1;
    localparam [1:0] S_MASTER_ACCESS = 2'd2;
    localparam [1:0] S_MASTER_RESP = 2'd3;
    reg [1:0] source_state_r;
    reg [1:0] master_state_r;
    reg [52:0] request_r;
    reg [32:0] response_r;
    reg [32:0] source_response_r;
    wire request_ready_w;
    wire request_valid_w;
    wire [52:0] request_w;
    wire response_ready_w;
    wire response_valid_w;
    wire [32:0] response_w;
    wire request_send_w;

    assign request_send_w = (source_state_r == S_IDLE) && s_apb_psel_i && s_apb_penable_i;
    assign s_apb_pready_o = (source_state_r == S_DONE);
    assign s_apb_prdata_o = source_response_r[31:0];
    assign s_apb_pslverr_o = source_response_r[32];
    assign m_apb_psel_o = (master_state_r == S_MASTER_SETUP) || (master_state_r == S_MASTER_ACCESS);
    assign m_apb_penable_o = (master_state_r == S_MASTER_ACCESS);
    assign {m_apb_pwrite_o, m_apb_paddr_o, m_apb_pwdata_o, m_apb_pstrb_o} = request_r;

    always @(posedge clk_s_i or negedge rst_s_n_i) begin
        if (!rst_s_n_i) begin
            source_state_r <= S_IDLE;
        end else begin
            case (source_state_r)
                S_IDLE: begin
                    if (request_send_w && request_ready_w) begin
                        source_state_r <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (response_valid_w) begin
                        source_state_r <= S_DONE;
                    end
                end
                S_DONE: begin
                    source_state_r <= S_IDLE;
                end
                default: begin
                    source_state_r <= S_IDLE;
                end
            endcase
        end
    end
    always @(posedge clk_s_i) begin
        if ((source_state_r == S_WAIT) && response_valid_w) begin
            source_response_r <= response_w;
        end
    end

    always @(posedge clk_m_i or negedge rst_m_n_i) begin
        if (!rst_m_n_i) begin
            master_state_r <= S_MASTER_IDLE;
        end else begin
            case (master_state_r)
                S_MASTER_IDLE: begin
                    if (request_valid_w) begin
                        master_state_r <= S_MASTER_SETUP;
                    end
                end
                S_MASTER_SETUP: begin
                    master_state_r <= S_MASTER_ACCESS;
                end
                S_MASTER_ACCESS: begin
                    if (m_apb_pready_i) begin
                        master_state_r <= S_MASTER_RESP;
                    end
                end
                S_MASTER_RESP: begin
                    if (response_ready_w) begin
                        master_state_r <= S_MASTER_IDLE;
                    end
                end
                default: begin
                    master_state_r <= S_MASTER_IDLE;
                end
            endcase
        end
    end
    always @(posedge clk_m_i) begin
        if ((master_state_r == S_MASTER_IDLE) && request_valid_w) begin
            request_r <= request_w;
        end
        if ((master_state_r == S_MASTER_ACCESS) && m_apb_pready_i) begin
            response_r <= {m_apb_pslverr_i, m_apb_prdata_i};
        end
    end

    edrv32_cdc_handshake #(
        .WIDTH(53)
    ) u_request (
        // Held request payload, clk_sys to clk_mem.
        .clk_src_i(clk_s_i),
        .rst_src_n_i(rst_s_n_i),
        .clk_dst_i(clk_m_i),
        .rst_dst_n_i(rst_m_n_i),
        .valid_i(request_send_w),
        .ready_o(request_ready_w),
        .data_i({s_apb_pwrite_i, s_apb_paddr_i, s_apb_pwdata_i, s_apb_pstrb_i}),
        .valid_o(request_valid_w),
        .ready_i(master_state_r == S_MASTER_IDLE),
        .data_o(request_w)
    );
    edrv32_cdc_handshake #(
        .WIDTH(33)
    ) u_response (
        // Held response payload, clk_mem to clk_sys.
        .clk_src_i(clk_m_i),
        .rst_src_n_i(rst_m_n_i),
        .clk_dst_i(clk_s_i),
        .rst_dst_n_i(rst_s_n_i),
        .valid_i(master_state_r == S_MASTER_RESP),
        .ready_o(response_ready_w),
        .data_i(response_r),
        .valid_o(response_valid_w),
        .ready_i(source_state_r == S_WAIT),
        .data_o(response_w)
    );
endmodule
