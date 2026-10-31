#!/usr/bin/env python3
# File: drm_budget.py
# Spec: Task T-DRM1; CLAUDE.md 1, 3.3, 12.
# Description: Add passive bind probes to existing test runners and scan temporary RAM copies.
# Clock domain: host; observed clocks are supplied by the bound RTL instance.
"""Run from the repository root after sourcing the normal toolchain environment."""
import argparse
import importlib.util
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
COMMON = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402


def bindings(sources, directory):
    text = ['// Generated passive binds; no RTL drives or verdict changes.']
    for source in sources:
        path = Path(source)
        if path.name.startswith('edrv32_ram_') and path.suffix == '.v':
            name = path.stem
            if name == 'edrv32_ram_sram':
                ports = ['clk_i', 'en_i && |wr_en_i', "32'(addr_i)",
                         'clk_i', 'en_i && !(|wr_en_i)', "32'(addr_i)"]
            else:
                independent = name in ('edrv32_ram_disp_scan', 'edrv32_ram_eth_fifo')
                ports = ['wr_clk_i' if independent else 'clk_i', 'wr_en_i',
                         "32'(wr_addr_i)", 'rd_clk_i' if independent else 'clk_i',
                         'rd_en_i', "32'(rd_addr_i)"]
            names = ['wr_clk_i', 'wr_en_i', 'wr_addr_i', 'rd_clk_i', 'rd_en_i', 'rd_addr_i']
            text.append(f'bind {name} edrv32_drm_probe u_drm_probe (\n' +
                        ',\n'.join(f'    .{n}({p})' for n, p in zip(names, ports)) + '\n);')
    levels = {
        'edrv32_mem_xbar_rbuf': ('clk_i', 'rst_n_i', "32'd128 - 32'(free_cnt_o)"),
        'edrv32_vin_ch': ('clk_i', 'rst_n_i', 'count_r'),
        'edrv32_vin_ch2': ('clk_i', 'rst_n_i', 'count_r'),
        'edrv32_vin_msrc': ('clk_i', 'rst_n_i', 'count_r'),
        'edrv32_npu_nonconv': ('clk_i', 'rst_n_i',
                                '$countones({plane_rd_en_w, row_rd_en_w})'),
        'edrv32_npu_conv': ('clk_i', 'rst_n_i', '$countones(slot_used_r)'),
        'edrv32_rnd_draw': ('clk_i', 'rst_n_i', '$countones(busy_r)'),
        'edrv32_rnd': ('clk_mem_i', 'rst_mem_n_i',
                       '$countones({u_draw.active_r, u_blit.active_r, (u_copy.state_r != u_copy.S_IDLE)})'),
        'edrv32_geo': ('clk_mem_i', 'rst_mem_n_i', '$countones(source_ready_r)'),
        'edrv32_async_fifo_ram': ('clk_write_i', 'rst_write_n_i',
                                 "($clog2(DEPTH)+1)'(write_bin_r - read_bin_r)"),
    }
    modules = {Path(source).stem for source in sources}
    for name, (clock, valid, value) in levels.items():
        if name in modules:
            text.append(f'bind {name} edrv32_drm_level_probe u_drm_level (\n'
                        f'    .clk_i({clock}),\n    .valid_i({valid}),\n'
                        f"    .level_i(32'({value}))\n);")
    if 'edrv32_geo' in modules:
        text.append("""bind edrv32_geo edrv32_drm_level_probe u_drm_groups (
    .clk_i(clk_mem_i),
    .valid_i(rst_mem_n_i),
    .level_i(32'($countones(source_ready_r |
        (fill_state_r != 0 ? (2'b01 << fill_group_r) : 2'b00))))
);""")
    if 'edrv32_mem_xbar' in modules:
        for port in range(1, 7):
            text.append(f"""bind edrv32_mem_xbar edrv32_drm_level_probe u_drm_w{port} (
    .clk_i(clk_i),
    .valid_i(rst_n_i),
    .level_i(32'(w_count_r[{port}]))
);""")
    if 'edrv32_npu_weight_store' in modules:
        text.append("""bind edrv32_npu_weight_store edrv32_drm_probe u_drm_logical (
    .wr_clk_i(clk_i),
    .wr_en_i(weight_wr_valid_i),
    .wr_addr_i(32'(weight_wr_addr_i[13:3])),
    .rd_clk_i(clk_i),
    .rd_en_i(weight_rd_en_i),
    .rd_addr_i(32'(weight_rd_addr_i))
);""")
    if 'edrv32_npu_nonconv' in modules:
        text.append("""bind edrv32_npu_nonconv edrv32_drm_level_probe u_drm_writes (
    .clk_i(clk_i),
    .valid_i(rst_n_i),
    .level_i(32'($countones({plane_wr_en_w, row_wr_en_w})))
);""")
    path = directory / 'bind.sv'
    path.write_text('\n'.join(text)+'\n')
    return [str(COMMON/'edrv32_drm_probe.sv'),
            str(COMMON/'edrv32_drm_level_probe.sv'), str(path)]


