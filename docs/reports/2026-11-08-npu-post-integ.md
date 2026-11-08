# NPU 后处理 (b) 联调回归（2026-11-08）

- 基线 `eb7b2754`；最终提交为本报告所属提交（`git log -1 --format=%h -- docs/reports/2026-11-08-npu-post-integ.md`）。
- 工具：Verilator 5.020、Icarus 12.0、Python 3.12.3、xPack GCC 15.2.0；目标PG2L200H-6，仅本机仿真。
- 时钟：perf NPU/mem=180/125 MHz，PP-P-02=200 MHz；SoC sys/NPU/mem=100/150/125 MHz。仿真均持锁、编译-j 1。 PP-P-01（六个identity CONV，EN1为CTRL=3）：单位为NPU拍；R/W为整个用例的32 B beat；装表等待是在途读等待，可与核心重叠。
- 通过：unit 29目录、32个回归条目（含各自变体）；block S 33项（RG-02由npu_top内嵌运行一次）；TL-01/02共17项、TL-03共12项、TL-05。
- 通过：PP-10/11/12、PP-P-01/02、NET-02 latency94 EN=0/1；PP-SW-01/02均通过（启动/invalidate分别2/2、3/3）。
- 风格：RTL 29文件（含SoC/FPGA顶层）、SV 9文件均0告警；edrv32_soc_top和edrv32_fpga_board_full_top -Wall lint均0告警。
- 测试错误 `91d10817`：CONV单元遗漏9个新增支路端口导致PINMISSING；接入关闭控制/unused输出，npu_conv重跑通过。
- RTL错误 `54c62593`：概率表按best+128存放而读用raw INT8位型，PP-08/09/13零候选；装载地址翻转bit7，tail合成表同步修正，全部失败项通过。
- 测试风格 `5a6cabb7`：既有超长行/同排端口换行，无语义变化；测试测量 `799623f6`：EN=0无后处理事件，CSV对应阶段周期记0，PP-P-01通过。
- 测试配置 `637edfb9`：PP-SW主机600秒含构建不足→3600秒；UART `c911e904`：实际约92160而对端115200→按100/125时钟比设置对端。周期守卫/功能判据/UTF-8严格解码均保留，两项PASS。
- 接入 `7a80256e`/`00e88216`：PP-P-02仅按RTL报告接口接入；NET从公开描述符定位三表、按anchor逐字段比全部候选并单独检查入队次序；接入期编译顺序/位宽告警已消除。
- 首跑环境缺项已补齐：本机Pango模型变量、固定版本ultralytics/lvgl子模块、board_npu参考数据；超时遗留sim已手工停止。

|候选/内存|核心EN0/EN1|装表等待|尾周期（µs@180M）|DONE观测|R/W EN1|
|---|---:|---:|---:|---:|---:|
|37/zero|184133/188097|247|16443（91.350）|204563|24136/22708|
|37/latency|188355/218118|25988|36257（201.428）|254401|24136/22708|
|37/bw|240538/270315|25989|36261（201.450）|306592|24136/22708|
|5040/zero|184133/188097|247|2340183（13001.017）|2528297|44148/26460|
|5040/latency|188355/218118|25988|5039585（27997.694）|5257718|44148/26460|
|5040/bw|240538/270315|25989|5039581（27997.672）|5309911|44148/26460|

- EN0两计数的DONE zero/latency/bw=184149/188372/240563，R/W=23796/22680；EN1尾部读/写：37条4736/896 B、5040条645120/120960 B。
- zero尾拍数对320×N估算的偏差：37条+38.9%、5040条+45.1%；其余档位含DDR停顿，均只记录、不设估算门禁。PP-P-02：12600连续拍/II=1、流水12拍、5040条完整排出，63 µs@200M等于接收预算。
- NET-02 latency94（真实68描述符）：EN0核心6277467、尾0、DONE6277482，R/W=512472/309000；EN1（CTRL=3）核心6307251、装表等待25991、尾36587、DONE6343852，R/W=512812/309028。
- NET EN1完整37条xyxy_q8/probability_q24/class_id/anchor与yolo_post_ref逐字段一致，入队顺序正确；保留debug cls使最后raw B标记完整核心结束。
- 周期口径：门铃APB接受→最后raw B为核心；最后raw B→最后候选B为尾部（含分类排空）；DONE为APB观测到完成，EN0无尾部。

- 复现：先`. ~/.local/opt/edrv32/env.sh`，每条仿真/构建命令前加`flock /tmp/edrv32-sim.lock`；以下目录/编号逐个替换，不重复通过项。 unit：`python3 tools/regress.py smoke --path verif/unit/npu_<目录后缀> -j 1`；mac_chain设置`EDRV32_PANGO_SIM_DIR=$HOME/.local/share/edrv32/pango`。
- block S：逐个smoke档目录`python3 tools/regress.py smoke --path verif/block/npu/<用例> -j 1`；跳过已由unit运行的rg_02；协调者仅额外批准重跑受影响npu_post_tail。
- TL：`~/.local/opt/edrv32-py/bin/python tools/npu/ref/test_ref.py`和`tools/npu/test_compile.py`；TL-05为`python3 verif/block/npu/post/run.py --test TL-05`。
- F：先`python3 verif/block/npu/run.py --test NET-01 --prepare-only`；再`python3 tools/regress.py full --path verif/block/npu/pp_<10|11|12> -j 1`。
- SW：初始化ultralytics/lvgl子模块；`python3 tools/regress.py full --path verif/soc/pp_sw_<01|02> -j 1`；Make自动生成board_npu/PP oracle依赖。
- P：`python3 tools/regress.py perf --path verif/block/npu/pp_p_<01|02> -j 1`；NET为`python3 verif/block/npu/post/net_latency.py`。
- lint/风格：`python3 verif/unit/npu_post_tail/lint.py`；`python3 tools/check/verilog_style.py rtl/npu rtl/tech/edrv32_ram_npu_post_*.v rtl/soc/edrv32_soc_top.v fpga/rtl/edrv32_fpga_board_full_top.v`；SV用`verif/block/npu/check_style.py`机械规则（含改动unit/SoC bench）。
- 原始数据：`build/regress/{smoke,full,perf}/`、`build/npu/post/{pp-p-01/performance.csv,pp-p-02/performance.json,net_02/performance.json}`、`build/npu/post_sw/`、`build/npu_post/*-lint.log`。
- SoC超时调试记录：[2026-11-08-npu-post-soc-timeout.md](../debug/2026-11-08-npu-post-soc-timeout.md)。
