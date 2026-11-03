# 上板比特流归档

按用户2026-11-03明确要求，各版本上板比特流统一放在此目录并上传仓库。此要求仅针对这里明确归档的比特流；PDS工程、IP、数据库仍留在本地。

| 文件 | 配置 | 来源 | 时序状态 |
|---|---|---|---|
| EdRV32-VRN-cpu100m.sbit | 卡48精简RND v1；VRN，无PIX/GEO、无ILA；CPU100MHz、DDR core125MHz、NPU150MHz | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1S/generate_bitstream/edrv32_fpga_board_vrn_top.sbit | 已布通；mem setup -0.124ns、NPU setup -0.022ns；RGMII慢角hold -0.361ns。不是全时序通过版本 |

该文件为用户指定名称的当前版本快照，归档时尚未修改本工程布线参数。源代码基线为卡48的11046fb0627afc3d182a072c8b150edab44191f3，器件PG2L200H-6 FBB676、PDS2022.2-SP6.1。文件大小9188552字节。

本版报告及参数建议：tasks/win/20261103-48-vrn-f-rnd1slim/cpu100_timing_notes.md；原生时序报告和路径明细见该卡artifacts/VRN-cpu100m/。

后续每个归档版本使用独立文件名，并在本表补充配置、来源和时序状态；不把“已生成bitstream”视为“时序全部通过”。
