#!/usr/bin/env python3
# File: audit_branches.py; cpu-v2-spec 5.2/5.4; clock: host.
"""Read-only per-branch audit of the unchanged model and RTL public cycle probe."""
import argparse
import csv
import inspect
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/cpu'))
import run_model_conformance as conformance


def model_audit(directory):
    simulate = conformance.simulate
    source, first = inspect.getsourcelines(simulate)
    issue_line = first + next(i for i, line in enumerate(source)
                              if 'record.late_store_data = older_store' in line)
    retire_line = first + next(i for i, line in enumerate(source)
                               if line.strip() == 'if record.late:')
    scheduled, issued, retired = {}, {}, {}
    timeline = []

    def trace_schedule(frame, event, result):
        if event == 'return':
            data = frame.f_locals
            instruction = data['instruction']
            if instruction.kind == 'branch':
                older = data['older']
                scheduled[(frame.f_back.f_locals['tick'], instruction.pc)] = {
                    'needs': list(data['needs']),
                    'older_pc': older.pc if older else None,
                    'older_rd': older.rd if older else None,
                    'sources': list(instruction.sources),
                    'ready': [data['ready_in'].get(s, 0) for s in instruction.sources]}
        return trace_schedule

    def trace_simulate(frame, event, unused):
        if event == 'line' and frame.f_lineno in (issue_line, retire_line):
            data = frame.f_locals
            record = data['record']
            if record.instruction.kind == 'branch':
                if frame.f_lineno == issue_line:
                    issued[id(record)] = (record, scheduled[(data['tick'], record.instruction.pc)], data['tick'])
                elif data['active'] and data['pc'] != data['end']:
                    instruction = record.instruction
                    _, waits, issue_tick = issued[id(record)]
                    retired[instruction.pc] = dict(waits,
                        tick=issue_tick, late=record.late,
                        wrong=(record.taken != (record.next_pc != instruction.pc+4) or
                               record.taken and record.target != record.next_pc))
        return trace_simulate

    def trace(frame, event, unused):
        if frame.f_code is simulate.__code__:
            return trace_simulate
        if (frame.f_code.co_filename == simulate.__code__.co_filename and
                frame.f_code.co_name == 'schedule'):
            return trace_schedule
        return None

    sys.settrace(trace)
    try:
        result = conformance.model(directory, 2, 0, timeline=timeline)
    finally:
        sys.settrace(None)
    for pc, record in retired.items():
        record['redirect'] = next((event[3].upper() for event in reversed(timeline)
                                   if event[1] == 'redirect' and event[2] == pc and
                                   event[0] >= record['tick']), '')
    return retired, result


