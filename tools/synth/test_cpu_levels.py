#!/usr/bin/env python3
# File: test_cpu_levels.py
# Spec: T-CPU-N-T2BE section 0.
# Description: Exercise distinct launch boundaries, CE paths and mapped primitive counting.
# Clock domain: host test.
import unittest
from pathlib import Path
import tempfile

from tools.synth.cpu_calibrate import read_pds

from tools.synth.cpu_levels import pairs
from tools.synth.test_netlist_paths import fixture, cell


class PairLevelsTest(unittest.TestCase):
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
