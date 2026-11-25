# E4 内容里程碑报告
日期：2026-11-24；分支：zc100116/gpu-dev；范围：tech 6 E4。
数据提交：ba87460fd；技能、召唤物与 AI 数值表提交：a30712bff。
模拟：c0a9f3541、cf0a84583；范围修正：619e91951；验证：db40d6b7a。
结论：E4 未完成；当前数据与机制回归通过，四项玩法语义的 ask 尚未答复。
范围停在 E4；不实现 E5 模式、经济、局外天赋和完整界面。

内容表含 191 个角色、装备、条目、宠物和敌人定义，另有 3 个召唤物模板。
角色 8；每个角色具有独立被动、K、L、U 和两类亲和。
主副武器 50：10 类 × 5 元素；每类 A/B 两种进化机制，共 20 类分支。
宠物种类 6；宠物武器 12；原生攻击与装备攻击分开。
遗物 38；铭文 18；祝福 13；共鸣 10；契约 6；净化道具 1。
敌人 21：15 小怪、3 头目、3 Boss；精英词缀 8。
遗物和祝福数量含 GDD 补充的棘甲、淬火内衬、反震。
每项拥有稳定 CSV ID；生成器同时输出 C 枚举和数值记录。
技能、进化、宠物、召唤物、条目和 AI 初值从 CSV 读取。
CSV 调参允许正常重新生成与编译，无需修改 C 机制代码。

逐项表：build/ember_isles/e4-coverage.csv，由e4_verify.py再生，不入库。
员工阶段194项；PM后续另加3种升级资源补位，集成结果见report-c1.md。
定向程序：../tools/e4_content_test.c；失败输出断言行号并返回非零。
十流派同次运行：钢铁反伤、群焰、永冻、星链、暗影吸取。
其余五个：弹幕、造物、夜行暴击、灯守、近战连击。
十个构筑分别检验组合标签、进化资格及实际命中、状态或召唤结果。
额外验证 50 把武器的元素和两分支数据、20 类进化机制及宠物铭文。
状态联动、混合元素、暴击、架势、光暗、深度、反弹与复用槽均有定向断言。
深度边界用例包含两轮各 3000 个弹体槽断言，计入总断言数。
确定性检查：8 角色 × 180 tick，各相同种子双运行逐字节状态相等。
CSV 独立调参：铁壁减伤 50 → 37 → 50，三次仅改表并正常重编译。
调参命令：python3 sw/apps/ember_isles/tools/e4_table_test.py。
调参日志：build/ember_isles/e4-table.log；C 源码未改动。

完整验收命令：make -C sw/apps/ember_isles linux test -j1。
完整验收已通过一次；日志：build/ember_isles/e4-make.log。
该次包含 Linux、E3 战斗、游戏流程、音乐音效、音频环和帧调度测试。
后续内容细化完成后重编译 Linux、E3 和游戏流程，结果见最终日志。
最终构建日志：build/ember_isles/e4-linux-final-build.log。
最终 E3/流程日志：build/ember_isles/e4-system-test.log。
E4 命令：python3 sw/apps/ember_isles/tools/e4_verify.py。
最终 E4 日志：build/ember_isles/e4-content.log；8053 条断言通过。
编译采用 gcc C11、-Wall -Wextra -Werror、-j1；构建 0 告警。

表现接口 facing8：0 下、1 右下、2 右、3 右上、4 上、5 左上、6 左、7 左下。
facing_frame 为五个原画方向索引；5–7 由 flip_x 镜像；旧 facing 派生保留。
移动朝向取运动；攻击、蓄力和施法朝向取瞄准。
弹体 dir16：0 右，每档逆时针 22.5°；previous_x/y 提供拖尾前点；delay 为弩连发等待 tick。
action_ticks 为当前动作局部 tick；重复攻击、施法、受伤等均重新从 0 开始。
弓、火铳、大剑及爆核法杖使用按住蓄力、释放攻击；其他武器按住连续攻击。
人物光区不含随身灯；敌人黑暗判定同时考虑固定光区和随身灯。
敌方弹体的黑暗伤害增益在发射或反弹时快照；接触伤害实时判定。
反弹立刻退出全部碰撞循环，下一 tick 执行敌方弹体路径。
界面仅按授权更新选择卡文字来源和新增选择种类，其他 gfx/ui 表现未改。

