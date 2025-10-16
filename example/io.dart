import 'dart:io';
import 'dart:convert';
import 'package:flatconfig/flatconfig.dart';

Future<void> main() async {
  // Create a temp working folder for this example
  final tmpDir = await Directory.systemTemp.createTemp('flatconfig_example_');
  final cfgPath = '${tmpDir.path}/app.conf';
  final outPath = '${tmpDir.path}/out.conf';
  final outWinPath = '${tmpDir.path}/out_windows.conf';

  // 1) Write a small config file (UTF-8)
  const sample = '''
# App settings
fullscreen = true
size = " 1280x720 "   # quoted keeps inner spaces
theme = dark
volume = 75
colors.primary = #336699
colors.primary = #336699cc   # last value wins on collapse
servers = host=a,port=8080 | host=b,port=9090
''';

  await File(cfgPath).writeAsString(sample, encoding: utf8);

  // 2) Parse using the convenience function
  final docA = await parseFlatFile(cfgPath);
  print('🔍 Parsed via parseFlatFile:');
  print(docA.toPrettyString(alignColumns: true));

  // 3) Parse via File extension with custom parsing options
  final docB = await File(cfgPath).parseFlat(
    options: const FlatParseOptions(
      // strict: true, // uncomment to see errors on malformed lines
      decodeEscapesInQuoted: true,
    ),
    readOptions: const FlatStreamReadOptions(
      // You could switch the splitter if you stream exotic inputs
      // lineSplitter: LineSplitter(),
      encoding: utf8,
    ),
  );

  // Extract some values
  final fullscreen = docB.getBool('fullscreen') ?? false;
  final size = docB.getTrimmed('size'); // trimmed from quoted value
  final theme = docB.getStringOr('theme', 'light');
  final color = docB.getHexColor('colors.primary'); // ARGB as int
  final servers = docB.getListOfDocuments('servers') ?? const [];

  print('\n🎯 Accessed values:');
  print('  - fullscreen: $fullscreen');
  print('  - size: $size');
  print('  - theme: $theme');
  print('  - colors.primary (ARGB int): ${color?.toRadixString(16)}');

  for (var i = 0; i < servers.length; i++) {
    final s = servers[i];
    final host = s['host'];
    final port = s.getInt('port');
    print('  - server[$i]: host=$host, port=$port');
  }

  // 4) Collapse duplicate keys and write back (default encode options)
  final collapsed = docB.collapse(order: CollapseOrder.lastWrite);
  await File(outPath).writeFlat(collapsed);

  print('\n💾 Wrote collapsed config (UTF-8, default line endings): $outPath');

  // 5) Write with Windows line endings and forced quoting+escaping
  await File(outWinPath).writeFlat(
    collapsed,
    options: const FlatEncodeOptions(
      alwaysQuote: true,
      escapeQuoted: true,
    ),
    writeOptions: const FlatStreamWriteOptions(
      encoding: utf8,
      lineTerminator: '\r\n',
      ensureTrailingNewline: true,
    ),
  );

  print('💾 Wrote collapsed config (UTF-8, CRLF, always quoted): $outWinPath');

  // 6) Use FlatDocument.saveToFile (same as File.writeFlat but from doc side)
  final merged = collapsed.merge(
    FlatConfig.fromMap({
      'generated.by': 'example/io.dart',
      'generated.when': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  final savedPath = '${tmpDir.path}/merged.conf';
  await merged.saveToFile(
    savedPath,
    options: const FlatEncodeOptions(escapeQuoted: true),
    writeOptions: const FlatStreamWriteOptions(
      lineTerminator: '\n',
      ensureTrailingNewline: true,
    ),
  );

  print('💾 Saved merged config: $savedPath');

  // 7) Read back synchronously to demonstrate sync API
  final readBack = File(savedPath).parseFlatSync();
  print('\n📖 Read back (sync):');
  print(readBack.toPrettyString(alignColumns: true));

  // Cleanup hint (leave files around so you can inspect them)
  print('\n📂 Temp folder with outputs: ${tmpDir.path}');
  print('🧹 Inspect the files, then delete the folder if you like.\n');
}