def split_model(path, directory, low_width):
    source = path.read_text()
    match = re.search(r'reg \[(\d+):0\] memory_r \[0:1023\];', source)
    width = int(match[1])+1
    source = source.replace(match[0],
        f'reg [{low_width-1}:0] low_r [0:1023];\n'
        f'    reg [{width-low_width-1}:0] high_r [0:1023];')
    source = source.replace('memory_r[wr_addr_i] <= wr_data_i;',
        f'low_r[wr_addr_i] <= wr_data_i[{low_width-1}:0];\n'
        f'            high_r[wr_addr_i] <= wr_data_i[{width-1}:{low_width}];')
    source = source.replace('memory_r[rd_addr_i]',
                            '{high_r[rd_addr_i], low_r[rd_addr_i]}')
    target = directory/path.name
    target.write_text(source)
    return str(target)


def packed_geo_model(path, directory):
    source = path.read_text()
    start = source.index('    reg [127:0] memory_r [0:255];')
    end = source.index('`endif', start)
    source = source[:start]+'''    // Measurement model: one 64-bit physical write per bank per cycle.
    // The queue measures required elasticity; it is not a proposed FIFO implementation.
    /* verilator lint_off BLKSEQ */
    typedef struct packed {
        reg [7:0] addr;
        reg [127:0] data;
    } request_t;
    request_t requests[$];
    request_t current_r;
    request_t incoming_r;
    reg high_r = 0;
    reg [63:0] memory_r [0:511];
    reg [15:0] rd_array_r;
    integer peak_r = 0;
    integer collisions_r = 0;
    assign rd_data_o = rd_array_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            incoming_r.addr = wr_addr_i;
            incoming_r.data = wr_data_i;
            requests.push_back(incoming_r);
        end
        if (requests.size() + 32'(high_r) > peak_r)
            peak_r = requests.size() + 32'(high_r);
        if (high_r) begin
            memory_r[{current_r.addr, 1'b1}] <= current_r.data[127:64];
            if (rd_en_i && rd_addr_i[10:2] == {current_r.addr, 1'b1})
                collisions_r = collisions_r + 1;
            high_r <= 0;
        end else if (requests.size() != 0) begin
            current_r = requests.pop_front();
            memory_r[{current_r.addr, 1'b0}] <= current_r.data[63:0];
            if (rd_en_i && rd_addr_i[10:2] == {current_r.addr, 1'b0})
                collisions_r = collisions_r + 1;
            high_r <= 1;
        end
        if (rd_en_i)
            rd_array_r <= memory_r[rd_addr_i[10:2]][{rd_addr_i[1:0], 4'b0} +: 16];
    end
    final $display("DRM_PACK_GEO %m pending_peak=%0d collisions=%0d", peak_r, collisions_r);
    /* verilator lint_on BLKSEQ */
'''+source[end:]
    target = directory/path.name
    target.write_text(source)
    return str(target)


