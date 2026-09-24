import 'package:flutter/services.dart';

import '../../domain/tool_codes.dart';
import '../../domain/tool_result.dart';

/// 备份与恢复的原生通道（`nexus/device_backup`）。
class AndroidBackupBridge {
  const AndroidBackupBridge();

  static const MethodChannel _channel = MethodChannel('nexus/device_backup');

  Future<Map<String, dynamic>> _map(String method,
          [Map<String, dynamic>? arguments]) async =>
      await _channel.invokeMapMethod<String, dynamic>(method, arguments) ??
      const {};

  Future<Map<String, dynamic>> listBackups() => _map('listBackups');

  Future<Map<String, dynamic>> inspectBackup(String backupId) =>
      _map('inspectBackup', {'backupId': backupId});

  Future<Map<String, dynamic>> personalDataPermission(String category) =>
      _map('personalDataPermission', {'category': category});

  Future<Map<String, dynamic>> exportPersonalData(String category) =>
      _map('exportPersonalData', {'category': category});

  Future<Map<String, dynamic>> backupAppData(
          String packageName, String scope) =>
      _map('backupAppData', {'packageName': packageName, 'scope': scope});

  Future<Map<String, dynamic>> backupDirectory(String path) =>
      _map('backupDirectory', {'path': path});

  Future<Map<String, dynamic>> restoreAppData(String backupId) =>
      _map('restoreAppData', {'backupId': backupId});

  Future<Map<String, dynamic>> importContacts(String backupId) =>
      _map('importContacts', {'backupId': backupId});

  Future<Map<String, dynamic>> deleteBackup(String backupId) =>
      _map('deleteBackup', {'backupId': backupId});
}

/// android_device 工具中的备份/恢复动作。
///
/// 独立成文件以免 android_device_tool.dart 继续膨胀；AndroidDeviceTool 只负责
/// 把这些 action 接入既有的“预览 → 审批 → 一次性票据 → 执行”流程。
const androidBackupReadActions = <String>{'backup_list', 'backup_inspect'};

const androidBackupMutatingActions = <String>{
  'backup_personal_data',
  'backup_app_data',
  'backup_directory',
  'restore_app_data',
  'restore_contacts',
  'backup_delete',
};

const androidBackupRootActions = <String>{
  'backup_app_data',
  'backup_directory',
  'restore_app_data',
};

/// 不可撤销的备份动作。恢复应用数据会先生成“恢复前快照”，因此不在此列。
const androidBackupIrreversibleActions = <String>{'backup_delete'};

const androidBackupActions = <String>{
  ...androidBackupReadActions,
  ...androidBackupMutatingActions,
};

const _personalCategories = {'contacts', 'sms', 'call_log'};
const _appDataScopes = {'config', 'full', 'apk'};
final _backupIdPattern =
    RegExp(r'^(personal|app|prerestore|dir|apk)-\d{8}-\d{6}-[a-z0-9]{4}$');
final _packagePattern = RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$');

/// 预览时读取的归档检查结果缓存（按 backupId），供同步的审批详情复用。
final Map<String, _CachedInspection> _inspectionCache = {};

class _CachedInspection {
  _CachedInspection(this.data) : loadedAt = DateTime.now();
  final Map<String, dynamic> data;
  final DateTime loadedAt;
  bool get fresh =>
      DateTime.now().difference(loadedAt) < const Duration(minutes: 5);
}

abstract final class AndroidBackupActions {
  static bool handles(Object? action) => androidBackupActions.contains(action);

  static String _categoryLabel(Object? category) => switch (category) {
        'contacts' => '联系人',
        'sms' => '短信',
        'call_log' => '通话记录',
        _ => '$category',
      };

  static bool _validBackupId(Object? value) =>
      value is String && _backupIdPattern.hasMatch(value.trim());

