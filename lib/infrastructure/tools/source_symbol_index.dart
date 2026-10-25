/// A bounded lexical index for languages without an embedded AST parser.
/// References are name candidates, never compiler-resolved bindings.
Map<String, dynamic> parseSourceSymbols(String source, String language) {
  final python = language == 'python';
  final tokens = <({String text, int line, bool identifier})>[];
  var i = 0;
  var line = 1;
  final identifierStart = RegExp(r'[A-Za-z_$\u0080-\uffff]');
  final identifierPart = RegExp(r'[A-Za-z0-9_$\u0080-\uffff]');
  while (i < source.length && tokens.length < 30000) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if ((python && c == '#') || (!python && source.startsWith('//', i))) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (!python && source.startsWith('/*', i)) {
      i += 2;
      while (i < source.length && !source.startsWith('*/', i)) {
        if (source[i++] == '\n') line++;
      }
      i = (i + 2).clamp(0, source.length);
      continue;
    }
    if (c == '"' || c == "'" || (!python && c == '`')) {
      final quote = python && source.startsWith(c * 3, i) ? c * 3 : c;
      i += quote.length;
      while (i < source.length && !source.startsWith(quote, i)) {
        if (source[i] == '\\') {
          if (i + 1 < source.length && source[i + 1] == '\n') line++;
          i = (i + 2).clamp(0, source.length);
        } else if (source[i++] == '\n') {
          line++;
        }
      }
      i = (i + quote.length).clamp(0, source.length);
      // A placeholder prevents tokens across a string joining as a declaration.
      tokens.add((text: '<literal>', line: line, identifier: false));
      continue;
    }
    // Conservative JS regex handling. Template interpolations and JSX are not
    // parsed; unsupported constructs are an explicit lexical-index limitation.
    if (!python &&
        c == '/' &&
        (tokens.isEmpty ||
            {'=', '(', '[', '{', ':', ',', 'return', '=>', '!', ';'}
                .contains(tokens.last.text))) {
      i++;
      var inClass = false;
      while (i < source.length && source[i] != '\n') {
        final next = source[i++];
        if (next == '\\') {
          i = (i + 1).clamp(0, source.length);
          continue;
        }
        if (next == '[') inClass = true;
        if (next == ']') inClass = false;
        if (next == '/' && !inClass) break;
      }
      while (i < source.length && identifierPart.hasMatch(source[i])) {
        i++;
      }
      tokens.add((text: '<literal>', line: line, identifier: false));
      continue;
    }
    if (identifierStart.hasMatch(c)) {
      final start = i++;
      while (i < source.length && identifierPart.hasMatch(source[i])) {
        i++;
      }
      tokens.add(
          (text: source.substring(start, i), line: line, identifier: true));
    } else {
      final text = source.startsWith('=>', i) ? '=>' : c;
      tokens.add((text: text, line: line, identifier: false));
      i += text.length;
    }
  }
  final declarations = <Map<String, dynamic>>[];
  final declared = <int>{};
  final keywords = python
      ? {'def': 'function', 'class': 'class'}
      : {
          'function': 'function',
          'class': 'class',
          'interface': 'interface',
          'type': 'type',
          'enum': 'enum',
          'const': 'variable',
          'let': 'variable',
          'var': 'variable',
        };
  for (var n = 0; n + 1 < tokens.length; n++) {
    final kind = keywords[tokens[n].text];
    if (kind == null || (n > 0 && tokens[n - 1].text == '.')) continue;
    var nameIndex = n + 1;
    if (tokens[n].text == 'function' && tokens[nameIndex].text == '*') {
      nameIndex++;
    }
    if (nameIndex >= tokens.length || !tokens[nameIndex].identifier) continue;
    declared.add(nameIndex);
    declarations.add({
      'name': tokens[nameIndex].text,
      'kind': kind,
      'line': tokens[nameIndex].line,
      'endLine': tokens[nameIndex].line,
      'precision': 'lexical'
    });
    if (declarations.length >= 1000) break;
  }
  const excluded = {
    'if',
    'for',
    'while',
    'switch',
    'catch',
    'with',
    'return',
    'typeof',
    'sizeof',
    'super',
    'import',
    'print',
    'assert',
    'match'
  };
  final references = <Map<String, dynamic>>[];
  for (var n = 0; n + 1 < tokens.length; n++) {
    if (tokens[n].identifier &&
        !declared.contains(n) &&
        tokens[n + 1].text == '(' &&
        !excluded.contains(tokens[n].text)) {
      references.add({'name': tokens[n].text, 'line': tokens[n].line});
      if (references.length >= 2000) break;
    }
  }
  return {
    'symbols': declarations,
    'references': references,
    'parseErrors': null,
    'precision': 'lexical',
    'truncated': i < source.length ||
        declarations.length >= 1000 ||
        references.length >= 2000
  };
}

/// Connect call-name occurrences to matching declarations within a language
/// family. Multiple targets remain ambiguous and are never silently resolved.
List<Map<String, dynamic>> buildReferenceCandidates(
    List<Map<String, dynamic>> symbols, List<Map<String, dynamic>> references) {
  String key(Map<String, dynamic> item) =>
      '${item['language'] == 'typescript' ? 'javascript' : item['language']}:${item['name']}';
  final byName = <String, List<Map<String, dynamic>>>{};
  for (final symbol in symbols) {
    (byName[key(symbol)] ??= []).add(symbol);
  }
  final edges = <Map<String, dynamic>>[];
  for (final reference in references) {
    final targets = byName[key(reference)] ?? const [];
    if (targets.isEmpty) continue;
    edges.add({
      ...reference,
      'resolution': 'name_candidate',
      'ambiguous': targets.length > 1,
      'targets': [
        for (final target in targets.take(10))
          {
            'path': target['path'],
            'line': target['line'],
            'kind': target['kind']
          }
      ],
      'targetsTruncated': targets.length > 10
    });
    for (final target in targets) {
      target['candidateReferences'] =
          (target['candidateReferences'] as int? ?? 0) + 1;
    }
    if (edges.length >= 1000) break;
  }
  return edges;
}
