# Storage subsystem tests

## Test mapping

Every directory below has `test.yaml` and `files.f`, with the shared self-checking
`edrv32_mem_subsys_tb.sv` top. S means smoke (also included in full); F means full.

| Test | Directory | CASE | Tier |
|---|---|---:|---|
| GW-01 | `gw_01` | 101 | S |
| GW-02 | `gw_02` | 102 | S |
| GW-03 | `gw_03` | 103 | S |
| GW-04 | `gw_04` | 104 | F |
| GW-05 | `gw_05` | 105 | F |
| MX-01 | `mx_01` | 201 | S |
| MX-02 | `mx_02` | 202 | F |
| MX-03 | `mx_03` | 203 | F |
| MX-04 | `mx_04` | 204 | F |
| MX-05 | `mx_05` | 205 | S |
| MX-06 | `mx_06` | 206 | S |
| MX-07 | `mx_07` | 207 | S |
| MX-08 | `mx_08` | 208 | S |
| MX-09 | `mx_09` | 209 | S |
| MX-10 | `mx_10` | 210 | F |
| MX-11 | `mx_11` | 211 | S |
| MX-12 | `mx_12/seed_01` … `seed_20` | 212 | F |
| PM-01 | `pm_01` | 301 | S |
| PM-02 | `pm_02` | 302 | S |
| PM-03 | `pm_03` | 303 | F |
| PM-04 | `pm_04` | 304 | S |
| PM-05 | `pm_05` | 305 | F |
| PM-06 | `pm_06` | 306 | F |
| PM-07 | `pm_07` | 307 | F |
| P6-01 | `p6_01` | 401 | S |
| TOP-01 | `top_01` | 501 | S |

There are 26 functional items / 45 MB regression entries and three environment
self-test entries:

- `model_selftest`: row hit/miss latency, bank selection, masked byte writes,
  B-ordered reference storage, exact last-write/B delay, queued read/write
  turnaround gap and refresh interruption (53 checked read beats, two writes).
- `checker_selftest`: 18 scenarios including alignment, 4 KiB, all five stalled
  channel payloads, WLAST/RLAST, response IDs/order, EXOKAY rejection, legal stalls
  and error responses, implicit downstream response readiness and continuous W.
- `master_selftest`: 12 queued writes plus 12 reads with independent W delay/gaps,
  random B/R readiness and urgent, checking 192 returned beats; additional P0-only
  and P1-only drivers each complete eight transactions against stalled empty slaves.
