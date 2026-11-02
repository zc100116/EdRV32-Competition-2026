# Linux 开发环境安装

本机没有 root 权限，所有工具都安装在用户目录 `~/.local/opt/` 下。使用前执行：

```sh
. ~/.local/opt/edrv32/env.sh
```

## 工具清单

| 工具 | 版本 | 安装位置 | 来源 |
|---|---|---|---|
| RISC-V GCC（`riscv-none-elf-gcc`） | 15.2.0 | `~/.local/opt/xpack-riscv-none-elf-gcc-15.2.0-1/` | xPack 预编译包 |
| Spike | riscv-isa-sim 源码，commit `2c300cd` | `~/.local/opt/spike/` | 从源码构建 |
| Verilator | 5.020 | `~/.local/opt/edrv32/usr/` | Ubuntu 24.04 deb 包解压 |
| GTKWave | 3.3.116 | `~/.local/opt/edrv32/usr/` | Ubuntu 24.04 deb 包解压 |
| dtc | 1.7.0 | `~/.local/opt/edrv32/usr/` | Ubuntu 24.04 deb 包解压 |
| Icarus Verilog | 12.0 | `~/.local/opt/iverilog/usr/` | Ubuntu 24.04 deb 包解压 |
| Yosys | 0.70+219（OSS CAD Suite 2026-10-25） | `~/.local/opt/oss-cad-suite/` | YosysHQ 预编译包解压；只用于结构性时序预估，FPGA 综合以 PDS 为准 |
| Python 虚拟环境（NPU 离线工具） | Python 3.12，torch 2.14.1 CPU，numpy 2.5.2，版本见 `tools/requirements.txt` | `~/.local/opt/edrv32-py/` | pip；ultralytics 用仓库子模块 `third_party/ultralytics`（8.4.160） |
| YOLOv8n 权重、COCO128 | ultralytics assets | `~/.local/share/edrv32/npu/` | GitHub release 下载，不入库 |

`~/.local/opt/edrv32/usr/bin/` 下还有 Ubuntu 的 `riscv64-unknown-elf-gcc` 13.2，它的预编译库缺少 rv32imc 组合，**项目统一使用 `riscv-none-elf-gcc` 15.2.0**。

## 安装步骤

### 1. Ubuntu deb 包（Verilator、GTKWave、dtc 及运行库）

```sh
mkdir -p ~/.cache/edrv32-debs && cd ~/.cache/edrv32-debs
apt-get download verilator gtkwave libjudydebian1 libtk8.6 device-tree-compiler libfdt1
mkdir -p ~/.local/opt/edrv32 && cd ~/.local/opt/edrv32
for d in ~/.cache/edrv32-debs/*.deb; do dpkg -x "$d" .; done
# Verilator 在 VERILATOR_ROOT 下查找 verilator_bin，Ubuntu 包把它放在 usr/bin
cd usr/share/verilator
for b in verilator_bin verilator_bin_dbg verilator_coverage_bin_dbg; do ln -sf ../../bin/$b $b; done
```

Icarus 用同样的方法解压到 `~/.local/opt/iverilog/`（`apt-get download iverilog`）。解压后的 Icarus 找不到自己的 `ivl` 目录，用包装脚本 `~/.local/opt/edrv32/bin/iverilog` 补上 `-B` 参数：

```sh
mkdir -p ~/.local/opt/edrv32/bin
cat > ~/.local/opt/edrv32/bin/iverilog <<'EOS'
#!/bin/sh
exec "$HOME/.local/opt/iverilog/usr/bin/iverilog" -B "$HOME/.local/opt/iverilog/usr/lib/x86_64-linux-gnu/ivl" "$@"
EOS
chmod +x ~/.local/opt/edrv32/bin/iverilog
```

### 2. RISC-V GCC

```sh
cd ~/.cache && mkdir -p edrv32-xpack && cd edrv32-xpack
U=https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1
curl -sSLO $U/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz
tar -xzf xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz -C ~/.local/opt
```

### 2.1 GCC 16.1.0（仅用于 CoreMark 编译器对比）

项目默认编译器仍为 xPack GCC 15.2.0；不修改 `env.sh`。比较工具链安装在
`~/.local/opt/riscv-gcc-16.1.0/`，构建 monitor 时显式传入该目录下的 `CC`、
`OBJDUMP` 和 `OBJCOPY`。源码为 GNU GCC 16.1.0 与 GNU binutils 2.45（与 xPack
15.2.0-1 的 binutils 版本相同），仅构建裸机 C 编译器和 libgcc，无 libc。

