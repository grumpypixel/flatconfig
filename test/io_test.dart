@TestOn('vm')
library io_test;

import 'dart:io';

import 'package:flatconfig/flatconfig_io.dart';
import 'package:flatconfig/src/io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('encode (options)', () {
    test('honors alwaysQuote and escapeQuoted', () async {
      final file = File('test/tmp_io_async_flags.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('k', r'He said: "hello" \ o/')]);

      await file.writeFlat(
        doc,
        options: const FlatEncodeOptions(alwaysQuote: true, escapeQuoted: true),
      );

      final content = file.readAsStringSync();
      // Value is quoted and inner quotes/backslashes are escaped
      expect(content.contains(r'k = "He said: \"hello\" \\ o/"'), isTrue);
    });
  });

  group('Top-level IO helpers', () {
    test('writeFlat writes document to path (async)', () async {
      final path = 'test/tmp_io_write_async.conf';
      final file = File(path);
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('k', 'v')]);
      await File(path).writeFlat(doc);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync().trim(), 'k = v');
    });

    test('writeFlatSync writes document to path (sync)', () {
      final path = 'test/tmp_io_write_sync.conf';
      final file = File(path);
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('x', 'y')]);
      File(path).writeFlatSync(doc);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync().trim(), 'x = y');
    });
  });

  group('File parsing (extras)', () {
    test('decodeEscapesInQuoted=true unescapes quoted content', () async {
      final file = File('test/tmp_io_decode.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      // Reason: In this test, we want to write a string with escaped quotes
      // and backslashes.
      // ignore: unnecessary_string_escapes
      file.writeAsStringSync('k = "He said: \\\"hi\\\" \\\\ o/"\n');

      final doc = await file.parseFlat(
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );
      expect(doc['k'], r'He said: "hi" \ o/');
    });

    test('parseWithIncludes parses file with includes', () async {
      final mainFile = File('test/tmp_io_parse_flat_with_includes.conf');
      final includeFile = File('test/tmp_io_include_file.conf');
      addTearDown(() {
        if (mainFile.existsSync()) mainFile.deleteSync();
        if (includeFile.existsSync()) includeFile.deleteSync();
      });

      // Create main file with include
      mainFile.writeAsStringSync('''
key1 = value1
config-file = tmp_io_include_file.conf
key2 = value2
''');

      // Create include file
      includeFile.writeAsStringSync('''
included_key = included_value
''');

      // Test the parseWithIncludes method
      final doc = await File(mainFile.path).parseWithIncludes();
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
      expect(doc['key2'], 'value2');
    });

    test('parseWithIncludes with custom options', () async {
      final mainFile = File('test/tmp_io_parse_flat_with_includes_opts.conf');
      final includeFile = File('test/tmp_io_include_file_opts.conf');
      addTearDown(() {
        if (mainFile.existsSync()) mainFile.deleteSync();
        if (includeFile.existsSync()) includeFile.deleteSync();
      });

      // Create main file with custom include key
      mainFile.writeAsStringSync('''
key1 = value1
include = tmp_io_include_file_opts.conf
''');

      // Create include file
      includeFile.writeAsStringSync('''
included_key = included_value
''');

      // Test with custom include key
      final doc = await File(mainFile.path).parseWithIncludes(
        includeOptions: const FlatIncludeOptions(includeKey: 'include'),
      );
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
    });

    test('respects custom single commentPrefix', () async {
      final file = File('test/tmp_io_comment.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      // With commentPrefix=';', a line starting with '#' is not a comment
      // here. The key is still rejected: key validity must not depend on the
      // options of whoever happens to parse the file, or a document written
      // with one prefix would lose entries when read with another (SPEC.md 3).
      file.writeAsStringSync('#key = zero\n; real comment\nx = 1\n');

      final doc = await file.parseFlat(
        options: const FlatParseOptions(commentPrefix: ';'),
      );
      expect(doc['x'], '1');
      expect(doc['#key'], isNull);
      expect(doc.keys.length, 1);
    });

    test('callbacks collect issues on invalid lines', () async {
      final file = File('test/tmp_io_try_issues.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('a=1\ninvalid\nb=2\n');
      var count = 0;
      final doc = await file.parseFlat(
        options: FlatParseOptions(onIssue: (_) => count++),
      );
      expect(doc['a'], '1');
      expect(doc['b'], '2');
      expect(count, greaterThan(0));
    });

    test('parse strips UTF-8 BOM on first line', () async {
      final file = File('test/tmp_io_try_bom.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final bomPlus = [0xEF, 0xBB, 0xBF, ...'k = v\n'.codeUnits];
      file.writeAsBytesSync(bomPlus);
      final doc = await file.parseFlat();
      expect(doc['k'], 'v');
    });

    test('parseFile strips UTF-8 BOM on first line', () async {
      final file = File('test/tmp_io_bom_parse.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final bomPlus = [0xEF, 0xBB, 0xBF, ...'key = v\n'.codeUnits];
      file.writeAsBytesSync(bomPlus);

      final doc = await file.parseFlat();
      expect(doc['key'], 'v');
    });

    test('parse: BOM + empty key triggers emptyKey callback', () async {
      final file = File('test/tmp_io_try_bom_emptykey.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final bomPlus = [0xEF, 0xBB, 0xBF, ...'   = v\n'.codeUnits];
      file.writeAsBytesSync(bomPlus);
      var empty = false;
      await file.parseFlat(
        options: FlatParseOptions(
          onIssue: (i) => empty = i.kind == FlatIssueKind.emptyKey,
        ),
      );
      expect(empty, isTrue);
    });

    test('strict mode throws on empty key in files', () async {
      final file = File('test/tmp_io_strict_empty_key.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);
      file.writeAsStringSync('   = value\n');
      expect(
        () => file.parseFlat(options: const FlatParseOptions(strict: true)),
        throwsFormatException,
      );
    });
  });

  group('encodeSync', () {
    test('writes with quoting options (defaults quoteIfWhitespace=true)', () {
      final file = File('test/tmp_io_sync_quote.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('k', ' spaced ')]);
      file.writeFlatSync(doc);
      final content = file.readAsStringSync();
      expect(content.trim(), 'k = " spaced "');
    });
  });

  group('File.parseFlatSync (extras)', () {
    test('honors commentPrefix and decodeEscapesInQuoted', () {
      final file = File('test/tmp_io_sync_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);
      file.writeAsStringSync(' ; c\nok = "A"\n');
      final doc = file.parseFlatSync(
        options: const FlatParseOptions(
          commentPrefix: ';',
          decodeEscapesInQuoted: true,
        ),
      );
      expect(doc['ok'], 'A');
      expect(doc.keys.toList(), ['ok']);
    });

    test('parseWithIncludesSync parses file with includes synchronously', () {
      final mainFile = File('test/tmp_io_sync_includes_main.conf');
      final includeFile = File('test/tmp_io_sync_includes_child.conf');
      addTearDown(() {
        if (mainFile.existsSync()) mainFile.deleteSync();
        if (includeFile.existsSync()) includeFile.deleteSync();
      });

      // main references child via default include key 'config-file'
      mainFile.writeAsStringSync('''
key1 = value1
config-file = tmp_io_sync_includes_child.conf
key2 = value2
''');
      includeFile.writeAsStringSync('included_key = included_value\n');

      final doc = io.FlatConfigIO(mainFile).parseWithIncludesSync();
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
      expect(doc['key2'], 'value2');
    });
  });

  group('encode quoting extras', () {
    test(
      'quotes values with leading/trailing tabs when writing to file',
      () async {
        final file = File('test/tmp_io_quote_tab.conf');
        addTearDown(() => file.existsSync() ? file.deleteSync() : null);
        final doc = FlatDocument([FlatEntry('k', '\tfoo\t')]);
        await file.writeFlat(doc);
        final content = file.readAsStringSync().trim();
        expect(content, 'k = "\tfoo\t"');
        final reparsed = FlatDocument.parse(content);
        expect(reparsed['k'], '\tfoo\t');
      },
    );
  });

  group('File.parseFlat', () {
    test('parses a file', () async {
      final file = File('test/tmp_parse_flat_file.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('key1 = value1\nkey2 = value2\n');

      final doc = await File('test/tmp_parse_flat_file.conf').parseFlat();
      expect(doc['key1'], 'value1');
      expect(doc['key2'], 'value2');
    });

    test('honours custom options', () async {
      final file = File('test/tmp_parse_flat_file_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('; comment\nkey = value\n');

      final doc = await File(
        'test/tmp_parse_flat_file_opts.conf',
      ).parseFlat(options: const FlatParseOptions(commentPrefix: ';'));
      expect(doc['key'], 'value');
      expect(doc.keys.length, 1);
    });
  });

  group('File.parseFlatSync', () {
    test('parses a file', () {
      final file = File('test/tmp_parse_flat_file_sync.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('key = value\n');

      final doc = File('test/tmp_parse_flat_file_sync.conf').parseFlatSync();
      expect(doc['key'], 'value');
    });
  });

  group('File.parseWithIncludes', () {
    test('follows the includes a file names', () async {
      final mainFile = File('test/tmp_parse_flat_file_with_includes.conf');
      final includeFile = File('test/tmp_include_file.conf');
      addTearDown(() {
        if (mainFile.existsSync()) mainFile.deleteSync();
        if (includeFile.existsSync()) includeFile.deleteSync();
      });

      // Create main file with include
      mainFile.writeAsStringSync('''
key1 = value1
config-file = tmp_include_file.conf
key2 = value2
''');

      // Create include file
      includeFile.writeAsStringSync('''
included_key = included_value
''');

      final doc = await File(
        'test/tmp_parse_flat_file_with_includes.conf',
      ).parseWithIncludes();
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
      expect(doc['key2'], 'value2');
    });

    test('honours a custom include key', () async {
      final mainFile = File('test/tmp_parse_flat_file_with_includes_opts.conf');
      final includeFile = File('test/tmp_include_file_opts.conf');
      addTearDown(() {
        if (mainFile.existsSync()) mainFile.deleteSync();
        if (includeFile.existsSync()) includeFile.deleteSync();
      });

      // Create main file with custom include key
      mainFile.writeAsStringSync('''
key1 = value1
include = tmp_include_file_opts.conf
''');

      // Create include file
      includeFile.writeAsStringSync('''
included_key = included_value
''');

      // Test with custom include key
      final doc = await File('test/tmp_parse_flat_file_with_includes_opts.conf')
          .parseWithIncludes(
            includeOptions: const FlatIncludeOptions(includeKey: 'include'),
          );
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
    });
  });

  group('File.writeFlat', () {
    test('writeFlat writes a document to a file', () async {
      final file = File('test/tmp_save_to_file.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

      await File('test/tmp_save_to_file.conf').writeFlat(doc);
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('a = 1'));
      expect(content, contains('b = 2'));
    });

    test('writeFlatSync writes a document synchronously', () {
      final file = File('test/tmp_save_to_file_sync.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('x', 'y'), FlatEntry('z', 'w')]);

      File('test/tmp_save_to_file_sync.conf').writeFlatSync(doc);
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('x = y'));
      expect(content, contains('z = w'));
    });

    test('writeFlat honours custom options', () async {
      final file = File('test/tmp_save_to_file_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('k', 'value with spaces')]);

      await File(
        'test/tmp_save_to_file_opts.conf',
      ).writeFlat(doc, options: const FlatEncodeOptions(alwaysQuote: true));
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('k = "value with spaces"'));
    });

    test('writeFlatSync honours custom options', () {
      final file = File('test/tmp_save_to_file_sync_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument([FlatEntry('k', 'value with spaces')]);

      File(
        'test/tmp_save_to_file_sync_opts.conf',
      ).writeFlatSync(doc, options: const FlatEncodeOptions(alwaysQuote: true));
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('k = "value with spaces"'));
    });
  });
}
