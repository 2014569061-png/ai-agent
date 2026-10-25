/// A PID alone is unsafe: operating systems reuse it after process termination.
class RuntimeProcessIdentity {
  const RuntimeProcessIdentity(this.platform, this.pid, this.birth);
  final String platform;
  final int pid;
  final String birth;
  Map<String, Object> toJson() =>
      {'platform': platform, 'pid': pid, 'birth': birth};
  static RuntimeProcessIdentity? fromJson(Object? value) {
    if (value is! Map ||
        value['platform'] is! String ||
        value['pid'] is! int ||
        value['birth'] is! String) {
      return null;
    }
    final id = RuntimeProcessIdentity(value['platform'] as String,
        value['pid'] as int, value['birth'] as String);
    return id.pid > 0 && id.birth.isNotEmpty ? id : null;
  }
}

abstract interface class RuntimeProcessProbe {
  RuntimeProcessIdentity? get current;

  /// true = same process is alive, false = positively gone/replaced,
  /// null = unsupported, inaccessible or otherwise unknown. Never guess dead.
  bool? isAlive(RuntimeProcessIdentity identity);
}
