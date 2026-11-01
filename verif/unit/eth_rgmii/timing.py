#!/usr/bin/env python3
# File: timing.py
# Spec: Task E-F1; CLAUDE.md 1.4, 3.5.
# Description: Compare RGMII/FIFO LUT6 path depths at a baseline commit and current RTL.
# Clock domain: host tool; no placement, routing or clock timing model.
"""Run from the repository root: python3 verif/unit/eth_rgmii/timing.py BASE_COMMIT."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.synth.netlist_paths import analyze

OUT = Path('build/eth_timing')
for version in ('before', 'after'):
    (OUT / version).mkdir(parents=True, exist_ok=True)
for source in ['fpga/rtl/edrv32_fpga_rgmii.v', 'rtl/eth/edrv32_eth_tx_front.v']:
    (OUT / 'before' / Path(source).name).write_bytes(subprocess.check_output(
        ['git', 'show', sys.argv[1] + ':' + source], cwd=ROOT))
(OUT / 'stubs.v').write_text('''
(* blackbox *) module ip_pll_eth(input clkin1, clkfb, output clkout0, output lock); endmodule
(* blackbox *) module GTP_CLKBUFG(input CLKIN, output CLKOUT); endmodule
(* blackbox *) module GTP_INBUF #(parameter IOSTANDARD="LVCMOS33")
(input I, output O); endmodule
(* blackbox *) module GTP_OUTBUF #(parameter IOSTANDARD="LVCMOS33", SLEW_RATE="FAST",
DRIVE_STRENGTH="4") (input I, output O); endmodule
(* blackbox *) module GTP_IODELAY_E2 #(parameter DELAY_STEP_SEL="PORT",
DELAY_STEP_VALUE=8'd0, TDELAY_EN="FALSE") (input DI, DELAY_SEL,
input [7:0] DELAY_STEP, input EN_N, output DO); endmodule
(* blackbox *) module GTP_IDDR_E1 #(parameter GRS_EN="TRUE",
IDDR_MODE="SAME_PIPELINED", RS_TYPE="ASYNC_RESET")
(input D, CLK, CE, RS, output Q0, Q1); endmodule
(* blackbox *) module GTP_ODDR_E1 #(parameter GRS_EN="TRUE",
ODDR_MODE="SAME_EDGE", RS_TYPE="ASYNC_RESET")
(input CLK, CE, RS, D0, D1, output Q); endmodule
(* blackbox *) module ip_ram_eth_fifo(input wr_clk, wr_rst, wr_en,
input [8:0] wr_addr, input [9:0] wr_data, input rd_clk, rd_rst, rd_clk_en,
input [8:0] rd_addr, output [9:0] rd_data); endmodule
''')
(OUT / 'wrapper.v').write_text('''
module eth_timing(input rxc, input [3:0] rxd, input rx_ctl,
input clk_mem, rst_mem_n, rst_eth_n,
input rx_ready, output rx_valid, output [9:0] rx_data,
input tx_valid, input [9:0] tx_data, output tx_ready,
output txc, output [3:0] txd, output tx_ctl, output done);
wire clk_eth;
wire [7:0] mac_rx_data;
wire [7:0] mac_tx_data;
wire mac_rx_dv;
wire mac_rx_er;
wire mac_tx_en;
wire mac_tx_er;
wire rx_fifo_valid;
wire rx_fifo_ready;
wire [9:0] rx_fifo_data;
wire tx_fifo_valid;
wire tx_fifo_ready;
wire [9:0] tx_fifo_data;
edrv32_fpga_rgmii u_rgmii (
    .rgmii_rxc_i(rxc),
    .rgmii_rxd_i(rxd),
    .rgmii_rx_ctl_i(rx_ctl),
    .clk_eth_o(clk_eth),
    .eth_rxd_o(mac_rx_data),
    .eth_rx_dv_o(mac_rx_dv),
    .eth_rx_er_o(mac_rx_er),
    .eth_txd_i(mac_tx_data),
    .eth_tx_en_i(mac_tx_en),
    .eth_tx_er_i(mac_tx_er),
    .rgmii_txc_o(txc),
    .rgmii_txd_o(txd),
    .rgmii_tx_ctl_o(tx_ctl));
edrv32_eth_rx_front u_rx_front (.clk_i(clk_eth), .rst_n_i(rst_eth_n),
    .data_i(mac_rx_data),
    .valid_i(mac_rx_dv),
    .error_i(mac_rx_er),
    .valid_o(rx_fifo_valid),
    .data_o(rx_fifo_data));
edrv32_eth_fifo u_rx_fifo (.clk_write_i(clk_eth), .rst_write_n_i(rst_eth_n),
    .clk_read_i(clk_mem),
    .rst_read_n_i(rst_mem_n),
    .valid_i(rx_fifo_valid),
    .ready_o(rx_fifo_ready),
    .data_i(rx_fifo_data),
    .valid_o(rx_valid),
    .ready_i(rx_ready),
    .data_o(rx_data));
edrv32_eth_fifo u_tx_fifo (.clk_write_i(clk_mem), .rst_write_n_i(rst_mem_n),
    .clk_read_i(clk_eth),
    .rst_read_n_i(rst_eth_n),
    .valid_i(tx_valid),
    .ready_o(tx_ready),
    .data_i(tx_data),
    .valid_o(tx_fifo_valid),
    .ready_i(tx_fifo_ready),
    .data_o(tx_fifo_data));
edrv32_eth_tx_front u_tx_front (.clk_i(clk_eth), .rst_n_i(rst_eth_n),
    .valid_i(tx_fifo_valid),
    .ready_o(tx_fifo_ready),
    .data_i(tx_fifo_data[8:0]),
    .data_o(mac_tx_data),
    .valid_o(mac_tx_en),
    .error_o(mac_tx_er),
    .done_o(done));
endmodule
''')
for version in ('before', 'after'):
    board = (str(OUT / 'before/edrv32_fpga_rgmii.v') if version == 'before'
             else 'fpga/rtl/edrv32_fpga_rgmii.v')
    front = (str(OUT / 'before/edrv32_eth_tx_front.v') if version == 'before'
             else 'rtl/eth/edrv32_eth_tx_front.v')
    files = [str(OUT / 'stubs.v'), str(OUT / 'wrapper.v'), board, front,
             'rtl/eth/edrv32_eth_rx_front.v', 'rtl/eth/edrv32_eth_crc.v',
             'rtl/eth/edrv32_eth_fifo.v', 'rtl/tech/edrv32_ram_eth_fifo.v',
             'rtl/common/edrv32_async_fifo_ram.v', 'rtl/common/edrv32_cdc_sync_bit.v']
    script = OUT / version / 'synth.ys'
    netlist = OUT / version / 'netlist.json'
    script.write_text('read_verilog -D FPGA_MODE -Irtl/include ' + ' '.join(files) + '\n' +
                      'hierarchy -top eth_timing\nsynth -top eth_timing -flatten -noabc\n' +
                      'abc -lut 6 -dress\nopt_clean\nwrite_json ' + str(netlist) + '\nstat\n')
    subprocess.run(['yosys', '-Q', '-T', '-l', str(OUT / version / 'synth.log'), '-s', str(script)],
                   check=True, stdout=subprocess.DEVNULL)
    design = json.loads(netlist.read_text())
    # netlist_paths recognizes ip_* black boxes; keep cell/instance names and raw JSON unchanged.
    renames = {name: 'ip_measure_' + name for name, module in design['modules'].items()
               if int(module.get('attributes', {}).get('blackbox', '0'), 2)
               and not name.startswith('ip_')}
    for module in design['modules'].values():
        for cell in module.get('cells', {}).values():
            cell['type'] = renames.get(cell['type'], cell['type'])
    for old, new in renames.items():
        design['modules'][new] = design['modules'].pop(old)
    queries = {
        'rx_io_to_ram': ([r'u_rgmii\.rx_(rise|fall)_w'], [r'u_rx_fifo\.u_memory\.u_ip\.wr_data']),
        'rx_io_to_frame': ([r'u_rgmii\.rx_(rise|fall)_w'], [r'u_rx_front\.frame_r']),
        'rx_io_to_crc': ([r'u_rgmii\.rx_(rise|fall)_w'], [r'u_rx_front\.crc_r']),
        'tx_ram_to_oddr': ([r'u_tx_fifo\.u_memory\.u_ip\.rd_data'],
                             [r'u_rgmii\.g_tx\[.*\.u_ddr\.D[01]']),
        'rx_io_to_stage': ([r'u_rgmii\.rx_(rise|fall)_w'], [r'u_rgmii\.rx_(data|dv|er)_r']),
        'rx_stage_to_ram': ([r'u_rgmii\.rx_(data|dv|er)_r'],
                              [r'u_rx_fifo\.u_memory\.u_ip\.wr_data']),
        'rx_stage_to_frame': ([r'u_rgmii\.rx_(data|dv|er)_r'], [r'u_rx_front\.frame_r']),
        'rx_stage_to_crc': ([r'u_rgmii\.rx_(data|dv|er)_r'], [r'u_rx_front\.crc_r']),
        'tx_ram_to_stage': ([r'u_tx_fifo\.u_memory\.u_ip\.rd_data'], [r'u_rgmii\.tx_(data|en|er)_r']),
        'tx_stage_to_oddr': ([r'u_rgmii\.tx_(data|en|er)_r'],
                               [r'u_rgmii\.g_tx\[.*\.u_ddr\.D[01]']),
    }
    summary = {}
    for name, (starts, ends) in queries.items():
        result = analyze(design, starts, ends)
        summary[name] = {'max_levels': result['max_levels'],
                         'endpoint_count': result['endpoint_count']}
        (OUT / version / (name + '.json')).write_text(json.dumps(result, indent=2) + '\n')
    (OUT / version / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(version, json.dumps(summary, indent=2))
