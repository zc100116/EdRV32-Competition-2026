// File: edrv32_cpu_csr.v
// Spec: cpu-spec 5, 7.1
// Description: Maintain machine CSRs, interrupt state and architectural counters.
// Apply CSR access permissions, WARL masks and precise trap/MRET updates.
// Clock domain: clk_sys.
module edrv32_cpu_csr #(
    parameter RVC_EN = 1
) (
    // Clock and architectural reset.
    input wire clk_i,
    input wire rst_n_i,
    // M-stage access: write_i denotes an actual, committed CSR write.
    // command: 1=write, 2=set, 3=clear; zero=read only.
    input wire access_valid_i,
    input wire [41:0] select_i,
    input wire write_i,
    input wire commit_i,
    input wire [1:0] command_i,
    input wire [31:0] write_data_i,
    output reg [31:0] read_data_o,
    output wire illegal_o,
    // D owns address decode/permissions; M consumes its registered selection.
    input wire decode_valid_i,
    input wire [11:0] decode_addr_i,
    input wire decode_write_i,
    output wire [41:0] decode_select_o,
    output wire decode_illegal_o,
    // Retirement and HPM counts: two bits per event, code 1 in [1:0].
    input wire [1:0] retire_count_i,
    input wire [31:0] event_count_i,
    // Precise trap and MRET updates. Trap has priority over CSR and MRET.
    input wire trap_i,
    input wire [31:0] trap_pc_i,
    input wire [31:0] trap_cause_i,
    input wire [31:0] trap_value_i,
    input wire mret_i,
    output wire [31:0] mstatus_o,
    output wire [31:0] mie_o,
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o,
    // Synchronized interrupt levels and CLINT time.
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i
);
    localparam [31:0] MISA = RVC_EN ? 32'h40001104 : 32'h40001100;
    localparam [31:0] EPC_MASK = RVC_EN ? 32'hfffffffe : 32'hfffffffc;
    reg [31:0] mstatus_r;
    reg [31:0] mie_r;
    reg [31:0] mtvec_r;
    reg [31:0] mscratch_r;
    reg [31:0] mepc_r;
    reg [31:0] mcause_r;
    reg [31:0] mtval_r;
    reg [31:0] inhibit_r;
    reg [4:0] event_r [0:7];
    reg [63:0] cycle_r;
    reg [63:0] instret_r;
    reg [63:0] counter_r [0:7];
    reg [31:0] event_count_r;
    reg [31:0] write_data_w;
    wire write_enable_w;
    integer read_idx;
    integer update_idx;
    assign mstatus_o = mstatus_r;
    assign mie_o = mie_r;
    assign mtvec_o = mtvec_r;
    assign mepc_o = mepc_r;
    // cpu-spec 4.6: D decodes once; E/M carry this selection without moving CSR access.
    // [15:0]: status/misa/mie/mtvec/inhibit/scratch/epc/cause/tval/ip,
    // cycle lo/hi, instret lo/hi, time lo/hi; [39:16]: event, HPM lo, HPM hi.
    // [40] implemented, [41] read-only. Counter aliases share their read selection.
    function [41:0] decode_select;
        input [11:0] address_i;
        reg [41:0] select_w;
        integer index;
        begin
            select_w = 0;
            select_w[0] = address_i == 12'h300;
            select_w[1] = address_i == 12'h301;
            select_w[2] = address_i == 12'h304;
            select_w[3] = address_i == 12'h305;
            select_w[4] = address_i == 12'h320;
            select_w[5] = address_i == 12'h340;
            select_w[6] = address_i == 12'h341;
            select_w[7] = address_i == 12'h342;
            select_w[8] = address_i == 12'h343;
            select_w[9] = address_i == 12'h344;
            select_w[10] = address_i == 12'hb00 || address_i == 12'hc00;
            select_w[11] = address_i == 12'hb80 || address_i == 12'hc80;
            select_w[12] = address_i == 12'hb02 || address_i == 12'hc02;
            select_w[13] = address_i == 12'hb82 || address_i == 12'hc82;
            select_w[14] = address_i == 12'hc01;
            select_w[15] = address_i == 12'hc81;
            for (index = 0; index < 8; index = index + 1) begin
                select_w[16 + index] = address_i == 12'h323 + index[11:0];
                select_w[24 + index] = address_i == 12'hb03 + index[11:0] ||
                    address_i == 12'hc03 + index[11:0];
                select_w[32 + index] = address_i == 12'hb83 + index[11:0] ||
                    address_i == 12'hc83 + index[11:0];
            end
            select_w[40] = |select_w[39:0] || address_i == 12'hf11 ||
                address_i == 12'hf12 || address_i == 12'hf13 || address_i == 12'hf14;
            select_w[41] = address_i == 12'h344 || address_i[11:8] == 4'hc ||
                address_i[11:8] == 4'hf;
            decode_select = select_w;
        end
    endfunction
    assign decode_select_o = decode_select(decode_addr_i);
    assign illegal_o = access_valid_i && (!select_i[40] || (write_i && select_i[41]));
    assign decode_illegal_o = decode_valid_i &&
        (!decode_select_o[40] || (decode_write_i && decode_select_o[41]));
    assign write_enable_w = access_valid_i && write_i && commit_i && !illegal_o;
    // Disjoint registered selects form a parallel read mux, before CSR set/clear.
    always @(*) begin
        read_data_o =
            ({32{select_i[0]}} & mstatus_r) |
            ({32{select_i[1]}} & MISA) |
            ({32{select_i[2]}} & mie_r) |
            ({32{select_i[3]}} & mtvec_r) |
            ({32{select_i[4]}} & inhibit_r) |
            ({32{select_i[5]}} & mscratch_r) |
            ({32{select_i[6]}} & mepc_r) |
            ({32{select_i[7]}} & mcause_r) |
            ({32{select_i[8]}} & mtval_r) |
            ({32{select_i[9]}} & {20'b0, irq_meip_i, 3'b0, irq_mtip_i, 3'b0, irq_msip_i, 3'b0}) |
            ({32{select_i[10]}} & cycle_r[31:0]) |
            ({32{select_i[11]}} & cycle_r[63:32]) |
            ({32{select_i[12]}} & instret_r[31:0]) |
            ({32{select_i[13]}} & instret_r[63:32]) |
            ({32{select_i[14]}} & mtime_i[31:0]) |
            ({32{select_i[15]}} & mtime_i[63:32]);
        for (read_idx = 0; read_idx < 8; read_idx = read_idx + 1) begin
            read_data_o = read_data_o |
                ({32{select_i[16 + read_idx]}} & {27'b0, event_r[read_idx]}) |
                ({32{select_i[24 + read_idx]}} & counter_r[read_idx][31:0]) |
                ({32{select_i[32 + read_idx]}} & counter_r[read_idx][63:32]);
        end
    end
    always @(*) begin
        write_data_w = write_data_i;
        case (command_i)
            2'd2: write_data_w = read_data_o | write_data_i;
            2'd3: write_data_w = read_data_o & ~write_data_i;
            default: write_data_w = write_data_i;
        endcase
    end
    // cpu-spec 7.1: event generation ends here, before selection and the 64-bit increment.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            event_count_r <= 0;
        else
            event_count_r <= event_count_i;
    end
    // Architectural state has specified reset values, unlike execution data registers.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mstatus_r <= 32'h1800;
            mie_r <= 0;
            mtvec_r <= 0;
            mscratch_r <= 0;
            mepc_r <= 0;
            mcause_r <= 0;
            mtval_r <= 0;
            inhibit_r <= 0;
            cycle_r <= 0;
            instret_r <= 0;
            for (update_idx = 0; update_idx < 8; update_idx = update_idx + 1) begin
                event_r[update_idx] <= 0;
                counter_r[update_idx] <= 0;
            end
        end else begin
            if (!inhibit_r[0])
                cycle_r <= cycle_r + 1'b1;
            if (!inhibit_r[2])
                instret_r <= instret_r + {62'b0, retire_count_i};
            for (update_idx = 0; update_idx < 8; update_idx = update_idx + 1) begin
                if (!inhibit_r[update_idx + 3] && event_r[update_idx] >= 1 &&
                    event_r[update_idx] <= 16)
                    counter_r[update_idx] <= counter_r[update_idx] +
                        {62'b0, event_count_r[(event_r[update_idx] - 1'b1) * 2 +: 2]};
            end
            if (write_enable_w && !trap_i) begin
                if (select_i[0])
                    mstatus_r <= (write_data_w & 32'h88) | 32'h1800;
                if (select_i[2])
                    mie_r <= write_data_w & 32'h888;
                if (select_i[3])
                    mtvec_r <= {write_data_w[31:2], 1'b0,
                        write_data_w[1:0] == 1};
                if (select_i[4])
                    inhibit_r <= write_data_w & 32'h7fd;
                if (select_i[5])
                    mscratch_r <= write_data_w;
                if (select_i[6])
                    mepc_r <= write_data_w & EPC_MASK;
                if (select_i[7])
                    mcause_r <= write_data_w;
                if (select_i[8])
                    mtval_r <= write_data_w;
                if (select_i[10])
                    cycle_r <= {cycle_r[63:32], write_data_w};
                if (select_i[11])
                    cycle_r <= {write_data_w, cycle_r[31:0]};
                if (select_i[12])
                    instret_r <= {instret_r[63:32], write_data_w};
                if (select_i[13])
                    instret_r <= {write_data_w, instret_r[31:0]};
                for (update_idx = 0; update_idx < 8; update_idx = update_idx + 1) begin
                    if (select_i[16 + update_idx])
                        event_r[update_idx] <= write_data_w[4:0];
                    if (select_i[24 + update_idx])
                        counter_r[update_idx] <= {counter_r[update_idx][63:32], write_data_w};
                    if (select_i[32 + update_idx])
                        counter_r[update_idx] <= {write_data_w, counter_r[update_idx][31:0]};
                end
            end
            if (trap_i) begin
                mepc_r <= trap_pc_i & EPC_MASK;
                mcause_r <= trap_cause_i;
                mtval_r <= trap_value_i;
                mstatus_r <= 32'h1800 | {24'b0, mstatus_r[3], 7'b0};
            end else if (mret_i) begin
                mstatus_r <= 32'h1880 | {28'b0, mstatus_r[7], 3'b0};
            end
        end
    end
endmodule
