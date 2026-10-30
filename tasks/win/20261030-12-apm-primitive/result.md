# 20261030-12-apm-primitive 结果

| 项 | 内容 |
|---|---|
| 代码 commit | d4c640b5e715e514faa37b2318447f01067c1a41 |
| PDS 安装目录 | G:/Program/pango/PDS_2022.2-SP6.1 |
| 执行范围 | 本地只读查找、复制模型/模板、解析 PDF；未运行 PDS 或仿真、未改 RTL |

## 取得的模型和模板

已取得明文仿真模型 model/GTP_APM_E2.v，完整保留原文。另取得 Multiply-Adder、Multiply-Accumulator、Multiplier、Accumulator 的 4 个明文 .v.xml 模板，位于 ip_rtl/。这些是生成器输入，保留 XML 外壳及占位符，不冒充可直接编译的生成 RTL。

| 文件 | 来源 | 说明 |
|---|---|---|
| model/GTP_APM_E2.v | G:/Program/pango/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation/GTP_APM_E2.v | 仿真模型 |
| ip_rtl/ipm2l_acc_v1_2.v.xml | G:/Program/pango/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_apm/ipm2l_flex_apm_eval/ipm2l_acc/rtl/ipm2l_acc_v1_2.v.xml | IP 生成器 RTL XML 模板 |
| ip_rtl/ipm2l_mult_v1_3.v.xml | G:/Program/pango/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_apm/ipm2l_flex_apm_eval/ipm2l_mult/rtl/ipm2l_mult_v1_3.v.xml | IP 生成器 RTL XML 模板 |
| ip_rtl/ipm2l_multacc_v1_2.v.xml | G:/Program/pango/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_apm/ipm2l_flex_apm_eval/ipm2l_multacc/rtl/ipm2l_multacc_v1_2.v.xml | IP 生成器 RTL XML 模板 |
| ip_rtl/ipm2l_multadd_v1_3.v.xml | G:/Program/pango/PDS_2022.2-SP6.1/ip/module_ip/ipm2l_flex_apm/ipm2l_flex_apm_eval/ipm2l_multadd/rtl/ipm2l_multadd_v1_3.v.xml | IP 生成器 RTL XML 模板 |
| manuals/fpga_reference.pdf | G:/Program/pango/PDS_2022.2-SP6.1/syn/doc/fpga_reference.pdf | 文档正文包含 GTP_APM_E2 |

## 搜索完整性与文件性质

递归搜索整个安装目录，使用 rg -l -a --hidden --no-ignore 匹配 GTP_APM_E2，并补查同名文件。共 62 个文件命中，完整路径、字节大小、明文/保护/二进制及用途见 artifacts/search.tsv。二进制工具、Liberty 时序库、其他系列原语引用均列入，但没有复制无关的大文件。

检测明文 protect 标记并单独记录到 encrypted_headers.txt；二进制不会被擅自判断为加密。本机目标仿真模型及 4 份模板可读，无需解密。原始版权头保留，不修改模型。

## 原语说明文档

递归查过 G:/Program/pango/PDS_2022.2-SP6.1 的全部 PDF/HTML/HTM/CHM 文件名，并扫描 PDF 封面/元数据标题及正文中的 GTP_APM_E2，HTML 标题/正文。名称/标题候选列表见 document_search.tsv；CHM 只检查文件名，未解包内部正文。

正文包含原语名的文档已复制，具体页码见 document_search.tsv；文档是否完整说明 SIMD 行为仍需逐页判断。

## 模型中与本任务直接相关的线索

明文模型包含 USE_SIMD、USE_POSTADD、MODEZ、CPI/CPO 的完整组合逻辑及寄存器行为。model_behavior_index.txt 提供原始行号索引，Linux 可直接以完整模型分析并构造定向测试。

- 模型第 364 行：USE_SIMD 时乘法结果打包为 {mult_out_h,mult_out_l}。
- 第 404–408 行：MODEZ 对应的选择分支可从 CPI 及其移位形式取后加器输入。
- 第 425 行：USE_SIMD 会改变高半部进位来源 cin_inter（需连同周边加法逻辑分析）。
- 第 446–447 行：P/CPO 的结果选择受 USE_POSTADD 控制，CPO 还受 CPO_REG 控制。

这些是仿真源码线索，不等于已验证 SIMD 双乘可跨 lane 求和，也不能单凭模型证明硬件级联的合法放置与时序。SIMD 双路加法的 lane 语义、溢出/符号与流水对齐仍需 Linux 端结合模板及定向仿真判断。

## 完成情况

已满足“至少取得明文模型或模板”的判据；模型和模板均已取得。专门原语手册的查找结果如实记录。用户无需操作，不生成 IP、不运行 PDS 流程。

## 文档命中核对

fpga_reference.pdf 是 Synplify Pro for Pango Reference Manual（August 2022）。PDF 第 318 页仅列出 GTP_APM_E2 支持的综合映射功能，包括乘法、乘加减、累加以及级联推断；没有说明 USE_SIMD=1 下的 MODEZ/USE_POSTADD/CPI/CPO 行为。因此专门原语说明仍记为“未找到”，这份手册仅作为综合能力的补充证据，不能替代仿真模型分析。
