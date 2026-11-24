# E3 确定性系统交付

代码提交：`551ca8366`；本报告提交另删除 system.csv 两个未使用参数列，无行为变化。
依据：GDD v2.0 2.2a、2.3、4.1/4.2/4.5、5a/5c/5c.1/5f，tech v2.0 2/3/6。
结论：系统接入原 E1/E2 程序；未另造演示程序，未开始 E4，未修改共享平台或 gfx/UI。
协调者 msg_31a9e4f1253e：J 持续普攻先实现；蓄力设计待用户讨论，要求不实现、不留空接口。
协调者后续确认：游戏调用 plat_game_keys()，旧 plat_keys() 保持原协议；接口依赖 f33181ace。

属性：attributes.csv 增加 range_maximum；maximum 为默认上限，cap_raise 按属性累加。
默认暴击率 100、暴伤 300、攻速 300、冷却 75、闪避 60、韧性 75、元素抗性 75、减伤 80。
增加灯光半径、燃料效率、光区效果、四抗/全抗/减伤属性；暴击率不接受百分比提高。
伤害：基础/固定 → 攻击 → 元素与标签提高 → 独立额外 → 单次暴击/超级暴击 → 易伤。
随后分六份结算护甲/抗性，独立减伤，再按份扣对应临时盾、混合临时盾、常驻盾、生命。
六份顺序为铁、烬、潮、星、影、真实；混伤共享一次暴击；转换、附加进入各份。
穿透/破甲免疫独立；真实伤害跳过防御及普通盾，仍受易伤/减伤与真伤盾影响。
闪避、不可闪避、概率/正面/主动格挡、无视格挡、受击/冲刺无敌接入共用结算路径。
临时盾有到期帧数；常驻盾 180 帧未受伤后每帧回复 10，参数来自 system.csv。
架势：伤害与弱点/控制削减；Boss 硬控替代削架势；破势 180 帧、易伤 50%，之后回满。
八状态及点燃末次 tick、蒸汽清潮湿、冰缓冻结/碎裂、感电跳跃、破甲暴击重击已连通。
腐蚀减最大生命/吸取/击杀回复、致盲落空/黑暗暴击额伤，以及韧性缩时已接入。
触发递归深度默认 3、trigger_bonus 可加一；定向测试检查第 3/4 层边界。

灯油内部单位为百分之一：10000 = 100；lighting.csv 提供消耗、半径、点灯与光区参数。
F 在灯柱范围内扣 30 油点亮；余烬拾取补油并充能；光区增伤/敌减速、黑暗敌增伤已连通。
主/副/宠物各一槽；Q 即时交换；普通副手不攻击，精良增益及稀有副手机制有实际执行路径。
J 自动瞄准最近目标持续攻击；K/L/U 与空格沿用守火人技能内容，F 点灯。
武器类别框架执行近战扇形/直线/圆形、投射物/法阵；宠物四形态共用实际命中链且数值独立。
动作状态提供 action/action_frame/combo、四向 facing 与相对 hand_x/hand_y；未替换美术。
接口：ember_sim_step 输入改 uint16_t；录像 EMBER2/uint16_t，bit0–12 按 tech3，保留位为 0。
旧函数名与原表现层读取字段保留；事件 value 扩为 uint32_t，新增 tier/damage_type/outcome。
新增 combat.h/c，公开共享伤害/防御/状态记录；weapon_system 提供元素份额、标签及副手参数。

验证：一次 make linux test 通过游戏流程、E3 定向、音频、音频环、帧节拍五组测试。
随后补充“物理武器来源的点燃仍按火抗”定向测试，通过；最终 Linux/Spike 重新构建通过。
GCC 13.3.0 / xPack GCC 15.2.0，C11 -Wall -Wextra -Werror；最终构建 0 warning / 0 error。
定向覆盖属性三层上限、结算九步、四抗负抗、真伤、混伤、格挡/免疫、临时/常驻盾及恢复。
覆盖八状态常驻联动、Boss 硬控替代/破势恢复、触发 3+1 层、灯油/点灯、槽位和输入。
录像 coast.txt：seed 20261124，10800 帧；第 9947 帧通关，230 击杀，260/260 生命，14 级。
录像实际点亮灯柱，交换主副手，并展示宠物攻击、K/L/U/空格；峰值 19 敌人、33 模拟弹。
PC/Spike 每 60 帧全部字段摘要相同，共 180 组；二者 END,10800,3,5；PC 音频欠载 0。

| 分项 | 平均 instret | 最大 instret | CPI1.3 最大周期 |
|---|---:|---:|---:|
| 模拟 | 66806.04 | 107845 | 140198.50 |
| 表现准备 | 167506.17 | 255791 | 332528.30 |
| 音频 | 61437.28 | 129298 | 168087.40 |
| 同帧三项合计 | 295749.48 | 477441 | 620673.30 |

音频峰值估算超 150000 周期预算 12.06%；CPI 未上板测量，表现计数不含 GPU/MMIO 提交。
本报告不宣称其他 E3 平台/PC 60 FPS/满载/GPU 周期/ART-3 或 E4 内容已经完成。
具体角色/武器/物品/敌人条目、完整类别动作与表现由 E4/ART-3 填充；蓄力仍待用户定案。
复现（仓库根目录，先 . ~/.local/opt/edrv32/env.sh）：
```sh
make -C sw/apps/ember_isles linux test -j1
make -C sw/apps/ember_isles spike -j1
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt > build/ember_isles/pc.log
python3 sw/apps/ember_isles/tools/measure.py > build/ember_isles/e3-measure.txt
```
原始证据：build/ember_isles/{e3-linux-test.log,e3-final-build.log,e3-final-unit.log,e3-sim-stats.txt,pc.log,spike.log,e3-measure.txt}。
