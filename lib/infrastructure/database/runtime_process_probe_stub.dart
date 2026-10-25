import 'runtime_process_identity.dart';

const RuntimeProcessProbe defaultRuntimeProcessProbe = _UnknownProcessProbe();

class _UnknownProcessProbe implements RuntimeProcessProbe {
  const _UnknownProcessProbe();
  @override
  RuntimeProcessIdentity? get current => null;
  @override
  bool? isAlive(RuntimeProcessIdentity identity) => null;
}
