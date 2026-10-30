# 本机手册与器件数据查找

递归查过：G:\Program\pango\PDS_2022.2-SP6.1。doc、help、ipcore、IP Compiler 文档所在子目录一并覆盖；不存在的目录没有假定存在。未从网络下载。

相关 PDF 共 31 个路径（含同一手册的多份副本），完整路径、大小、封面标题、版本与日期见 manual_inventory.tsv。

已复制 Logos2 APM IP 用户指南 UG041003 V1.5 (2023-08-21)，覆盖 Multiplier、Multiply-Adder、Multiply-Accumulator、Accumulator；DRM Based RAM/FIFO IP 用户指南 UG041002 V1.10 (2023-08-23)，覆盖 DPRAM、SDPRAM、SPRAM、ROM、FIFO。

未找到独立于上述 IP 用户指南的 Logos2 APM/DRM 硬块架构专册；不把 IP 指南冒称为完整硬块架构手册。

PG2L200H db/clk_region_info.txt 是明文，包含 10 个时钟区域的站点清单。已提取 APM/DRM、IO 和时钟相关内容，未提交其他 CLMA/CLMS 站点明细（仅保留计数）。该清单不含 region 的整数边界换算信息，也不把 IO 站点数当成当前封装引脚数。

arch_lp.eadf、arch_nt.eadf、arch_schm.eadf、fp_arch_lp.eadf、fp_arch_schm.eadf 为带 PANG 头的二进制文件，本轮未解析。没有执行架构生成脚本或修改安装目录。

