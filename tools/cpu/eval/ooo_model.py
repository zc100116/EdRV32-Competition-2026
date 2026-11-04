#!/usr/bin/env python3
# File: ooo_model.py; Spec: cpu-spec 2.3/4.4; Clock: host.
# Replay commits through F1/F2/D/RN/DS/IS/RR/EX and an in-order retirement ROB.
# Reuse the calibrated hit frontend; all out-of-order timing is a model assumption.
"""Hit-only renamed CPU model; dynamic memory addresses come from Spike commits."""
import argparse
from array import array
from collections import Counter, deque
from dataclasses import dataclass
import json
from pathlib import Path

from analyze import COMMIT, CONTROL
from pipe_model import Predictor, Record, program_and_trace
from wide_model import fill_width, request

NEVER = float('inf')
LATENCY = {'alu': 1, 'branch': 1, 'jal': 1, 'jalr': 1,
           'load': 2, 'mul': 3, 'div': 34, 'csr': 2, 'serial': 1}
RENAME_CAUSES = ('renamed', 'mispredict', 'rob_full', 'iq_full', 'frontend')


@dataclass(eq=False)
class Entry:
    record: Record
    age: int
    deps: tuple
    address_dep: object = None
    data_dep: object = None
    address: int = 0
    width: int = 0
    ready: float = NEVER
    address_ready: float = NEVER
    execute: int = -1

    @property
    def instruction(self):
        return self.record.instruction


def memory_trace(directory, program, trace):
    """Read actual effective addresses without changing the shared PC trace reader."""
    addresses = array('I')
    with (directory / 'spike.log').open() as log:
        for line in log:
            if not (match := COMMIT.match(line)):
                continue
            instruction = program[int(match[1], 16)]
            address = int(line.split(' mem ')[1].split()[0], 16) if (
                instruction.kind in {'load', 'store'}) else 0
            addresses.append(address)
            if len(addresses) == len(trace):
                break
    return addresses


def memory_width(instruction):
    if instruction.size == 2:
        return 4  # RV32C loads/stores in this ISA are word accesses.
    return 1 << ((instruction.bits >> 12) & 3)


def ready_at(dependency):
    return dependency.ready if dependency is not None else 0


def load_order(entry, stores, execute, known_at):
    """No dependence prediction: all older addresses must be known before this EX."""
    overlaps = []
    for store in stores:
        if store.age >= entry.age:
            break
        if store.address_ready > known_at:
            return 'store_unknown'
        if (entry.address < store.address + store.width
                and store.address < entry.address + entry.width):
            overlaps.append(store)
    if not overlaps:
        return None
    youngest = overlaps[-1]
    if youngest.address == entry.address and youngest.width == entry.width:
        return 'store_data' if ready_at(youngest.data_dep) > execute else 'forward'
    return 'store_overlap'