截图：outputs/ember_isles/e4/frame00120.png、frame00570.png。
另两张：同目录 frame01020.png、frame01695.png；均为 1280×720。
视频：outputs/ember_isles/e4/content.avi；640×360、15 fps、450 帧、30 秒。
视频由 8 个独立角色战斗片段构成；使用实际 game/GPU 路径，合计 1800 tick。
AVI 无压缩，约 311 MB；截图、视频及 build 生成物不入库。
画面沿用现有占位美术、HUD 和动画；不代表 tech 7 的美术质量验收。
未测：Windows、Spike 跨平台回放、实机性能及完整三关通关。
60 fps 实测问题、美术方向帧、旋转 quad 和升级图标由 PM 安排表现工作。
未完成：沙漏冷却时机、中性减速、影步转向窗口、维修强化叠加的答复及相应回归。
答复后完成 E4；等待协调者确认才进入 E5。
待答复消息：msg_d675f4338d1e、msg_1a476fb6b19b、msg_d80a9c881d8c、msg_8e7959ee02bd。

## E4b：协调者裁定收尾（2026-11-24）
结论：六项裁定和追加事件完成；本节取代上文四项待答复状态，E5 未进入。
实现提交 a741f9701；定向断言和 CSV 调参工具提交 068a1dbfe。
元素提高按转化、附加后的实际类型分别结算；规格例旧 112 → 新 125（25 铁 + 100 烬）。
颜色按防御、独立减伤后且吸收前的份额选取；元素盾吸收不会改变颜色。
中性减速独立存储星门、深渊、藤缚、蛛网、漩涡来源，取最高比例，同源刷新，韧性缩时。
群星沙漏为单个待用标记；K/L 消耗并减冷却，既有冷却和 U 不受影响。
影步锁目标 facing8 十二 tick，仍允许移动、攻击；维修按造物创建时基础值强化一次。
事件 0–11 常量在 core.h；PICKUP=10、WEAPON_CHANGE=11，新增末尾 subtype，保留伤害字段。
PICKUP 的 subtype=经验/金币/余烬/物品，value=数量（物品为 ID）；换武器 subtype=主/副/宠物，value=新 ID。
经验、遗物拾取及主副交换/新副武器/宠物武器变更已发事件；Q 每个变化槽各一次，不改随机流。
完整命令 make -C sw/apps/ember_isles linux test -j1 一次通过；日志 build/ember_isles/e4b-linux-test.log。
事件字段冻结后重编 Linux/Spike，并通过 E3/流程；日志 e4b-final-build.log、e4b-final-unit.log（同目录）。
E4 全部 8132 条断言通过，含六项新规则、转化附加混伤及拾取/换武器事件；逐项表 197 行。
定向程序 build/ember_isles/e4-content-test；日志 e4b-content.log，逐项表 e4b-coverage.csv（同目录）。
CSV 命令 python3 sw/apps/ember_isles/tools/e4b_table_test.py；日志 build/ember_isles/e4b-table.log。
仅改 CSV、生成并重编：锁向 12→7，星门 30%/90帧→45%/70帧，深渊 90→40帧。
同次调参：沙漏 60→17帧，维修伤害 24→28、护甲 10→6；恢复原表后全部恢复，C 源码未改。
跨平台：10800 输入帧、180 组全部字段摘要逐项一致，PC/Spike 均 END,10800,2,5。
旧→新摘要基线：战斗 tick 9264→9264，HP 246→246，击杀 175→175，伤害 17335→17335。
该录像旧/新 180 组摘要均未变化；终点为第5波升级界面，不作为 E5 通关证据。
复现（先加载 edrv32/env.sh）：make -C sw/apps/ember_isles linux spike -j1；build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt > build/ember_isles/e4b-pc.log。
Spike 参数和 PC 命令同 report-c1.md；新日志 build/ember_isles/e4b-{pc,spike}.log。
比较：python3 sw/apps/ember_isles/tools/compare_replay.py build/ember_isles/e4b-pc.log build/ember_isles/e4b-spike.log。
原始旧摘要 e4b-old-summary.log、比较结果 e4b-cross-summary.txt（同目录）；构建零告警，未完成项无。