def weight_tail_model(path, directory):
    source = path.read_text()
    source = source.replace('    reg [255:0] memory_r [0:511];', '''    reg [255:0] memory_r [0:511];
    reg [255:0] tail_r [0:127];
    reg is_tail_r = 0;
    initial begin
        string scope;
        scope = $sformatf("%m");
        for (integer i = 0; i <= scope.len()-12; i = i+1)
            if (scope.substr(i, i+11) == "g_segment[2]") is_tail_r = 1;
    end''')
    source = source.replace('memory_r[wr_addr_i] <= wr_data_i;',
        'if (is_tail_r) tail_r[wr_addr_i[6:0]] <= wr_data_i;\n'
        '            else memory_r[wr_addr_i] <= wr_data_i;')
    source = source.replace('rd_array_r <= memory_r[rd_addr_i];',
        'rd_array_r <= is_tail_r ? tail_r[rd_addr_i[6:0]] : memory_r[rd_addr_i];')
    target = directory/path.name
    target.write_text(source)
    return str(target)


def shared_model(path, directory, kind):
    """Temporary behavioral storage sharing; preserve the original enabled read process."""
    package = directory/'drm_shared.sv'
    package.write_text('package drm_shared;\n/* verilator lint_off MULTIDRIVEN */\n'
                       '    reg [255:0] memory_r [0:11][0:511];\n'
                       '/* verilator lint_on MULTIDRIVEN */\nendpackage\n')
    source = path.read_text()
    source = source.replace('    reg [255:0] memory_r [0:511];',
        '''    function automatic integer contains(input string scope, input string key);
        contains = 0;
        for (integer i = 0; i <= scope.len()-key.len(); i = i+1)
            if (scope.substr(i, i+key.len()-1) == key) contains = 1;
    endfunction
    reg [3:0] physical_r;
    integer offset_r;
    initial begin
        string scope;
        scope = $sformatf("%m");
        offset_r = 0;
''' + (
        '''        physical_r = 0;
        if (contains(scope, "u_row_scratch")) offset_r = 128;
''' if kind == 'scratch' else '''        physical_r = contains(scope, "g_bank[1]") ? 6 : 0;
        if (contains(scope, "u_copy")) physical_r = 2;
        if (contains(scope, "u_blit") && contains(scope, "u_target")) physical_r += 4;
        if (contains(scope, "u_result")) physical_r += 1;
        if (contains(scope, "u_source")) begin
            physical_r += 2;
            if (contains(scope, "g_sample[1]")) physical_r += 2;
            if (contains(scope, "u_source_next")) physical_r += 1;
        end
''') + '    end')
    source = re.sub(r'contains\(scope, "[^"]+"\)', r'(\g<0> != 0)', source)
    if kind == 'rnd':
        source = source.replace('    integer offset_r;\n', '').replace('        offset_r = 0;\n', '')
    source = source.replace('memory_r[wr_addr_i]',
                            "drm_shared::memory_r[physical_r][offset_r + 32'(wr_addr_i)]")
    source = source.replace('memory_r[rd_addr_i]',
                            "drm_shared::memory_r[physical_r][offset_r + 32'(rd_addr_i)]")
    if kind == 'rnd':
        for address in ('wr_addr_i', 'rd_addr_i'):
            source = source.replace("offset_r + 32'("+address+")",
                "(physical_r % 6 < 2 ? 32'("+address+"[5:0]) : 32'("+address+"))")
    target = directory/path.name
    target.write_text(source)
    return [str(package), str(target)]