  static bool _validDirectory(Object? value) {
    if (value is! String) return false;
    final path = value.trim().replaceAll(RegExp(r'/+'), '/');
    if (!path.startsWith('/') ||
        path.contains('\u0000') ||
        path.split('/').any((part) => part == '..' || part == '.')) {
      return false;
    }
    final normalized =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return const ['/sdcard', '/storage/emulated/0', '/data/local/tmp']
        .any((root) => normalized.startsWith('$root/'));
  }

  static String? validate(Object? action, Map<String, dynamic> arguments) {
    switch (action) {
      case 'backup_list':
        return null;
      case 'backup_inspect':
      case 'restore_app_data':
      case 'restore_contacts':
      case 'backup_delete':
        return _validBackupId(arguments['backupId'])
            ? null
            : '需要 backup_list 返回的有效 backupId';
      case 'backup_personal_data':
        return _personalCategories.contains(arguments['category'])
            ? null
            : 'category 仅支持 contacts、sms、call_log';
      case 'backup_app_data':
        final packageName = arguments['packageName'];
        final scope = arguments['scope'] ?? 'config';
        if (packageName is! String ||
            !_packagePattern.hasMatch(packageName.trim())) {
          return '需要有效的 Android packageName';
        }
        return _appDataScopes.contains(scope)
            ? null
            : 'scope 仅支持 config（配置包）、full（完整数据）或 apk（仅安装包，无需 Root）';
      case 'backup_directory':
        return _validDirectory(arguments['path'])
            ? null
            : '目录必须位于 /sdcard、/storage/emulated/0 或 /data/local/tmp 之下，且不能是存储根目录';
    }
    return '不支持的备份动作';
  }

  /// 恢复/删除前读取归档实际内容，供预览展示文件列表、大小和覆盖范围。
  static Future<void> loadInspection(
    AndroidBackupBridge bridge,
    Object? action,
    Map<String, dynamic> arguments,
  ) async {
    if (action != 'restore_app_data' &&
        action != 'restore_contacts' &&
        action != 'backup_delete') {
      return;
    }
    final backupId = (arguments['backupId'] as String).trim();
    try {
      _inspectionCache[backupId] =
          _CachedInspection(await bridge.inspectBackup(backupId));
    } on PlatformException catch (error) {
      _inspectionCache[backupId] = _CachedInspection({
        'inspectionError': error.message ?? error.code,
        'inspectionErrorCode': error.code,
      });
    } on MissingPluginException {
      _inspectionCache.remove(backupId);
    }
    _inspectionCache.removeWhere((_, value) => !value.fresh);
  }

  static Map<String, dynamic>? _inspection(Map<String, dynamic> arguments) {
    final backupId = arguments['backupId'];
    if (backupId is! String) return null;
    final cached = _inspectionCache[backupId.trim()];
    return cached != null && cached.fresh ? cached.data : null;
  }

  static String _formatBytes(Object? value) {
    final bytes = value is num ? value.toDouble() : 0.0;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${bytes.toInt()} B';
  }

