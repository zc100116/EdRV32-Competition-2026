# B3N SRAM 连线冒烟程序

T-BN1 的仿真程序，配套 `verif/soc/board_npu/`。读 NPU/ETH ID、验证一次已移除 VIN
槽的 load access fault，启动 DDR 后门预加载的单条 CONV，经 PLIC13 收到 DONE
后比较 64 个输出字节。寄存器访问使用生成的寄存器头，DDR 读取使用非缓存别名。

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/soc/board_npu/run.py --prepare-only
make -C sw PROGRAM=board_npu_smoke
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_npu -j 1
```

runner 通过 `tools/npu/gen_case.py --op conv --seed 1 --width 4 --height 1 --cout 16`
生成数据并调用独立参考模型，细节见验证目录 README。生成的参考数组和区域基址头文件
为 `build/board_npu/npu_case.h`，由 `program.mk` 引入；ELF、反汇编和镜像位于
`build/sw/board_npu_smoke/`。所有生成数据都保留在 `build/`。
