import 'runtime_process_identity.dart';
import 'runtime_process_probe_stub.dart'
    if (dart.library.io) 'runtime_process_probe_io.dart' as platform;
export 'runtime_process_identity.dart';

RuntimeProcessProbe get runtimeProcessProbe =>
    platform.defaultRuntimeProcessProbe;
