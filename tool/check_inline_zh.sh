#!/usr/bin/env bash
# i18n 门禁（2026-09-12 用户决策：产品仅面向中文，不做 ARB/gen-l10n 改造）。
#
# 规则：lib/presentation 下含中文字符的 .dart 内容行数不得上升（基线见
# tool/inline_zh_baseline.txt）。允许下降 —— 做文案收敛后应同步调低基线；
# 任何上升都会被本门禁拦下，意味着有人绕过了 AppStrings 或组件默认文案，
# 需先评审再有意更新基线。
#
# 统计口径（2026-09-12 修正）：
#   · **排除 `lib/presentation/l10n/`**：那是文案表的合法落点，`app_strings.dart`
#     本身就是「内联中文」的收纳处。原口径把它也计入，结果是「把文案搬进
#     AppStrings」与「新增文案」都会顶到基线，反而逼人去改基线数字。
#   · 只统计"内容行"：纯注释行（// 开头）与空行不计 —— 门禁拦的是用户可见文案，
#     不是代码注释（2026-09-12 实测：注释里的中文说明会把门禁误伤成红）。
set -euo pipefail
export LC_ALL=C.UTF-8
cd "$(dirname "$0")/.."

BASELINE_FILE="tool/inline_zh_baseline.txt"
BASELINE=$(cat "$BASELINE_FILE")

# -H 强制带上文件名：单文件命中时 grep -c 只打印计数，会让下面的求和静默变 0。
COUNT=$(grep -rlP '[\x{4E00}-\x{9FFF}]' lib/presentation --include='*.dart' \
  | grep -v '/l10n/' \
  | xargs grep -cHP '^(?!\s*//).*[\x{4E00}-\x{9FFF}]' \
  | awk -F: '{s+=$2} END {print s+0}')

echo "inline CJK content lines: $COUNT (baseline: $BASELINE)"

if [ "$COUNT" -gt "$BASELINE" ]; then
  echo ""
  echo "!! 内联中文行数超过基线：$COUNT > $BASELINE"
  echo "   产品决策为「仅中文，不新增内联文案」。请把新文案收入"
  echo "   lib/presentation/l10n/app_strings.dart，或说明为何必须上升，"
  echo "   并有意更新 tool/inline_zh_baseline.txt。"
  exit 1
fi

echo "OK"
