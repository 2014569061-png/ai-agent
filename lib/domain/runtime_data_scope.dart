import 'dart:async';

/// A run keeps its original epoch even in detached timers and late callbacks.
/// Revoking it is permanent; clearing maintenance never revives old callbacks.
class RuntimeDataScope {
  RuntimeDataScope.run(this.epoch) : maintenanceOwner = null;
  RuntimeDataScope.maintenance(this.epoch, this.maintenanceOwner);

  final int epoch;
  final String? maintenanceOwner;
  bool revoked = false;
  static final _scopeKey = Object();
  static final _controlKey = Object();
  static RuntimeDataScope? get current =>
      Zone.current[_scopeKey] as RuntimeDataScope?;
  static bool get isControl => Zone.current[_controlKey] == true;

  Future<T> enter<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_scopeKey: this, _controlKey: false});

  /// Only metadata/schema plumbing uses this; never wrap business callbacks.
  static Future<T> control<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_controlKey: true});
}

class RuntimeDataRevoked implements Exception {
  const RuntimeDataRevoked([this.message = '数据正在维护或运行代次已失效，请稍后重试']);
  final String message;
  @override
  String toString() => message;
}