  static Map<String, dynamic> previewFor(
    String action,
    Map<String, dynamic> arguments, {
    required String riskClass,
  }) {
    final inspection = _inspection(arguments);
    final packageName = arguments['packageName']?.toString().trim();
    final scope = arguments['scope'] ?? 'config';
    final backupId = arguments['backupId']?.toString().trim();
    if ((action == 'backup_app_data' && scope == 'apk') ||
        (action == 'restore_app_data' &&
            (inspection?['kind'] == 'apk' ||
                (backupId?.startsWith('apk-') ?? false)))) {
      return _apkPreview(action, arguments, inspection, riskClass);
    }
    final target = switch (action) {
      'backup_personal_data' =>
        '导出${_categoryLabel(arguments['category'])}到应用备份目录',
      'backup_app_data' =>
        '应用 $packageName 的${scope == 'full' ? '完整数据' : '配置包（shared_prefs、databases）'}',
      'backup_directory' => '目录 ${arguments['path']}',
      'restore_app_data' =>
        '备份 $backupId → 应用 ${inspection?['packageName'] ?? '（读取清单后确定）'}',
      'restore_contacts' => '备份 $backupId 中的联系人 vCard',
      'backup_delete' => '备份 $backupId',
      _ => action,
    };
    final impact = switch (action) {
      'backup_personal_data' => arguments['category'] == 'contacts'
          ? '读取全部联系人并写入本应用外部文件目录；需要 READ_CONTACTS 运行时权限'
          : '读取全部${_categoryLabel(arguments['category'])}并写入本应用外部文件目录；只导出，不支持写回',
      'backup_app_data' =>
        '通过 Root 以只读方式打包 /data/user/0/$packageName 的数据，流式写入本应用备份目录；应用运行中打包的数据库可能不一致',
      'backup_directory' => '通过 Root 以只读方式打包该目录，不修改源文件',
      'restore_app_data' =>
        '先对当前数据做恢复前快照，再停止应用、删除并替换下列目录，最后修正属主与 SELinux 标签；目标应用会被强制停止',
      'restore_contacts' => '把 vCard 交给系统通讯录；是否导入以及导入到哪个账户由用户在系统界面确认，可能产生重复联系人',
      'backup_delete' => '永久删除该备份目录及其中所有文件',
      _ => '备份操作',
    };
    final scopeText = switch (action) {
      'backup_personal_data' => '只读取所选类别，最多 50,000 条',
      'backup_app_data' => scope == 'full'
          ? '应用私有目录下除 cache、code_cache、lib 以外的全部内容；归档上限 2 GiB'
          : '只包含 shared_prefs 与 databases；归档上限 2 GiB',
      'backup_directory' => '只打包所列目录；不跟随源目录本身的符号链接；归档上限 2 GiB',
      'restore_app_data' =>
        (inspection?['restoreCoverage'] as List?)?.join('、') ?? '以归档清单中的顶层目录为准',
      'restore_contacts' => '只把该备份中的 contacts.vcf 交给系统通讯录',
      'backup_delete' => '只删除应用备份目录下的这一个备份',
      _ => '仅针对预览中列出的目标',
    };
    final command = switch (action) {
      'backup_app_data' =>
        'su -c "cd /data/user/0/$packageName && tar -czf - -- ${scope == 'full' ? '<除 cache/code_cache/lib 外的顶层目录>' : 'shared_prefs databases'}" > backups/<id>/data.tar.gz',
      'backup_directory' =>
        'su -c "cd <父目录> && tar -czf - -- <目录名>" > backups/<id>/data.tar.gz',
      'restore_app_data' =>
        'su -c "am force-stop <pkg>; rm -rf <覆盖目录>; tar -xzf - -C /data/user/0/<pkg>; chown -R <原属主>; restorecon -R" < backups/$backupId/data.tar.gz',
      _ => null,
    };
    final executionPlan = switch (action) {
      'backup_personal_data' =>
        'Android ContentResolver 只读查询；缺少权限时由系统弹出一次运行时权限请求，拒绝则不导出任何数据。',
      'backup_app_data' =>
        'Root 模板脚本先用 readlink 校验 /data/user/0/<pkg> 未被符号链接重定向，再把 tar 数据写到 stdout，由应用写入自身目录并记录 SHA-256；超时 180 秒。',
      'backup_directory' => 'Root 模板脚本校验目录存在且不是符号链接后流式打包；超时 180 秒。',
      'restore_app_data' =>
        '校验清单 SHA-256、拒绝含绝对路径或 .. 的归档、拒绝降级恢复；生成恢复前快照；随后执行 Root 模板脚本并通过 stdin 输入归档；超时 180 秒。',
      'restore_contacts' =>
        '把 vCard 暂存到应用私有目录，通过 FileProvider 以只读 URI 交给系统通讯录。',
      'backup_delete' => '在应用备份目录内递归删除该备份，不需要 Root。',
      _ => null,
    };
    final rollback = switch (action) {
      'backup_personal_data' ||
      'backup_app_data' ||
      'backup_directory' =>
        '只新增备份文件；不需要时用 backup_delete 删除即可',
      'restore_app_data' =>
        '执行前自动生成恢复前快照（结果中的 undoBackupId）；对该快照再次执行 restore_app_data 即可撤销',
      'restore_contacts' => '导入由系统通讯录完成；如需撤销，需要在通讯录中手动删除导入的联系人',
      _ => null,
    };
    final entries = inspection?['entries'];
    final preview = <String, dynamic>{
      'preview': true,
      'action': action,
      'arguments': Map<String, dynamic>.from(arguments)..remove('preview'),
      'target': target,
      'scope': scopeText,
      'impact': impact,
      'riskClass': riskClass,
      'command': command,
      'executionPlan': executionPlan,
      'reversible': !androidBackupIrreversibleActions.contains(action),
      'rollback': rollback,
      'requiresConfirmation': true,
      'mustWaitForUser': true,
      if (inspection != null) ...{
        if (inspection['inspectionError'] != null)
          'inspectionError': inspection['inspectionError'],
        if (entries is List) 'files': entries.take(20).toList(),
        if (inspection['entryCount'] != null)
          'fileCount': inspection['entryCount'],
        if (inspection['remainingEntries'] != null)
          'remainingFiles': inspection['remainingEntries'],
        if (inspection['uncompressedBytes'] != null)
          'totalSize': _formatBytes(inspection['uncompressedBytes']),
        if (inspection['totalBytes'] != null)
          'archiveSize': _formatBytes(inspection['totalBytes']),
        if (inspection['restoreCoverage'] != null)
          'overwriteScope': inspection['restoreCoverage'],
        if (inspection['restoreCompatibility'] != null)
          'compatibility': inspection['restoreCompatibility'],
        if (inspection['versionName'] != null ||
            inspection['versionCode'] != null)
          'backupVersion':
              '${inspection['versionName'] ?? ''}(${inspection['versionCode'] ?? '?'})',
        if (inspection['installedVersionCode'] != null)
          'installedVersion':
              '${inspection['installedVersionName'] ?? ''}(${inspection['installedVersionCode']})',
        if (inspection['unsafeEntries'] is List &&
            (inspection['unsafeEntries'] as List).isNotEmpty)
          'unsafeEntries': inspection['unsafeEntries'],
      },
    };
    preview.removeWhere((key, value) => value == null);
    return preview;
  }

