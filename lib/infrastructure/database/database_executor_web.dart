import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/wasm.dart';

/// Web 端数据库：WasmDatabase（sqlite3 编译为 WebAssembly，持久化到
/// IndexedDB / OPFS），替代已废弃的 `package:drift/web.dart`。
///
/// 依赖 `web/sqlite3.wasm` 与 `web/drift_worker.js`（来自 drift 官方
/// GitHub Release 对应版本，见 pubspec.lock 中 drift 版本）。
Future<QueryExecutor> createDatabaseExecutor() async {
  final result = await WasmDatabase.open(
    databaseName: 'mobile_agent',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}
