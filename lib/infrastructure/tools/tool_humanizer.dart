import '../../domain/models.dart';

/// 把一次工具调用转成人类可读的摘要，供审批框 / 工具卡片在前端展示。
///
/// 摘要面向高频、有副作用的工具，避免把整段 JSON 直接甩给用户盲点。
/// 未知工具或无法解析的参数回退为 null，调用方再回退到原始 JSON。
class ToolHumanizer {
  const ToolHumanizer();

  static String _s(Map<String, dynamic> args, String key) {
    final v = args[key];
    return v == null ? '' : v.toString();
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  /// 简短的动词开头描述，例如「写入文件 src/a.txt」。
  /// 无法给出干净摘要时返回 null。
  String? summaryOf(ToolCall call) {
    final a = call.arguments;
    final path = _s(a, 'path');
    return switch (call.name) {
      'write_file' || 'read_file' => _fileSummary(call.name, path),
      'edit_file' => _editSummary(path),
      'delete_file' => _deleteSummary(path),
      'move_file' => _moveSummary(path, _s(a, 'newPath')),
      'list_directory' => path.isEmpty ? '列出工作区根目录' : '列出目录 $path',
      'search_files' => _s(a, 'query').isNotEmpty
          ? '全文搜索 “${_clip(_s(a, 'query'), 40)}”'
          : null,
      'http_request' => _httpSummary(a),
      'web_search' => _s(a, 'query').isNotEmpty
          ? '联网搜索 “${_clip(_s(a, 'query'), 40)}”'
          : null,
      'terminal' => _s(a, 'command').isNotEmpty
          ? '执行命令 ${_clip(_s(a, 'command'), 60)}'
          : null,
      'get_time' => '读取当前时间',
      'json_query' =>
        _s(a, 'path').isNotEmpty ? '解析 JSON 字段 ${_s(a, 'path')}' : '解析 JSON',
      'calculator' => '执行数学计算',
      'remember' => _s(a, 'content').isNotEmpty
          ? '记住：${_clip(_s(a, 'content'), 40)}'
          : '写入一条记忆',
      'memory_get' => _s(a, 'query').isNotEmpty
          ? '检索记忆 “${_clip(_s(a, 'query'), 40)}”'
          : '读取已保存记忆',
      'memory_write' => '写入一条记忆',
      'skills_read' => _s(a, 'skill').isNotEmpty
          ? '读取 Skill ${_clip(_s(a, 'skill'), 40)}'
          : '读取 Skill 内容',
      'skills_read_resource' => _s(a, 'path').isNotEmpty
          ? '读取 Skill 资源 ${_clip(_s(a, 'path'), 40)}'
          : '读取 Skill 资源',
      'sub_agent' => _s(a, 'prompt').isNotEmpty
          ? '委派子 Agent：${_clip(_s(a, 'prompt'), 40)}'
          : '委派子 Agent 交叉验证',
      'android_device' => _androidDeviceSummary(a),
      'android_automation' => _androidAutomationSummary(a),
      _ => null,
    };
  }

  /// 关键参数的 (label, value) 行，审批框展示用。未知工具返回空。
  List<(String, String)> paramLines(ToolCall call) {
    final a = call.arguments;
    String v(String key) {
      final val = a[key];
      return val == null ? '' : val.toString();
    }

    String vv(String key, String fallback) {
      final val = a[key];
      return val == null || val.toString().isEmpty ? fallback : val.toString();
    }

    return switch (call.name) {
      'write_file' || 'read_file' || 'delete_file' => [
          ('path', v('path')),
        ],
      'move_file' => [
          ('path', v('path')),
          ('newPath', v('newPath')),
        ],
      'edit_file' => [
          ('path', v('path')),
          ('替换目标', '${v('targetContent').length} 字符'),
          ('替换为', '${v('replacementContent').length} 字符'),
        ],
      'http_request' => [
          ('method', vv('method', 'GET')),
          ('url', v('url')),
          if (a['body'] != null) ('body', _clip(a['body'].toString(), 120)),
        ],
      'web_search' => [
          ('query', v('query')),
          if (a['maxResults'] != null) ('maxResults', '${a['maxResults']}'),
        ],
      'terminal' => [
          ('command', v('command')),
          if (a['workingDirectory'] != null)
            ('workingDirectory', v('workingDirectory')),
        ],
      'search_files' => [
          ('query', v('query')),
          if (a['fileExtension'] != null) ('fileExtension', v('fileExtension')),
        ],
      'list_directory' => [('path', vv('path', '.'))],
      'android_device' ||
      'android_automation' =>
        _androidDeviceApprovalLines(a),
      _ => [],
    };
  }

  String _androidDeviceSummary(Map<String, dynamic> arguments) {
    final action = _s(arguments, 'action');
    final details = arguments['_approvalDetails'];
    if (details is Map && details['target'] is String) {
      return '$action · ${details['target']}';
    }
    return action.isEmpty ? 'Android 设备操作' : 'Android 设备操作 · $action';
  }

  String _androidAutomationSummary(Map<String, dynamic> arguments) {
    final action = _s(arguments, 'action');
    final label = switch (action) {
      'create_rule' => '创建设备自动化规则',
      'set_rule_enabled' =>
        arguments['enabled'] == true ? '启用设备自动化规则' : '暂停设备自动化规则',
      'delete_rule' => '删除设备自动化规则',
      'list_rules' => '查看设备自动化规则',
      'rule_history' => '查看自动化执行记录',
      'trigger_status' => '读取自动化触发器状态',
      'pending_fires' => '查看待确认的自动化触发',
      _ => '设备自动化',
    };
    final name = _s(arguments, 'name');
    return name.isEmpty ? label : '$label「${_clip(name, 40)}」';
  }

  List<(String, String)> _androidDeviceApprovalLines(
    Map<String, dynamic> arguments,
  ) {
    final details = arguments['_approvalDetails'];
    if (details is! Map) {
      return [
        if (_s(arguments, 'action').isNotEmpty)
          ('action', _s(arguments, 'action')),
        if (_s(arguments, 'packageName').isNotEmpty)
          ('packageName', _s(arguments, 'packageName')),
        if (_s(arguments, 'path').isNotEmpty) ('path', _s(arguments, 'path')),
      ];
    }
    String detail(String key) => details[key]?.toString() ?? '';
    final rows = <(String, String)>[
      if (detail('target').isNotEmpty) ('目标', detail('target')),
      if (detail('scope').isNotEmpty) ('影响范围', detail('scope')),
      if (detail('impact').isNotEmpty) ('影响', detail('impact')),
      if (detail('command').isNotEmpty) ('Root 命令', detail('command')),
      if (detail('executionPlan').isNotEmpty) ('执行计划', detail('executionPlan')),
      if (details['reversible'] == true)
        ('可撤销', detail('rollback').isEmpty ? '可再次设置恢复' : detail('rollback')),
      if (details['reversible'] == false)
        ('可撤销', detail('rollback').isEmpty ? '否' : '否；${detail('rollback')}'),
    ];
    return rows
        .map((row) => (row.$1, _clip(row.$2, 400)))
        .toList(growable: false);
  }

  String _fileSummary(String name, String path) {
    final isWrite = name == 'write_file';
    final desc = isWrite ? '写入文件' : '读取文件';
    return path.isEmpty ? desc : '$desc $path';
  }

  String _editSummary(String path) => path.isEmpty ? '编辑文件' : '编辑文件 $path';

  String _deleteSummary(String path) => path.isEmpty ? '删除文件' : '删除文件 $path';

  String _moveSummary(String path, String newPath) {
    if (path.isEmpty || newPath.isEmpty) return '移动文件';
    return '移动 $path -> $newPath';
  }

  String _httpSummary(Map<String, dynamic> a) {
    final method =
        (_s(a, 'method').isEmpty ? 'GET' : _s(a, 'method')).toUpperCase();
    final url = _s(a, 'url');
    if (url.isEmpty) return '发起 HTTP 请求';
    return '请求 $method $url';
  }
}
