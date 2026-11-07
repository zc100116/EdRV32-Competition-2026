#!/usr/bin/env python3
# File: test_cpu_levels.py
# Spec: T-CPU-N-T2BE section 0.
# Description: Exercise distinct launch boundaries, CE paths and mapped primitive counting.
# Clock domain: host test.
import unittest
from pathlib import Path
import tempfile

from tools.synth.cpu_calibrate import read_pds

from tools.synth.cpu_levels import pairs, worst
from tools.synth.test_netlist_paths import fixture, cell


class PairLevelsTest(unittest.TestCase):
    def test_global_reduction_matches_full_pair_extrema(self):
        design = fixture()
        design['modules']['test']['cells']['l2']['connections']['A'].append(8)
        for start, end in [(None, None), ('^a ', 'ff.D'), ('ip_r', '^q_r '),
                           ('q_r', 'ff.D'), (None, 'no_such_endpoint')]:
            rows = list(pairs(design, start, end))
            expected = {kind: max((row[5], row[6]) for row in rows if row[2] == kind)
                        for kind in {row[2] for row in rows}}
            actual = {kind: (row['levels'], row['max_fanout'])
                      for kind, row in worst(design, start, end).items()}
            self.assertEqual(actual, expected)

    def test_shorter_start_is_not_lost_and_enable_has_own_pair(self):
        design = fixture()
        design['modules']['test']['cells']['l2']['connections']['A'].append(8)
        rows = list(pairs(design, end=r'^q_r '))
        actual = {(r[0], r[4]): (r[5], r[6]) for r in rows}
        self.assertEqual(actual['a', 'ff.D[0]'], (2, 3))
        self.assertEqual(actual['ip_r', 'ff.D[0]'], (1, 3))
        self.assertEqual(actual['ip_r', 'ff.E[0]'], (1, 2))
        self.assertNotIn(('q_r', 'ff.D[0]'), actual)

    def test_async_lutram_preserves_address_path_and_storage_origin(self):
        design = fixture()
        ram = design['modules']['test']['cells']['ip_test']
        ram['type'] = 'ip_lutram_cpu_btb'
        ram['connections'] = {'rd_addr': [2], 'wr_clk': [3], 'rd_data': [8]}
        ram['port_directions'] = {'rd_addr': 'input', 'wr_clk': 'input', 'rd_data': 'output'}
        design['modules']['ip_lutram_cpu_btb'] = {'attributes': {'blackbox': '1'}}
        rows = list(pairs(design, end=r'ff.E'))
        actual = {r[0]: (r[2], r[5]) for r in rows}
        self.assertEqual(actual['a'], ('top', 1))
        self.assertEqual(actual['ip_r <storage>'], ('LUTRAM', 1))

    def test_mux_carry_and_lut_each_count_once_inverter_does_not(self):
        design = fixture()
        module = design['modules']['test']
        module['cells']['l1']['type'] = 'INV'
        module['cells']['l2']['type'] = 'MUXF7'
        module['cells']['carry'] = cell('CARRY4',
            {'S': [6, '0', '0', '0'], 'DI': ['0'] * 4,
             'CI': ['0'], 'CYINIT': ['0']},
            {'O': [11, 12, 13, 14], 'CO': [15, 16, 17, 18]}, 16)
        module['cells']['last'] = cell('LUT1', {'I': [18]}, {'O': [19]}, 17)
        module['ports']['result'] = {'direction': 'output', 'bits': [19]}
        rows = list(pairs(design, start='^a ', end='result'))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][5], 3)

    def carry_fixture(self, length):
        design = fixture()
        module = design['modules']['test']
        previous = 6
        for index in range(length):
            base = 100 + index*8
            module['cells']['carry' + str(index)] = cell('CARRY4',
                {'S': ['0']*4, 'DI': ['0']*4, 'CI': [previous], 'CYINIT': ['0']},
                {'O': list(range(base, base+4)), 'CO': list(range(base+4, base+8))}, 30)
            previous = base + 7
        module['ports']['result'] = {'direction': 'output', 'bits': [previous]}
        return design

    def test_carry_reduction_matches_full_pair_extrema(self):
        for sum_break in (False, True):
            design = self.carry_fixture(8)
            if sum_break:
                design['modules']['test']['cells']['carry4']['connections']['CI'] = [127]
            for carry_two in (False, True):
                for start, end in [(None, None), ('^a ', 'result'), ('ip_r', '^q_r ')]:
                    rows = list(pairs(design, start, end, carry_two))
                    expected = {kind: max((row[5], row[6]) for row in rows if row[2] == kind)
                                for kind in {row[2] for row in rows}}
                    actual = {kind: (row['levels'], row['max_fanout']) for kind, row in
                              worst(design, start, end, carry_two).items()}
                    self.assertEqual(actual, expected)

    def test_continuous_carry_chain_has_two_levels_and_default_is_unchanged(self):
        design = self.carry_fixture(8)
        raw, = pairs(design, start='^a ', end='result')
        normalized, = pairs(design, start='^a ', end='result', carry_chain_two=True)
        self.assertEqual(raw[5], 10)
        self.assertEqual(normalized[5], 4)

    def test_new_sum_input_path_can_overtake_longer_raw_carry_path(self):
        design = self.carry_fixture(8)
        module = design['modules']['test']
        previous = 2
        for index in range(4):
            bit = 200 + index
            module['cells']['detour' + str(index)] = cell('LUT1', {'I': [previous]},
                                                        {'O': [bit]}, 31)
            previous = bit
        module['cells']['carry7']['connections']['S'][3] = previous
        raw, = pairs(design, start='^a ', end='result')
        normalized, = pairs(design, start='^a ', end='result', carry_chain_two=True)
        self.assertEqual(raw[5], 10)
        self.assertEqual(normalized[5], 6)

    def test_sum_output_does_not_continue_native_carry_chain(self):
        design = self.carry_fixture(8)
        design['modules']['test']['cells']['carry4']['connections']['CI'] = [127]
        normalized, = pairs(design, start='^a ', end='result', carry_chain_two=True)
        self.assertEqual(normalized[5], 6)

    def test_lut_between_carry_chains_counts_two_separate_chains(self):
        design = self.carry_fixture(8)
        module = design['modules']['test']
        module['cells']['break'] = cell('LUT1', {'I': [131]}, {'O': [220]}, 32)
        module['cells']['carry4']['connections']['CI'] = [220]
        normalized, = pairs(design, start='^a ', end='result', carry_chain_two=True)
        self.assertEqual(normalized[5], 7)