def instrument(sources, directory, scan, share, pack_pix, pack_geo, pack_line, weight_tail):
    probes = bindings(sources, directory)
    result = []
    for source in sources:
        path = Path(source)
        if scan and path.name == scan[0]+'.v':
            depth = scan[1]
            source_text = path.read_text()
            source_text, count = re.subn(r'memory_r \[0:\d+\]',
                                        f'memory_r [0:{depth-1}]', source_text)
            if count != 1:
                raise ValueError(f'Expected one memory array in {path.name}, got {count}')
            # Deliberate depth experiment: high address bits alias in this temporary copy.
            bits = (depth-1).bit_length()
            for address in ('wr_addr_i', 'rd_addr_i', 'addr_i'):
                source_text = source_text.replace(f'memory_r[{address}]',
                                                  f'memory_r[{address}[{bits-1}:0]]')
            if path.name == 'edrv32_ram_geo_src.v':
                source_text = source_text.replace('memory_r[rd_addr_i[10:3]]',
                    f'memory_r[rd_addr_i[{bits+2}:3]]')
            target = directory/path.name
            target.write_text(source_text)
            source = str(target)
        if weight_tail and path.name == 'edrv32_ram_npu_weight.v':
            result.append(weight_tail_model(path, directory))
        elif pack_line and path.name == 'edrv32_ram_npu_line.v':
            result.append(split_model(path, directory, 252))
        elif pack_geo and path.name == 'edrv32_ram_geo_src.v':
            result.append(packed_geo_model(path, directory))
        elif pack_pix and path.name == 'edrv32_ram_pix_line.v':
            result.append(split_model(path, directory, 36))
        elif share and path.name == ('edrv32_ram_npu_scratch.v' if share == 'scratch'
                                    else 'edrv32_ram_rnd_line.v'):
            result += shared_model(path, directory, share)
        else:
            result.append(source)
    return result+probes


def snapshot(module, tier, out, case_dir):
    if case_dir:
        logs = [case_dir.resolve()/('drm_'+out.name+'.log')]
    elif module in ('vin', 'sram', 'mem_xbar') or (module == 'disp' and tier == 'frame'):
        logs = [out/(tier+'.log')]
    elif module == 'npu':
        name = 'yolo' if tier in ('NET-01', 'NET-02') else tier.lower().replace('-', '_')
        logs = sorted((ROOT/'build/npu'/name).rglob('run_*.log'))
    elif module == 'disp':
        logs = sorted((ROOT/'build/disp').glob('DS-*.log'))
    else:
        folder = ROOT/'build'/module/('dut' if module == 'pix' else tier)
        logs = sorted(folder.rglob('run.log'))
    lines = []
    for log in logs:
        lines.append(str(log.relative_to(ROOT)))
        lines += [line for line in log.read_text().splitlines()
                  if any(word in line for word in ('DRM_', 'PERF', 'PASS', 'FAIL',
                                                    'doorbell_irq_cycles'))]
    (out/(tier+'-usage.txt')).write_text('\n'.join(lines)+'\n')


