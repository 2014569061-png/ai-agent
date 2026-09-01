#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Batch-replace ScaffoldMessenger.of(context).showSnackBar(...) with FloatingToast.show(context, ...)."""
import os, re

FILES = [
    ('lib/presentation/chat/chat_page.dart', '../widgets/floating_toast.dart'),
    ('lib/presentation/markdown/code_block.dart', '../widgets/floating_toast.dart'),
    ('lib/presentation/settings/settings_page.dart', '../widgets/floating_toast.dart'),
]

# 行扫描：
# - 整行匹配 `ScaffoldMessenger.of(<ctx>).showSnackBar(<arg>);`
# - <arg> 是 (?:const\s+)?SnackBar(content:\s*Text(<inner>))
LINE_PAT = re.compile(
    r"ScaffoldMessenger\.of\(([^)]+)\)\.showSnackBar\((.+)\);?\s*$"
)

# 提取 SnackBar 内的字符串字面量或表达式
SNACK_PAT = re.compile(r"(?:const\s+)?SnackBar\(content:\s*Text\((.+)\)\)\s*$")


def extract_message(arg: str):
    a = arg.strip()
    m = SNACK_PAT.match(a)
    if not m:
        return None
    inner = m.group(1).strip()
    # 字面量 '...' 或 "..."
    if (inner.startswith("'") and inner.endswith("'")) or (inner.startswith('"') and inner.endswith('"')):
        # 保留外层引号（Dart 字符串字面量）
        return inner
    # 表达式
    return inner


for path, import_path in FILES:
    full = os.path.join('D:/AIIIIII/ai agent/mobile_agent', path)
    txt = open(full, encoding='utf-8').read()
    out_lines = []
    changed = 0
    for line in txt.split('\n'):
        m = LINE_PAT.match(line.strip())
        if m:
            ctx = m.group(1).strip()
            arg = m.group(2).strip()
            msg = extract_message(arg)
            if msg is not None:
                indent = line[:len(line) - len(line.lstrip())]
                out_lines.append(f"{indent}FloatingToast.show({ctx}, {msg});")
                changed += 1
                continue
        out_lines.append(line)
    new = '\n'.join(out_lines)
    if 'floating_toast.dart' not in new:
        lines = new.split('\n')
        for i, l in enumerate(lines):
            if l.startswith('import '):
                lines.insert(i, f"import '{import_path}';")
                break
        new = '\n'.join(lines)
    open(full, 'w', encoding='utf-8').write(new)
    print(f'{path}: {changed} replacements')

print('done')