  /// 安装包备份/恢复预览：不需要 Root，恢复交给系统安装器由用户确认。
  static Map<String, dynamic> _apkPreview(
    String action,
    Map<String, dynamic> arguments,
    Map<String, dynamic>? inspection,
    String riskClass,
  ) {
    final backup = action == 'backup_app_data';
    final packageName = backup
        ? arguments['packageName']?.toString().trim()
        : inspection?['packageName'] ?? '（读取清单后确定）';
    final entries = inspection?['entries'];
    final preview = <String, dynamic>{
      'preview': true,
      'action': action,
      'arguments': Map<String, dynamic>.from(arguments)..remove('preview'),
      'target': backup
          ? '应用 $packageName 的安装包（base + 拆分 APK）'
          : '备份 ${arguments['backupId']} → 通过系统安装器安装 $packageName',
      'scope': backup
          ? '只复制 APK 文件；不含应用数据、账号、缓存和 OBB'
          : '安装归档中的 ${inspection?['apkCount'] ?? inspection?['entryCount'] ?? '全部'} 个 APK；不恢复任何应用数据',
      'impact': backup
          ? '通过 PackageManager 读取已安装应用的 APK 路径并复制到本应用备份目录，记录 SHA-256 与签名摘要；不需要 Root'
          : '创建 PackageInstaller 会话写入 APK，随后系统弹出安装确认，是否安装由你决定；签名与已安装版本不一致会被拒绝',
      'riskClass': riskClass,
      'executionPlan': backup
          ? 'ApplicationInfo.sourceDir + splitSourceDirs 逐个复制，写入 manifest.json（版本、签名 SHA-256、每个文件的 SHA-256）。'
          : '校验每个 APK 的 SHA-256 与签名兼容性 → PackageInstaller.createSession → 写入全部 APK → commit；结果由系统安装确认界面和 ApkInstallResultReceiver 回报。',
      'executedVia': backup ? 'app' : 'package_installer',
      'reversible': true,
      'rollback': backup
          ? '只新增备份文件；不需要时用 backup_delete 删除即可'
          : '新装的应用可直接卸载；覆盖安装后若要回到原版本，需要有该版本的安装包备份',
      'requiresConfirmation': true,
      'mustWaitForUser': true,
      if (inspection != null) ...{
        if (inspection['inspectionError'] != null)
          'inspectionError': inspection['inspectionError'],
        if (entries is List) 'files': entries.take(20).toList(),
        if (inspection['entryCount'] != null)
          'fileCount': inspection['entryCount'],
        if (inspection['totalBytes'] != null)
          'totalSize': _formatBytes(inspection['totalBytes']),
        if (inspection['restoreCompatibility'] != null)
          'compatibility': inspection['restoreCompatibility'],
        if (inspection['signatureMatches'] != null)
          'signatureMatches': inspection['signatureMatches'],
        if (inspection['installPermissionGranted'] == false)
          'installPermissionHint': '尚未允许 NEXUS 安装应用；执行时系统会先要求你开启“安装未知应用”',
        if (inspection['versionName'] != null ||
            inspection['versionCode'] != null)
          'backupVersion':
              '${inspection['versionName'] ?? ''}(${inspection['versionCode'] ?? '?'})',
        if (inspection['installedVersionCode'] != null)
          'installedVersion':
              '${inspection['installedVersionName'] ?? ''}(${inspection['installedVersionCode']})',
        if (inspection['lastInstallResult'] != null)
          'lastInstallResult': inspection['lastInstallResult'],
      },
    };
    preview.removeWhere((key, value) => value == null);
    return preview;
  }

