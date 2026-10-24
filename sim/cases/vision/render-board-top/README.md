运行 `make case-sim CASE=vision/render-board-top`，检查板级演示命令 AXI 写入 DDR 的两个 64-byte 描述符，以及板内 APB 主控向真实帧控制器提交列表。`board_ip_stubs.v` 仅供顶层 lint；PDS 编译使用工程中的实际 IP。
