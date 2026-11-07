#!/usr/bin/env python3
# File: cpu_t3_paths.py
# Spec: T-CPU-N-T3BE/FE timing acceptance; cpu-spec 4.9.
# Description: Measure the card-62 A-F boundary groups in an XC7 proxy netlist.
# Clock domain: host tool; measured RTL uses clk_sys.
"""Print A-F maximum mapped levels and path fanout, counting carry chains as two."""
import argparse
import csv
import json
from pathlib import Path
import sys

from tools.synth.cpu_levels import worst


QUERIES = {
    'A1_tag_metadata': (r'u_icache.u_tag[01]',
                        r'u_icache.*(valid[01]_bank_r|lru_bank_r)'),
    'A1_tag_capture': (r'u_icache.u_tag[01]', r'u_icache.*metadata_miss[01]_r'),
    'A1_registered_metadata': (r'u_icache.*metadata_.*_r',
                               r'u_icache.*(valid[01]_bank_r|lru_bank_r)'),
    'A1_request_snapshot': (r'u_core.u_frontend.(f1_pc.*_r|.*query_.*copy1_r)',
                            r'u_icache.*lookup_lru_bank.*_r'),
    'A2_tag_lru': (r'u_dcache.u_(early_)?tag[01]',
                   r'u_dcache.*(lru_bank_r|lookup_lru_bank_r)'),
    'A2_tag_capture': (r'u_dcache.u_(early_)?tag[01]',
                       r'u_dcache.*(hit_copy1_r|way_copy1_r)'),
    'A2_registered_metadata': (r'u_dcache.*(hit_copy1_r|way_copy1_r|metadata_.*_r|early_response)',
                              r'u_dcache.*(lru_bank_r|lookup_lru_bank_r)'),
    'A3_tag_store_payload': (r'u_dcache.u_tag[01]',
                             r'u_dcache.*(buffer_data_r|buffer_mask_r|store_size_r)'),
    'A3_registered_payload': (r'u_dcache.(addr_r|size_r|store_.*_r)|u_core.m_store_r',
                              r'u_dcache.*(buffer_data_r|buffer_mask_r|store_size_r)'),
    'B1_tag_operands': (r'u_dcache.u_(early_)?tag[01]',
                        r'u_core.*(e_operand|e_alu_operand|e_branch|amount_copy1|e_csr_select)'),
    'B2_tag_m_result': (r'u_dcache.u_(early_)?tag[01]', r'u_core.m_result_r'),
    'B3_tag_IB_pointer': (r'u_dcache.u_(early_)?tag[01]',
                          r'u_core.u_frontend.u_ib.*read_ptr'),
    'B_early_payload_capture': (r'u_dcache.u_(early_)?tag[01]',
                                r'u_dcache.early_response_data_r'),
    'B_early_way_capture': (r'u_dcache.u_(early_)?tag[01]',
                            r'u_dcache.early_response_way_r'),
    'C1_F2_correction': (r'u_core.u_frontend.f2_payload_r',
                         r'u_core.u_frontend.(f1_pc.*_r|.*query_.*copy1_r)'),
    'C1_registered_correction': (
        r'u_core.u_frontend.(f2_.*_r|.*correct.*_r|u_predictor.*(local_direction|chooser))',
        r'u_core.u_frontend.(f1_pc.*_r|.*query_.*copy1_r)'),
    'C2_F1_loop': (r'u_core.u_frontend.(f1_pc.*_r|.*query_.*copy1_r)',
                    r'u_core.u_frontend.(f1_pc.*_r|.*query_.*copy1_r)'),
    'D_frontend_capture': (r'u_icache.u_tag[01]', r'u_core.u_frontend.words_r'),
    'D1_tag_IB': (r'u_icache.u_tag[01]',
                  r'u_core.u_frontend.u_ib.*(predecode_r|words_r|entries_r)'),
    'D2_F2_IB': (r'u_core.u_frontend.f2_payload_r',
                 r'u_core.u_frontend.u_ib.*(predecode_r|words_r|entries_r|write_ptr|count.*_r)'),
    'E1_IB_operands': (r'u_core.u_frontend.u_ib.*(read_ptr|predecode_r|entries_r)',
                       r'u_core.*(e_operand|e_alu_operand|e_branch|amount_copy1|early_valid)'),
    'E2_ALU_loop': (r'u_core.(e_operand|e_alu_operand)',
                    r'u_core.*(e_operand|e_alu_operand|e_branch|amount_copy1)'),
    'F_div_control': (r'u_core.*(e_record_r|e_div|e_exception1|e_control_r|e_swap_r|e_valid_r)',
                      r'u_core.(div_result|u_div.result_o)'),
    'F_W_operands': (r'u_core.*(w_forward_valid_copy1_r|w_valid_r)',
                     r'u_core.*(e_operand|e_alu_operand|e_branch|amount_copy1)'),
    'F_HPM_operands': (r'g_counter.*count_r',
                       r'u_core.*(e_operand|e_alu_operand|e_branch|amount_copy1)'),
    'F_direction_DI': (r'u_core.update_index_r', r'u_direction.*wr_data'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', type=Path)
    args = parser.parse_args()
    design = json.loads(args.netlist.read_text())
    writer = csv.writer(sys.stdout, delimiter='\t', lineterminator='\n')
    writer.writerow(['group', 'boundary', 'levels', 'max_fanout', 'launch', 'capture'])
    for group, (start, end) in QUERIES.items():
        results = worst(design, start, end, carry_chain_two=True)
        if not results:
            writer.writerow([group, 'none', '', '', '', ''])
        for category, point in results.items():
            writer.writerow([group, category, point['levels'], point['max_fanout'],
                             point['start'], point['end']])


if __name__ == '__main__':
    main()
