import '../infrastructure/database/app_database.dart';

/// Framework-owned pending decision. Run-plan and result-action scopes share
/// transport, not grants: neither can widen the other's permission boundary.
abstract interface class ApprovalDecisionScope {
  AppDatabase get db;
  String get requestId;
  Future<void> get invalidated;
  Future<bool> isCurrent();
}
