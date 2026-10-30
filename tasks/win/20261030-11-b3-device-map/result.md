# 20261030-11-b3-device-map 结果

已完成 Windows 侧布局解析、6 个坐标样点、区域统计、全器件 APM/DRM 站点清单提取、手册查找和停止进度整理。没有运行综合/PnR/bitstream，也没有修改 RTL 或保存 PCE 临时区域约束。

| 项 | 内容 |
|---|---|
| 任务卡来源 | origin/zc100116/b3，070cddd7（含第 9 节补充） |
| 当前分支 | win/20261030-11-b3-device-map |
| B3V 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3V，复用卡 10 布线结果 |
| PDS | 2022.2-SP6.1；PG2L200H-6 FBB676 |
| 三个工程停止时间 | 未取得；日志无明确停止时刻，不以文件时间推算 |

## 布局导出与解析

| 文件 | 行数 | 字节数 | 说明 |
|---|---|---|---|
| b3v-placement.pcf | 62165 | 5441452 | 原始导出，未修改 |
| b3v-apm.pcf | 157 | 13383 | 原始导出，未修改 |
| b3v-drm.pcf | 117 | 18089 | 原始导出，未修改 |
| b3v-placement.fdc | 29312 | 2639885 | 原始导出，未修改 |

完整 PCF：62,023 条 def_inst_site、137 条 def_port。APM 专用导出与完整导出相同，155 条约束，91 个独立站点；资源报告为 161，差 6，按补充任务卡保留“未查明”，不继续追查。DRM：115 条约束、109 个独立站点，其中 103 个 36K + 12 个 18K = 109 个 36K 等效，与资源报告一致。

自动整理表：placement_instances.tsv、hardblock_instances.tsv、occupied_columns.tsv、module_resource_placement.tsv、io_ports.tsv。名称中的编码数字不等于 PCE siteX/siteY，也不直接当成区域约束坐标。

## 坐标样点

| 类型 | 位置 | name | siteX/siteY | Properties x/y 原值 | 截图 |
|---|---|---|---|---|---|
| CLMA | ll | CLMA_21_486 | 4/79 | 3840/8307 | pce/pce-CLMA_21_486.png |
| CLMA | ur | CLMA_717_1225 | 235/200 | 48976/8533 | pce/pce-CLMA_717_1225.png |
| DRM | ll | DRM_226_366 | 70/62 | 33568/8465 | pce/pce-DRM_226_366.png |
| DRM | ur | DRM_694_732 | 226/122 | 10768/8529 | pce/pce-DRM_694_732.png |
| APM | ll | APM_65_120 | 18/22 | 1968/8344 | pce/pce-APM_65_120.png |
| APM | ur | APM_587_1008 | 190/167 | 15552/8514 | pce/pce-APM_587_1008.png |

6 个样点均清晰可读。pce_devices.tsv 的 fp_x/fp_y 表头沿用任务卡，数值仅为 Properties x/y 原样抄录（手册称像素坐标），没有断言它们是区域约束坐标，也没有拟合未经验证的换算关系。原图位于 artifacts/pce/。

## 区域 cr_x1y2

任务创建命令：region -create cr_x1y2 -value (124,238,100,149)。截图 pce/pce-region-cr_x1y2.png 已显示区域名称和 Statistics；创建坐标来自操作命令，截图未直接显示坐标。

| 资源 | PCE 原值 | 指南 X1,Y2 | 比较 |
|---|---|---|---|
| CLMA、CLMS | 合计 4600 | 3500 + 1100 = 4600 | 一致；PCE 未拆分 |
| DRM | 50 | 50 | 一致 |
| APM | 50 | 100 | 差 2 倍，统计口径不同 |

其他原值：BKCL (1)、DDRPHY_IOCLK_DIV (1)、GCLK_INBUF_SYN (4)、GPLL (1)、IOCKB (4)、MRCKB (2)、PPLL (1)、RCKB (4)、TSERDES (8)。

安装目录的 CLOCK_REGION_6 资源清单同样含 CLMA 3500、CLMS 1100、APM 50 个站点、DRM 50 个站点。全器件 APM 清单是 370 个站点，而资源报告容量 740；布局 PCF 同一 APM 站点又可出现 XAPM_CORE_U/D 两类子单元。这些证据支持“PCE/站点清单按整站点、资源报告按上下运算子单元计数”的解释，但未把名称编码据此换算成 region 坐标。

