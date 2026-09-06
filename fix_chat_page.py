import re

filepath = 'lib/presentation/chat/chat_page.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# 278: 已接收图片
content = content.replace("FloatingToast.show(context, '已接收图片，可点击发送');", "FloatingToast.show(context, '已接收图片，可点击发送', tone: ToastTone.success);")

# 280: 图片分享解析失败
content = content.replace("} catch (_) {\n        FloatingToast.show(context, '图片分享解析失败');", "} catch (e) {\n        FloatingToast.error(context, '图片分享解析失败', rawDetail: e.toString());")

# 328: conversationCopied
content = content.replace("FloatingToast.show(context, AppStrings.conversationCopied);", "FloatingToast.show(context, AppStrings.conversationCopied, tone: ToastTone.success);")

# 339: copiedToClipboard / 已导出
content = content.replace("FloatingToast.show(context,\n        kIsWeb || path.isEmpty ? AppStrings.copiedToClipboard : '已导出到 $path');", "FloatingToast.show(context, kIsWeb || path.isEmpty ? AppStrings.copiedToClipboard : '已导出到 $path', tone: ToastTone.success);")

# 352: 分享失败
content = content.replace("} catch (_) {\n      if (mounted) FloatingToast.show(context, '分享失败');", "} catch (e) {\n      if (mounted) FloatingToast.error(context, '分享失败', rawDetail: e.toString());")

# 550: 无法获取图片
content = content.replace("} catch (_) {\n      if (mounted) FloatingToast.show(context, '无法获取图片');", "} catch (e) {\n      if (mounted) FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());")

# 618: 无法获取图片
# There is a second occurrence of catch (_) for pickImage
content = content.replace("} catch (_) {\n      if (mounted) FloatingToast.show(context, '无法获取图片');", "} catch (e) {\n      if (mounted) FloatingToast.error(context, '无法获取图片', rawDetail: e.toString());")

# 632: voiceError (available false)
content = content.replace("if (mounted) FloatingToast.show(context, AppStrings.voiceError);", "if (mounted) FloatingToast.error(context, AppStrings.voiceError);")

# 651: voiceError (catch block)
content = content.replace("} catch (_) {\n      if (mounted) {\n        setState(() => _listening = false);\n        FloatingToast.show(context, AppStrings.voiceError);", "} catch (e) {\n      if (mounted) {\n        setState(() => _listening = false);\n        FloatingToast.error(context, AppStrings.voiceError, rawDetail: e.toString());")

# Paste errors
content = content.replace("if (mounted) FloatingToast.show(context, '剪贴板不可用');", "if (mounted) FloatingToast.error(context, '剪贴板不可用');")
content = content.replace("if (mounted) FloatingToast.show(context, '剪贴板没有图片');", "if (mounted) FloatingToast.error(context, '剪贴板没有图片');")
content = content.replace("if (mounted) FloatingToast.show(context, '无法读取剪贴板图片');", "if (mounted) FloatingToast.error(context, '无法读取剪贴板图片');")
content = content.replace("FloatingToast.show(context, '已粘贴图片');", "FloatingToast.show(context, '已粘贴图片', tone: ToastTone.success);")
content = content.replace("} catch (_) {\n      if (mounted) FloatingToast.show(context, '无法读取剪贴板，请手动选图');", "} catch (e) {\n      if (mounted) FloatingToast.error(context, '无法读取剪贴板，请手动选图', rawDetail: e.toString());")

# Audio record
content = content.replace("FloatingToast.show(context, '录音已添加');", "FloatingToast.show(context, '录音已添加', tone: ToastTone.success);")
content = content.replace("if (mounted) FloatingToast.show(context, '未获得麦克风权限');", "if (mounted) FloatingToast.error(context, '未获得麦克风权限');")
content = content.replace("if (mounted) FloatingToast.show(context, '录音不可用');", "if (mounted) FloatingToast.error(context, '录音不可用');")

# Other positive
content = content.replace("FloatingToast.show(context, AppStrings.applyAsSystemPrompt);", "FloatingToast.show(context, AppStrings.applyAsSystemPrompt, tone: ToastTone.success);")
content = content.replace("FloatingToast.show(context, AppStrings.insertedToInput);", "FloatingToast.show(context, AppStrings.insertedToInput, tone: ToastTone.success);")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)
