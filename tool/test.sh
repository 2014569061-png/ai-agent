#!/usr/bin/env bash
# 本机跑 flutter test 的环境修正脚本。
#
# 为什么需要它：本机（Windows + Git Bash + 沙箱）环境下 `flutter test` 会连报两个错，
# 且都跟代码无关：
#
#   1) `%PROGRAMFILES(X86)% environment variable not found`
#      环境里没有 PROGRAMFILES(X86) 这个变量，而 flutter_tester 的启动链路会读它，
#      导致测试进程根本起不来。
#
#   2) `Unable to connect to flutter_tester process:
#       WebSocketException: Invalid WebSocket upgrade request`
#      shell 里 http_proxy/https_proxy 指向本地代理（127.0.0.1:xxxxx）。
#      Dart 的 HttpClient 默认走 findProxyFromEnvironment，会把**连向 127.0.0.1 的
#      WebSocket 请求也发给代理**；代理收到的是普通 HTTP 请求而不是 upgrade 握手，
#      于是直接回绝。
#
# 两点修正一起用即可正常跑测试：
#   · 补上 PROGRAMFILES(X86)
#   · 清空代理变量，并让 127.0.0.1 / localhost 走 NO_PROXY 直连
#
# 用法：
#   tool/test.sh                          # 跑全部测试
#   tool/test.sh test/xxx_test.dart       # 跑指定文件
#   tool/test.sh test/xxx_test.dart -n "用例名"
#
# 注意：`flutter analyze` 不受影响，无需本脚本。

set -euo pipefail
cd "$(dirname "$0")/.."

exec env \
  "PROGRAMFILES(X86)=C:\\Program Files (x86)" \
  http_proxy= https_proxy= HTTP_PROXY= HTTPS_PROXY= \
  NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost \
  flutter test "$@"
