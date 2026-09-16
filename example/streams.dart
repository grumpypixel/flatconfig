import 'dart:async';
import 'dart:convert' show LineSplitter, utf8;
import 'dart:io';

import 'package:flatconfig/flatconfig_io.dart';

// Reuse the same options everywhere. One handler covers every kind of
// problem, so nothing here changes when the parser learns to report a new one.
final laxWithWarn = FlatParseOptions(
  // strict stays false → unparseable lines are skipped, not thrown
  onIssue: (issue) {
    stderr.writeln('  [warn] line ${issue.line}: ${issue.message}');
  },
);

Future<void> main(List<String> args) async {
  final useStdin = args.contains('--stdin');

  if (useStdin) {
    stdout.writeln('📥 Reading from stdin (bytes → parseBytes):');
    final doc = await FlatDocument.parseBytes(
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
    stdout.writeln('🔌 parseBytes (utf8 bytes):');
    final bytes = utf8.encode(sampleLines.join('\n'));
    final byteStream = Stream<List<int>>.value(bytes);

    final doc = await FlatDocument.parseBytes(
      byteStream,
      options: laxWithWarn,
      readOptions: const FlatStreamReadOptions(
        encoding: utf8,
        lineSplitter: LineSplitter(), // robust \r\n/\n/\r
      ),
    );

    _dump(doc);
  }

  // 2) Already split into lines, with strict showing the exception path
  {
    stdout.writeln('\n🔤 parseLines (already split):');
    try {
      final doc = FlatDocument.parseLines(
        sampleLines,
        options: const FlatParseOptions(strict: true),
      );
      _dump(doc);
    } on FormatException catch (e) {
      stderr.writeln('  [strict error] $e');
    }
  }

  // 3) Lazy: process individual entries while reading from a BYTES stream
  {
    stdout.writeln('\n🐢 streamEntries (byte stream) [lazy]:');
    final bytes = utf8.encode(sampleLines.join('\n'));
    final byteStream = Stream<List<int>>.value(bytes);

    await for (final e in FlatDocument.streamEntries(byteStream)) {
      stdout.writeln('    ${e.key} = ${e.value ?? "null"}');
    }
  }

  // 4) strict vs lax difference visible
  {
    stdout.writeln('\n⚖️ strict vs lax:');

    final badLines = ['onlykey', 'good = ok', ' = emptykey', 'x=1'];

    // lax
    final laxDoc = FlatDocument.parseLines(
      badLines,
      options: FlatParseOptions(
        strict: false,
        onIssue: (issue) => stderr.writeln(
          '  [lax warn] ${issue.kind.name} at line ${issue.line}, '
          'column ${issue.column}: ${issue.rawLine}',
        ),
      ),
    );
    stdout.writeln('lax result:');
    _dump(laxDoc);

    // strict
    stdout.writeln('strict result:');
    try {
      final strictDoc = FlatDocument.parseLines(
        badLines,
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
  final colorCss = doc.getAs('colors.primary', _parseArgb);
  final colorArgb = doc.getAs(
    'colors.primary',
    (v) => _parseArgb(v, cssAlphaAtEnd: false),
  );

  stdout
    ..writeln('  -> fullscreen: $enabled')
    ..writeln('  -> size: ${w}x$h')
    ..writeln('  -> primary (CSS RRGGBBAA): ${colorCss?.toRadixString(16)}')
    ..writeln('  -> primary (AARRGGBB):    ${colorArgb?.toRadixString(16)}');
}

/// Parses `RRGGBB` or `RRGGBBAA` into a packed ARGB integer.
///
/// getHexColor used to ship with the package. It is a presentation decision,
/// not a format one, so it now lives where the presentation does.
int _parseArgb(String value, {bool cssAlphaAtEnd = true}) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) {
    throw FormatException('Expected RRGGBB or RRGGBBAA', value);
  }

  final n = int.parse(hex, radix: 16);
  if (hex.length == 6) {
    return 0xFF000000 | n;
  }

  return cssAlphaAtEnd ? (n & 0xFF) << 24 | (n >> 8) & 0xFFFFFF : n;
}
