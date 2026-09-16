@TestOn('vm')
/// Imports nothing but the IO barrel, which re-exports the other two.
library barrel_io_test;

import 'dart:io';

import 'package:flatconfig/flatconfig_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flatconfig_barrel_io_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a file round-trips through the barrel', () async {
    final file = File('${tempDir.path}/config.flat');
    final doc = FlatDocument([FlatEntry('background', '343028')]);

    await file.writeFlat(doc);
    expect((await file.parseFlat())['background'], '343028');

    file.writeFlatSync(FlatDocument([FlatEntry('background', 'ffaa00')]));
    expect(file.parseFlatSync()['background'], 'ffaa00');
  });

  test('includes resolve against the including file', () async {
    await File('${tempDir.path}/theme.conf').writeAsString('theme = dark\n');
    final main = File('${tempDir.path}/main.conf');
    await main.writeAsString('config-file = theme.conf\n');

    expect((await main.parseWithIncludes())['theme'], 'dark');
    expect(main.parseWithIncludesSync()['theme'], 'dark');
  });

  test('FileIncludeResolver reads a unit from disk', () {
    final file = File('${tempDir.path}/unit.conf')
      ..writeAsStringSync('k = file\n');

    final unit = FileIncludeResolver().resolveSync(IncludeRequest(file.path));

    expect(unit?.content, contains('k = file'));
  });

  test('the core and include barrels come along', () {
    expect(FlatDocument.parse('a = 1\n').requireInt('a'), 1);
    expect(
      parseWithIncludesSync(
        'config-file = a\n',
        resolver: MemoryIncludeResolver(const {'a': 'k = v\n'}),
      )['k'],
      'v',
    );
  });
}