  static Future<ToolResult> execute(
    AndroidBackupBridge bridge,
    String action,
    Map<String, dynamic> arguments,
  ) async {
    final validationError = validate(action, arguments);
    if (validationError != null) {
      return ToolResult.failure(
        code: ToolCodes.invalidArguments,
        message: validationError,
      );
    }
    final backupId = arguments['backupId']?.toString().trim();
    switch (action) {
      case 'backup_list':
        final data = await bridge.listBackups();
        final backups = (data['backups'] as List?) ?? const [];
        return ToolResult.success(
          message: '共有 ${data['total'] ?? backups.length} 个备份',
          data: data,
        );
      case 'backup_inspect':
        return ToolResult.success(
          message: '已读取备份清单与归档内容',
          data: await bridge.inspectBackup(backupId!),
        );
      case 'backup_personal_data':
        final category = arguments['category'] as String;
        final data = await bridge.exportPersonalData(category);
        return ToolResult.success(
          message: '已导出 ${data['itemCount'] ?? 0} 条${_categoryLabel(category)}'
              '${category == 'contacts' ? '' : '（只导出，不支持写回）'}',
          data: data,
          effect: ToolEffect.applied,
        );
      case 'backup_app_data':
        final data = await bridge.backupAppData(
          (arguments['packageName'] as String).trim(),
          (arguments['scope'] as String?) ?? 'config',
        );
        return ToolResult.success(
          message: arguments['scope'] == 'apk'
              ? '已备份安装包 ${data['backupId']}（${data['apkCount'] ?? data['entryCount'] ?? '?'} 个 APK，${_formatBytes(data['totalBytes'])}）'
              : '已创建应用数据备份 ${data['backupId']}（${_formatBytes(data['totalBytes'])}）',
          data: data,
          effect: ToolEffect.applied,
        );
      case 'backup_directory':
        final data =
            await bridge.backupDirectory((arguments['path'] as String).trim());
        return ToolResult.success(
          message:
              '已导出目录备份 ${data['backupId']}（${_formatBytes(data['totalBytes'])}'
              '${data['executedVia'] == null ? '' : '，通道：${data['executedVia']}'}）',
          data: data,
          effect: ToolEffect.applied,
        );
      case 'restore_app_data':
        try {
          final data = await bridge.restoreAppData(backupId!);
          if (data['installRequested'] == true) {
            // 安装包恢复：会话已提交，是否安装由用户在系统界面决定。
            return ToolResult.success(
              message:
                  '已提交 ${data['packageName']} 的安装会话（${data['apkCount'] ?? '?'} 个 APK），请在系统安装界面确认；'
                  '结果可稍后用 backup_inspect 查看 lastInstallResult',
              data: data,
              effect: ToolEffect.unknown,
            );
          }
          return ToolResult.success(
            message:
                '已恢复 ${data['packageName']} 的数据；撤销快照 ${data['undoBackupId']}',
            data: data,
            effect: ToolEffect.applied,
          );
        } on PlatformException catch (error) {
          // 校验阶段的拒绝不会动数据；脚本阶段失败时数据可能已部分替换。
          final beforeChange = const {
            'NOT_FOUND',
            'INVALID_ARGS',
            'UNSUPPORTED_OPERATION',
            'RESTORE_BLOCKED',
            'CORRUPT_ARCHIVE',
            'UNSAFE_ARCHIVE',
            'EMPTY_ARCHIVE',
            'INSUFFICIENT_STORAGE',
            'ROOT_UNAVAILABLE',
            'ROOT_REQUIRED',
            'PRIVILEGE_REQUIRED',
            'PRIVILEGE_UNAVAILABLE',
            'PERMISSION_REQUIRED',
          }.contains(error.code);
          return ToolResult.failure(
            code: _codeFor(error.code),
            message: error.message ?? '恢复失败 (${error.code})',
            data: {'nativeCode': error.code},
            effect: beforeChange ? ToolEffect.none : ToolEffect.unknown,
          );
        }
      case 'restore_contacts':
        return ToolResult.success(
          message: '已打开系统通讯录导入界面；导入与否由你在系统界面确认',
          data: await bridge.importContacts(backupId!),
          effect: ToolEffect.applied,
        );
      case 'backup_delete':
        final data = await bridge.deleteBackup(backupId!);
        _inspectionCache.remove(backupId);
        return ToolResult.success(
          message: '已删除备份 $backupId，释放 ${_formatBytes(data['freedBytes'])}',
          data: data,
          effect: ToolEffect.applied,
        );
    }
    return ToolResult.failure(
      code: ToolCodes.invalidArguments,
      message: '不支持的备份动作: $action',
    );
  }

