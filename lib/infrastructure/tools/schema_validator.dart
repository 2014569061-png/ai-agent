/// 工具参数使用的轻量 JSON Schema 校验器。
///
/// 这里只实现工具契约需要的子集，保持执行前校验可预测且不引入第三方
/// 运行时依赖：type、required、enum、pattern、maxLength、items、
/// additionalProperties，以及本地 `$ref`。
class SchemaValidationResult {
  const SchemaValidationResult.valid()
      : path = null,
        message = null;

  const SchemaValidationResult.invalid(this.message, {this.path});

  final String? path;
  final String? message;

  bool get isValid => message == null;

  String get error {
    final detail = message ?? '参数校验失败';
    return path == null ? detail : '$path: $detail';
  }
}

class JsonSchemaSubsetValidator {
  const JsonSchemaSubsetValidator({this.maxDepth = 32});

  final int maxDepth;

  SchemaValidationResult validate(dynamic value, Map<String, dynamic> schema) {
    return _validate(
      value,
      schema,
      root: schema,
      path: r'$',
      depth: 0,
      resolvingRefs: const {},
    );
  }

  SchemaValidationResult _validate(
    dynamic value,
    Map<String, dynamic> schema, {
    required Map<String, dynamic> root,
    required String path,
    required int depth,
    required Set<String> resolvingRefs,
  }) {
    if (depth > maxDepth) {
      return SchemaValidationResult.invalid('参数嵌套层级超过限制', path: path);
    }

    final ref = schema[r'$ref'];
    if (ref is String) {
      if (!ref.startsWith('#/')) {
        return SchemaValidationResult.invalid('仅支持本地 schema 引用', path: path);
      }
      if (resolvingRefs.contains(ref)) {
        return SchemaValidationResult.invalid('schema 引用存在循环', path: path);
      }
      final resolved = _resolveRef(root, ref);
      if (resolved == null) {
        return SchemaValidationResult.invalid('schema 引用不存在: $ref', path: path);
      }
      return _validate(
        value,
        resolved,
        root: root,
        path: path,
        depth: depth + 1,
        resolvingRefs: {...resolvingRefs, ref},
      );
    }

    final enumValues = schema['enum'];
    if (enumValues is List &&
        !enumValues.any((candidate) => _deepEquals(candidate, value))) {
      return SchemaValidationResult.invalid('值不在允许的 enum 中', path: path);
    }

    final type = schema['type'];
    if (type != null && !_matchesType(value, type)) {
      return SchemaValidationResult.invalid(
        '类型错误，期望 ${_typeDescription(type)}',
        path: path,
      );
    }

    if (value is String) {
      final minLength = _asInt(schema['minLength']);
      final maxLength = _asInt(schema['maxLength']);
      final length = value.runes.length;
      if (minLength != null && length < minLength) {
        return SchemaValidationResult.invalid('字符串长度不能小于 $minLength',
            path: path);
      }
      if (maxLength != null && length > maxLength) {
        return SchemaValidationResult.invalid('字符串长度不能超过 $maxLength',
            path: path);
      }
      final pattern = schema['pattern'];
      if (pattern is String) {
        try {
          if (!RegExp(pattern).hasMatch(value)) {
            return SchemaValidationResult.invalid('字符串不符合 pattern', path: path);
          }
        } on FormatException {
          return SchemaValidationResult.invalid('schema pattern 无效',
              path: path);
        }
      }
    }

    if (value is num) {
      final minimum = _asNum(schema['minimum']);
      final maximum = _asNum(schema['maximum']);
      if (minimum != null && value < minimum) {
        return SchemaValidationResult.invalid('数值不能小于 $minimum', path: path);
      }
      if (maximum != null && value > maximum) {
        return SchemaValidationResult.invalid('数值不能大于 $maximum', path: path);
      }
    }

    if (value is List) {
      final minItems = _asInt(schema['minItems']);
      final maxItems = _asInt(schema['maxItems']);
      if (minItems != null && value.length < minItems) {
        return SchemaValidationResult.invalid('数组元素不能少于 $minItems', path: path);
      }
      if (maxItems != null && value.length > maxItems) {
        return SchemaValidationResult.invalid('数组元素不能多于 $maxItems', path: path);
      }
      final items = schema['items'];
      if (items is Map) {
        final itemSchema = Map<String, dynamic>.from(items);
        for (var index = 0; index < value.length; index++) {
          final result = _validate(
            value[index],
            itemSchema,
            root: root,
            path: '$path[$index]',
            depth: depth + 1,
            resolvingRefs: resolvingRefs,
          );
          if (!result.isValid) return result;
        }
      }
    }

    if (value is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final name in required.whereType<String>()) {
          if (!value.containsKey(name)) {
            return SchemaValidationResult.invalid('缺少必填参数: $name', path: path);
          }
        }
      }

      final properties = schema['properties'];
      final propertySchemas = properties is Map
          ? Map<String, dynamic>.from(properties)
          : const <String, dynamic>{};
      final additional = schema['additionalProperties'];
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final childPath = '$path.$key';
        final childSchema = propertySchemas[key];
        if (childSchema is Map) {
          final result = _validate(
            entry.value,
            Map<String, dynamic>.from(childSchema),
            root: root,
            path: childPath,
            depth: depth + 1,
            resolvingRefs: resolvingRefs,
          );
          if (!result.isValid) return result;
          continue;
        }
        if (additional == false) {
          return SchemaValidationResult.invalid('不允许额外参数: $key', path: path);
        }
        if (additional is Map) {
          final result = _validate(
            entry.value,
            Map<String, dynamic>.from(additional),
            root: root,
            path: childPath,
            depth: depth + 1,
            resolvingRefs: resolvingRefs,
          );
          if (!result.isValid) return result;
        }
      }
    }

    return const SchemaValidationResult.valid();
  }

  Map<String, dynamic>? _resolveRef(
      Map<String, dynamic> root, String reference) {
    dynamic current = root;
    for (final segment in reference.substring(2).split('/')) {
      final key = segment.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is! Map || !current.containsKey(key)) return null;
      current = current[key];
    }
    return current is Map ? Map<String, dynamic>.from(current) : null;
  }

  bool _matchesType(dynamic value, dynamic type) {
    if (type is List) return type.any((item) => _matchesType(value, item));
    if (type is! String) return true;
    switch (type) {
      case 'object':
        return value is Map;
      case 'array':
        return value is List;
      case 'string':
        return value is String;
      case 'integer':
        return value is num && value.isFinite && value % 1 == 0;
      case 'number':
        return value is num && value.isFinite;
      case 'boolean':
        return value is bool;
      case 'null':
        return value == null;
      default:
        return true;
    }
  }

  String _typeDescription(dynamic type) =>
      type is List ? type.join(' | ') : '$type';

  int? _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');

  num? _asNum(dynamic value) => value is num ? value : num.tryParse('$value');

  bool _deepEquals(dynamic left, dynamic right) {
    if (left is num && right is num) return left == right;
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_deepEquals(left[i], right[i])) return false;
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_deepEquals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }
}

typedef SchemaValidator = JsonSchemaSubsetValidator;
