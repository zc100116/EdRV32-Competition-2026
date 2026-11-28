# GPU v2 SFU probe

依据 gpu-v2-spec v0.1 §2.4、VT06、M-6/M-7 和 GP-A2 协调者确认的 ROM 打包结论。
`edrv32_gpu2_sfu` 由两条 II1/11拍引擎（含bank捕获及10拍标量MUL/FMA）、共享种子ROM、
同步scratch及两个独立返回队列组成；RCP/RSQ/LOG2/EXP2接受到无背压返回握手
为56/79/102/91拍（GP-C G2-01候选，原47/68/88/78拍）。
请求只在固定模4相位接收，连续请求II4；两返回口分别承接RSQ和其余操作，RF单写口
冲突由上层静态排程/ready仲裁处理。总32信用使算术流水无需全局停顿或新增等待拍。

一颗1024×36 TDP内存存32bit表项：RCP0..63、RSQ64..127、LOG128..176、
INV177..225、EXP226..289；SFU A口先后读LOG/INV，setup B口独立读取RCP。
前端增加两拍，将LZ、规格化和索引分开；字段在第6采样边沿写入。
预取偏移5/18/29/40/52/63/75/86（valid tap）保留混合II4；bank捕获切开DRM至操作数路径，
槽间11/12/13拍空隙避开发射/返回写口相位碰撞，显式旁路与同址转发保持依赖。
七输入字段副本加七结果bank共14DRM；engine0不读LOG基值、
末槽7无后继，因此较M-7的16scratch bank规划省两颗DRM，连种子ROM共15颗。
元数据32×21双副本及返回32×37双队列合计116 LR分配额；原生16/5位区域用同边沿
使能副本限制每叶≤16负载；ROM捕获同样分16位使能叶，不增加拍数；每对APM另48外部FF。

独立标准库参考 `tools/gpu2/sfu.py` 每节点用整数FP32 RNE；表使用原M6公式。
`corpus.py` 保留M5原14变体×128组（末32组G类定向）、M6原四函数/近1/窄域与广域pow；
保留underflow及原M5对照分支输入。原执行398760次调用之外，补回M6跳过的12405对underflow输入（49620次调用）；
full加512混合前缀，共448892请求。
smoke为512混合前缀加256短压力样本；前512请求连续II4且逐拍检查四种返回延迟，随后
强制双口背压和随机ready；全程setup并发读/禁读保持。TB从外部接受时刻生成到期日历，
数值不读RTL内部信号；RTL预约one-hot、scratch单写口互斥和实际发射总数另作断言。

EXP在 `-1/64<x<0` 的精确残差用 `FMA(x,ln2,ln2/64)`，不增加槽或APM；
原料bb77b4d6保持3f7f5488，额外舍入残差会错误变成3f7f5486。
特殊值仍按IEEE开发初值核对，G2-07未冻结，不能算作特殊值契约的规格验收PASS。

```sh
python3 -B tools/gpu2/gen_sfu_rom.py
python3 tools/regress.py smoke --path verif/unit/gpu2_sfu -j 1
python3 tools/regress.py full --path verif/unit/gpu2_sfu/full -j 1
python3 tools/gpu2/synth.py edrv32_gpu2_sfu edrv32_fpga_probe_gpu2_sfu_top edrv32_gpu2_fp32_add
python3 tools/gpu2/synth_summary.py build/gpu2_synth/*.json
```

ROM镜像及所有编译/测试/测量产物在build/；IP创建说明在fpga/ip/，导入仅rtl/include。
原前端/缩放独立测试保留 `run_prepare.py` / `run_scale.py`；统一入口运行完整SFU。
Yosys映射切开注册APM和存储IP边界，包含RAM外部转发寄存器；不含IP内部FF/逻辑。
通用LUT4未映射Pango进位链；220MHz约束已提供，220/200/150MHz实际裕量、DRM及CLMS
占用需Windows PDS/ModelSim核实，不能把Linux功能通过或黑盒数量当作PDS收敛。

GP-C资源参考（Yosys0.70+219，基线35ec01496）：

| 资源 | 旧值 | 新值 | 增量 |
|---|---:|---:|---:|
| LUT4 / LUT6 | 8899 / 6704 | 8891 / 6792 | −8 / +88 |
| 外部FF | 3625 | 4470 | +845 |
| LR / DRM / APM | 116 / 15 / 4 | 116 / 15 / 4 | 0 / 0 / 0 |

bank捕获有效448bit替换原后置操作数捕获，预译码选择叶各16位；metadata只延长20位。
校准估计：ROM前端各≤7普通LUT级，DRM捕获field/result为1/2级，捕获后选择/LZ与
两拍缩放各≤7普通级另计carry；选择/LZ及复制保留仍需PDS重测。
详细段表和复现命令见设计记录GP-C节；最终时延由协调者和用户定稿。