def simulate(program, trace, addresses, begin, end, *, rob_size=32, iq_size=16,
             penalty=7, issue_width=2, lsus=1, timeline=None):
    """Select oldest ready entries; timeline is a directed-test event sink."""
    predictor = Predictor(128, 4096, 8, 4, 2)
    ib = deque()
    halfwords, pending = [], []
    fetch_pc, cross = trace[0], None
    decoded, renamed = [], []
    rob, iq, stores = deque(), [], []
    mapping = [None] * 32
    executing = {}
    load_ports = Counter()
    divider_until = 0
    fetch_delay = 0
    recovering = False
    cursor, age, tick = 0, 0, 0
    on_path = True
    active = False
    cycles = instructions = controls = 0
    rename_slots = dict.fromkeys(RENAME_CAUSES, 0)
    events = dict.fromkeys(('mispredictions', 'squashed', 'squashed_memory', 'lsu_conflict',
                            'store_unknown',
                            'store_data', 'store_overlap', 'forwarded', 'operand_wait',
                            'div_busy', 'commit_wait', 'commit_store_port'), 0)
    # Each event counts cycles with that condition, except predictions/forwarded/squashed.

    def event(name, entry):
        if timeline is not None:
            timeline.append((tick, name, entry.record.trace_index, entry.instruction.pc))

    while True:
        seen = set()
        retiring = []
        for entry in rob:
            if len(retiring) == issue_width:
                break
            inst = entry.instruction
            done = max(entry.address_ready, ready_at(entry.data_dep)) if (
                inst.kind == 'store') else entry.ready
            if done > tick or entry.record.trace_index < 0:
                seen.add('commit_wait')
                break
            if inst.kind == 'store':
                if load_ports[tick] + sum(
                        e.instruction.kind == 'store' for e in retiring) >= lsus:
                    seen.add('commit_store_port')
                    break
            retiring.append(entry)
        if any(e.instruction.pc == end for e in retiring):
            break
        active |= any(e.instruction.pc == begin for e in retiring)
        for entry in retiring:
            rob.popleft()
            if entry.instruction.kind == 'store':
                stores.remove(entry)
            if mapping[entry.instruction.rd] is entry:
                mapping[entry.instruction.rd] = None
            event('commit', entry)
        if active:
            instructions += len(retiring)
            controls += sum(e.instruction.kind in CONTROL for e in retiring)

        # RR has no variable stall: IS checks availability at its future EX boundary.
        resolved = executing.pop(tick, [])
        load_ports.pop(tick, None)
        redirect = None
        updates = []
        for entry in resolved:
            event('execute', entry)
            record = entry.record
            inst = entry.instruction
            actual = inst.kind in {'jal', 'jalr'} or (
                inst.kind == 'branch' and record.next_pc != inst.pc + inst.size)
            wrong = record.taken != actual or (record.taken and record.target != record.next_pc)
            if record.trace_index >= 0:
                updates.append(record)
                if wrong:
                    redirect = entry
                    break

        query = None
        rename_cause = None
        renamed_count = 0
        if redirect is not None:
            cut = redirect.age
            killed = [e for e in rob if e.age > cut]
            rob = deque(e for e in rob if e.age <= cut)
            iq = [e for e in iq if e.age <= cut]
            stores = [e for e in stores if e.age <= cut]
            for cycle in list(executing):
                executing[cycle] = [e for e in executing[cycle] if e.age <= cut]
            load_ports = Counter({cycle: sum(e.instruction.kind == 'load' for e in entries)
                                  for cycle, entries in executing.items()})
            divider_until = max((e.ready for e in rob if e.instruction.kind == 'div'
                                 and e.execute >= 0), default=0)
            mapping = [None] * 32
            for entry in rob:
                if entry.instruction.rd:
                    mapping[entry.instruction.rd] = entry
            ib.clear()
            decoded, renamed, halfwords, pending = [], [], [], []
            cursor = redirect.record.trace_index + 1
            on_path = True
            fetch_pc, cross = redirect.record.next_pc, None
            predictor.restore(redirect.record)
            fetch_delay = max(0, penalty - 7)
            if penalty < 7:
                # F1 overlaps redirect for 6; 5 additionally overlaps F2.
                pending, fetch_pc, cross, query = request(
                    predictor, fetch_pc, cross, issue_width)
                if penalty == 5:
                    halfwords.extend(pending)
                    pending = []
                    fill_width(program, ib, halfwords, issue_width)
            rename_cause = 'mispredict'
            recovering = True
            if active:
                events['mispredictions'] += 1
                events['squashed'] += len(killed)
                events['squashed_memory'] += sum(e.instruction.kind in {'load', 'store'}
                                                 and e.record.trace_index < 0 for e in killed)
            event('redirect', redirect)
        else:
            used = dict(alu=0, lsu=0, mul=0, div=0, branch=0)
            selected = []
            for entry in iq:
                if len(selected) == issue_width:
                    break
                inst = entry.instruction
                execute = tick + 2
                if inst.kind in {'load', 'store'} and entry.record.trace_index < 0:
                    continue
                deps = (entry.address_dep,) if inst.kind == 'store' else entry.deps
                if any(ready_at(dep) > execute for dep in deps):
                    seen.add('operand_wait')
                    continue
                unit = ('lsu' if inst.kind in {'load', 'store'} else
                        'branch' if inst.kind in CONTROL else
                        inst.kind if inst.kind in {'mul', 'div'} else 'alu')
                if used[unit] == (issue_width if unit == 'alu' else lsus if unit == 'lsu' else 1):
                    if unit == 'lsu':
                        seen.add('lsu_conflict')
                    continue
                if unit == 'div' and divider_until > execute:
                    seen.add('div_busy')
                    continue
                if inst.kind in {'csr', 'serial', 'illegal'}:
                    if entry is not rob[0] or selected or inst.kind == 'illegal':
                        continue
                if inst.kind == 'load':
                    reason = load_order(entry, stores, execute, tick)
                    if reason not in {None, 'forward'}:
                        seen.add(reason)
                        continue
                    if reason == 'forward' and active:
                        events['forwarded'] += 1
                    load_ports[execute] += 1
                entry.execute = execute
                if inst.kind == 'store':
                    entry.address_ready = execute + 1
                else:
                    entry.ready = execute + LATENCY[inst.kind]
                if inst.kind == 'div':
                    divider_until = entry.ready
                executing.setdefault(execute, []).append(entry)
                selected.append(entry)
                used[unit] += 1
                event('select', entry)
                if inst.kind in {'csr', 'serial'}:
                    break
            if selected:
                selected_ids = {e.age for e in selected}
                iq = [e for e in iq if e.age not in selected_ids]

            # DS, RN and D are distinct one-cycle stages with width-entry latches.
            if renamed and len(iq) + len(renamed) <= iq_size:
                iq.extend(renamed)
                renamed = []
            if renamed:
                rename_cause = 'iq_full'
            elif decoded:
                capacity = min(issue_width, rob_size - len(rob))
                if not capacity:
                    rename_cause = 'rob_full'
                for record in decoded[:capacity]:
                    inst = record.instruction
                    deps = tuple(mapping[source] for source in inst.sources if source)
                    address_dep = data_dep = None
                    if inst.kind == 'store':
                        data_source, address_source = inst.sources
                        address_dep = mapping[address_source] if address_source else None
                        data_dep = mapping[data_source] if data_source else None
                    entry = Entry(record, age, deps, address_dep, data_dep)
                    if inst.kind in {'load', 'store'}:
                        if record.trace_index >= 0:
                            entry.address = addresses[record.trace_index]
                        entry.width = memory_width(inst)
                    if inst.rd:
                        mapping[inst.rd] = entry
                    rob.append(entry)
                    renamed.append(entry)
                    if inst.kind == 'store':
                        stores.append(entry)
                    age += 1
                    renamed_count += 1
                    event('rename', entry)
                decoded = decoded[renamed_count:]
                if decoded:
                    rename_cause = 'rob_full'
            if not decoded:
                for _ in range(min(issue_width, len(ib))):
                    record = ib.popleft()
                    inst = record.instruction
                    # Once the predicted stream diverges, no later coincidental PC can rejoin it.
                    on_path &= cursor < len(trace) and inst.pc == trace[cursor]
                    if on_path:
                        record.trace_index = cursor
                        record.next_pc = (trace[cursor + 1] if cursor + 1 < len(trace)
                                          else inst.pc + inst.size)
                        cursor += 1
                    else:
                        record.next_pc = inst.pc + inst.size
                    decoded.append(record)
                    if inst.kind in {'csr', 'serial', 'illegal'}:
                        break
            if renamed_count:
                recovering = False
            if rename_cause is None:
                rename_cause = 'mispredict' if recovering else 'frontend'

            halfwords.extend(pending)
            pending = []
            fill_width(program, ib, halfwords, issue_width)
            if fetch_delay:
                fetch_delay -= 1
            elif len(halfwords) <= (4 if issue_width == 2 else 8):
                pending, fetch_pc, cross, query = request(predictor, fetch_pc, cross, issue_width)

        # Preserve concurrent F1 query / EX update order from the calibrated predictor.
        for record in updates:
            predictor.update(record)
        if query and query[1]:
            predictor.action(query[0][0])
        if active:
            cycles += 1
            rename_slots['renamed'] += renamed_count
            rename_slots[rename_cause] += issue_width - renamed_count
            for name in seen:
                events[name] += 1
        tick += 1

    return dict(cycles=cycles, instructions=instructions, ipc=instructions / cycles,
                controls=controls, **events,
                **{'rename_slots_' + k: v for k, v in rename_slots.items()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--rob', type=int, choices=(16, 32, 64), default=32)
    parser.add_argument('--iq', type=int, choices=(8, 16, 32), default=16)
    parser.add_argument('--penalty', type=int, choices=(5, 6, 7, 8, 9), default=7)
    parser.add_argument('--issue-width', type=int, choices=(2, 3, 4), default=2)
    parser.add_argument('--lsus', type=int, choices=(1, 2), default=1)
    args = parser.parse_args()
    program, symbols, trace = program_and_trace(args.directory)
    addresses = memory_trace(args.directory, program, trace)
    print(json.dumps(simulate(program, trace, addresses, symbols['start_time'],
                              symbols['stop_time'],
                              rob_size=args.rob, iq_size=args.iq, penalty=args.penalty,
                              issue_width=args.issue_width, lsus=args.lsus), indent=2))


if __name__ == '__main__':
    main()
