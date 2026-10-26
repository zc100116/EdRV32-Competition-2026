#!/usr/bin/env python3
# File: test_netlist_paths.py
# Spec: C-Y1 acceptance.
# Description: Handwritten LUT-chain netlist with FF/IP boundaries and known fanout.
# Clock domain: host unit test.
import unittest

from netlist_paths import (analyze, core_bypass_cone, frontend_shift_sources,
                           hierarchy_resources, locations)


def cell(kind, inputs, outputs, line):
    return {'type': kind, 'attributes': {'src': f'rtl/test.v:{line}.1-{line}.9'},
            'port_directions': {**{p: 'input' for p in inputs},
                                **{p: 'output' for p in outputs}},
            'connections': dict(inputs, **outputs)}


def fixture():
    # a -> LUT1 -> LUT2 -> FF.D; FF.Q -> LUT3 -> y.
    # IP.out -> LUT4 -> FF.E; a and LUT2 -> IP.in. CLK/R are not fanout candidates.
    ports = {'a': ('input', 2), 'clk_i': ('input', 3), 'rst_n_i': ('input', 4),
             'y': ('output', 9), 'tap': ('output', 6)}
    return {'modules': {'test': {
        'attributes': {'top': '1', 'src': 'rtl/test.v:1.1-20.1'},
        'ports': {n: {'direction': d, 'bits': [b]} for n, (d, b) in ports.items()},
        'netnames': {n: {'hide_name': 0, 'bits': [b],
                         'attributes': {'src': 'rtl/test.v:1.1-1.9'}}
                     for n, b in [('a', 2), ('clk_i', 3), ('rst_n_i', 4), ('l1_w', 5),
                                  ('l2_w', 6), ('q_r', 7), ('ip_r', 8), ('y', 9),
                                  ('enable_w', 10)]},
        'cells': {
            'l1': cell('$lut', {'A': [2]}, {'Y': [5]}, 10),
            'l2': cell('$lut', {'A': [5, 2]}, {'Y': [6]}, 11),
            'ff': cell('$_DFFE_PN0P_', {'C': [3], 'R': [4], 'D': [6], 'E': [10]},
                       {'Q': [7]}, 12),
            'l3': cell('$lut', {'A': [7]}, {'Y': [9]}, 13),
            'l4': cell('$lut', {'A': [8]}, {'Y': [10]}, 14),
            'ip_test': cell('ip_test', {'clk': [3], 'addr': [2], 'en': [6]}, {'data': [8]}, 15),
        }}, 'ip_test': {'attributes': {'blackbox': '1'}}}}


