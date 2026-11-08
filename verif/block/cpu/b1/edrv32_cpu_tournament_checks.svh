// File: edrv32_cpu_tournament_checks.svh
// Spec: cpu-testplan B-12; cpu-spec v0.18 4.4.
// Description: Observe the F2 bubble and chooser training at the actual write edge.
// Clock: clk_sys; included in the B1 core harness.
    integer tournament_corrections = 0;
    integer tournament_agreements = 0;
    integer tournament_local_wins = 0;
    integer tournament_index;
    integer tournament_expected;
    logic tournament_check_update;
    logic tournament_check_correction;
    logic [31:0] tournament_target;
    always @(posedge clk) begin
        tournament_check_update = 0;
        tournament_check_correction = 0;
        if (rst_n && test_id == "b-12") begin
            if (u_core.u_frontend.f2_correct_w) begin
                tournament_corrections++;
                tournament_check_correction = 1;
                tournament_target = u_core.u_frontend.f2_correct_pc_w;
                if (ic_req_valid)
                    $fatal(1, "FAIL B-12 discarded F1 request accepted cycle=%0d", cycles);
            end
            if (u_core.update_valid_r && u_core.update_type_r == 0) begin
                tournament_check_update = 1;
                tournament_index = int'(u_core.update_index_r);
                tournament_expected =
                    int'(u_core.u_frontend.u_predictor.u_chooser.memory_r[tournament_index]);
                if (u_core.update_tournament_r[10] == u_core.update_tournament_r[11])
                    tournament_agreements++;
                else if (u_core.update_tournament_r[10] == u_core.update_taken_r) begin
                    tournament_local_wins++;
                    if (tournament_expected < 3) tournament_expected++;
                end else if (tournament_expected > 0) tournament_expected--;
            end
        end
        #1;
        if (tournament_check_correction && u_core.u_frontend.f1_pc_r != tournament_target)
            $fatal(1, "FAIL B-12 correction next PC expected=%h actual=%h cycle=%0d",
                tournament_target, u_core.u_frontend.f1_pc_r, cycles);
        if (tournament_check_update &&
            int'(u_core.u_frontend.u_predictor.u_chooser.memory_r[tournament_index]) !=
            tournament_expected)
            $fatal(1, "FAIL B-12 chooser index=%0d expected=%0d actual=%0d",
                tournament_index, tournament_expected,
                u_core.u_frontend.u_predictor.u_chooser.memory_r[tournament_index]);
    end