class PdsParserTest(unittest.TestCase):
    def test_clock_fanout_and_async_paths_are_excluded(self):
        text = """Startpoint  : u_cpu/q_r/opit_0/CLK
Endpoint    : u_cpu/d_r/opit_0/D
Path Type   : max (slow corner)
Path Class  : sequential timing path
 net (fanout=9000) 1.000 4.000 clk_i
 Q tco 0.200 4.200 r u_cpu/q_r/opit_0/Q
 net (fanout=7) 0.300 4.500 u_cpu/q_r [0]
 Y td 0.100 4.600 r u_cpu/ip_lutram/mem/ram64x1d/DO
 net (fanout=3) 0.100 4.700 n1
 Y td 0.100 4.800 r u_cpu/logic/L6
 net (fanout=2) 0.100 4.900 n2
 Data arrival time 4.900 Logic Levels: 2
 Slack (VIOLATED) -0.125
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'timing.rtr'
            path.write_text(text + text.replace('sequential timing path', 'async timing path'))
            rows = list(read_pds(path))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]['fanout'], 7)
            self.assertEqual(rows[0]['launch_net'], 'u_cpu/q_r[0]')
            self.assertEqual(rows[0]['levels'], 2)
            cuts = list(read_pds(path, ram_cuts=True))
            self.assertEqual(len(cuts), 1)
            self.assertEqual((cuts[0]['category'], cuts[0]['levels'], cuts[0]['fanout']),
                             ('LUTRAM', 1, 3))


if __name__ == '__main__':
    unittest.main()
