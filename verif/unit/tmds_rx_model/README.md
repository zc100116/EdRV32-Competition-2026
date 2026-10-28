# Independent TMDS receiver self-test

`make smoke REGRESS_ARGS='-j 1 --path verif/unit/tmds_rx_model'`

The receiver in `verif/models/tmds_rx_model.sv` inverts the DVI transition and
inversion stages directly. It does not call an encoder or use DISP RTL. Its
`frame_pixels` queue holds the most recently completed active frame at a VS
rising edge; `frame_pixel_count_o` and `frame_count_o` describe that capture.
HS/VS retain the last control values during active video.

`tb.sv` supplies a separate forward encoder based on DDWG DVI 1.0 Figure 3-5.
It exercises all 256 byte values in three different lane sequences, four
continuous running disparity sequences separated by blanking, all four control
symbols, and two frame collection sizes with an explicit final pixel check.

Lint uses `-Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL`: blocking assignments implement
ordered behavioral sampling and queues; the collected frame queue is read by
hierarchical testbench access. No functional/width warnings are waived.

Normative algorithm source: [DDWG DVI 1.0, sections 3.2.2 and 3.3.3](https://glenwing.github.io/docs/DVI-1.0.pdf).
