// test/parser_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatConfig.parse (String)', () {
    test('returns empty document for empty or whitespace-only input', () {
      // Test completely empty string
      final doc1 = FlatConfig.parse('');
      expect(doc1, FlatDocument.empty());
      expect(doc1.keys, isEmpty);

      // Test whitespace-only string
      final doc2 = FlatConfig.parse('   \t\n  ');
      expect(doc2, FlatDocument.empty());
      expect(doc2.keys, isEmpty);

      // Test string with only newlines
      final doc3 = FlatConfig.parse('\n\n\r\n');
      expect(doc3, FlatDocument.empty());
      expect(doc3.keys, isEmpty);
    });

    test('parses duplicates, comments and empty values', () {
      const src = '''
# comment
background = 282c34
keybind = ctrl+z=close_surface
keybind = ctrl+d=new_split:right
font-family =
''';

      final doc = FlatConfig.parse(src);

      expect(doc['background'], '282c34');
      expect(
        doc.valuesOf('keybind'),
        ['ctrl+z=close_surface', 'ctrl+d=new_split:right'],
      );
      expect(doc['font-family'], isNull);
    });

    test('ignores lines without "="', () {
      const src = '''
# comment
justakey
another key
k = v
''';
      final doc = FlatConfig.parse(src);
      expect(doc.toMap(), containsPair('k', 'v'));
      expect(doc.keys.toList(), ['k']); // only valid line counted
    });

    test('trims whitespace around key and value', () {
      const src = '  key   =   value   ';
      final doc = FlatConfig.parse(src);
      expect(doc['key'], 'value');
    });

    test('handles CRLF (Windows) newlines', () {
      const src = 'a = 1\r\nb = 2\r\n';
      final doc = FlatConfig.parse(src);
      expect(doc['a'], '1');
      expect(doc['b'], '2');
    });

    test('indented comments are treated as comments after trim', () {
      const src = '   # comment\nx = 1';
      final doc = FlatConfig.parse(src);
      expect(doc['x'], '1');
      expect(doc.keys.length, 1);
    });

    test('empty value becomes null (reset)', () {
      const src = 'feature =';
      final doc = FlatConfig.parse(src);
      expect(doc['feature'], isNull);
      expect(doc.valuesOf('feature'), [null]);
    });

    test(
        'duplicate keys preserve insertion order; indexer returns last '
        'value', () {
      const src = '''
mode = a
mode = b
mode = c
''';
      final doc = FlatConfig.parse(src);
      expect(doc.valuesOf('mode'), ['a', 'b', 'c']);
      expect(doc['mode'], 'c');
      expect(doc.keys.toList(), ['mode']);
    });

    test('value may contain "=" characters', () {
      const src = 'bind = ctrl+z=close_surface';
      final doc = FlatConfig.parse(src);
      expect(doc['bind'], 'ctrl+z=close_surface');
    });

    test('unicode is preserved', () {
      const src = 'greeting = Hey ya! 👋';
      final doc = FlatConfig.parse(src);
      expect(doc['greeting'], 'Hey ya! 👋');
    });

    test('quoted string handling', () {
      const src = 'k1 = "   foo   "\n'
          'k2 = ""\n'
          'k3 =   foo   \n'
          'k4 =';

      final doc = FlatConfig.parse(src);

      expect(doc['k1'], '   foo   '); // spaces preserved inside quotes
      expect(doc['k2'], ''); // empty quoted string -> empty string
      expect(doc['k3'], 'foo'); // unquoted -> trimmed
      expect(doc['k4'], isNull); // empty -> null
    });

    test('quoted value may contain "=" characters', () {
      const src = 'k = "left=close_surface"';
      final doc = FlatConfig.parse(src);
      expect(doc['k'], 'left=close_surface');
    });

    test('encode -> parse roundtrip (comments are lost)', () {
      const src = 'x = 1\n# c\ny = \n';
      final doc = FlatConfig.parse(src);
      final out = doc.encode();
      final doc2 = FlatConfig.parse(out);

      expect(doc2['x'], '1');
      expect(doc2['y'], isNull);
      expect(out.contains('# c'), isFalse); // comments are not preserved
    });

    test('strict mode throws on invalid line', () {
      const src = 'justakey\nk = v';
      expect(
        () => FlatConfig.parse(
          src,
          options: const FlatParseOptions().copyWith(strict: true),
        ),
        throwsFormatException,
      );
    });

    test('onMissingEquals is called for ignored lines', () {
      const src = 'justakey\nk = v';
      var called = false;
      FlatConfig.parse(
        src,
        options: FlatParseOptions(onMissingEquals: (_, __) => called = true),
      );
      expect(called, isTrue);
    });

    test('does not support inline comments', () {
      const src = 'k = v # this is not an inline comment';
      final doc = FlatConfig.parse(src);
      expect(doc['k'], 'v # this is not an inline comment');
    });

    test('ignores empty key and trims value', () {
      const src = '   = value  ';
      final doc = FlatConfig.parse(src);
      expect(doc.keys, isEmpty);
      expect(doc.toMap(), isEmpty);
    });

    test('whitespace-only lines are ignored', () {
      const src = '   \n\t\nkey = v\n';
      final doc = FlatConfig.parse(src);
      expect(doc.toMap(), containsPair('key', 'v'));
      expect(doc.keys.length, 1);
    });

    test('no spaces around "=" and trailing spaces imply null', () {
      const src = 'a=1\nb=\nc=   \n';
      final doc = FlatConfig.parse(src);
      expect(doc['a'], '1');
      expect(doc['b'], isNull);
      expect(doc['c'], isNull);
      expect(doc.keys.toList(), ['a', 'b', 'c']);
    });

    test('callback provides accurate line and content', () {
      const src = '  # comment\ninvalidline\nk = v\n  noeq   \n';
      final calls = <Map<String, Object>>[];
      FlatConfig.parse(
        src,
        options: FlatParseOptions(onMissingEquals: (n, l) {
          calls.add({'n': n, 'l': l});
        }),
      );
      expect(calls.length, 2);
      expect(calls[0]['n'], 2);
      expect(calls[0]['l'], 'invalidline');
      expect(calls[1]['n'], 4);
      expect(calls[1]['l'], '  noeq   ');
    });

    test('unicode in key is preserved', () {
      const src = 'Hey ya! 👋 = hi';
      final doc = FlatConfig.parse(src);
      expect(doc['Hey ya! 👋'], 'hi');
    });
  });

  group('FlatConf non-throwing via callbacks', () {
    test('respects custom comment prefix (others are invalid)', () {
      const src = '; c\n# c2\nk = v\n';
      final lines = <int>[];
      final doc = FlatConfig.parse(
        src,
        options: FlatParseOptions(
          commentPrefix: ';',
          onMissingEquals: (n, _) => lines.add(n),
        ),
      );
      expect(lines.isNotEmpty, isTrue);
      expect(doc['k'], 'v');
    });

    test('collects issues and returns document', () {
      const src = 'ok = 1\ninvalid\n# c\nfoo = 2';
      var missingCount = 0;
      final doc = FlatConfig.parse(
        src,
        options: FlatParseOptions(
          onMissingEquals: (_, __) => missingCount++,
        ),
      );
      expect(doc['ok'], '1');
      expect(doc['foo'], '2');
      expect(missingCount, greaterThan(0));
    });

    test('collects empty key issue', () {
      const src = 'ok = 1\n = value\nfoo = 2\n';
      var emptyCount = 0;
      final doc = FlatConfig.parse(
        src,
        options: FlatParseOptions(onEmptyKey: (_, __) => emptyCount++),
      );
      expect(emptyCount, 1);
      expect(doc.keys.toList(), ['ok', 'foo']); // empty key line is ignored
    });
  });

  group('FlatConfig.parse custom comments and strict/errors', () {
    test('custom comment prefix ";" works after trim', () {
      const src = ' ; comment after trim\n; real comment\nkey = v\n';
      final doc = FlatConfig.parse(
        src,
        options: const FlatParseOptions(commentPrefix: ';'),
      );
      expect(doc['key'], 'v');
      expect(doc.keys.toList(), ['key']);
    });

    test('parseLines strict=true throws and onMissingEquals collects', () {
      final lines = [
        'x',
        'k = v',
      ];
      expect(
        () => FlatConfig.parseLines(
          lines,
          options: const FlatParseOptions(strict: true),
        ),
        throwsFormatException,
      );

      var called = false;
      FlatConfig.parseLines(
        lines,
        options: FlatParseOptions(onMissingEquals: (_, __) => called = true),
      );
      expect(called, isTrue);
    });

    test('single comment prefix only: other prefix lines are not comments', () {
      const src = '  # c1\n// c2\nkey = v\n';
      final doc = FlatConfig.parse(
        src,
        // default is '#', so '//' is not treated as comment
      );
      // '// c2' is invalid (no '=') and thus ignored, not parsed as key
      expect(doc.keys.toList(), ['key']);
      expect(doc['key'], 'v');
    });

    test('strict=true throws on empty key', () {
      const src = '   = value';
      expect(
        () => FlatConfig.parse(src,
            options: const FlatParseOptions(strict: true)),
        throwsFormatException,
      );
    });

    test('parseLines strict=true throws on empty key', () {
      final lines = [
        '= value',
      ];
      expect(
        () => FlatConfig.parseLines(
          lines,
          options: const FlatParseOptions(strict: true),
        ),
        throwsFormatException,
      );
    });
  });

  group('FlatConf quoted escapes toggle', () {
    test(r'decodeEscapesInQuoted=false preserves \\" and \\\"', () {
      const src = r'k = "He said: \"hi\" \\ o/"';
      final doc = FlatConfig.parse(
        src,
      );
      expect(doc['k'], r'He said: \"hi\" \\ o/');
    });

    test('decodeEscapesInQuoted=true but no escapes leaves string unchanged',
        () {
      const src = 'k = "plain"';
      final doc = FlatConfig.parse(
        src,
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );
      expect(doc['k'], 'plain');
    });

    test('tryParse decodeEscapesInQuoted=true with no escapes yields no issues',
        () {
      const src = 'a = "abc"\n# c\n';
      var called = false;
      final doc = FlatConfig.parse(
        src,
        options: FlatParseOptions(
          decodeEscapesInQuoted: true,
          onMissingEquals: (_, __) => called = true,
          onEmptyKey: (_, __) => called = true,
        ),
      );
      expect(called, isFalse);
      expect(doc['a'], 'abc');
    });

    test(r'decodeEscapesInQuoted=true: only \" and \\ change; others kept', () {
      const src = r'k = "keep \n and \t; fix: \" and \\"';
      final doc = FlatConfig.parse(
        src,
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );
      // \n and \t remain as two chars, while \" -> " and \\ -> \
      expect(doc['k'], r'keep \n and \t; fix: " and \');
    });
  });

  group('FlatConf line numbers with CRLF via callbacks', () {
    test('reports correct line for missing = with CRLF', () {
      const src = 'ok = 1\r\ninvalid\r\nnext = 2\r\n';
      final lines = <int>[];
      final doc = FlatConfig.parse(
        src,
        options: FlatParseOptions(onMissingEquals: (n, _) => lines.add(n)),
      );
      expect(lines, isNotEmpty);
      expect(lines.first, 2);
      expect(doc['ok'], '1');
      expect(doc['next'], '2');
    });
  });

  group('FlatConfig.parseLines commentPrefixes edge cases', () {
    test('empty commentPrefix does not treat # as comment', () {
      final lines = [
        '# comment',
        'k = v',
      ];

      var called = false;
      final doc = FlatConfig.parseLines(
        lines,
        options: const FlatParseOptions(commentPrefix: ''),
      );
      // simulate non-throwing collection
      FlatConfig.parseLines(
        lines,
        options: FlatParseOptions(
            onMissingEquals: (_, __) => called = true, commentPrefix: ''),
      );
      // '# comment' is not treated as a comment and therefore invalid (no '=')
      expect(called, isTrue);
      expect(doc['k'], 'v');
    });

    test('callback counts all invalid lines', () {
      final lines = const ['ok = 1', 'bad1', 'bad2', '# c', 'k = 2'];
      var count = 0;
      final doc = FlatConfig.parseLines(
        lines,
        options: FlatParseOptions(onMissingEquals: (_, __) => count++),
      );
      expect(count, 2);
      expect(doc['ok'], '1');
      expect(doc['k'], '2');
    });

    test('commentPrefix="#" treats # as comment (default)', () {
      final doc = FlatConfig.parse(
        'key = v\n# c',
      );
      expect(doc['key'], 'v');
      expect(doc.keys.toList(), ['key']);
    });

    test('custom single comment prefix via callbacks (others invalid)', () {
      var count = 0;
      final doc = FlatConfig.parseLines(
        const ['; c', '# c2', 'k = v'],
        options: FlatParseOptions(
          commentPrefix: ';',
          onMissingEquals: (_, __) => count++,
        ),
      );
      expect(count, greaterThan(0));
      expect(doc['k'], 'v');
    });
  });

  group('FlatConf parse value escapes', () {
    test(r'decodeEscapesInQuoted unescapes \" and \\', () {
      const src = r'k = "He said: "hi" \\ o/"';
      final doc = FlatConfig.parse(
        src,
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );
      expect(doc['k'], r'He said: "hi" \ o/');
    });
  });

  group('FlatConfig.parseFromString and parseLines', () {
    test('parseLines (via convert) works like parse', () {
      const src = '''
# comment
background = 282c34
keybind = ctrl+z=close_surface
font-family =
''';

      final doc1 = FlatConfig.parse(src);
      final doc2 = FlatConfig.parseLines(const LineSplitter().convert(src));

      expect(doc1['background'], doc2['background']);
      expect(doc1['keybind'], doc2['keybind']);
      expect(doc1['font-family'], doc2['font-family']);
      expect(doc1.keys.toList(), doc2.keys.toList());
    });

    test('parseLines processes list of strings', () {
      const strings = [
        '# comment',
        'background = 282c34',
        'keybind = ctrl+z=close_surface',
        'font-family =',
        '', // empty line
        'another = value',
      ];

      final doc = FlatConfig.parseLines(strings);

      expect(doc['background'], '282c34');
      expect(doc['keybind'], 'ctrl+z=close_surface');
      expect(doc['font-family'], isNull);
      expect(doc['another'], 'value');
      expect(
        doc.keys.toList(),
        [
          'background',
          'keybind',
          'font-family',
          'another',
        ],
      );
    });

    test('parseLines ignores comments and empty lines', () {
      const strings = [
        '# this is a comment',
        'key1 = value1',
        '', // empty line
        '   # indented comment',
        'key2 = value2',
        '   ', // whitespace only line
        'key3 = value3',
      ];

      final doc = FlatConfig.parseLines(strings);

      expect(doc.keys.length, 3);
      expect(doc['key1'], 'value1');
      expect(doc['key2'], 'value2');
      expect(doc['key3'], 'value3');
    });

    test('parseLines handles lines without equals sign', () {
      const strings = [
        'key1 = value1',
        'invalid line without equals',
        'key2 = value2',
        'another invalid line',
      ];

      final doc = FlatConfig.parseLines(strings);

      expect(doc.keys.length, 2);
      expect(doc['key1'], 'value1');
      expect(doc['key2'], 'value2');
    });

    // No direct tests for the internal parser. We test only public API.
  });

  group('FlatConfIO.parseFile (File)', () {
    test('parses file asynchronously', () async {
      final file = File('test/tmp_FlatConfig.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = '''
# Example
background = 282c34
font-family =
keybind = ctrl+d=new_split:right
''';
      file.writeAsStringSync(src);

      final doc = await file.parseFlat();
      expect(doc['background'], '282c34');
      expect(doc['font-family'], isNull);
      expect(doc.valuesOf('keybind'), ['ctrl+d=new_split:right']);
    });

    test('honors custom encoding and LineSplitter', () async {
      final file = File('test/tmp_flatconf_crlf.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = 'a = 1\r\nb = 2\r\n';
      file.writeAsBytesSync(utf8.encode(src));

      final doc = await file.parseFlat();

      expect(doc['a'], '1');
      expect(doc['b'], '2');
    });

    test('ignores invalid lines without "=" in files', () async {
      final file = File('test/tmp_flatconf_invalid.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = 'a=1\ninvalid\nb=2\n';
      file.writeAsStringSync(src);

      final doc = await file.parseFlat();
      expect(doc.keys.toList(), ['a', 'b']);
      expect(doc['a'], '1');
      expect(doc['b'], '2');
    });

    test('quoted values in files match FlatConfig.parse semantics', () async {
      final file = File('test/tmp_flatconf_quoted.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = 'k1 = "   foo   "\n'
          'k2 = ""\n'
          'k3 =   foo   \n'
          'k4 =\n';

      file.writeAsStringSync(src);

      final doc = await file.parseFlat();

      expect(doc['k1'], '   foo   '); // spaces preserved inside quotes
      expect(doc['k2'], ''); // empty quoted string -> empty string
      expect(doc['k3'], 'foo'); // unquoted -> trimmed
      expect(doc['k4'], isNull); // empty -> null
    });

    test('parity with FlatConfig.parse for unquoted values', () async {
      final file = File('test/tmp_flatconf_parity.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = 'a=1\n'
          'b = 2\n'
          'c =   \n'
          'd = ctrl+z=close_surface\n'
          'e = Hey ya! 👋\n';

      file.writeAsStringSync(src);

      final docString = FlatConfig.parse(src);
      final docFile = await file.parseFlat();

      expect(docFile['a'], docString['a']);
      expect(docFile['b'], docString['b']);
      expect(docFile['c'], docString['c']);
      expect(docFile['d'], docString['d']);
      expect(docFile['e'], docString['e']);
      expect(docFile.keys.toList(), docString.keys.toList());
    });

    test('strict mode throws on invalid line in files', () async {
      final file = File('test/tmp_flatconf_strict.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = 'a=1\ninvalid\nb=2\n';
      file.writeAsStringSync(src);

      expect(
        () => file.parseFlat(options: const FlatParseOptions(strict: true)),
        throwsFormatException,
      );
    });

    test('onInvalidLine is called for ignored lines in files', () async {
      final file = File('test/tmp_flatconf_invalid_callback.conf');
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      const src = 'a=1\ninvalid\nb=2\n';
      file.writeAsStringSync(src);

      var called = false;
      await file.parseFlat(
        options: FlatParseOptions(onMissingEquals: (_, __) => called = true),
      );
      expect(called, isTrue);
    });
  });

  test('encode writes encoded content', () async {
    final file = File('test/tmp_out.conf');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final doc = FlatDocument(const [
      FlatEntry('a', '1'),
      FlatEntry('b', null),
    ]);

    await file.writeFlat(doc);
    final content = file.readAsStringSync();

    expect(content.trim(), 'a = 1\nb =');
  });

  test('encode ends with newline', () async {
    final file = File('test/tmp_out_newline.conf');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    final doc = FlatDocument(const [
      FlatEntry('only', 'x'),
    ]);

    await file.writeFlat(doc);
    final content = file.readAsStringSync();
    expect(content.endsWith('\n'), isTrue);
  });

  group('FlatConfig.encode (quoting behavior)', () {
    test(
        'quotes values with leading/trailing spaces when quoteIfWhitespace=true',
        () {
      final doc = FlatDocument(const [
        FlatEntry('k', '  spaced  '),
      ]);
      final out = doc.encode();
      expect(out.trim(), 'k = "  spaced  "');

      final reparsed = FlatConfig.parse(out);
      expect(reparsed['k'], '  spaced  ');
    });

    test('alwaysQuote forces quoting for all non-null values', () {
      final doc = FlatDocument(const [
        FlatEntry('a', 'x'),
        FlatEntry('b', ' y '),
      ]);
      final out =
          doc.encode(options: const FlatEncodeOptions(alwaysQuote: true));
      expect(out.split('\n')[0], 'a = "x"');
      expect(out.contains('b = " y "'), isTrue);

      final reparsed = FlatConfig.parse(out);
      expect(reparsed['a'], 'x');
      expect(reparsed['b'], ' y ');
    });

    test('escapeQuoted=true escapes quotes and backslashes', () {
      final doc = FlatDocument(const [
        FlatEntry('k', r'He said: "hello" \ o/'),
      ]);
      final out = doc.encode(
          options:
              const FlatEncodeOptions(alwaysQuote: true, escapeQuoted: true));
      // Verify that quotes are escaped and the single backslash is doubled
      expect(out.contains(r'\"hello\"'), isTrue);
      expect(out.contains(r'\\ o/'), isTrue);

      final reparsed = FlatConfig.parse(
        out,
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );
      expect(reparsed['k'], r'He said: "hello" \ o/');
    });

    test('quotes values with leading/trailing tabs', () {
      final doc = FlatDocument(const [
        FlatEntry('k', '\tfoo\t'),
      ]);
      final out = doc.encode();
      expect(out.trim(), 'k = "\tfoo\t"');
      final reparsed = FlatConfig.parse(out);
      expect(reparsed['k'], '\tfoo\t');
    });

    test('quotes values with leading/trailing NBSP (U+00A0)', () {
      const nbsp = '\u00A0';
      final doc = FlatDocument(const [
        FlatEntry('k', '${nbsp}x$nbsp'),
      ]);
      final out = doc.encode();
      expect(out.contains('"'), isTrue);
      final reparsed = FlatConfig.parse(out);
      expect(reparsed['k'], '${nbsp}x$nbsp');
    });

    test('quotes when value contains the separator', () {
      final doc = FlatDocument(const [
        FlatEntry('k', 'left=right'),
      ]);
      final out = doc.encode();
      expect(out.trim(), 'k = "left=right"');
      final reparsed = FlatConfig.parse(out);
      expect(reparsed['k'], 'left=right');
    });

    test('quotes when value starts with the comment prefix after trim', () {
      final doc = FlatDocument(const [
        FlatEntry('k', '# danger'),
      ]);
      final out = doc.encode(
        options: const FlatEncodeOptions(commentPrefix: '#'),
      );
      expect(out.trim(), 'k = "# danger"');
      final reparsed = FlatConfig.parse(out);
      expect(reparsed['k'], '# danger');
    });

    test('quotes when value contains double quotes', () {
      final doc = FlatDocument(const [
        FlatEntry('k', 'say "hi"'),
      ]);
      final out = doc.encode();
      expect(out.contains('"say "hi""') || out.contains('"say "hi""'), isTrue);
      final reparsed = FlatConfig.parse(out);
      expect(reparsed['k'], 'say "hi"');
    });

    test('quotes when value contains newlines', () {
      final doc = FlatDocument(const [
        FlatEntry('k', 'a\nb'),
      ]);
      final out = doc.encode();
      expect(out.contains('"a\nb"'), isTrue);
    });
  });

  group('FlatConfig.fromMap / fromDynamicMap', () {
    test('fromMap preserves order and nulls become resets', () {
      final map = {
        'a': '1',
        'b': null,
        'c': ' x ',
      };
      final doc = FlatConfig.fromMap(map);
      expect(doc.keys.toList(), ['a', 'b', 'c']);
      expect(doc.valuesOf('a'), ['1']);
      expect(doc.valuesOf('b'), [null]);
      expect(doc.valuesOf('c'), [' x ']);

      final encoded = doc.encode();
      expect(encoded.split('\n')[0], 'a = 1');
      expect(encoded.contains('\nb = '), isTrue);
    });

    test('fromDynamicMap uses default toString and custom encoder', () {
      final doc1 = FlatConfig.fromDynamicMap({
        'i': 42,
        'b': true,
        'n': null,
      });
      expect(doc1['i'], '42');
      expect(doc1['b'], 'true');
      expect(doc1['n'], isNull);

      final doc2 = FlatConfig.fromDynamicMap(
        {
          'i': 7,
          's': ' x ',
        },
        valueEncoder: (k, v) {
          if (v is int) {
            return '0x${v.toRadixString(16)}';
          }

          return v?.toString();
        },
      );
      expect(doc2['i'], '0x7');
      expect(doc2['s'], ' x ');
    });
  });

  group('FlatConfig.parseFromString edge values', () {
    test('empty quoted string yields empty string', () {
      const src = 'k = ""';
      final doc = FlatConfig.parse(src);
      expect(doc['k'], '');
    });

    test('unquoted trimmed to empty becomes null', () {
      const src = 'k =    ';
      final doc = FlatConfig.parse(src);
      expect(doc['k'], isNull);
    });
  });

  group('FlatConfig.preprocessLine', () {
    test('returns trimmed line for non-empty input', () {
      expect(FlatConfig.preprocessLine('  key = v  ', '#'), 'key = v');
      expect(FlatConfig.preprocessLine('x', '#'), 'x');
    });

    test('returns null for empty or whitespace-only lines', () {
      expect(FlatConfig.preprocessLine('', '#'), isNull);
      expect(FlatConfig.preprocessLine('   \t', '#'), isNull);
    });

    test('returns null for comments with default #', () {
      expect(FlatConfig.preprocessLine('# c', '#'), isNull);
      expect(FlatConfig.preprocessLine('   # indented', '#'), isNull);
    });

    test('respects custom comment prefix', () {
      expect(FlatConfig.preprocessLine('; c', ';'), isNull);
      expect(FlatConfig.preprocessLine('   ; c', ';'), isNull);
      expect(FlatConfig.preprocessLine('# c', ';'), '# c');
    });

    test('empty commentPrefix disables comment handling', () {
      expect(FlatConfig.preprocessLine('# c', ''), '# c');
      expect(FlatConfig.preprocessLine('   # c', ''), '# c');
    });
  });

  group('FlatConf streaming APIs', () {
    test('parseFromStringStream handles BOM on first line and callbacks',
        () async {
      final lines = Stream.fromIterable(const [
        '\u{FEFF}key = v',
        'x = 1',
        'invalid',
        '# c',
      ]);

      var missingCount = 0;
      final doc = await FlatConfig.parseFromStringStream(
        lines,
        options: FlatParseOptions(onMissingEquals: (_, __) => missingCount++),
      );

      expect(doc['key'], 'v');
      expect(doc['x'], '1');
      expect(missingCount, 1);
    });

    test('parseFromByteStream splits CRLF and parses entries', () async {
      final bytes = utf8.encode('a = 1\r\nb = 2\r\n');
      final stream = Stream<List<int>>.value(bytes);
      final doc = await FlatConfig.parseFromByteStream(
        stream,
        readOptions: const FlatStreamReadOptions(lineSplitter: LineSplitter()),
      );
      expect(doc['a'], '1');
      expect(doc['b'], '2');
    });

    test('parseEntries yields only valid entries in order', () async {
      final bytes = utf8.encode('  # c\nkey = 1\nbad\nz = \n');
      final entries =
          await FlatConfig.parseEntries(Stream<List<int>>.value(bytes))
              .toList();

      expect(entries.length, 2);
      expect(entries[0].key, 'key');
      expect(entries[0].value, '1');
      expect(entries[1].key, 'z');
      expect(entries[1].value, isNull);
    });

    test(
        'regex pairSeparator match at position 0 triggers empty-key callback (non-strict)',
        () {
      var emptyCalls = 0;
      final doc = FlatConfig.parse(
        '= v',
        options: FlatParseOptions(
          onEmptyKey: (_, __) => emptyCalls++,
        ),
      );
      expect(emptyCalls, 1);
      expect(doc.keys, isEmpty); // empty key line is ignored
    });

    test(
        'parseValue early return via custom separator and empty unquoted value',
        () {
      final doc = FlatConfig.parse(
        'k ->   ',
        options: const FlatParseOptions(),
      );
      expect(doc['k'], isNull);
    });
  });

  group('Options copyWith coverage', () {
    test('FlatParserOptions.copyWith fallback and overrides', () {
      var missing = 0;
      var empty = 0;
      final base = FlatParseOptions(
        commentPrefix: ';',
        decodeEscapesInQuoted: true,
        strict: true,
        onMissingEquals: (_, __) => missing++,
        onEmptyKey: (_, __) => empty++,
      );

      final fallback = base.copyWith();
      expect(fallback.commentPrefix, ';');
      expect(fallback.decodeEscapesInQuoted, isTrue);
      expect(fallback.strict, isTrue);

      final overridden = base.copyWith(
        commentPrefix: '#',
        decodeEscapesInQuoted: false,
        strict: false,
        onMissingEquals: (_, __) => missing += 10,
        onEmptyKey: (_, __) => empty += 10,
      );
      expect(overridden.commentPrefix, '#');
      expect(overridden.decodeEscapesInQuoted, isFalse);
      expect(overridden.strict, isFalse);

      // sanity: callbacks are callable
      overridden.onMissingEquals?.call(1, 'x');
      overridden.onEmptyKey?.call(1, 'x');
      expect(missing, 10);
      expect(empty, 10);
    });

    test('FlatStreamReadOptions.copyWith for encoding and splitter', () {
      final base = const FlatStreamReadOptions();

      final changedEnc = base.copyWith(encoding: latin1);
      expect(changedEnc.encoding, latin1);
      expect(changedEnc.lineSplitter, isA<LineSplitter>());

      final changedSplit = base.copyWith(lineSplitter: const LineSplitter());
      expect(changedSplit.encoding, utf8);
      expect(changedSplit.lineSplitter, isA<LineSplitter>());
    });
  });

  group('parseEntriesFromStringStream BOM handling', () {
    test('strips BOM on first string line', () async {
      final lines = Stream<String>.fromIterable(const [
        '\u{FEFF}key = v',
        'x = 1',
      ]);

      final entries =
          await FlatConfig.parseEntriesFromStringStream(lines).toList();

      expect(entries.first.key, 'key');
      expect(entries.first.value, 'v');
      expect(entries.last.key, 'x');
      expect(entries.last.value, '1');
    });
  });

  group('FlatConfig.parseLines convenience method', () {
    test('parseLines is equivalent to parse', () {
      const lines = [
        '# comment',
        'background = 282c34',
        'keybind = ctrl+z=close_surface',
        'font-family =',
        '', // empty line
        'another = value',
      ];

      final doc1 = FlatConfig.parseLines(lines);
      final doc2 = FlatConfig.parse(lines.join('\n'));

      expect(doc1['background'], doc2['background']);
      expect(doc1['keybind'], doc2['keybind']);
      expect(doc1['font-family'], doc2['font-family']);
      expect(doc1['another'], doc2['another']);
      expect(doc1.keys.toList(), doc2.keys.toList());
    });

    test('parseLines respects custom options', () {
      const lines = [
        '; comment',
        'key = value',
        'invalid line',
      ];

      var missingCount = 0;
      final doc = FlatConfig.parseLines(
        lines,
        options: FlatParseOptions(
          commentPrefix: ';',
          onMissingEquals: (_, __) => missingCount++,
        ),
      );

      expect(doc['key'], 'value');
      expect(missingCount, 1); // 'invalid line' triggers callback
    });

    test('parseLines handles empty list', () {
      const lines = <String>[];
      final doc = FlatConfig.parseLines(lines);

      expect(doc, FlatDocument.empty());
      expect(doc.keys, isEmpty);
    });

    test('parseLines handles list with only comments and empty lines', () {
      const lines = [
        '# comment',
        '',
        '   # indented comment',
        '   ',
      ];
      final doc = FlatConfig.parseLines(lines);

      expect(doc, FlatDocument.empty());
      expect(doc.keys, isEmpty);
    });

    test('parseLines processes valid entries correctly', () {
      const lines = [
        'a = 1',
        'b = 2',
        'c = 3',
      ];
      final doc = FlatConfig.parseLines(lines);

      expect(doc['a'], '1');
      expect(doc['b'], '2');
      expect(doc['c'], '3');
      expect(doc.keys.toList(), ['a', 'b', 'c']);
    });

    test('parseLines handles duplicate keys', () {
      const lines = [
        'key = first',
        'key = second',
        'key = third',
      ];
      final doc = FlatConfig.parseLines(lines);

      expect(doc['key'], 'third');
      expect(doc.valuesOf('key'), ['first', 'second', 'third']);
    });

    test('parseLines with strict mode throws on invalid lines', () {
      const lines = [
        'valid = 1',
        'invalid line',
        'another = 2',
      ];

      expect(
        () => FlatConfig.parseLines(
          lines,
          options: const FlatParseOptions(strict: true),
        ),
        throwsFormatException,
      );
    });

    group('parseLine', () {
      test('parses valid key-value pairs', () {
        final result = FlatConfig.parseLine(
          'key=value',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNotNull);
        expect(result!.key, 'key');
        expect(result.value, 'value');
      });

      test('handles quoted values', () {
        final result = FlatConfig.parseLine(
          'key="quoted value"',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNotNull);
        expect(result!.key, 'key');
        expect(result.value, 'quoted value');
      });

      test('handles empty values', () {
        final result = FlatConfig.parseLine(
          'key=',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNotNull);
        expect(result!.key, 'key');
        expect(result.value, isNull);
      });

      test('handles whitespace around key and value', () {
        final result = FlatConfig.parseLine(
          '  key  =  value  ',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNotNull);
        expect(result!.key, 'key');
        expect(result.value, 'value');
      });

      test('returns null for empty lines', () {
        final result = FlatConfig.parseLine(
          '',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNull);
      });

      test('returns null for whitespace-only lines', () {
        final result = FlatConfig.parseLine(
          '   ',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNull);
      });

      test('returns null for comment lines', () {
        final result = FlatConfig.parseLine(
          '# This is a comment',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNull);
      });

      test('handles custom comment prefix', () {
        final result = FlatConfig.parseLine(
          '// This is a comment',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '//',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNull);
      });

      test('handles lines without equals in strict mode', () {
        expect(
          () => FlatConfig.parseLine(
            'key without equals',
            lineNumber: 1,
            options: const FlatParseOptions(
              commentPrefix: '#',
              strict: true,
              decodeEscapesInQuoted: false,
            ),
          ),
          throwsA(isA<MissingEqualsException>()),
        );
      });

      test('handles lines without equals in non-strict mode', () {
        var callbackCalled = false;
        final result = FlatConfig.parseLine(
          'key without equals',
          lineNumber: 1,
          options: FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
            onMissingEquals: (lineNumber, raw) {
              callbackCalled = true;
              expect(lineNumber, 1);
              expect(raw, 'key without equals');
            },
          ),
        );
        expect(result, isNull);
        expect(callbackCalled, isTrue);
      });

      test('handles empty key in strict mode', () {
        expect(
          () => FlatConfig.parseLine(
            '=value',
            lineNumber: 1,
            options: const FlatParseOptions(
              commentPrefix: '#',
              strict: true,
              decodeEscapesInQuoted: false,
            ),
          ),
          throwsA(isA<EmptyKeyException>()),
        );
      });

      test('handles empty key in non-strict mode', () {
        var callbackCalled = false;
        final result = FlatConfig.parseLine(
          '=value',
          lineNumber: 1,
          options: FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
            onEmptyKey: (lineNumber, raw) {
              callbackCalled = true;
              expect(lineNumber, 1);
              expect(raw, '=value');
            },
          ),
        );
        expect(result, isNull); // empty key returns null
        expect(callbackCalled, isTrue);
      });

      test('handles BOM in input', () {
        final result = FlatConfig.parseLine(
          '\uFEFFkey=value',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: false,
          ),
        );
        expect(result, isNotNull);
        expect(result!.key, 'key');
        expect(result.value, 'value');
      });

      test('handles decodeEscapesInQuoted option', () {
        final result = FlatConfig.parseLine(
          'key="escaped \\"quote\\""',
          lineNumber: 1,
          options: const FlatParseOptions(
            commentPrefix: '#',
            strict: false,
            decodeEscapesInQuoted: true,
          ),
        );
        expect(result, isNotNull);
        expect(result!.key, 'key');
        expect(result.value, 'escaped "quote"');
      });
    });

    group('preprocessLine', () {
      test('removes BOM from beginning of line', () {
        final result = FlatConfig.preprocessLine('\uFEFFkey=value', '#');
        expect(result, 'key=value');
      });

      test('returns null for empty line', () {
        final result = FlatConfig.preprocessLine('', '#');
        expect(result, isNull);
      });

      test('returns null for whitespace-only line', () {
        final result = FlatConfig.preprocessLine('   ', '#');
        expect(result, isNull);
      });

      test('returns null for comment line', () {
        final result = FlatConfig.preprocessLine('# comment', '#');
        expect(result, isNull);
      });

      test('returns null for custom comment prefix', () {
        final result = FlatConfig.preprocessLine('// comment', '//');
        expect(result, isNull);
      });

      test('trims whitespace from valid lines', () {
        final result = FlatConfig.preprocessLine('  key=value  ', '#');
        expect(result, 'key=value');
      });

      test('handles empty comment prefix', () {
        final result = FlatConfig.preprocessLine('key=value', '');
        expect(result, 'key=value');
      });

      test('handles line that starts with comment prefix but is not a comment',
          () {
        final result = FlatConfig.preprocessLine('key#value', '#');
        expect(result, 'key#value');
      });
    });
  });
}
