// example/streams.dart
//
// Run:
//   dart example/streams.dart
//   cat example/data.conf | dart example/streams.dart --stdin
//
// Requires:
//   import 'package:flatconfig/flatconfig.dart';

import 'dart:async';
import 'dart:convert' show LineSplitter, utf8;
import 'dart:io';

import 'package:flatconfig/flatconfig.dart';

// Reuse the same options everywhere.
final laxWithWarn = FlatParseOptions(
  // strict remains default=false → missing "=" are ignored
  onMissingEquals: (ln, raw) {
    stderr.writeln('  [warn] missing "=" in line $ln: $raw');
  },
  onEmptyKey: (ln, raw) {
    stderr.writeln('  [warn] empty key at line $ln: $raw');
  },
);

Future<void> main(List<String> args) async {
  final useStdin = args.contains('--stdin');

  if (useStdin) {
    stdout.writeln('📥 Reading from stdin (bytes → parseFromByteStream):');
    final doc = await FlatConfig.parseFromByteStream(
      stdin,
      options: laxWithWarn,
      readOptions: const FlatStreamReadOptions(
        encoding: utf8,
        lineSplitter: LineSplitter(),
      ),
    );
    _dump(doc);
    return;
  }

  // Example lines (as if we were reading from a stream)
  final sampleLines = <String>[
    '# demo stream',
    'fullscreen = true',
    'width = 1280',
    'height = 720',
    'theme = dark',
    'colors.primary = #336699cc', // RRGGBBAA (CSS)
    'invalid_line_without_equals',
    'empty.key = ',
    'title = " hello = world "',
  ];

  // 1) Byte-Stream (e.g. File.openRead, Socket, stdin)
  {
    stdout.writeln('🔌 parseFromByteStream (utf8 bytes):');
    final bytes = utf8.encode(sampleLines.join('\n'));
    final byteStream = Stream<List<int>>.value(bytes);

    final doc = await FlatConfig.parseFromByteStream(
      byteStream,
      options: laxWithWarn,
      readOptions: const FlatStreamReadOptions(
        encoding: utf8,
        lineSplitter: LineSplitter(), // robust \r\n/\n/\r
      ),
    );

    _dump(doc);
  }

  // 2) String-Stream with already split lines
  {
    stdout.writeln('\n🔤 parseFromStringStream (line-by-line strings):');
    // Simulate "lines come one after the other":
    final stringStream = Stream<String>.fromIterable(sampleLines);

    // Use strict here to demonstrate the exception path in a controlled way:
    try {
      final doc = await FlatConfig.parseFromStringStream(
        stringStream,
        options: const FlatParseOptions(strict: true),
      );
      _dump(doc);
    } on FormatException catch (e) {
      stderr.writeln('  [strict error] $e');
    }
  }

  // 3) Lazy: process individual entries while reading from a BYTES stream
  {
    stdout.writeln('\n🐢 parseEntries (byte stream) [lazy]:');
    final bytes = utf8.encode(sampleLines.join('\n'));
    final byteStream = Stream<List<int>>.value(bytes);

    await for (final e in FlatConfig.parseEntries(byteStream)) {
      stdout.writeln('    ${e.key} = ${e.value ?? "null"}');
    }
  }

  // ...same, same but different, starting from a STRING stream of lines:
  {
    stdout.writeln('\n🐇 parseEntriesFromStringStream (string stream) [lazy]:');
    final lineStream = Stream<String>.fromIterable(sampleLines);

    await for (final e in FlatConfig.parseEntriesFromStringStream(lineStream)) {
      stdout.writeln('    ${e.key} = ${e.value ?? "null"}');
    }
  }

  // 4) strict vs lax difference visible
  {
    stdout.writeln('\n⚖️ strict vs lax:');

    final badLines = ['onlykey', 'good = ok', ' = emptykey', 'x=1'];

    // lax
    final laxDoc = await FlatConfig.parseFromStringStream(
      Stream<String>.fromIterable(badLines),
      options: FlatParseOptions(
        strict: false,
        onMissingEquals: (ln, line) =>
            stderr.writeln('  [lax warn] missing "=" in line $ln: $line'),
        onEmptyKey: (ln, line) =>
            stderr.writeln('  [lax warn] empty key in line $ln: $line'),
      ),
    );
    stdout.writeln('lax result:');
    _dump(laxDoc);

    // strict
    stdout.writeln('strict result:');
    try {
      final strictDoc = await FlatConfig.parseFromStringStream(
        Stream<String>.fromIterable(badLines),
        options: const FlatParseOptions(strict: true),
      );
      _dump(strictDoc);
    } on FormatException catch (e) {
      stderr.writeln('  [strict error] $e');
    }
  }
}

void _dump(FlatDocument doc) {
  stdout.writeln(doc.toPrettyString(
    includeIndexes: true,
    sortByKey: false,
    alignColumns: true,
  ));

  // a few accessor examples
  final enabled = doc.getBool('fullscreen');
  final w = doc.getInt('width');
  final h = doc.getInt('height');
  final colorCss = doc.getHexColor('colors.primary', cssAlphaAtEnd: true);
  final colorArgb = doc.getHexColor('colors.primary', cssAlphaAtEnd: false);

  stdout
    ..writeln('  -> fullscreen: $enabled')
    ..writeln('  -> size: ${w}x$h')
    ..writeln('  -> primary (CSS RRGGBBAA): ${colorCss?.toRadixString(16)}')
    ..writeln('  -> primary (AARRGGBB):    ${colorArgb?.toRadixString(16)}');
}
