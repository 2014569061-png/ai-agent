#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复 chat_controller.dart 中的乱码字符串字面量。
源代码作者输入"通用助手"等中文时，文件被错误保存为 GBK 字节，再用 UTF-8 读取，
得到罕用 CJK 字符。修复策略：直接字符替换。
"""
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else 'lib/application/chat_controller.dart'

# 字符串字面量映射表（按出现频率/重要性排序）
MAPPINGS = [
    # 默认 agent 名（首页显示）
    ('閫氱敤鍔╂墜', '通用助手'),
    # 默认会话标题（AppBar 显示）
    ('鏂颁細', '新会话'),
    # 演示模式模型名
    ('婕旂ず妯″瀷', '演示模型'),
    # 文件附件相关
    ('鏂囦欢', '文件'),
    # 通用"附件"前缀
    ('闄勪欢', '附件'),
    # 8MB 大小限制
    ('瓒呰繃 8MB锛屽凡璺宠繃', '超过 8MB，已跳过'),
    # 工具执行状态
    ('宸ュ叿', '工具'),
    ('鎵ц澶辫触', '执行失败'),
    # PDF 提取失败提示（含特殊 Unicode 字符）
    ('鏈\ue045彁鍙栧埌鍙\ue21c敤鏂囨湰', '未提取到可用文本'),
    # 文件内容前缀
    ('鍐呭\ue190锛歕n', '内容：\\n'),
    # 状态文字
    ('绛夊緟', '等待'),
    ('绛夊緟鎵ц', '等待执行'),
    ('绛夊緟纭\ue1bf\ue17b', '等待确认'),
    ('纭\ue1bf\ue17b', '确认'),
    ('澶辫触', '失败'),
    ('宸插畬', '已完成'),
]

with open(PATH, encoding='utf-8') as f:
    txt = f.read()

new = txt
applied = []
for k, v in MAPPINGS:
    if k in new and k != v:
        cnt = new.count(k)
        new = new.replace(k, v)
        applied.append((k, v, cnt))

print(f'已应用 {len(applied)} 项替换:')
for k, v, c in applied:
    print(f'  {c:3d}x  {k!r} -> {v!r}')

with open(PATH, 'w', encoding='utf-8') as f:
    f.write(new)
print(f'\n文件已修复: {PATH}')