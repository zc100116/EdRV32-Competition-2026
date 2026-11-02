# V3s CPU unit

Real core with fixed-latency instruction and data responders. Eighteen independent
programs check swapped ALU/load WAW and bypass, pipe-1 conditional branch and JAL,
older branch cancellation of a younger load, younger load misalignment with older
commit, and older branch-target misalignment with no younger request or commit.
Further programs check interrupts before/after a younger device operation starts,
a stalled slot-1 JAL retaining both IB entries, a younger branch fault waiting for
an older load response, oldest-first simultaneous exceptions, and a warm slot-1 JALR with its pipe-0
target-comparison operands selected after swapping, both for a correct prediction
and for an operand change that requires an E redirect. Older branch redirects and faults
also cancel younger DIV/MUL operations before their execution units accept them.
A surviving swapped DIV checks one start, the quotient, and younger WAW forwarding.
A stalled cold slot-0 JAL pairs with its target load after redirecting once.

Run under `flock /tmp/edrv32-sim.lock`:
`python3 tools/regress.py smoke --path verif/unit/cpu_v3s -j 1`.
