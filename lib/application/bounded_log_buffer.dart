/// Bounded display tail. Full output remains in the managed job log store.
class BoundedLogBuffer {
  BoundedLogBuffer({this.maxCharacters = 256 * 1024, this.maxLines = 3000});
  final int maxCharacters, maxLines;
  String _text = '';
  List<String> _lines = const [];
  int droppedCharacters = 0;
  String get text => _text;
  List<String> get lines => _lines;
  void clear() {
    _text = '';
    _lines = const [];
    droppedCharacters = 0;
  }

  void append(String value) {
    if (value.length > maxCharacters) {
      droppedCharacters += value.length - maxCharacters;
      value = value.substring(value.length - maxCharacters);
    }
    _text += value;
    if (_text.length > maxCharacters) {
      final start = _text.length - maxCharacters;
      droppedCharacters += start;
      _text = _text.substring(start);
    }
    var lines = _text.split('\n');
    if (lines.length > maxLines) {
      final kept = lines.sublist(lines.length - maxLines).join('\n');
      droppedCharacters += _text.length - kept.length;
      _text = kept;
      lines = _text.split('\n');
    }
    _lines = lines;
  }
}
