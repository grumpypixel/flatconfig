@TestOn('vm')
library io_test;

import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('FlatConfIO encode (options)', () {
    test('honors alwaysQuote and escapeQuoted', () async {
      final file = File('test/tmp_io_async_flags.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument(const [
        FlatEntry('k', r'He said: "hello" \ o/'),
      ]);

      await file.writeFlat(
        doc,
        options: const FlatEncodeOptions(
          alwaysQuote: true,
          escapeQuoted: true,
        ),
      );

      final content = file.readAsStringSync();
      // Value is quoted and inner quotes/backslashes are escaped
      expect(content.contains(r'k = "He said: \"hello\" \\ o/"'), isTrue);
    });
  });

  group('FlatConfIO parseFile (extras)', () {
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
      final doc = await io.parseFileWithIncludes(mainFile.path);
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
      final doc = await io.parseFileWithIncludes(
        mainFile.path,
        options: const FlatParseOptions(includeKey: 'include'),
      );
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
    });

    test('respects custom single commentPrefix', () async {
      final file = File('test/tmp_io_comment.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      // With commentPrefix=';', a line starting with '#' is not a comment.
      // Make it a valid assignment so it is parsed, not ignored.
      file.writeAsStringSync('#key = zero\n; real comment\nx = 1\n');

      final doc = await file.parseFlat(
        options: const FlatParseOptions(commentPrefix: ';'),
      );
      expect(doc['x'], '1');
      expect(doc['#key'], 'zero');
      expect(doc.keys.length, 2);
    });

    test('callbacks collect issues on invalid lines', () async {
      final file = File('test/tmp_io_try_issues.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('a=1\ninvalid\nb=2\n');
      var count = 0;
      final doc = await file.parseFlat(
        options: FlatParseOptions(onMissingEquals: (_, __) => count++),
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
          options: FlatParseOptions(onEmptyKey: (_, __) => empty = true));
      expect(empty, isTrue);
    });

    test('strict mode throws on empty key in files', () async {
      final file = File('test/tmp_io_strict_empty_key.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);
      file.writeAsStringSync('   = value\n');
      expect(
          () => file.parseFlat(options: const FlatParseOptions(strict: true)),
          throwsFormatException);
    });
  });

  group('FlatConfIO encodeSync', () {
    test('writes with quoting options (defaults quoteIfWhitespace=true)', () {
      final file = File('test/tmp_io_sync_quote.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument(const [FlatEntry('k', ' spaced ')]);
      file.writeFlatSync(doc);
      final content = file.readAsStringSync();
      expect(content.trim(), 'k = " spaced "');
    });
  });

  group('FlatConfIO parseFileSync (extras)', () {
    test('honors commentPrefix and decodeEscapesInQuoted', () {
      final file = File('test/tmp_io_sync_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);
      file.writeAsStringSync(' ; c\nok = "A"\n');
      final doc = file.parseFlatSync(
        options: const FlatParseOptions(
            commentPrefix: ';', decodeEscapesInQuoted: true),
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

  group('FlatConfIO encode quoting extras', () {
    test('quotes values with leading/trailing tabs when writing to file',
        () async {
      final file = File('test/tmp_io_quote_tab.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);
      final doc = FlatDocument(const [FlatEntry('k', '\tfoo\t')]);
      await file.writeFlat(doc);
      final content = file.readAsStringSync().trim();
      expect(content, 'k = "\tfoo\t"');
      final reparsed = FlatConfig.parse(content);
      expect(reparsed['k'], '\tfoo\t');
    });
  });

  group('parseFlatFile function', () {
    test('parses file using parseFlatFile function', () async {
      final file = File('test/tmp_parse_flat_file.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('key1 = value1\nkey2 = value2\n');

      // Test the actual parseFlatFile function
      final doc = await parseFlatFile('test/tmp_parse_flat_file.conf');
      expect(doc['key1'], 'value1');
      expect(doc['key2'], 'value2');
    });

    test('parseFlatFile with custom options', () async {
      final file = File('test/tmp_parse_flat_file_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      file.writeAsStringSync('; comment\nkey = value\n');

      final doc = await parseFlatFile(
        'test/tmp_parse_flat_file_opts.conf',
        options: const FlatParseOptions(commentPrefix: ';'),
      );
      expect(doc['key'], 'value');
      expect(doc.keys.length, 1);
    });
  });

  group('parseFileWithIncludes function', () {
    test('parses file with includes using parseFileWithIncludes function',
        () async {
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

      // Test the actual parseFileWithIncludes function
      final doc = await parseFileWithIncludes(
          'test/tmp_parse_flat_file_with_includes.conf');
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
      expect(doc['key2'], 'value2');
    });

    test('parseFileWithIncludes with custom options', () async {
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
      final doc = await parseFileWithIncludes(
        'test/tmp_parse_flat_file_with_includes_opts.conf',
        options: const FlatParseOptions(includeKey: 'include'),
      );
      expect(doc['key1'], 'value1');
      expect(doc['included_key'], 'included_value');
    });
  });

  group('FlatDocumentIO extension', () {
    test('saveToFile saves document to file', () async {
      final file = File('test/tmp_save_to_file.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);

      // Test the actual saveToFile method
      await doc.saveToFile('test/tmp_save_to_file.conf');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('a = 1'));
      expect(content, contains('b = 2'));
    });

    test('saveToFileSync saves document to file synchronously', () {
      final file = File('test/tmp_save_to_file_sync.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument(const [
        FlatEntry('x', 'y'),
        FlatEntry('z', 'w'),
      ]);

      // Test the actual saveToFileSync method
      doc.saveToFileSync('test/tmp_save_to_file_sync.conf');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('x = y'));
      expect(content, contains('z = w'));
    });

    test('saveToFile with custom options', () async {
      final file = File('test/tmp_save_to_file_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument(const [
        FlatEntry('k', 'value with spaces'),
      ]);

      await doc.saveToFile(
        'test/tmp_save_to_file_opts.conf',
        options: const FlatEncodeOptions(alwaysQuote: true),
      );
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('k = "value with spaces"'));
    });

    test('saveToFileSync with custom options', () {
      final file = File('test/tmp_save_to_file_sync_opts.conf');
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);

      final doc = FlatDocument(const [
        FlatEntry('k', 'value with spaces'),
      ]);

      doc.saveToFileSync(
        'test/tmp_save_to_file_sync_opts.conf',
        options: const FlatEncodeOptions(alwaysQuote: true),
      );
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('k = "value with spaces"'));
    });
  });
}
