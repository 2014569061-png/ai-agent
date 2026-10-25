// Compare token lexemes and non-whitespace gaps, retaining string literals and
// comments exactly. Only formatting outside tokens/comments may differ.
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';

List<String> canonical(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) throw const FormatException('invalid_source');
  final result = <String>[];
  var token = parsed.unit.beginToken;
  var end = 0;
  while (true) {
    result.add(source.substring(end, token.offset).trim());
    result.add('${token.type}:${token.lexeme}');
    end = token.end;
    if (token.isEof) break;
    token = token.next!;
  }
  result.add(source.substring(end).trim());
  return result;
}

void main(List<String> args) {
  try {
    final pairs = jsonDecode(File(args.single).readAsStringSync()) as Map;
    final result = <String, bool>{};
    for (final entry in pairs.entries) {
      final pair = entry.value as Map;
      result[entry.key as String] = jsonEncode(canonical(pair['live'] as String)) ==
          jsonEncode(canonical(pair['disk'] as String));
    }
    stdout.write(jsonEncode(result));
  } catch (_) {
    stderr.writeln('Source token verification failed');
    exitCode = 1;
  }
}
