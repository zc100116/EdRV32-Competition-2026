// File: edrv32_cpu2_csr.v
// Spec: cpu-v2-spec 3.5, 4, 6; fpu-spec 4.
// Description: Ordered machine and floating CSR state, local read completion,
// architectural counters and interrupt selection. Clock domain: clk_sys.
module edrv32_cpu2_csr #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire csr_req_valid_i,
    output wire csr_req_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] csr_req_tag_i,
    input wire [31:0] csr_req_instr_i,
    input wire [31:0] csr_req_src_i,
    input wire csr_commit_valid_i,
    output wire csr_complete_valid_o,
    input wire csr_complete_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] csr_complete_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] csr_complete_data_o,
    output wire [4:0] csr_complete_flags_o,
    output wire csr_complete_exception_o,
    output wire [3:0] csr_complete_cause_o,
    output wire [31:0] csr_complete_tval_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] cancel_tag_i,
    input wire fp_commit_flags_valid_i,
    input wire [4:0] fp_commit_flags_i,
    input wire fp_commit_write_i,
    output wire [2:0] csr_frm_o,
    output wire [1:0] csr_fs_o,
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i,
    output wire irq_pending_o,
    output wire [31:0] irq_cause_o,
    output wire [31:0] trap_target_o,
    input wire mret_valid_i,
    output wire [31:0] csr_mepc_o,
    output wire irq_wake_o,
    input wire trap_valid_i,
    input wire [31:0] trap_pc_i,
    input wire [31:0] trap_cause_i,
    input wire [31:0] trap_tval_i,
    input wire [1:0] counter_retire_count_i,
    input wire [15:0] hpm_event_i,
    input wire [1:0] hpm_branch_count_i
);
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam H = ISSUE_WIDTH == 1 ? 2 : 8;
    localparam [31:0] MISA = 32'h40001100 |
        (FPU_FORMAT == "NONE" ? 32'b0 : 32'h20) |
        (FPU_FORMAT == "FD" ? 32'h8 : 32'b0);
    localparam [31:0] INHIBIT_MASK = ISSUE_WIDTH == 1 ? 32'h1d : 32'h7fd;
    reg mie_enable_r;
    reg mpie_r;
    reg [1:0] fs_r;
    reg [4:0] fflags_r;
    reg [2:0] frm_r;
    reg [31:0] mie_r;
    reg [31:0] mtvec_r;
    reg [31:0] mscratch_r;
    reg [31:0] mepc_r;
    reg [31:0] mcause_r;
    reg [31:0] mtval_r;
    reg [31:0] inhibit_r;
    reg [63:0] cycle_r;
    reg [63:0] instret_r;
    wire [4:0] event_select_w [0:7];
    wire [63:0] hpm_count_w [0:7];
    wire [31:0] mip_w;
    wire [31:0] mstatus_w;
    wire [11:0] req_addr_w;
    wire [11:0] commit_addr_w;
    wire req_write_w;
    wire commit_write_w;
    wire req_illegal_w;
    reg req_exists_w;
    reg [31:0] req_read_w;
    wire [31:0] commit_read_w;
    reg [31:0] commit_data_w;
    wire [31:0] commit_operand_w;
    wire mret_w;
    reg [15:0] event_r;
    reg [1:0] branch_count_r;
    reg complete_r;
    reg [T-1:0] complete_tag_r;
    reg [31:0] complete_data_r;
    reg complete_exception_r;
    reg [31:0] complete_instr_r;
    reg [31:0] complete_src_r;
    wire [T-1:0] cancel_distance_w;
    wire [T-1:0] complete_distance_w;
    wire complete_cancel_w;
    wire request_cancel_w;
    wire [T-1:0] request_distance_w;
    assign mip_w = {20'b0, irq_meip_i, 3'b0, irq_mtip_i, 3'b0, irq_msip_i, 3'b0};
    assign mstatus_w = 32'h1800 | {24'b0, mpie_r, 3'b0, mie_enable_r, 3'b0} |
        (FPU_FORMAT == "NONE" ? 32'b0 :
        {fs_r == 2'b11, 16'b0, fs_r, 13'b0});
    assign csr_frm_o = frm_r;
    assign csr_fs_o = fs_r;
    assign csr_mepc_o = mepc_r;
    assign irq_wake_o = |(mie_r & mip_w);
    assign irq_pending_o = mie_enable_r && irq_wake_o;
    assign irq_cause_o = mie_r[11] && irq_meip_i ? 32'h8000000b :
        mie_r[3] && irq_msip_i ? 32'h80000003 : 32'h80000007;
    assign trap_target_o = {mtvec_r[31:2], 2'b0} +
        ((mtvec_r[0] && trap_cause_i[31]) ? {2'b0, trap_cause_i[29:0]} << 2 : 32'b0);
    assign req_addr_w = csr_req_instr_i[31:20];
    assign commit_addr_w = complete_instr_r[31:20];
    assign req_write_w = csr_req_instr_i[13:12] == 2'b01 ||
        csr_req_instr_i[19:15] != 5'b0;
    assign commit_write_w = csr_commit_valid_i && !trap_valid_i &&
        complete_instr_r[6:0] == 7'h73 && complete_instr_r[14:12] != 3'b0 &&
        (complete_instr_r[13:12] == 2'b01 || complete_instr_r[19:15] != 5'b0);
    assign commit_operand_w = complete_instr_r[14] ?
        {27'b0, complete_instr_r[19:15]} : complete_src_r;
    assign mret_w = mret_valid_i;
    assign req_illegal_w = csr_req_instr_i[14:12] != 3'b0 &&
        (!req_exists_w || (req_write_w &&
        (req_addr_w[11:10] == 2'b11 || req_addr_w == 12'h344)) ||
        ((req_addr_w == 12'h001 || req_addr_w == 12'h002 || req_addr_w == 12'h003) &&
        (FPU_FORMAT == "NONE" || fs_r == 2'b0)));
    always @(*) begin
        req_read_w = 32'b0;
        req_exists_w = 1'b1;
        case (req_addr_w)
            12'h001: req_read_w = {27'b0, fflags_r};
            12'h002: req_read_w = {29'b0, frm_r};
            12'h003: req_read_w = {24'b0, frm_r, fflags_r};
            12'h300: req_read_w = mstatus_w;
            12'h301: req_read_w = MISA;
            12'h304: req_read_w = mie_r;
            12'h305: req_read_w = mtvec_r;
            12'h320: req_read_w = inhibit_r;
            12'h340: req_read_w = mscratch_r;
            12'h341: req_read_w = mepc_r;
            12'h342: req_read_w = mcause_r;
            12'h343: req_read_w = mtval_r;
            12'h344: req_read_w = mip_w;
            12'hb00: req_read_w = cycle_r[31:0];
            12'hc00: req_read_w = cycle_r[31:0];
            12'hb80: req_read_w = cycle_r[63:32];
            12'hc80: req_read_w = cycle_r[63:32];
            12'hb02: req_read_w = instret_r[31:0];
            12'hc02: req_read_w = instret_r[31:0];
            12'hb82: req_read_w = instret_r[63:32];
            12'hc82: req_read_w = instret_r[63:32];
            12'hc01: req_read_w = mtime_i[31:0];
            12'hc81: req_read_w = mtime_i[63:32];
            12'hf11: req_read_w = 32'b0;
            12'hf12: req_read_w = 32'b0;
            12'hf13: req_read_w = 32'b0;
            12'hf14: req_read_w = 32'b0;
            default: begin
                req_exists_w = 1'b0;
                if (H > 0 && req_addr_w == 12'h323) begin
                    req_read_w = {27'b0, event_select_w[0]};
                    req_exists_w = 1'b1;
                end
                if (H > 0 && req_addr_w == 12'hb03) begin
                    req_read_w = hpm_count_w[0][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 0 && req_addr_w == 12'hc03) begin
                    req_read_w = hpm_count_w[0][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 0 && req_addr_w == 12'hb83) begin
                    req_read_w = hpm_count_w[0][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 0 && req_addr_w == 12'hc83) begin
                    req_read_w = hpm_count_w[0][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 1 && req_addr_w == 12'h324) begin
                    req_read_w = {27'b0, event_select_w[1]};
                    req_exists_w = 1'b1;
                end
                if (H > 1 && req_addr_w == 12'hb04) begin
                    req_read_w = hpm_count_w[1][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 1 && req_addr_w == 12'hc04) begin
                    req_read_w = hpm_count_w[1][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 1 && req_addr_w == 12'hb84) begin
                    req_read_w = hpm_count_w[1][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 1 && req_addr_w == 12'hc84) begin
                    req_read_w = hpm_count_w[1][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 2 && req_addr_w == 12'h325) begin
                    req_read_w = {27'b0, event_select_w[2]};
                    req_exists_w = 1'b1;
                end
                if (H > 2 && req_addr_w == 12'hb05) begin
                    req_read_w = hpm_count_w[2][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 2 && req_addr_w == 12'hc05) begin
                    req_read_w = hpm_count_w[2][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 2 && req_addr_w == 12'hb85) begin
                    req_read_w = hpm_count_w[2][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 2 && req_addr_w == 12'hc85) begin
                    req_read_w = hpm_count_w[2][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 3 && req_addr_w == 12'h326) begin
                    req_read_w = {27'b0, event_select_w[3]};
                    req_exists_w = 1'b1;
                end
                if (H > 3 && req_addr_w == 12'hb06) begin
                    req_read_w = hpm_count_w[3][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 3 && req_addr_w == 12'hc06) begin
                    req_read_w = hpm_count_w[3][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 3 && req_addr_w == 12'hb86) begin
                    req_read_w = hpm_count_w[3][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 3 && req_addr_w == 12'hc86) begin
                    req_read_w = hpm_count_w[3][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 4 && req_addr_w == 12'h327) begin
                    req_read_w = {27'b0, event_select_w[4]};
                    req_exists_w = 1'b1;
                end
                if (H > 4 && req_addr_w == 12'hb07) begin
                    req_read_w = hpm_count_w[4][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 4 && req_addr_w == 12'hc07) begin
                    req_read_w = hpm_count_w[4][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 4 && req_addr_w == 12'hb87) begin
                    req_read_w = hpm_count_w[4][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 4 && req_addr_w == 12'hc87) begin
                    req_read_w = hpm_count_w[4][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 5 && req_addr_w == 12'h328) begin
                    req_read_w = {27'b0, event_select_w[5]};
                    req_exists_w = 1'b1;
                end
                if (H > 5 && req_addr_w == 12'hb08) begin
                    req_read_w = hpm_count_w[5][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 5 && req_addr_w == 12'hc08) begin
                    req_read_w = hpm_count_w[5][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 5 && req_addr_w == 12'hb88) begin
                    req_read_w = hpm_count_w[5][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 5 && req_addr_w == 12'hc88) begin
                    req_read_w = hpm_count_w[5][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 6 && req_addr_w == 12'h329) begin
                    req_read_w = {27'b0, event_select_w[6]};
                    req_exists_w = 1'b1;
                end
                if (H > 6 && req_addr_w == 12'hb09) begin
                    req_read_w = hpm_count_w[6][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 6 && req_addr_w == 12'hc09) begin
                    req_read_w = hpm_count_w[6][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 6 && req_addr_w == 12'hb89) begin
                    req_read_w = hpm_count_w[6][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 6 && req_addr_w == 12'hc89) begin
                    req_read_w = hpm_count_w[6][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 7 && req_addr_w == 12'h32a) begin
                    req_read_w = {27'b0, event_select_w[7]};
                    req_exists_w = 1'b1;
                end
                if (H > 7 && req_addr_w == 12'hb0a) begin
                    req_read_w = hpm_count_w[7][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 7 && req_addr_w == 12'hc0a) begin
                    req_read_w = hpm_count_w[7][31:0];
                    req_exists_w = 1'b1;
                end
                if (H > 7 && req_addr_w == 12'hb8a) begin
                    req_read_w = hpm_count_w[7][63:32];
                    req_exists_w = 1'b1;
                end
                if (H > 7 && req_addr_w == 12'hc8a) begin
                    req_read_w = hpm_count_w[7][63:32];
                    req_exists_w = 1'b1;
                end
            end
        endcase
    end
    // Only one CSR may be uncommitted. The response data remains intact after
    // handshake until the next request, so rd and the committed RMW use one snapshot.
    assign commit_read_w = complete_data_r;
    always @(*) begin
        commit_data_w = commit_operand_w;
        case (complete_instr_r[13:12])
            2'b10: commit_data_w = commit_read_w | commit_operand_w;
            2'b11: commit_data_w = commit_read_w & ~commit_operand_w;
            default: commit_data_w = commit_operand_w;
        endcase
    end
    // The read pipeline advances independently of the rest of the CPU.
    assign cancel_distance_w = cancel_tag_i - age_head_i;
    assign complete_distance_w = complete_tag_r - age_head_i;
    assign request_distance_w = csr_req_tag_i - age_head_i;
    assign complete_cancel_w = cancel_valid_i && complete_distance_w >= cancel_distance_w;
    assign request_cancel_w = cancel_valid_i && request_distance_w >= cancel_distance_w;
    assign csr_req_ready_o = !complete_r;
    assign csr_complete_valid_o = complete_r;
    assign csr_complete_tag_o = complete_tag_r;
    assign csr_complete_data_o = {{(FPU_FORMAT == "FD" ? 32 : 0){1'b0}},
        complete_data_r};
    assign csr_complete_flags_o = 5'b0;
    assign csr_complete_exception_o = complete_exception_r;
    assign csr_complete_cause_o = 4'd2;
    assign csr_complete_tval_o = complete_instr_r;
    // One local response capture followed by completion capture gives the
    // specified two-cycle CSR dependency distance. Ready uses registered capacity.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            complete_r <= 1'b0;
        else begin
            if (csr_complete_ready_i || complete_cancel_w)
                complete_r <= 1'b0;
            if (csr_req_valid_i && csr_req_ready_o)
                complete_r <= !request_cancel_w;
        end
    end
    always @(posedge clk_i) begin
        if (csr_req_valid_i && csr_req_ready_o) begin
            complete_tag_r <= csr_req_tag_i;
            complete_data_r <= req_read_w;
            complete_exception_r <= req_illegal_w;
            complete_instr_r <= csr_req_instr_i;
            complete_src_r <= csr_req_src_i;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mie_enable_r <= 1'b0;
            mpie_r <= 1'b0;
            fs_r <= 2'b0;
            fflags_r <= 5'b0;
            frm_r <= 3'b0;
            mie_r <= 32'b0;
            mtvec_r <= 32'b0;
            mscratch_r <= 32'b0;
            mepc_r <= 32'b0;
            mcause_r <= 32'b0;
            mtval_r <= 32'b0;
            inhibit_r <= 32'b0;
        end else begin
            if (FPU_FORMAT != "NONE") begin
                if (fp_commit_flags_valid_i)
                    fflags_r <= fflags_r | fp_commit_flags_i;
                if (fp_commit_write_i ||
                    (fp_commit_flags_valid_i && |fp_commit_flags_i))
                    fs_r <= 2'b11;
            end
            if (commit_write_w) begin
                case (commit_addr_w)
                    12'h300: begin
                        mie_enable_r <= commit_data_w[3];
                        mpie_r <= commit_data_w[7];
                        if (FPU_FORMAT != "NONE")
                            fs_r <= commit_data_w[14:13];
                    end
                    12'h304: mie_r <= commit_data_w & 32'h888;
                    12'h305: mtvec_r <= {commit_data_w[31:2], 1'b0,
                        commit_data_w[1:0] == 2'b01};
                    12'h320: inhibit_r <= commit_data_w & INHIBIT_MASK;
                    12'h340: mscratch_r <= commit_data_w;
                    12'h341: mepc_r <= {commit_data_w[31:2], 2'b0};
                    12'h342: mcause_r <= commit_data_w;
                    12'h343: mtval_r <= commit_data_w;
                    12'h001: begin
                        if (FPU_FORMAT != "NONE") begin
                            fflags_r <= commit_data_w[4:0];
                            fs_r <= 2'b11;
                        end
                    end
                    12'h002: begin
                        if (FPU_FORMAT != "NONE") begin
                            frm_r <= commit_data_w[2:0];
                            fs_r <= 2'b11;
                        end
                    end
                    12'h003: begin
                        if (FPU_FORMAT != "NONE") begin
                            frm_r <= commit_data_w[7:5];
                            fflags_r <= commit_data_w[4:0];
                            fs_r <= 2'b11;
                        end
                    end
                    default: begin end
                endcase
            end
            if (trap_valid_i) begin
                mepc_r <= {trap_pc_i[31:2], 2'b0};
                mcause_r <= trap_cause_i;
                mtval_r <= trap_tval_i;
                mpie_r <= mie_enable_r;
                mie_enable_r <= 1'b0;
            end else if (mret_w) begin
                mie_enable_r <= mpie_r;
                mpie_r <= 1'b1;
            end
        end
    end
    // C04: event generation is registered before 64-bit counter selection/addition.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            event_r <= 16'b0;
            branch_count_r <= 2'b0;
        end else begin
            event_r <= {hpm_event_i[15:8],
                hpm_event_i[7] && !(|hpm_event_i[6:4]),
                hpm_event_i[6] && !(|hpm_event_i[5:4]),
                hpm_event_i[5] && !hpm_event_i[4], hpm_event_i[4], hpm_event_i[3:0]};
            branch_count_r <= hpm_branch_count_i;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            cycle_r <= 64'b0;
        else if (commit_write_w && commit_addr_w == 12'hb00)
            cycle_r <= {cycle_r[63:32], commit_data_w};
        else if (commit_write_w && commit_addr_w == 12'hb80)
            cycle_r <= {commit_data_w, cycle_r[31:0]};
        else if (!inhibit_r[0])
            cycle_r <= cycle_r + 1'b1;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            instret_r <= 64'b0;
        else if (commit_write_w && commit_addr_w == 12'hb02)
            instret_r <= {instret_r[63:32], commit_data_w};
        else if (commit_write_w && commit_addr_w == 12'hb82)
            instret_r <= {commit_data_w, instret_r[31:0]};
        else if (!inhibit_r[2])
            instret_r <= instret_r + {62'b0, counter_retire_count_i};
    end
    genvar h;
    generate
        for (h = 0; h < H; h = h + 1) begin : g_hpm
            localparam [11:0] EVENT_ADDR = 12'h323 + h;
            localparam [11:0] LOW_ADDR = 12'hb03 + h;
            localparam [11:0] HIGH_ADDR = 12'hb83 + h;
            reg [4:0] select_r;
            reg [63:0] count_r;
            reg [1:0] increment_w;
            assign event_select_w[h] = select_r;
            assign hpm_count_w[h] = count_r;
            always @(*) begin
                increment_w = 2'b0;
                case (select_r)
                    5'd1: increment_w = {1'b0, event_r[0]};
                    5'd2: increment_w = {1'b0, event_r[1]};
                    5'd3: increment_w = {1'b0, event_r[2]};
                    5'd4: increment_w = branch_count_r;
                    5'd5: increment_w = {1'b0, event_r[4]};
                    5'd6: increment_w = {1'b0, event_r[5]};
                    5'd7: increment_w = {1'b0, event_r[6]};
                    5'd8: increment_w = {1'b0, event_r[7]};
                    5'd9: increment_w = {1'b0, event_r[8]};
                    5'd10: increment_w = {1'b0, event_r[9]};
                    5'd11: increment_w = {1'b0, event_r[10]};
                    5'd12: increment_w = {1'b0, event_r[11]};
                    5'd13: increment_w = {1'b0, event_r[12]};
                    5'd14: increment_w = {1'b0, event_r[13]};
                    5'd15: increment_w = {1'b0, event_r[14]};
                    5'd16: increment_w = {1'b0, event_r[15]};
                    default: increment_w = 2'b0;
                endcase
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    select_r <= 5'b0;
                    count_r <= 64'b0;
                end else begin
                    if (commit_write_w && commit_addr_w == EVENT_ADDR)
                        select_r <= commit_data_w[4:0];
                    if (commit_write_w && commit_addr_w == LOW_ADDR)
                        count_r <= {count_r[63:32], commit_data_w};
                    else if (commit_write_w && commit_addr_w == HIGH_ADDR)
                        count_r <= {commit_data_w, count_r[31:0]};
                    else if (!inhibit_r[h+3])
                        count_r <= count_r + {62'b0, increment_w};
                end
            end
        end
        for (h = H; h < 8; h = h + 1) begin : g_absent_hpm
            assign event_select_w[h] = 5'b0;
            assign hpm_count_w[h] = 64'b0;
        end
    endgenerate
    // Architectural observation after this edge's ordered updates.
    wire [ISSUE_WIDTH-1:0] trace_csr_valid_w;
    wire [12*ISSUE_WIDTH-1:0] trace_csr_addr_w;
    wire [32*ISSUE_WIDTH-1:0] trace_csr_data_w;
    wire [4:0] trace_fflags_w;
    wire [2:0] trace_frm_w;
    wire [1:0] trace_fs_w;
    wire fp_csr_write_w;
    reg [31:0] trace_csr_value_w;
    integer trace_event_idx;
    assign fp_csr_write_w = commit_write_w &&
        (commit_addr_w == 12'h001 || commit_addr_w == 12'h002 || commit_addr_w == 12'h003);
    assign trace_csr_valid_w = {{(ISSUE_WIDTH-1){1'b0}},
        commit_write_w && commit_addr_w != 12'h301};
    assign trace_csr_addr_w = {{(12*(ISSUE_WIDTH-1)){1'b0}}, commit_addr_w};
    assign trace_csr_data_w = {{(32*(ISSUE_WIDTH-1)){1'b0}}, trace_csr_value_w};
    always @(*) begin
        trace_event_idx = 0;
        trace_csr_value_w = commit_data_w;
        case (commit_addr_w)
            12'h001: trace_csr_value_w = {27'b0, commit_data_w[4:0]};
            12'h002: trace_csr_value_w = {29'b0, commit_data_w[2:0]};
            12'h003: trace_csr_value_w = {24'b0, commit_data_w[7:0]};
            12'h300: trace_csr_value_w = 32'h1800 | (commit_data_w & 32'h88) |
                (FPU_FORMAT == "NONE" ? 32'b0 :
                {commit_data_w[14:13] == 2'b11, 16'b0, commit_data_w[14:13], 13'b0});
            12'h301: trace_csr_value_w = MISA;
            12'h304: trace_csr_value_w = commit_data_w & 32'h888;
            12'h305: trace_csr_value_w = {commit_data_w[31:2], 1'b0,
                commit_data_w[1:0] == 2'b01};
            12'h320: trace_csr_value_w = commit_data_w & INHIBIT_MASK;
            12'h341: trace_csr_value_w = {commit_data_w[31:2], 2'b0};
            default: begin
                for (trace_event_idx = 0; trace_event_idx < H;
                    trace_event_idx = trace_event_idx + 1) begin
                    if (commit_addr_w == 12'h323 + trace_event_idx[11:0])
                        trace_csr_value_w = {27'b0, commit_data_w[4:0]};
                end
            end
        endcase
    end
    assign trace_fflags_w = FPU_FORMAT == "NONE" ? 5'b0 :
        commit_write_w && (commit_addr_w == 12'h001 || commit_addr_w == 12'h003) ?
        commit_data_w[4:0] : fflags_r | ({5{fp_commit_flags_valid_i}} & fp_commit_flags_i);
    assign trace_frm_w = FPU_FORMAT == "NONE" ? 3'b0 :
        commit_write_w && commit_addr_w == 12'h002 ? commit_data_w[2:0] :
        commit_write_w && commit_addr_w == 12'h003 ? commit_data_w[7:5] : frm_r;
    assign trace_fs_w = FPU_FORMAT == "NONE" ? 2'b0 :
        commit_write_w && commit_addr_w == 12'h300 ? commit_data_w[14:13] :
        fp_csr_write_w || fp_commit_write_i ||
        (fp_commit_flags_valid_i && |fp_commit_flags_i) ? 2'b11 : fs_r;
    // Unused configuration fields and internal architectural observation wires.
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{
        trace_csr_valid_w, trace_csr_addr_w, trace_csr_data_w,
        trace_fflags_w, trace_frm_w, trace_fs_w,
        complete_instr_r[11:7],
        trap_pc_i[1:0],
        event_r[3]
    };
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