def weight_reload(case_dir):
    from prepare import Image, regs
    image = Image(case_dir)
    register = regs(case_dir)
    extra = 0
    weights = 0
    max_block = 0
    for index in range(register['DESC_COUNT']):
        address = register['DESC_BASE'] + 64*index
        word = [image.word(address+4*n) for n in range(16)]
        if word[0] & 15:
            continue
        blocks = (word[10] >> 8) & 15
        block_bytes = word[12] & 0xfffff
        half = bool(word[0] & 512) and not bool(word[0] & 256)
        layer_bytes = (blocks-1)*block_bytes + block_bytes//(2 if half else 1)
        weights += layer_bytes
        max_block = max(max_block, block_bytes)
        if blocks > 1:
            extra += (((word[9] >> 16) & 4095)-1)*layer_bytes
    print(f'DRM_RELOAD weights={weights} max_block={max_block} extra_bytes={extra}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('module', choices=('npu', 'rnd', 'vin', 'pix', 'geo', 'disp',
                                          'sram', 'mem_xbar', 'vin_ch2'))
    parser.add_argument('tier', help='Existing runner tier, or smoke/full for unit tests')
    parser.add_argument('--weight-tail', action='store_true')
    parser.add_argument('--pack-npu-line', action='store_true')
    parser.add_argument('--pack-geo', action='store_true')
    parser.add_argument('--pack-pix', action='store_true')
    parser.add_argument('--share', choices=('scratch', 'rnd'))
    parser.add_argument('--case-dir', type=Path, help='Prepared NPU interchange directory')
    parser.add_argument('--scan', nargs=2, metavar=('WRAPPER', 'DEPTH'))
    args = parser.parse_args()
    scan = (args.scan[0], int(args.scan[1])) if args.scan else None
    if args.weight_tail:
        label = 'weight-tail'
    elif args.pack_npu_line:
        label = 'pack-npu-line'
    elif args.pack_geo:
        label = 'pack-geo'
    elif args.pack_pix:
        label = 'pack-pix'
    elif args.share:
        label = 'share-'+args.share
    else:
        label = f'{scan[0]}-{scan[1]}' if scan else 'baseline'
    out = ROOT/'build/drm_budget'/args.module/label
    out.mkdir(parents=True, exist_ok=True)
    if args.module in ('sram', 'mem_xbar', 'vin') or (
            args.module == 'disp' and args.tier == 'frame'):
        folder = ('verif/block/disp' if args.module == 'disp' else
                  'verif/block/vin' if args.module == 'vin' else
                  'verif/unit/'+('bus_sram' if args.module == 'sram' else 'mem_xbar'))
        sources = instrument(expand_files(ROOT/folder/'files.f'), out, scan, args.share,
                             args.pack_pix, args.pack_geo, args.pack_npu_line, args.weight_tail)
        top = ('tb_layers' if args.module == 'disp' else
               'edrv32_vin_tb' if args.module == 'vin' else 'tb')
        command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                   '--timescale', '1ns/1ps', '-Wno-BLKSEQ', '-Wno-UNUSEDSIGNAL',
                   '-Wno-SYNCASYNCNET', '--top-module', top,
                   '--Mdir', str(out/'obj'), '-o', 'sim', '+define+SIM_MODE']
        if args.module == 'mem_xbar':
            command += ['-Wno-UNDRIVEN']
            command += [f'-GFULL={int(args.tier == "full")}']
        with (out/'compile.log').open('w') as log:
            subprocess.run(command+sources, cwd=ROOT, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        with (out/(args.tier+'.log')).open('w') as log:
            selected = 6 if args.module == 'disp' else args.tier
            subprocess.run([str(out/'obj/sim'), f'+CASE={selected}'], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        print(f'PASS {args.module} {args.tier}: {out/(args.tier+".log")}')
        snapshot(args.module, args.tier, out, args.case_dir)
        return
    folder = ROOT/'verif/block'/('vin/ch2' if args.module == 'vin_ch2' else args.module)
    sys.path.insert(0, str(folder))
    spec = importlib.util.spec_from_file_location('drm_runner', folder/'run.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    def measured_files(path):
        sources = expand_files(path)
        if any(Path(p).name.startswith('edrv32_ram_') for p in sources):
            return instrument(sources, out, scan, args.share, args.pack_pix, args.pack_geo,
                              args.pack_npu_line, args.weight_tail)
        return sources
    runner.expand_files = measured_files
    sys.argv = ['run.py']+(['--test', args.tier] if args.module == 'npu' else [args.tier])
    if args.case_dir:
        weight_reload(args.case_dir.resolve())
        executable = runner.build(False)
        code, output, log = runner.simulate(executable, args.case_dir.resolve(),
            [f'+TEST_ID={args.tier}', '+MEM_MODE=bw'], 'drm_'+label)
        if code or 'PASS NB' not in output or 'FAIL' in output:
            raise RuntimeError(f'NPU {args.tier} failed: {log}')
        print(f'PASS NPU {args.tier} '+label)
        result = 0
    else:
        result = runner.main()
    snapshot(args.module, args.tier, out, args.case_dir)
    if result:
        raise SystemExit(result)


if __name__ == '__main__':
    main()
