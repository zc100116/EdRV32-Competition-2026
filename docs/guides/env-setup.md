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

### 4. 环境脚本 `~/.local/opt/edrv32/env.sh`

```sh
export EDRV32_TOOLS=$HOME/.local/opt/edrv32
export PATH=$EDRV32_TOOLS/bin:$HOME/.local/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin:$HOME/.local/opt/spike/bin:$EDRV32_TOOLS/usr/bin:$HOME/.local/opt/iverilog/usr/bin:$PATH
export LD_LIBRARY_PATH=$EDRV32_TOOLS/usr/lib/x86_64-linux-gnu:$HOME/.local/opt/iverilog/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}
export VERILATOR_ROOT=$EDRV32_TOOLS/usr/share/verilator
```

## 检查

```sh
verilator --version              # Verilator 5.020
riscv-none-elf-gcc --version     # 15.2.0
spike --help | head -1
iverilog -V | head -1
```
