#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复 Python 替换脚本误去掉的外层单引号。
特征：FloatingToast.show(ctx, HANS) 中 args 以 CJK 字符开头（应该带单引号）。"""
import os, re

FILES = [
    'lib/presentation/chat/chat_page.dart',
    'lib/presentation/markdown/code_block.dart',
    'lib/presentation/settings/settings_page.dart',
]

# 匹配: FloatingToast.show(<ctx>, <args>);
# - <args> 以 CJK 字符开头（非引号/$）→ 损坏
# - <args> 以 $ 或 ' 开头 → 正确
LINE_PAT = re.compile(r"(FloatingToast\.show\(([^,]+),\s*)(.+?)(\);)")

CJK_START = re.compile(r"[\u4E00-\u9FFF]")

for path in FILES:
    full = os.path.join('D:/AIIIIII/ai agent/mobile_agent', path)
    txt = open(full, encoding='utf-8').read()
    fixed = []
    for line in txt.split('\n'):
        m = LINE_PAT.match(line.strip())
        if m:
            prefix = m.group(1)
            args = m.group(3).strip()
            if CJK_START.match(args):
                # 加单引号
                line = line.replace(prefix + args, prefix + "'" + args + "'")
        fixed.append(line)
    new = '\n'.join(fixed)
    if new != txt:
        open(full, 'w', encoding='utf-8').write(new)
        print(f'fixed: {path}')

print('done')