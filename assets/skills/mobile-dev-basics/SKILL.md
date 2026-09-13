---
name: mobile-dev-basics
description: 在本机 Android Linux 环境（内置 Alpine PRoot）里搭建并使用编程工具链：环境体检、apk 安装 Python/Node/Go/C 等、在工作区创建与运行项目。
author: NEXUS
version: 1.0.0
tags: [dev, terminal, alpine]
---

# 手机本地开发环境

终端工具运行在 Android Linux 运行时中（优先内置 Alpine PRoot，rootfs 持久化在应用目录，安装的包跨会话保留）。工作区目录是文件工具与终端的默认 cwd。

## 1. 先体检，再动手

首次接到开发类任务时，先执行一次环境体检（一条命令即可）：

```sh
uname -m && cat /etc/os-release 2>/dev/null | head -2 && command -v apk && command -v python3 node go gcc 2>/dev/null; true
```

- `aarch64` + Alpine → 内置 PRoot 环境正常，`apk` 可用。
- 体检结果决定后面是否需要安装工具链；把结果作为后续所有判断依据。

## 2. 安装语言工具链

需要什么装什么，不要一次全装：

```sh
apk add --no-cache python3      # Python
apk add --no-cache nodejs npm   # Node.js
apk add --no-cache go           # Go
apk add --no-cache gcc g++ make musl-dev   # C/C++
apk add --no-cache openjdk17    # Java 17（含 javac/keytool/jar）
apk add --no-cache rust cargo   # Rust
```

- 单条命令默认 120s 超时；安装/下载慢时在 terminal 调用里传 `timeoutSeconds`（上限 86400）。
- 网络失败时换镜像源（中国大陆网络常用清华源）：
  `sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && apk update`

## 3. 创建与运行项目

项目一律放在工作区（终端的 cwd）里，用 write_file 写源码，用终端运行：

```sh
python3 main.py
node index.js
go run .
gcc main.c -o app && ./app
java Main
```

Go 项目 `go mod init <name>` 后再 `go run .`；依赖下载慢时 `go env -w GOPROXY=https://goproxy.cn,direct`。

## 4. 汇报纪律

- 一切结论基于真实命令输出；命令失败就如实说失败和原因，禁止伪造执行成功。
- 长任务（编译、下载）先告诉用户预计耗时，再用大 timeoutSeconds 执行。
