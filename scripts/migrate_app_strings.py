#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把核心页面字面量文案替换为 AppStrings 引用（精确匹配，避免误伤）。"""
import os, re

BASE = 'D:/AIIIIII/ai agent/mobile_agent'

# (文件, [(旧字面量, 新引用)])
REPLACEMENTS = {
    'lib/presentation/chat/chat_page.dart': [
        ("'开始一个新的 Agent 任务'", 'AppStrings.startNewAgentTask'),
        ("'选择一个方向，或者直接输入你的任务'", 'AppStrings.pickDirectionOrTypeTask'),
        ("'输入任务…'", 'AppStrings.inputTaskHint'),
        ("'添加文件'", 'AppStrings.addFile'),
        ("'演示模式（未配置）'", 'AppStrings.demoModeUnconfigured'),
        ("'复制会话'", 'AppStrings.copyConversation'),
        ("'导出 Markdown'", 'AppStrings.exportMarkdown'),
        ("'重新生成'", 'AppStrings.regenerate'),
        ("'切换模型'", 'AppStrings.switchModel'),
        ("'新会话'", 'AppStrings.newConversation'),
        ("'确认工具调用'", 'AppStrings.confirmToolCall'),
        ("'执行前需要你的授权'", 'AppStrings.requiresAuthorization'),
        ("'调用参数'", 'AppStrings.toolArguments'),
        ("'拒绝'", 'AppStrings.reject'),
        ("'允许一次'", 'AppStrings.allowOnce'),
        ("'危险操作'", 'AppStrings.dangerOperation'),
        ("'需要确认'", 'AppStrings.requiresConfirmation'),
        ("'当前会话已复制到剪贴板'", 'AppStrings.conversationCopied'),
        ("'已复制 Markdown 到剪贴板'", 'AppStrings.copiedToClipboard'),
        ("'已应用为系统提示词'", 'AppStrings.applyAsSystemPrompt'),
        ("'已插入到输入框'", 'AppStrings.insertedToInput'),
        ("'选择 Agent'", 'AppStrings.selectAgent'),
        ("'浏览器预览暂不启用 Agent 持久化。'", 'AppStrings.agentPersistenceDisabled'),
        ("'浏览器预览暂不启用会话持久化。'", 'AppStrings.conversationPersistenceDisabled'),
        ("'切换模型服务商'", 'AppStrings.switchProvider'),
        ("'尚未配置 Provider，请前往「设置」添加。'", 'AppStrings.noProviderConfigured'),
        ("'本地直连模式'", 'AppStrings.localDirectMode'),
    ],
    'lib/presentation/settings/settings_page.dart': [
        ("'Provider 设置'", 'AppStrings.providerSettings'),
        ("'模型服务配置'", 'AppStrings.modelServiceConfig'),
        ("'快速套用服务商模板'", 'AppStrings.quickApplyTemplate'),
        ("'协议类型'", 'AppStrings.protocolType'),
        ("'已保存 Provider'", 'AppStrings.savedProviders'),
        ("'Provider 名称'", 'AppStrings.providerName'),
        ("'Base URL'", 'AppStrings.baseUrl'),
        ("'模型名称'", 'AppStrings.modelName'),
        ("'API Key'", 'AppStrings.apiKey'),
        ("'Tavily API Key（联网搜索，可选）'", 'AppStrings.tavilyApiKey'),
        ("'保存配置'", 'AppStrings.saveConfig'),
        ("'保存中…'", 'AppStrings.saving'),
        ("'测试连接'", 'AppStrings.testConnection'),
        ("'测试中…'", 'AppStrings.testing'),
        ("'Provider 配置已保存'", 'AppStrings.providerConfigSaved'),
        ("'请先填写 Base URL 和 API Key'", 'AppStrings.fillBaseUrlAndKey'),
        ("'仅 OpenAI 兼容协议支持自动获取模型列表，请手动填写模型名称。'", 'AppStrings.onlyOpenAiCompatible'),
        ("'服务未返回可用模型'", 'AppStrings.noModelsReturned'),
        ("'API Key 仅保存到系统安全存储。'", 'AppStrings.apiKeySecureStorage'),
        ("'日间模式'", 'AppStrings.dayMode'),
        ("'当前使用蓝白浅色主题'", 'AppStrings.dayModeSubtitle'),
        ("'当前使用深色主题'", 'AppStrings.darkModeSubtitle'),
        ("'MCP 服务器'", 'AppStrings.mcpServers'),
        ("'MCP 工具会在 Agent 执行时自动合并进工具集，风险默认需要确认。'", 'AppStrings.mcpServersHint'),
        ("'尚未配置 MCP 服务器。'", 'AppStrings.noMcpServers'),
        ("'添加 MCP 服务器'", 'AppStrings.addMcpServer'),
        ("'清空全部'", 'AppStrings.clearAll'),
        ("'清空 MCP 服务器？'", 'AppStrings.clearMcpServers'),
        ("'将移除全部已配置的 MCP 服务器。'", 'AppStrings.clearMcpServersConfirm'),
        ("'清空'", 'AppStrings.clear'),
        ("'取消'", 'AppStrings.cancel'),
        ("'添加'", 'AppStrings.add'),
        ("'连接方式'", 'AppStrings.connectionMethod'),
        ("'Streamable HTTP（推荐）'", 'AppStrings.streamableHttp'),
        ("'stdio 子进程（仅桌面）'", 'AppStrings.stdioProcess'),
        ("'名称'", 'AppStrings.serverName'),
        ("'服务器 URL（如 http://localhost:3000/mcp）'", 'AppStrings.serverUrl'),
        ("'命令（如 npx）'", 'AppStrings.command'),
        ("'参数（空格分隔）'", 'AppStrings.argsSpaceSeparated'),
        ("'请填写服务器 URL'", 'AppStrings.fillServerUrl'),
        ("'连接成功'", 'AppStrings.connectionSuccess'),
    ],
    'lib/presentation/agents/agents_page.dart': [
        ("'可用工具'", 'AppStrings.availableTools'),
        ("'危险操作，执行前必须确认'", 'AppStrings.dangerToolHint'),
        ("'执行前需要确认'", 'AppStrings.confirmToolHint'),
        ("'安全工具'", 'AppStrings.safeTool'),
        ("'模型参数'", 'AppStrings.modelParams'),
        ("'温度'", 'AppStrings.temperature'),
        ("'Top P'", 'AppStrings.topP'),
        ("'最大输出 Token'", 'AppStrings.maxOutputTokens'),
        ("'最大执行步数'", 'AppStrings.maxExecutionSteps'),
    ],
}

for rel, pairs in REPLACEMENTS.items():
    full = os.path.join(BASE, rel)
    txt = open(full, encoding='utf-8').read()
    changed = 0
    for old, new in pairs:
        cnt = txt.count(old)
        if cnt:
            txt = txt.replace(old, new)
            changed += cnt
    # 加 import（如果还没有）
    if 'app_strings.dart' not in txt:
        lines = txt.split('\n')
        # 计算相对路径
        depth = rel.count('/') - 1  # lib/presentation/... 下的目录层级
        if rel.startswith('lib/presentation/chat/'):
            imp = "import '../l10n/app_strings.dart';"
        elif rel.startswith('lib/presentation/settings/'):
            imp = "import '../l10n/app_strings.dart';"
        elif rel.startswith('lib/presentation/agents/'):
            imp = "import '../l10n/app_strings.dart';"
        else:
            imp = "import '../l10n/app_strings.dart';"
        for i, l in enumerate(lines):
            if l.startswith('import '):
                lines.insert(i, imp)
                break
        txt = '\n'.join(lines)
    open(full, 'w', encoding='utf-8').write(txt)
    print(f'{rel}: {changed} replacements')

print('done')