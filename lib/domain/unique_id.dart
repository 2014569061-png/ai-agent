import 'dart:math';

class UniqueId {
  UniqueId._();

  static final Random _random = Random.secure();
  static int _sequence = 0;

  static String generate(String prefix, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    final sequence = _sequence = (_sequence + 1) & 0x7fffffff;
    final random = _random.nextInt(0x7fffffff);
    return '$prefix-$timestamp-$sequence-$random';
  }
}
