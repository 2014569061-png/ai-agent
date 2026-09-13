---
name: mobile-dev-basics
description: 仅在任务需要搭建或变更 Android Linux（Alpine PRoot）工具链，或需要在该环境创建、运行项目时使用。
author: NEXUS
version: 1.0.0
tags: [dev, terminal, alpine]
---

# 手机本地开发环境

仅适用于 Android Linux/Alpine PRoot。工作区是终端的默认 cwd。

## 触发与路由

环境状态未知，或任务所需命令缺失时才执行体检；环境和工具已验证可用时跳过：

    uname -m && cat /etc/os-release 2>/dev/null | head -2 && command -v apk

体检只确认运行时和 apk；按当前任务检查所需命令，缺失才安装。按需安装对应包：
python3、nodejs npm、go、gcc g++ make musl-dev、openjdk17、rust cargo。

网络失败时停止并报告；只使用环境预先配置的可信 apk 源，不自动修改 /etc/apk/repositories，也不自动切换到任意代理镜像。

## 工作区与执行

项目放在工作区（终端 cwd）内。用当前可用的文件编辑工具写源码；在 Codex 中使用 apply_patch。用终端运行项目。

长任务先告知预计耗时，然后立即执行，不等待确认。安全的本地编译、测试和修复可连续完成。

## 汇报

结论必须基于真实命令输出。命令失败时如实报告失败步骤、原因和原始错误，禁止伪造成功。
