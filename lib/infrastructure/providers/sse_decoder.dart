import 'dart:convert';

/// Incrementally decodes UTF-8 bytes and emits complete SSE `data` payloads.
///
/// The network layer is allowed to split both UTF-8 code points and SSE
/// records at arbitrary boundaries. Keeping both buffers here prevents each
/// provider from having to reimplement subtly different framing logic.
class SseDecoder {
  SseDecoder() {
    _byteSink = utf8.decoder.startChunkedConversion(_TextSink(_appendText));
  }

  late final ByteConversionSink _byteSink;
  String _lineBuffer = '';
  final List<String> _dataLines = <String>[];
  List<String> _emitted = <String>[];

  /// Adds a network chunk and returns all complete event payloads found in it.
  List<String> add(List<int> bytes) {
    _emitted = <String>[];
    _byteSink.add(bytes);
    return List<String>.of(_emitted);
  }

  /// Closes the UTF-8 decoder and flushes a final unterminated SSE record.
  List<String> close() {
    _emitted = <String>[];
    _byteSink.close();
    if (_lineBuffer.isNotEmpty) {
      _consumeLine(_lineBuffer);
      _lineBuffer = '';
    }
    _emitEvent();
    return List<String>.of(_emitted);
  }

  void _appendText(String text) {
    _lineBuffer += text;
    for (;;) {
      final newline = _lineBuffer.indexOf('\n');
      if (newline < 0) return;
      var line = _lineBuffer.substring(0, newline);
      _lineBuffer = _lineBuffer.substring(newline + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      _consumeLine(line);
    }
  }

  void _consumeLine(String line) {
    if (line.isEmpty) {
      _emitEvent();
      return;
    }
    // SSE comments and event/id/retry fields are not part of the JSON payload.
    if (!line.startsWith('data:')) return;
    var data = line.substring(5);
    if (data.startsWith(' ')) data = data.substring(1);
    _dataLines.add(data);
  }

  void _emitEvent() {
    if (_dataLines.isEmpty) return;
    _emitted.add(_dataLines.join('\n'));
    _dataLines.clear();
  }
}

class _TextSink implements Sink<String> {
  _TextSink(this.onText);

  final void Function(String text) onText;

  @override
  void add(String data) => onText(data);

  @override
  void close() {}
}