```sh
mkdir -p ~/.cache/edrv32-gcc16
cd ~/.cache/edrv32-gcc16
curl -fLO https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz
curl -fLO https://ftp.gnu.org/gnu/binutils/binutils-2.45.tar.xz
tar -xf gcc-16.1.0.tar.xz
tar -xf binutils-2.45.tar.xz
cd gcc-16.1.0
contrib/download_prerequisites --no-verify
cd ..
mkdir build-binutils
cd build-binutils
../binutils-2.45/configure --target=riscv-none-elf \
  --prefix=$HOME/.local/opt/riscv-gcc-16.1.0 --disable-nls
make -j3
make install
cd ..
mkdir build-gcc
cd build-gcc
PATH=$HOME/.local/opt/riscv-gcc-16.1.0/bin:$PATH ../gcc-16.1.0/configure \
  --target=riscv-none-elf --prefix=$HOME/.local/opt/riscv-gcc-16.1.0 \
  --without-headers --with-newlib --enable-languages=c --disable-multilib \
  --disable-shared --disable-threads --disable-libssp --disable-libquadmath \
  --disable-libgomp --disable-nls --with-arch=rv32im_zicsr_zifencei --with-abi=ilp32
PATH=$HOME/.local/opt/riscv-gcc-16.1.0/bin:$PATH make -j3 all-gcc all-target-libgcc
PATH=$HOME/.local/opt/riscv-gcc-16.1.0/bin:$PATH make install-gcc install-target-libgcc
~/.local/opt/riscv-gcc-16.1.0/bin/riscv-none-elf-gcc -dumpfullversion
~/.local/opt/riscv-gcc-16.1.0/bin/riscv-none-elf-gcc -v
```

`download_prerequisites` 获取 gettext 0.22、GMP 6.3.0、MPFR 4.2.2、MPC 1.3.1
和 ISL 0.24；按仓库规则使用 `--no-verify`。构建完成后按协调者要求清理本次源码和中间目录，
本机保留 `~/.cache/edrv32-gcc16/monitor-logs/`；八个 monitor 的选项与大小见
`tasks/win/20261102-40-coremark-gcc/src/variants.md`。

### 3. Spike

```sh
mkdir -p ~/.cache/src && cd ~/.cache/src
git clone https://github.com/riscv-software-src/riscv-isa-sim.git
cd riscv-isa-sim && git submodule update --init --depth 1
mkdir build && cd build
. ~/.local/opt/edrv32/env.sh        # 需要 dtc
../configure --prefix=$HOME/.local/opt/spike --without-boost --without-boost-asio --without-boost-regex
make -j$(nproc) && make install
```

### 4. Yosys（OSS CAD Suite）

```sh
curl -L -o oss-cad-suite.tgz https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-25/oss-cad-suite-linux-x64-20261025.tgz
tar -xzf oss-cad-suite.tgz -C ~/.local/opt/
```

其 `bin/` 追加在 PATH 末尾，使套件自带的 Verilator、Icarus 不覆盖项目版本。

### 5. 环境脚本 `~/.local/opt/edrv32/env.sh`

```sh
export EDRV32_TOOLS=$HOME/.local/opt/edrv32
export PATH=$EDRV32_TOOLS/bin:$HOME/.local/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$HOME/.local/opt/spike/bin:$EDRV32_TOOLS/usr/bin:$HOME/.local/opt/iverilog/usr/bin:$PATH
export LD_LIBRARY_PATH=$EDRV32_TOOLS/usr/lib/x86_64-linux-gnu:$HOME/.local/opt/iverilog/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
export VERILATOR_ROOT=$EDRV32_TOOLS/usr/share/verilator
export PATH=$PATH:$HOME/.local/opt/oss-cad-suite/bin
```

### 6. NPU 离线工具的 Python 环境

系统 Python 没有 `ensurepip`，用 `--without-pip` 建虚拟环境，再用系统 pip 的 `--python` 安装：

```sh
python3 -m venv --without-pip ~/.local/opt/edrv32-py
P=~/.local/opt/edrv32-py/bin/python
python3 -m pip --python $P install torch==2.14.1 torchvision==0.29.1 --index-url https://download.pytorch.org/whl/cpu
python3 -m pip --python $P install -r tools/requirements.txt
git submodule update --init third_party/ultralytics
```

ultralytics 不装进虚拟环境，运行时用 `PYTHONPATH=<仓库>/third_party/ultralytics`，这样每个工作区都用自己检出的子模块版本。

模型和数据放在仓库外：

```sh
D=~/.local/share/edrv32/npu; mkdir -p $D
curl -L -o $D/yolov8n.pt https://github.com/ultralytics/assets/releases/download/v8.4.0/yolov8n.pt
curl -L -o $D/coco128.zip https://github.com/ultralytics/assets/releases/download/v0.0.0/coco128.zip
python3 -c "import zipfile; zipfile.ZipFile('$D/coco128.zip').extractall('$D')"
```

在本机（3 核）上用旧工程脚本实测（2026-10-27）：检查点核对 6 s；96 张图标定并导出 INT8 镜像 1 分 24 秒；单图整网 INT8 主机模拟 6 s；32 张图精度评估 2 分 5 秒（浮点 mAP50 0.642，INT8 0.611）。

## 检查

```sh
verilator --version              # Verilator 5.020
riscv-none-elf-gcc --version     # 15.2.0
spike --help | head -1
iverilog -V | head -1
yosys -V                         # Yosys 0.70+219
~/.local/opt/edrv32-py/bin/python -c "import torch, numpy; print(torch.__version__, numpy.__version__)"   # 2.14.1+cpu 2.5.2
```