  /// 原生错误码 → 工具结果码；Root/SELinux/权限问题必须如实返回，不假装成功。
  static String _codeFor(String nativeCode) => switch (nativeCode) {
        'NOT_FOUND' => ToolCodes.notFound,
        'INVALID_ARGS' => ToolCodes.invalidArguments,
        'PERMISSION_DENIED' || 'SELINUX_DENIED' => ToolCodes.permissionRequired,
        'ROOT_UNAVAILABLE' ||
        'ROOT_DENIED' ||
        'ROOT_REQUIRED' ||
        'PRIVILEGE_REQUIRED' ||
        'PRIVILEGE_UNAVAILABLE' =>
          ToolCodes.rootRequired,
        'PERMISSION_REQUIRED' ||
        'STORAGE_PERMISSION_REQUIRED' =>
          ToolCodes.permissionRequired,
        'UNAVAILABLE' => ToolCodes.capabilityUnavailable,
        'TIMEOUT' => ToolCodes.timeout,
        'INSUFFICIENT_STORAGE' => ToolCodes.tooLarge,
        'CORRUPT_ARCHIVE' || 'UNSAFE_ARCHIVE' => ToolCodes.invalidFormat,
        'UNSUPPORTED_OPERATION' => ToolCodes.capabilityUnavailable,
        _ => ToolCodes.toolError,
      };

  static String codeForPlatformError(String nativeCode) => _codeFor(nativeCode);
}
