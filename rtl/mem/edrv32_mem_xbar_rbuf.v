// File: edrv32_mem_xbar_rbuf.v
// Spec: mem-subsys-spec 2.2; edrv32-soc-spec 6.4.4; task M-R2b.
// Description: 128-beat DRM ring with eight ordered transaction descriptors.
// DDR returns locate the oldest unfinished descriptor of that ID. Each port sends
// in grant order; ring space retires in global grant order after upstream consumption.
// Illegal reads reserve ring space too and synthesize SLVERR without writing DRM.
// Clock: clk_mem.
module edrv32_mem_xbar_rbuf (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Reservation from the scheduler.
    input wire reserve_i,
    input wire [2:0] reserve_port_i,
    input wire reserve_id_i,
    input wire [4:0] reserve_beats_i,
    input wire reserve_error_i,
    output reg [7:0] free_cnt_o,
    output wire slot_ready_o,

    // DDR return channel has no backpressure.
    input wire [3:0] ddr_rid_i,
    input wire [255:0] ddr_rdata_i,
    input wire [1:0] ddr_rresp_i,
    input wire ddr_rlast_i,
    input wire ddr_rvalid_i,

    // Upstream read channels, little-endian port slices.
    output wire [6:0] rid_o,
    output wire [1791:0] rdata_o,
    output wire [13:0] rresp_o,
    output wire [6:0] rlast_o,
    output wire [6:0] rvalid_o,
    input wire [6:0] rready_i
);
    reg [7:0] valid_r;
    reg [7:0] error_r;
    // ID already encodes both port and local ID; no duplicate tag fields are stored.
    reg [3:0] id_r [0:7];
    reg [6:0] start_r [0:7];
    reg [4:0] length_r [0:7];
    reg [4:0] received_r [0:7];
    reg [4:0] fetched_r [0:7];
    reg [4:0] sent_r [0:7];
    reg [2:0] head_r;
    reg [2:0] tail_r;
    reg [3:0] count_r;
    reg [6:0] write_ptr_r;
    reg [6:0] read_mask_r;
    reg [6:0] port_active_r;
    reg [2:0] port_head_r [0:6];
    reg [4:0] port_available_r [0:6];
    reg [6:0] port_addr_r [0:6];
    wire [6:0] last_take_w;
    wire pending_r;
    reg [6:0] pending_valid_r;
    reg [2:0] pending_slot_r;
    reg [2:0] pending_port_r;
    reg pending_id_r;
    reg pending_error_r;
    reg pending_last_r;
    reg [6:0] skid_valid_r;
    reg [2:0] skid_slot_r [0:6];
    reg [258:0] skid_data_r [0:6];
    reg [6:0] skid_id_r;
    wire release_w;
    wire [258:0] ram_data_w;
    wire [258:0] pending_data_w;
    wire [6:0] take_w;
    reg [7:0] return_match_w;
    reg [2:0] return_slot_w;
    wire [6:0] return_addr_w;
    reg [7:0] port_match_w [0:6];
    reg [2:0] port_slot_w [0:6];
    reg [6:0] ready_ports_w;
    reg [7:0] sent_take_w;
    integer take_port;
    reg fetch_w;
    reg [2:0] fetch_port_w;
    reg [2:0] fetch_slot_w;
    reg [6:0] fetch_addr_w;
    wire [6:0] preferred_ports_w;
    wire [6:0] fetch_select_w;
    integer match_idx;
    integer match_port;
    integer state_idx;
    integer skid_idx;
    genvar p;

    function [2:0] first8;
        input [7:0] mask_i;
        input [2:0] turn_i;
        reg [7:0] after_turn_w;
        reg [7:0] choice_w;
        begin
            after_turn_w = mask_i & (8'hff << turn_i);
            choice_w = |after_turn_w ? after_turn_w : mask_i;
            if (choice_w[0]) first8 = 3'd0;
            else if (choice_w[1]) first8 = 3'd1;
            else if (choice_w[2]) first8 = 3'd2;
            else if (choice_w[3]) first8 = 3'd3;
            else if (choice_w[4]) first8 = 3'd4;
            else if (choice_w[5]) first8 = 3'd5;
            else if (choice_w[6]) first8 = 3'd6;
            else first8 = choice_w[7] ? 3'd7 : 3'd0;
        end
    endfunction

    assign pending_r = |pending_valid_r;
    // mem-subsys 6: illegal beats override response/last; payload is unspecified.
    assign pending_data_w = {pending_error_r ? pending_last_r : ram_data_w[258],
        pending_error_r ? 2'b10 : ram_data_w[257:256], ram_data_w[255:0]};
    assign slot_ready_o = count_r < 4'd8;
    assign release_w = valid_r[head_r] && sent_r[head_r] == length_r[head_r];
    assign return_addr_w = start_r[return_slot_w] + {2'b0, received_r[return_slot_w]};
    // X-F1 path 1: advance each descriptor address before arbitration, not after it.
    assign preferred_ports_w = ready_ports_w & read_mask_r;
    assign fetch_select_w[0] = ready_ports_w[0] &&
        (read_mask_r[0] || !(|preferred_ports_w));
    generate
        for (p = 1; p < 7; p = p + 1) begin : g_fetch_select
            assign fetch_select_w[p] = ready_ports_w[p] &&
                ((read_mask_r[p] && !(|preferred_ports_w[p-1:0])) ||
                    (!(|preferred_ports_w) && !(|ready_ports_w[p-1:0])));
        end
    endgenerate
    assign take_w = rvalid_o & rready_i;
    assign last_take_w = take_w & rlast_o;

    edrv32_ram_mem_xbar_r u_ram (
        .clk_i(clk_i),
        .wr_en_i(ddr_rvalid_i),
        .wr_addr_i(return_addr_w),
        .wr_data_i({ddr_rlast_i, ddr_rresp_i, ddr_rdata_i}),
        .rd_en_i(fetch_w && !error_r[fetch_slot_w]),
        .rd_addr_i(fetch_addr_w),
        .rd_data_o(ram_data_w)
    );

    generate
        for (p = 0; p < 7; p = p + 1) begin : g_output
            wire [258:0] data_w;
            assign data_w = skid_valid_r[p] ? skid_data_r[p] : pending_data_w;
            assign rvalid_o[p] = skid_valid_r[p] || pending_valid_r[p];
            assign rid_o[p] = skid_valid_r[p] ? skid_id_r[p] : pending_id_r;
            assign rdata_o[p*256 +: 256] = data_w[255:0];
            assign rresp_o[p*2 +: 2] = data_w[257:256];
            assign rlast_o[p] = data_w[258];
        end
    endgenerate

    always @(*) begin
        sent_take_w = 8'b0;
        for (take_port = 0; take_port < 7; take_port = take_port + 1) begin
            if (take_w[take_port]) begin
                sent_take_w[skid_valid_r[take_port] ? skid_slot_r[take_port] :
                    pending_slot_r] = 1'b1;
            end
        end
        return_match_w = 8'b0;
        return_slot_w = 3'b0;
        ready_ports_w = 7'b0;
        fetch_w = 1'b0;
        fetch_port_w = 3'b0;
        fetch_slot_w = 3'b0;
        fetch_addr_w = 7'b0;
        for (match_port = 0; match_port < 7; match_port = match_port + 1) begin
            port_match_w[match_port] = 8'b0;
            port_slot_w[match_port] = 3'b0;
        end
        for (match_idx = 0; match_idx < 8; match_idx = match_idx + 1) begin
            return_match_w[match_idx] = valid_r[match_idx] && !error_r[match_idx] &&
                id_r[match_idx] == ddr_rid_i && received_r[match_idx] < length_r[match_idx];
            for (match_port = 0; match_port < 7; match_port = match_port + 1) begin
                port_match_w[match_port][match_idx] = valid_r[match_idx] &&
                    {29'b0, id_r[match_idx][3:1]} == match_port &&
                    sent_r[match_idx] < length_r[match_idx] &&
                    match_idx[2:0] != port_head_r[match_port];
            end
        end
        return_slot_w = first8(return_match_w, head_r);
        for (match_port = 0; match_port < 7; match_port = match_port + 1) begin
            port_slot_w[match_port] = first8(port_match_w[match_port], head_r);
            ready_ports_w[match_port] = port_active_r[match_port] &&
                port_available_r[match_port] != 0 &&
                (!rvalid_o[match_port] || rready_i[match_port]);
        end
        fetch_w = |ready_ports_w;
        // One-hot selection keeps the RAM address off the encoded port/descriptor mux chain.
        for (match_port = 0; match_port < 7; match_port = match_port + 1) begin
            fetch_port_w = fetch_port_w | (match_port[2:0] & {3{fetch_select_w[match_port]}});
            fetch_addr_w = fetch_addr_w | (port_addr_r[match_port] &
                {7{fetch_select_w[match_port]}});
        end
        fetch_slot_w = port_head_r[fetch_port_w];
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 8'b0;
            head_r <= 3'b0;
            tail_r <= 3'b0;
            count_r <= 4'b0;
            write_ptr_r <= 7'b0;
            free_cnt_o <= 8'd128;
            read_mask_r <= 7'h7f;
            pending_valid_r <= 7'b0;
            skid_valid_r <= 7'b0;
            port_active_r <= 7'b0;
            for (skid_idx = 0; skid_idx < 7; skid_idx = skid_idx + 1) begin
                port_head_r[skid_idx] <= 3'b0;
                port_available_r[skid_idx] <= 5'b0;
            end
        end else begin
            count_r <= count_r + (reserve_i ? 4'd1 : 4'd0) - (release_w ? 4'd1 : 4'd0);
            free_cnt_o <= free_cnt_o - (reserve_i ? {3'b0, reserve_beats_i} : 8'b0) +
                (release_w ? {3'b0, length_r[head_r]} : 8'b0);
            if (release_w) begin
                valid_r[head_r] <= 1'b0;
                head_r <= head_r + 3'd1;
            end
            if (reserve_i) begin
                valid_r[tail_r] <= 1'b1;
                tail_r <= tail_r + 3'd1;
                write_ptr_r <= write_ptr_r + {2'b0, reserve_beats_i};
            end
            pending_valid_r <= fetch_select_w;
            for (skid_idx = 0; skid_idx < 7; skid_idx = skid_idx + 1) begin
                if (fetch_select_w[skid_idx]) begin
                    read_mask_r <= skid_idx == 6 ? 7'h7f : (7'h7f << (skid_idx + 1));
                end
                // X-F1 path 1: keep the head's available-beat count before arbitration.
                port_available_r[skid_idx] <= port_available_r[skid_idx] +
                    ((ddr_rvalid_i && ddr_rid_i[3:1] == skid_idx[2:0] &&
                        return_slot_w == port_head_r[skid_idx]) ?
                        5'd1 : 5'd0) -
                    ((fetch_w && fetch_port_w == skid_idx[2:0]) ? 5'd1 : 5'd0);
                if (last_take_w[skid_idx]) begin
                    port_active_r[skid_idx] <= |port_match_w[skid_idx];
                    port_head_r[skid_idx] <= port_slot_w[skid_idx];
                    port_available_r[skid_idx] <= received_r[port_slot_w[skid_idx]] +
                        ((ddr_rvalid_i && return_slot_w == port_slot_w[skid_idx]) ?
                            5'd1 : 5'd0);
                end
                if (reserve_i && reserve_port_i == skid_idx[2:0] &&
                    (!port_active_r[skid_idx] ||
                        (last_take_w[skid_idx] && port_match_w[skid_idx] == 0))) begin
                    port_active_r[skid_idx] <= 1'b1;
                    port_head_r[skid_idx] <= tail_r;
                    port_available_r[skid_idx] <= reserve_error_i ? reserve_beats_i : 5'b0;
                end
                if (take_w[skid_idx]) begin
                    skid_valid_r[skid_idx] <= 1'b0;
                end
                if (pending_valid_r[skid_idx] && !rready_i[skid_idx])
                begin
                    skid_valid_r[skid_idx] <= 1'b1;
                end
            end
        end
    end

    // Table payload and per-descriptor progress are initialized on allocation only.
    always @(posedge clk_i) begin
        for (state_idx = 0; state_idx < 8; state_idx = state_idx + 1) begin
            if (ddr_rvalid_i && {29'b0, return_slot_w} == state_idx) begin
                received_r[state_idx] <= received_r[state_idx] + 5'd1;
            end
            if (fetch_w && {29'b0, fetch_slot_w} == state_idx) begin
                fetched_r[state_idx] <= fetched_r[state_idx] + 5'd1;
            end
            if (sent_take_w[state_idx]) sent_r[state_idx] <= sent_r[state_idx] + 5'd1;
            if (reserve_i && {29'b0, tail_r} == state_idx) begin
                error_r[state_idx] <= reserve_error_i;
                id_r[state_idx] <= {reserve_port_i, reserve_id_i};
                start_r[state_idx] <= write_ptr_r;
                length_r[state_idx] <= reserve_beats_i;
                received_r[state_idx] <= reserve_error_i ? reserve_beats_i : 5'b0;
                fetched_r[state_idx] <= 5'b0;
                sent_r[state_idx] <= 5'b0;
            end
        end
        for (state_idx = 0; state_idx < 7; state_idx = state_idx + 1) begin
            if (fetch_w && fetch_port_w == state_idx[2:0]) begin
                port_addr_r[state_idx] <= port_addr_r[state_idx] + 7'd1;
            end
            if (last_take_w[state_idx]) begin
                port_addr_r[state_idx] <= start_r[port_slot_w[state_idx]];
            end
            if (reserve_i && reserve_port_i == state_idx[2:0] &&
                (!port_active_r[state_idx] ||
                    (last_take_w[state_idx] && port_match_w[state_idx] == 0))) begin
                port_addr_r[state_idx] <= write_ptr_r;
            end
        end
        if (fetch_w) begin
            pending_slot_r <= fetch_slot_w;
            pending_port_r <= fetch_port_w;
            pending_id_r <= id_r[fetch_slot_w][0];
            pending_error_r <= error_r[fetch_slot_w];
            pending_last_r <= fetched_r[fetch_slot_w] + 5'd1 == length_r[fetch_slot_w];
        end
        if (pending_r && !rready_i[pending_port_r]) begin
            skid_data_r[pending_port_r] <= pending_data_w;
            skid_slot_r[pending_port_r] <= pending_slot_r;
            skid_id_r[pending_port_r] <= pending_id_r;
        end
    end
endmodule
