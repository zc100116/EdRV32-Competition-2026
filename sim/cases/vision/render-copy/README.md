# Render COPY

运行 `make case-sim CASE=vision/render-copy`。用独立快照作为参考，在随机 AXI 背压下验证 RGB565/ARGB8888 矩形的水平前移/后移、垂直上移/下移、跨 4 KiB 的独立 Surface 搬运，以及未对齐边界的 WSTRB；另运行 32 组随机矩形与 2 组不同 stride 的独立 Surface 搬运，并比较整个测试内存。共 41 个用例、386 个写 beat 合并为 169 个 Burst；专门检查反向复制跨 4 KiB 时边界后的 8-beat Burst。同 Surface 重叠 COPY 要求源与目标 stride 相同；源与目标明确不相交时置 `separate_surfaces_i`，可分别指定 stride。行地址和 stride 均为 32-byte 对齐，X 可以是任意像素位置。