def rtl_audit(directory, csv_path):
    rows = list(csv.DictReader(csv_path.open()))
    symbols = conformance.symbols(directory / 'coremark.elf')
    end = next(int(r['cycle']) for r in rows if any(
        int(r[f'trace{j}_valid'], 16) and
        int(r[f'trace{j}_pc'], 16) == symbols['stop_time'] for j in (0, 1)))
    start = max(int(r['cycle']) for r in rows if int(r['cycle']) < end and
                int(r['allocate_valid'], 16) and int(r['allocate_ready'], 16) and any(
                    int(r[f'allocate{j}_pc'], 16) == symbols['start_time']
                    for j in range(int(r['allocate_count'], 16))))
    owners, allocated, visible, executed, redirects = {}, {}, {}, {}, {}
    for row in rows:
        cycle = int(row['cycle'])
        for head in (0, 1):
            if int(row[f'ib_head{head}_valid'], 16):
                pc = int(row[f'ib_head{head}_pc'], 16)
                waits = []
                for source in (1, 2):
                    if head == 1 and int(row['group_late'], 16):
                        waits = [f'paired@{int(row["ib_head0_pc"], 16):08x}']
                        break
                    if int(row[f'id{head}_wait{source}'], 16):
                        tag = int(row[f'id{head}_source{source}_tag'], 16)
                        waits.append(f'rs{source}:tag{tag}@{owners[tag]:08x}')
                value = f'credit{int(row["allocate_credit"], 16)}/' + (';'.join(waits) or '-')
                if pc not in visible or visible[pc][-1][0] != cycle-1:
                    visible[pc] = []
                visible[pc].append((cycle, value))
        for lane in (0, 1):
            prefix = f'execute{lane}'
            if (start <= cycle <= end and int(row[prefix+'_valid'], 16) and
                    int(row[prefix+'_ready'], 16)):
                waits = []
                for source in (1, 2):
                    if int(row[f'{prefix}_source{source}_wait'], 16):
                        tag = int(row[f'{prefix}_source{source}_tag'], 16)
                        waits.append(f'rs{source}:tag{tag}@{owners[tag]:08x}')
                executed[int(row[prefix+'_pc'], 16)] = {
                    'cycle': cycle, 'late': bool(int(row[prefix+'_late'], 16)),
                    'waits': ';'.join(waits) or '-',
                    'id_waits': allocated[int(row[prefix+'_tag'], 16)]}
        if start <= cycle <= end and int(row['branch_redirect_valid'], 16):
            redirects[int(row['branch_source_pc'], 16)] = (
                'E' if int(row['branch_stage'], 16) == 2 else 'M')
        if int(row['allocate_valid'], 16) and int(row['allocate_ready'], 16):
            for lane in range(int(row['allocate_count'], 16)):
                tag = int(row[f'allocate{lane}_tag'], 16)
                pc = int(row[f'allocate{lane}_pc'], 16)
                owners[tag] = pc
                allocated[tag] = ';'.join(f'{c-cycle}:{text}' for c, text in visible[pc])
    recovery = {}
    for row in rows:
        cycle = int(row['cycle'])
        pc = int(row['branch_source_pc'], 16)
        if start <= cycle <= end and int(row['branch_redirect_valid'], 16):
            target = int(row['branch_redirect_pc'], 16)
            visible = next(r for r in rows if int(r['cycle']) > cycle and any(
                int(r[f'ib_head{j}_valid'], 16) and
                int(r[f'ib_head{j}_pc'], 16) == target for j in (0, 1)))
            accepted = next(r for r in rows if int(r['cycle']) > cycle and
                int(r['allocate_valid'], 16) and int(r['allocate_ready'], 16) and any(
                    int(r[f'allocate{j}_pc'], 16) == target
                    for j in range(int(r['allocate_count'], 16))))
            recovery[pc] = (int(visible['cycle'])-cycle,
                            int(accepted['cycle'])-cycle, int(visible['allocate_credit'], 16))
    return executed, redirects, recovery


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=conformance.OUT / 'branch_alternating/branch-audit.csv')
    parser.add_argument('--rtl-csv', type=Path,
                        default=conformance.OUT / 'branch_alternating/w2.csv')
    args = parser.parse_args()
    directory = conformance.OUT / 'branch_alternating'
    model, summary = model_audit(directory)
    rtl, redirects, recovery = rtl_audit(directory, args.rtl_csv)
    rows = []
    for pc, expected in sorted(model.items()):
        actual = rtl[pc]
        waits = []
        for source, need, ready in zip(expected['sources'], expected['needs'], expected['ready']):
            owner = (f'paired@{expected["older_pc"]:08x}' if expected['older_rd'] and expected['older_rd'] == source
                     else f'prior_ready_in={ready}')
            waits.append(f'x{source}:{need}/{owner}')
        rows.append(dict(pc=f'{pc:08x}', model_late=int(expected['late']),
            model_resolve='M' if expected['late'] else 'E',
            model_redirect=expected['redirect'] or '-', model_waits=';'.join(waits),
            rtl_late=int(actual['late']), rtl_resolve='M' if actual['late'] else 'E',
            rtl_redirect=redirects.get(pc, '-'), rtl_waits=actual['waits'],
            rtl_id_waits=actual['id_waits'],
            rtl_to_ib=recovery[pc][0] if pc in recovery else '-',
            rtl_to_issue=recovery[pc][1] if pc in recovery else '-',
            rtl_credit_at_ib=recovery[pc][2] if pc in recovery else '-',
            stage_difference=int(expected['late'] != actual['late'])))
    with args.output.open('w') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({'branches': len(rows), 'stage_difference': sum(
        r['stage_difference'] for r in rows), 'model_late': sum(r['model_late'] for r in rows),
        'rtl_late': sum(r['rtl_late'] for r in rows), 'model': summary}, indent=2))


if __name__ == '__main__':
    main()
