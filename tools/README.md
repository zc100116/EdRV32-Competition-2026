# 工具

| 路径 | 用途 |
|---|---|
| `debug_tool/` | 自研 PC 调试工具：串口与网口会话、程序加载、虚拟键鼠、识别结果与参考模型比对、性能遥测（见其 README） |
| `board/` | 调试工具使用的串口加载协议和网卡等待 |
| `npu/` | NPU 与 YOLOv8n 后处理参考模型，供调试工具比对 |
| `sw/` | showcase 构建脚本：内嵌 NPU 模型、字体、图片、游戏记录 |
| `s3/lvgl_assets.py` | LVGL 资源生成，showcase 构建使用 |
| `elf2mem.py` | 把 ELF 切分为 ROM / SRAM / DDR 镜像 |
| `fpga/mem_init.py` | 生成 Boot ROM 和 SRAM IP 的初始化文件 |
| `requirements.txt` | Python 依赖 |