## 全器件硬块与时钟区域清单

在安装目录 arch/vendor/pango/logos2/pg2l200h/db/clk_region_info.txt 找到明文站点列表，包含空闲与已用位置。提取后共 370 个 APM 站点（9 个名称编码 X 分组）、415 个 DRM 站点（10 个编码 X 分组）。已验证 B3V PCF 中所有 APM/DRM 站点均在安装清单中。

**任务卡 B 的 12 条人工列探测不再需要执行。** 原始列表过滤版、完整站点 TSV、全部硬块列、区域统计和指定探测结果均已保存：pg2l200h_sites_filtered.txt、pg2l200h_sites.tsv、pg2l200h_all_hardblock_columns.tsv、pg2l200h_clock_regions.tsv、column_probes_from_install.tsv。

清单附带 IOLHR 和时钟相关器件名称及所属区域，不提供 FBB676 全部 bank 坐标对应；IOLHR 500 是器件站点数，不是当前封装的 IO 可用量。未提交 CLMA/CLMS 站点全文，只保存每区计数。

| 时钟区域原名 | CLMA | CLMS | APM 站点 | DRM 站点 |
|---|---|---|---|---|
| CLOCK_REGION_1 | 2650 | 950 | 20 | 30 |
| CLOCK_REGION_2 | 2350 | 850 | 30 | 30 |
| CLOCK_REGION_3 | 3700 | 1200 | 40 | 50 |
| CLOCK_REGION_4 | 3500 | 1100 | 50 | 50 |
| CLOCK_REGION_5 | 3000 | 900 | 40 | 50 |
| CLOCK_REGION_6 | 3500 | 1100 | 50 | 50 |
| CLOCK_REGION_7 | 3000 | 900 | 40 | 50 |
| CLOCK_REGION_8 | 3500 | 1100 | 50 | 50 |
| CLOCK_REGION_9 | 2525 | 925 | 20 | 25 |
| CLOCK_REGION_10 | 2350 | 850 | 30 | 30 |

## 三个停止工程最后路由进度

| 工程 | 最后迭代 | 未布通 general nets | overused | 停止时刻 |
|---|---|---|---|---|
| B3VN | 19 | 49334 | 182864 | 未取得 |
| B3R | 62 | 3820 | 9887 | 未取得 |
| B3F | 16 | 72543 | 337616 | 未取得 |

原始末尾日志与原始 MT total route time 字段保存在 stopped_route_log_tails.txt / stopped_route_progress.tsv。进程检查未发现正在运行的 -action place_route pds_shell；不从此推算具体停止时刻。

## APM/DRM 手册

| 文件 | 版本/日期 | 内容 |
|---|---|---|
| manuals/UG041003_APM_IP.pdf | V1.5 / 2023-08-21 | Logos2 APM IP：乘法、乘加、乘累加、累加器 |
| manuals/UG041002_DRM_Based_RAM_IP.pdf | V1.10 / 2023-08-23 | Logos2 DPRAM、SDPRAM、SPRAM、ROM、FIFO |

本机 PDS 安装目录递归查找，得到 31 个相关 PDF 路径（含重复副本）；全部文件的路径、大小、标题、版本、日期保存在 manual_inventory.tsv。只复制上述两份合并 IP 指南，覆盖任务卡要求的 APM 乘法/乘加和 DRM IP。未找到独立的 Logos2 APM/DRM 硬块架构专册，明确记录“未找到”，不以 IP 指南冒充。查找目录及二进制架构数据边界见 local_search_notes.md。没有从网络下载。

## 限制与完成情况

已取得全部六个样点和区域 Statistics，完整安装站点清单替代手工列探测。Windows 侧可取得的任务产物均已整理；停止时间未取得、APM 155/161 未查明、独立硬块架构专册未找到，均按任务卡如实留缺。区域坐标换算与后续全局规划交给 Linux 端分析，不在本轮改 RTL 或加入区域约束。

原始布局导出本地目录：G:/codex_project/EdRV32-FPGA/EdRV32-B3V。手册和架构数据原始路径见各自 TSV。PDS 工程/数据库、二进制架构数据库和 bitstream 未上传。完整 PCF 约 5.2 MiB，是任务卡要求的必要产物。
