/// Typed input only. This is not an execution, permission or approval engine.
/// Android adapters must still use the existing device preview/approval ledger.
enum SystemConnectorId { calendar, contacts, maps, files, media }

class SystemConnectorRequest {
  SystemConnectorRequest._(this.connector, this.operation, this.arguments);

  final SystemConnectorId connector;
  final String operation;
  final Map<String, dynamic> arguments;

  static const operations = {
    SystemConnectorId.calendar: 'prepare_event',
    SystemConnectorId.contacts: 'prepare_contact',
    SystemConnectorId.maps: 'search_place',
    SystemConnectorId.files: 'pick_document',
    SystemConnectorId.media: 'pick_media',
  };

  factory SystemConnectorRequest.fromJson(Map<String, dynamic> json) {
    _keys(json, {'connectorId', 'operation', 'arguments'});
    final id = json['connectorId'];
    final matching =
        SystemConnectorId.values.where((value) => value.name == id);
    if (matching.isEmpty) throw const FormatException('不支持的系统连接器');
    final connector = matching.single;
    if (json['operation'] != operations[connector]) {
      throw const FormatException('连接器与操作不匹配');
    }
    final raw = json['arguments'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('arguments 必须是对象');
    }
    final Map<String, dynamic> arguments;
    switch (connector) {
      case SystemConnectorId.calendar:
        _keys(raw, {'title', 'start', 'end', 'location', 'description'});
        final start = _instant(raw['start']);
        final end = _instant(raw['end']);
        if (!end.isAfter(start)) {
          throw const FormatException('事件结束时间必须晚于开始时间');
        }
        arguments = {
          'title': _text(raw['title'], '事件标题', 200),
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          if (raw.containsKey('location'))
            'location': _text(raw['location'], '事件地点', 500),
          if (raw.containsKey('description'))
            'description': _text(raw['description'], '事件说明', 4000),
        };
      case SystemConnectorId.contacts:
        _keys(raw, {'name', 'phone', 'email'});
        arguments = {
          'name': _text(raw['name'], '联系人名称', 200),
          if (raw.containsKey('phone'))
            'phone': _text(raw['phone'], '电话号码', 80),
          if (raw.containsKey('email'))
            'email': _text(raw['email'], '电子邮件', 254),
        };
        final email = arguments['email'];
        if (email is String &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
          throw const FormatException('电子邮件格式无效');
        }
      case SystemConnectorId.maps:
        _keys(raw, {'query'});
        arguments = {'query': _text(raw['query'], '地点搜索词', 1000)};
      case SystemConnectorId.files:
        _keys(raw, {'mimeTypes'});
        final types = raw.containsKey('mimeTypes') ? raw['mimeTypes'] : ['*/*'];
        if (types is! List || types.isEmpty || types.length > 8) {
          throw const FormatException('文件 MIME 类型数量必须为 1–8');
        }
        final parsed = <String>[];
        for (final type in types) {
          if (type is! String ||
              type.length > 127 ||
              !(type == '*/*' ||
                  RegExp(r'^[a-z0-9][a-z0-9!#$&^_.+\-]*/(?:\*|[a-z0-9][a-z0-9!#$&^_.+\-]*)$')
                      .hasMatch(type))) {
            throw const FormatException('文件 MIME 类型无效');
          }
          if (!parsed.contains(type)) parsed.add(type);
        }
        parsed.sort();
        arguments = {'mimeTypes': List<String>.unmodifiable(parsed)};
      case SystemConnectorId.media:
        _keys(raw, {'kind'});
        final kind = raw['kind'];
        if (kind != 'image' && kind != 'video') {
          throw const FormatException('媒体类型仅支持 image 或 video');
        }
        arguments = {'kind': kind};
    }
    return SystemConnectorRequest._(
      connector,
      operations[connector]!,
      Map<String, dynamic>.unmodifiable(arguments),
    );
  }

  Map<String, dynamic> toJson() => {
        'connectorId': connector.name,
        'operation': operation,
        'arguments': Map<String, dynamic>.from(arguments),
      };

  /// Opening an editor or a map cannot prove that an external task completed.
  bool get requiresSystemConfirmation =>
      connector == SystemConnectorId.calendar ||
      connector == SystemConnectorId.contacts;

  static void _keys(Map<String, dynamic> value, Set<String> allowed) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('包含未支持字段，不接受任意 URI、Intent 或命令');
    }
  }

  static String _text(Object? value, String label, int limit) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > limit ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw FormatException('$label 为空、过长或包含控制字符');
    }
    return value.trim();
  }

  static DateTime _instant(Object? value) {
    if (value is! String) throw const FormatException('时间必须是字符串');
    final parts = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(value);
    if (parts == null) {
      throw const FormatException('时间必须包含秒及明确 UTC 偏移，不推测本地时区');
    }
    final year = int.parse(parts[1]!);
    final month = int.parse(parts[2]!);
    final day = int.parse(parts[3]!);
    final hour = int.parse(parts[4]!);
    final minute = int.parse(parts[5]!);
    final second = int.parse(parts[6]!);
    final date = DateTime.utc(year, month, day);
    if (year < 1 ||
        date.year != year ||
        date.month != month ||
        date.day != day ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw const FormatException('日期或时间无效');
    }
    final zone = parts[8]!;
    if (zone != 'Z') {
      final hours = int.parse(zone.substring(1, 3));
      final minutes = int.parse(zone.substring(4, 6));
      if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
        throw const FormatException('UTC 偏移无效');
      }
    }
    final instant = DateTime.parse(value).toUtc();
    if (instant.year < 1 || instant.year > 9999) {
      throw const FormatException('UTC 时间超出支持范围');
    }
    return instant;
  }
}
