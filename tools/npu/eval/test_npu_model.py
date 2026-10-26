"""Directed stage checks for known small C16/C32 layers and serial DMA."""

import unittest

from npu_model import conv_stages, operator_cycles, read_cycles


class LegacyStageTests(unittest.TestCase):
    def small_conv(self):
        return dict(index=1, name='small', kind='conv', input_width=8,
                    input_height=3, output_width_pairs=4, output_height=3,
                    cin_blocks=1, output_blocks=1, kernel3=1, stride2=0,
                    tile_pairs=4, lut_enable=1, last_c16_only=0,
                    quant_base=4096, weight_base=8192, weight_block_stride=4608,
                    input_base=12288, input_plane_stride=384,
                    output_base=16384, output_plane_stride=384,
                    weight_bytes=4608, quant_bytes=512)

    def test_c16_3x3_three_rows(self):
        c = self.small_conv()
        p = conv_stages(c, 0)
        # 8x3 output, K=18, four pixel pairs per row; all three input rows
        # are cached once, including the middle row shared by all outputs.
        self.assertEqual(p['mac'], 216)
        self.assertEqual(p['weight'], 149)
        self.assertEqual(p['quant'], 310)
        self.assertEqual(p['feature'], 24)
        self.assertEqual(p['row_prepare'], 12)
        self.assertEqual(p['patch_pipeline'], 288)
        self.assertEqual(p['write_response'], 9)
        self.assertEqual(sum(p.values()), 1047)

    def test_latency_charges_only_missing_rows(self):
        c = self.small_conv()
        zero = conv_stages(c, 0)
        delayed = conv_stages(c, 30)
        self.assertEqual(delayed['feature'] - zero['feature'], 90)
        self.assertEqual(delayed['write_response'] - zero['write_response'], 90)
        self.assertEqual(delayed['mac'], zero['mac'])
        self.assertEqual(delayed['patch_pipeline'], zero['patch_pipeline'])

    def test_reader_outstanding_and_boundary(self):
        self.assertEqual(read_cycles(16, 0, 0), 16)
        self.assertEqual(read_cycles(16, 0, 30), 46)
        self.assertEqual(read_cycles(80, 0, 100), 233)
        self.assertEqual(read_cycles(20, 126, 0), 20)

    def test_residual_serial_three_transactions(self):
        c = dict(kind='add', beat_count=16)
        self.assertEqual(operator_cycles(c, 0), 62)
        self.assertEqual(operator_cycles(c, 30), 152)

    def test_pool_has_three_sample_states(self):
        c = dict(kind='pool', input_width=20, input_height=12, cin_blocks=8,
                 input_base=4096, input_plane_stride=3840,
                 output_base=8192, output_plane_stride=3840)
        # 1920 vector pixels * 25 neighbours * 3 state cycles = 144000.
        self.assertEqual(operator_cycles(c, 0), 146164)
        self.assertEqual(operator_cycles(c, 30), 149464)


if __name__ == '__main__':
    unittest.main()
