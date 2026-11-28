#!/usr/bin/env python3
"""Yosys LUT4/LUT6 reference excluding technology APM/LUTRAM internals."""
from pathlib import Path
import argparse
import io
import tarfile
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lut', type=int, choices=(4, 6), default=4)
parser.add_argument('--revision')
parser.add_argument('--out', type=Path, default=Path('build/gpu2_synth'))
parser.add_argument('tops', nargs='*')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = root / args.out
out.mkdir(parents=True, exist_ok=True)
source_root = root
if args.revision:
    source_root = out / 'source'
    source_root.mkdir(exist_ok=True)
    archive = subprocess.check_output(['git', 'archive', args.revision, 'rtl/gpu2',
                                       'rtl/tech', 'rtl/include', 'fpga/rtl'], cwd=root)
    with tarfile.open(fileobj=io.BytesIO(archive)) as archive_file:
        archive_file.extractall(source_root, filter='data')
(out / 'tech.v').write_text('''(* blackbox *) module edrv32_apm_gpu2_u24xu24 (
 input clk_i, input [5:0] enable_i, input [23:0] a_i, input [23:0] b_i,
 output [47:0] product_o); endmodule
(* blackbox *) module edrv32_ram_gpu2_queue (
 input clk_i, input wr_en_i, input [3:0] wr_addr_i, input [31:0] wr_data_i,
 input [3:0] rd_addr_i, output [31:0] rd_data_o); endmodule
(* blackbox *) module ip_rom_gpu2_sfu (
 input a_clk, input a_rst, input a_wr_en, input [31:0] a_wr_data, input a_clk_en, input [9:0] a_addr, output [31:0] a_rd_data,
 input b_clk, input b_rst, input b_wr_en, input [31:0] b_wr_data, input b_clk_en, input [9:0] b_addr, output [31:0] b_rd_data); endmodule
(* blackbox *) module ip_ram_gpu2_sfu_scratch (
 input wr_clk, input wr_rst, input wr_en, input [9:0] wr_addr, input [31:0] wr_data,
 input rd_clk, input rd_rst, input rd_clk_en, input [9:0] rd_addr, output [31:0] rd_data); endmodule
(* blackbox *) module ip_lutram_gpu2_sfu_word16 (
 input wr_clk, input rd_clk, input rst, input wr_en, input [4:0] wr_addr,
 input [15:0] wr_data, input [4:0] rd_addr, output [15:0] rd_data); endmodule
(* blackbox *) module ip_lutram_gpu2_sfu_word5 (
 input wr_clk, input rd_clk, input rst, input wr_en, input [4:0] wr_addr,
 input [4:0] wr_data, input [4:0] rd_addr, output [4:0] rd_data); endmodule
''')
sources = sorted([*(source_root / 'rtl/gpu2').glob('edrv32_gpu2_fp32*.v'),
                  *(source_root / 'rtl/gpu2').glob('edrv32_gpu2_sfu*.v')])
sources += [source_root / 'fpga/rtl/edrv32_fpga_probe_gpu2_fp32_top.v',
            source_root / 'fpga/rtl/edrv32_fpga_probe_gpu2_sfu_top.v']
sources += sorted((source_root / 'rtl/tech').glob('edrv32_ram_gpu2_sfu*.v'))
sources += [source_root / 'rtl/tech/edrv32_rom_gpu2_sfu.v']
for top in args.tops or ['edrv32_gpu2_fp32_scalar', 'edrv32_gpu2_fp32',
                                  'edrv32_gpu2_sfu_arithmetic',
                                  'edrv32_fpga_probe_gpu2_fp32_top', 'edrv32_gpu2_sfu',
                                  'edrv32_fpga_probe_gpu2_sfu_top', 'edrv32_gpu2_fp32_add']:
    script = (f'read_verilog -D FPGA_MODE -I{source_root / "rtl/include"} {out / "tech.v"} '
              + ' '.join(str(p) for p in sources)
              + f'; synth -top {top} -flatten -noabc; abc -lut {args.lut}; stat; ltp -noff; '
              + f'write_json {out / (top + ".json")}')
    with (out / (top + '.log')).open('w') as log:
        subprocess.run(['yosys', '-p', script], cwd=source_root, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    print(top, 'reference log:', out / (top + '.log'))