class PathsTest(unittest.TestCase):
    def test_filtered_internal_interface_endpoint(self):
        result = analyze(fixture(), starts=[r'^a$'], end_nets=[r'^l1_w$'])
        self.assertEqual(result['max_levels'], 1)
        self.assertEqual(result['selected_endpoint_count'], 1)
        self.assertEqual(result['paths'][0]['end']['signal'], 'l1_w')
        self.assertEqual(result['paths'][0]['end']['boundary'], 'net')
        # An output alias of register Q must not accidentally select register D.
        result = analyze(fixture(), starts=[r'^a$'], end_nets=[r'^q_r$'])
        self.assertEqual(result['selected_endpoint_count'], 1)
        self.assertEqual(result['paths'], [])
        result = analyze(fixture(), starts=[r'^q_r$'], end_nets=[r'^q_r$'])
        self.assertEqual(result['max_levels'], 0)

    def test_filtered_start_propagates_before_longest_path_selection(self):
        design = fixture()
        module = design['modules']['test']
        # The selected IP root reaches FF.D in one level, while a takes two.
        module['cells']['l2']['connections']['A'].append(8)
        result = analyze(design, starts=[r'^ip_r$'], ends=[r'^q_r$'])
        self.assertEqual(result['max_levels'], 1)
        self.assertEqual(result['selected_start_bits'], 1)
        self.assertEqual(result['selected_endpoint_count'], 3)  # D, E and reset.
        self.assertEqual({p['end']['pin'] for p in result['paths']},
                         {'ff.D[0]', 'ff.E[0]'})
        self.assertTrue(all(p['start']['signal'] == 'ip_r' for p in result['paths']))

    def test_filtered_alias_sets_and_internal_cut(self):
        design = fixture()
        module = design['modules']['test']
        module['netnames']['u_cache.tag_w'] = dict(module['netnames']['l1_w'])
        result = analyze(design, starts=[r'^u_cache\.tag_w$'], ends=[r'^tap$', r'^ff\.D'])
        self.assertEqual(result['max_levels'], 1)
        self.assertEqual({p['end']['pin'] for p in result['paths']}, {'tap[0]', 'ff.D[0]'})
        self.assertTrue(all(p['start']['boundary'] == 'cut' for p in result['paths']))
        result = analyze(design, starts=[r'^a$', r'^ip_r$'], ends=[r'^tap$'])
        self.assertEqual(result['selected_start_bits'], 2)
        self.assertEqual(result['max_levels'], 2)

    def test_filtered_unreachable_endpoints_and_ff_cut(self):
        result = analyze(fixture(), starts=[r'^a$'], ends=[r'^y$'])
        self.assertIsNone(result['max_levels'])
        self.assertEqual(result['paths'], [])
        self.assertEqual(result['selected_endpoint_count'], 1)
        result = analyze(fixture(), starts=[r'^q_r$'], ends=[r'^y$'])
        self.assertEqual(result['max_levels'], 1)
        result = analyze(fixture(), starts=[r'^missing$'], ends=[r'^y$'])
        self.assertEqual(result['selected_start_bits'], 0)
        self.assertEqual(result['paths'], [])

    def test_levels_boundaries_and_fanout(self):
        design = fixture()
        design['modules']['test']['netnames']['u_reset_ctrl.a_w'] = {
            'hide_name': 1, 'bits': [2], 'attributes': {}}
        result = analyze(design)
        self.assertEqual(result['totals'], {'LUT': 4, 'FF': 1, 'blackbox': 1})
        self.assertEqual(result['max_levels'], 2)
        self.assertEqual(result['histogram'], {0: 2, 1: 2, 2: 3})
        ends = {p['end']['pin']: p for p in result['paths']}
        self.assertEqual(ends['ff.D[0]']['levels'], 2)
        self.assertEqual(ends['ff.D[0]']['start']['signal'], 'a')
        self.assertEqual(ends['y[0]']['levels'], 1)
        self.assertEqual(ends['y[0]']['start']['boundary'], 'FF')
        self.assertEqual(ends['ff.E[0]']['start']['boundary'], 'ip_test')
        self.assertEqual(ends['ip_test.en[0]']['levels'], 2)
        fanout = {p['signal']: p['fanout'] for p in result['fanout']}
        self.assertEqual(fanout['a'], 3)
        self.assertEqual(fanout['l2_w'], 3)
        self.assertNotIn('clk_i', fanout)
        self.assertNotIn('rst_n_i', fanout)
        self.assertEqual(sum(v.get('LUT', 0) for v in result['by_file'].values()), 4)

    def test_hierarchical_instance_counts(self):
        design = fixture()
        design['modules']['test']['attributes']['top'] = '0'
        design['modules']['host'] = {
            'attributes': {'top': '1', 'src': 'rtl/host.v:1.1-9.1'},
            'cells': {name: {'type': 'test'} for name in ('u_first', 'u_second')}}
        result = hierarchy_resources(design)
        self.assertEqual(result['totals'], {'LUT': 8, 'FF': 2, 'blackbox': 2})
        self.assertEqual(result['by_module']['test'], result['totals'])
        self.assertEqual(result['instances']['host.u_first']['own_cells']['LUT'], 4)

    def test_bypass_cone_shared_luts(self):
        module = fixture()['modules']['test']
        names = module['netnames']
        for index in range(4):
            names[f'd_operand_w[{index}]'] = dict(names['l2_w'])
        names['d_source_w[0]'] = dict(names['a'])
        result = core_bypass_cone(module)
        self.assertEqual(result['LUT'], 2)
        self.assertEqual(result['lut_cells'], ['l1', 'l2'])
        self.assertEqual(result['reached_cut_bits'], 1)

    def test_xc7_cells_and_carry_dependencies(self):
        design = fixture()
        module = design['modules']['test']
        module['cells']['l1']['type'] = 'LUT1'
        module['cells']['l2']['type'] = 'MUXF7'
        module['cells']['ff']['type'] = 'FDRE'
        module['cells']['ff']['connections']['CE'] = \
            module['cells']['ff']['connections'].pop('E')
        module['cells']['ff']['port_directions']['CE'] = \
            module['cells']['ff']['port_directions'].pop('E')
        module['cells']['carry'] = cell('CARRY4',
            {'S': [5, 2, 2, 2], 'DI': [2, 2, 2, 2], 'CI': ['0'], 'CYINIT': ['0']},
            {'O': [11, 12, 13, 14], 'CO': [15, 16, 17, 18]}, 16)
        module['ports']['carry'] = {'direction': 'output', 'bits': [18]}
        for kind in ['LUT1', 'FDRE', 'MUXF7', 'CARRY4']:
            design['modules'][kind] = {'attributes': {'blackbox': '1'}}
        result = analyze(design)
        self.assertEqual(result['totals'],
                         {'LUT': 3, 'MUX': 1, 'FF': 1, 'blackbox': 1, 'carry': 1})
        paths = {p['end']['pin']: p for p in result['paths']}
        self.assertEqual(paths['carry[0]']['carry_levels'], 1)
        self.assertEqual(paths['carry[0]']['levels'], 2)
        self.assertEqual(paths['tap[0]']['mux_levels'], 1)
        self.assertEqual(paths['tap[0]']['lut_levels'], 1)

    def test_frontend_source_span_union(self):
        module = fixture()['modules']['test']
        for name, source in [('l1', '231.1-231.9'), ('l2', '382.1-382.9'),
                             ('l3', '250.1-250.9'), ('l4', '267.1-382.9')]:
            module['cells'][name]['attributes']['src'] = 'rtl/cpu/edrv32_cpu_frontend.v:' + source
        result = frontend_shift_sources(module)
        self.assertEqual(result['frontend_LUT'], 4)
        self.assertEqual(result['with_frontend_src_LUT'], 4)
        self.assertEqual(result['source_union_LUT'], 3)
        self.assertEqual(result['by_source_line_LUT'], {231: 1, 267: 1, 382: 2})

    def test_inverter_level_and_resource(self):
        design = fixture()
        design['modules']['test']['cells']['l1'] = cell('INV', {'I': [2]}, {'O': [5]}, 10)
        result = analyze(design)
        self.assertEqual(result['totals']['INV'], 1)
        path = next(p for p in result['paths'] if p['end']['pin'] == 'ff.D[0]')
        self.assertEqual(path['levels'], 2)
        self.assertEqual(path['inv_levels'], 1)

    def test_combinational_dsp_and_registered_rejection(self):
        design = fixture()
        cells = design['modules']['test']['cells']
        cells['dsp'] = cell('DSP48E1', {'A': [5], 'B': [2], 'CLK': [3]}, {'P': [11]}, 18)
        cells['dsp']['parameters'] = {'AREG': '0', 'BREG': '0', 'PREG': '0'}
        cells['l4']['connections']['A'] = [11]
        result = analyze(design)
        self.assertEqual(result['totals']['DSP'], 1)
        path = next(p for p in result['paths'] if p['end']['pin'] == 'ff.E[0]')
        self.assertEqual(path['levels'], 3)
        self.assertEqual(path['dsp_levels'], 1)
        cells['dsp']['parameters']['PREG'] = '1'
        with self.assertRaisesRegex(ValueError, 'registered DSP48E1 is unsupported'):
            analyze(design)

    def test_lutram_read_address_and_write_boundary(self):
        design = fixture()
        module = design['modules']['test']
        del module['cells']['ip_test']
        module['cells']['btb_tag_r.0.0'] = cell('RAM32M',
            {'ADDRA': [6], 'ADDRD': [2], 'DIA': [10], 'WE': [4], 'WCLK': [3]},
            {'DOA': [8]}, 17)
        design['modules']['RAM32M'] = {'attributes': {'blackbox': '1'}}
        result = analyze(design)
        self.assertEqual(result['totals'], {'LUT': 4, 'FF': 1, 'LUTRAM': 1})
        paths = {p['end']['pin']: p for p in result['paths']}
        self.assertEqual(paths['ff.E[0]']['levels'], 4)
        self.assertEqual(paths['ff.E[0]']['memory_levels'], 1)
        self.assertEqual(paths['btb_tag_r.0.0.DIA[0]']['levels'], 4)
        self.assertEqual(result['memory_cells'][0]['rtl_array'], 'btb_tag_r')
        self.assertNotIn('btb_tag_r.0.0.ADDRA[0]', paths)
        self.assertIn('btb_tag_r.0.0.ADDRD[0]', paths)
        module['cells']['btb_tag_r.0.0']['connections']['ADDRA'] = ['0']
        result = analyze(design)
        path = next(p for p in result['paths'] if p['end']['pin'] == 'ff.E[0]')
        self.assertEqual(path['levels'], 2)
        self.assertEqual(path['start']['boundary'], 'RAM32M')
        self.assertLess(path['start']['bit'], 0)

    def test_mapped_carry_and_missing_source(self):
        design = fixture()
        cells = design['modules']['test']['cells']
        cells['l2']['type'] = 'CARRY'
        cells['l2']['attributes'] = {}
        design['modules']['test']['netnames']['l2_w']['attributes'] = {}
        result = analyze(design)
        path = next(p for p in result['paths'] if p['end']['pin'] == 'ff.D[0]')
        self.assertEqual((path['levels'], path['carry_levels']), (2, 1))
        self.assertEqual(result['totals']['carry'], 1)
        self.assertEqual(path['sources'][-1]['src'], '<ABC:no-src>')
        self.assertEqual(result['by_file']['<ABC-unattributed>']['carry'], 1)
        self.assertEqual(locations('rtl/test.v:10.1-12.4|/opt/yosys/techmap.v:1.1-2.2'),
                         ['rtl/test.v:10-12'])


if __name__ == '__main__':
    unittest.main()
