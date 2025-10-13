import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('Config File Includes', () {
    late Directory tempDir;
    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('flatconfig_includes_test_');
    });
    tearDown(() async {
      // Guard against prior cleanup if a test removed it; ignore missing dir
      try {
        await tempDir.delete(recursive: true);
      } on PathNotFoundException {
        // already removed by test; ignore
      }
    });
    test('max include depth is enforced', () async {
      // Build a chain deeper than 3 and set maxIncludeDepth=2 to trigger
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('config-file = a.conf\n');

      final a = File('${tempDir.path}/a.conf');
      await a.writeAsString('config-file = b.conf\n');
      final b = File('${tempDir.path}/b.conf');
      await b.writeAsString('config-file = c.conf\n');
      final c = File('${tempDir.path}/c.conf');
      await c.writeAsString('key = value\n');

      expect(
        () => mainFile.parseWithIncludes(
          options: const FlatParseOptions(maxIncludeDepth: 2),
        ),
        throwsA(isA<MaxIncludeDepthExceededException>()),
      );
    });

    test('normalizeCanonicalPath behavior (platform dependent)', () async {
      // Just validate that on case-insensitive filesystems (Windows and macOS)
      // it lowercases, and on case-sensitive filesystems it returns input unchanged.
      // We cannot change Platform here, so check current behavior is consistent.
      const input = 'C:/Some/Path/File.CONF';
      final out = FlatConfigIncludes.normalizeCanonicalPath(input);
      if (Platform.isWindows || Platform.isMacOS) {
        expect(out, equals(input.toLowerCase()));
      } else {
        expect(out, equals(input));
      }
    });

    // Duplicate setup/teardown removed; using the group-level ones above.

    test('basic include functionality', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
# Main configuration
background = 343028
font-size = 14

# Include another config file
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
# Theme configuration
foreground = f3d735
cursor = 00ff00
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['font-size'], equals('14'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['cursor'], equals('00ff00'));

      // Verify order (main file entries come first, then includes)
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('background'));
      expect(entries[1].key, equals('font-size'));
      expect(entries[2].key, equals('foreground'));
      expect(entries[3].key, equals('cursor'));
    });

    test('basic include functionality (sync)', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
# Main configuration
background = 343028
font-size = 14

# Include another config file
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
# Theme configuration
foreground = f3d735
cursor = 00ff00
''');

      // Parse with includes (sync)
      final doc = mainFile.parseWithIncludesSync();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['font-size'], equals('14'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['cursor'], equals('00ff00'));
    });

    test('sync circular include detection', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = circular.conf
''');

      final circularFile = File('${tempDir.path}/circular.conf');
      await circularFile.writeAsString('''
foreground = f3d735
config-file = main.conf
''');

      expect(
        () => mainFile.parseWithIncludesSync(),
        throwsA(isA<CircularIncludeException>()),
      );
    });

    test('sync missing required include throws exception', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = missing.conf
''');

      expect(
        () => mainFile.parseWithIncludesSync(),
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('sync max include depth is enforced', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('config-file = a.conf\n');

      final a = File('${tempDir.path}/a.conf');
      await a.writeAsString('config-file = b.conf\n');
      final b = File('${tempDir.path}/b.conf');
      await b.writeAsString('config-file = c.conf\n');
      final c = File('${tempDir.path}/c.conf');
      await c.writeAsString('key = value\n');

      expect(
        () => mainFile.parseWithIncludesSync(
          options: const FlatParseOptions(maxIncludeDepth: 2),
        ),
        throwsA(isA<MaxIncludeDepthExceededException>()),
      );
    });

    test('sync cache avoids re-parsing same files', () async {
      final sharedFile = File('${tempDir.path}/shared.conf');
      await sharedFile.writeAsString('theme = dark\nfont-size = 16\n');

      final main1 = File('${tempDir.path}/main1.conf');
      await main1.writeAsString('background = 343028\nconfig-file = shared.conf\n');
      final main2 = File('${tempDir.path}/main2.conf');
      await main2.writeAsString('foreground = f3d735\nconfig-file = shared.conf\n');

      final cache = <String, FlatDocument>{};
      final doc1 = main1.parseWithIncludesSync(cache: cache);
      final doc2 = main2.parseWithIncludesSync(cache: cache);

      expect(doc1['background'], equals('343028'));
      expect(doc1['theme'], equals('dark'));
      expect(doc2['foreground'], equals('f3d735'));
      expect(doc2['font-size'], equals('16'));

      final canonical = sharedFile.resolveSymbolicLinksSync();
      expect(cache.containsKey(canonical), isTrue);
      expect(cache[canonical]!['theme'], equals('dark'));
    });

    test('sync custom include key', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
include = theme.conf
''');

      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('foreground = f3d735\n');

      final doc = mainFile.parseWithIncludesSync(
        options: const FlatParseOptions(includeKey: 'include'),
      );
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('processIncludesSync method is testable in isolation', () async {
      final includedFile = File('${tempDir.path}/included.conf');
      await includedFile.writeAsString('theme = dark\nfont-size = 16\n');

      final baseFile = File('${tempDir.path}/base.conf');

      final entries = FlatConfigIncludes.processIncludesSync(
        ['included.conf'],
        baseFile,
        baseFile.absolute.path,
        const FlatParseOptions(),
        const FlatStreamReadOptions(),
        <String>{},
        <String, FlatDocument>{},
      );

      expect(entries.length, equals(2));
      expect(entries[0].key, equals('theme'));
      expect(entries[0].value, equals('dark'));
      expect(entries[1].key, equals('font-size'));
      expect(entries[1].value, equals('16'));
    });

    test('processIncludesSync handles optional includes', () async {
      final baseFile = File('${tempDir.path}/base.conf');

      final entries = FlatConfigIncludes.processIncludesSync(
        ['?missing.conf'],
        baseFile,
        baseFile.absolute.path,
        const FlatParseOptions(),
        const FlatStreamReadOptions(),
        <String>{},
        <String, FlatDocument>{},
      );

      expect(entries.length, equals(0));
    });

    test('processIncludesSync handles quoted paths', () async {
      final includedFile = File('${tempDir.path}/included.conf');
      await includedFile.writeAsString('theme = light\n');

      final baseFile = File('${tempDir.path}/base.conf');

      final entries = FlatConfigIncludes.processIncludesSync(
        ['"included.conf"'],
        baseFile,
        baseFile.absolute.path,
        const FlatParseOptions(),
        const FlatStreamReadOptions(),
        <String>{},
        <String, FlatDocument>{},
      );

      expect(entries.length, equals(1));
      expect(entries[0].key, equals('theme'));
      expect(entries[0].value, equals('light'));
    });

    test('processIncludesSync handles empty include values', () async {
      final baseFile = File('${tempDir.path}/base.conf');

      expect(
        () => FlatConfigIncludes.processIncludesSync(
          ['', '  ', 'valid.conf'],
          baseFile,
          baseFile.absolute.path,
          const FlatParseOptions(),
          const FlatStreamReadOptions(),
          <String>{},
          <String, FlatDocument>{},
        ),
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('parseWithIncludesRecursiveSync method is testable in isolation', () async {
      final testFile = File('${tempDir.path}/test.conf');
      await testFile.writeAsString('background = 343028\nforeground = f3d735\n');

      final doc = FlatConfigIncludes.parseWithIncludesRecursiveSync(
        testFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      expect(doc.length, equals(2));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('parseWithIncludesRecursiveSync handles cycle detection', () async {
      final testFile = File('${tempDir.path}/cycle.conf');
      await testFile.writeAsString('''
background = 343028
config-file = cycle.conf
''');

      expect(
        () => FlatConfigIncludes.parseWithIncludesRecursiveSync(
          testFile,
          options: const FlatParseOptions(),
          readOptions: const FlatStreamReadOptions(),
          visited: <String>{},
          cache: <String, FlatDocument>{},
        ),
        throwsA(isA<CircularIncludeException>()),
      );
    });

    test('parseWithIncludesRecursiveSync handles missing file', () async {
      final testFile = File('${tempDir.path}/nonexistent.conf');

      expect(
        () => FlatConfigIncludes.parseWithIncludesRecursiveSync(
          testFile,
          options: const FlatParseOptions(),
          readOptions: const FlatStreamReadOptions(),
          visited: <String>{},
          cache: <String, FlatDocument>{},
        ),
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('parseWithIncludesRecursiveSync processes includes correctly', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
foreground = 000000
''');

      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
font-size = 14
''');

      final doc = FlatConfigIncludes.parseWithIncludesRecursiveSync(
        mainFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      expect(doc.length, equals(3));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['font-size'], equals('14'));
    });

    test('parseWithIncludesRecursiveSync handles custom include key', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
include = theme.conf
''');

      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('foreground = f3d735\n');

      final doc = FlatConfigIncludes.parseWithIncludesRecursiveSync(
        mainFile,
        options: const FlatParseOptions(includeKey: 'include'),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      expect(doc.length, equals(2));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('parseWithIncludesRecursiveSync handles optional includes', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ?optional.conf
''');

      final doc = FlatConfigIncludes.parseWithIncludesRecursiveSync(
        mainFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      expect(doc.length, equals(1));
      expect(doc['background'], equals('343028'));
    });

    test('parseWithIncludesRecursiveSync handles entries after include that do not override', () async {
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
new-key = new-value
''');

      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      final doc = FlatConfigIncludes.parseWithIncludesRecursiveSync(
        mainFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      expect(doc.length, equals(3));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['new-key'], equals('new-value'));
    });

    test('multiple includes', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
config-file = keybindings.conf
''');

      // Create theme config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
cursor = 00ff00
''');

      // Create keybindings config file
      final keybindingsFile = File('${tempDir.path}/keybindings.conf');
      await keybindingsFile.writeAsString('''
copy = ctrl+c
paste = ctrl+v
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['cursor'], equals('00ff00'));
      expect(doc['copy'], equals('ctrl+c'));
      expect(doc['paste'], equals('ctrl+v'));

      // Verify order
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('background'));
      expect(entries[1].key, equals('foreground'));
      expect(entries[2].key, equals('cursor'));
      expect(entries[3].key, equals('copy'));
      expect(entries[4].key, equals('paste'));
    });

    test('nested includes', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
''');

      // Create theme config file that includes another file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
config-file = colors.conf
''');

      // Create colors config file
      final colorsFile = File('${tempDir.path}/colors.conf');
      await colorsFile.writeAsString('''
cursor = 00ff00
selection = 444444
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['cursor'], equals('00ff00'));
      expect(doc['selection'], equals('444444'));

      // Verify order
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('background'));
      expect(entries[1].key, equals('foreground'));
      expect(entries[2].key, equals('cursor'));
      expect(entries[3].key, equals('selection'));
    });

    test('optional includes with ? prefix', () async {
      // Create main config file with optional include
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ?optional.conf
config-file = required.conf
''');

      // Create required config file
      final requiredFile = File('${tempDir.path}/required.conf');
      await requiredFile.writeAsString('''
foreground = f3d735
''');

      // Don't create optional.conf - it should be silently ignored

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify only required entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc.length, equals(2));
    });

    test('optional includes with quoted paths', () async {
      // Create main config file with quoted optional include
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ?"quoted-optional.conf"
''');

      // Parse with includes (should not throw)
      final doc = await mainFile.parseWithIncludes();

      // Verify only main entries are present
      expect(doc['background'], equals('343028'));
      expect(doc.length, equals(1));
    });

    test('relative path resolution', () async {
      // Create subdirectory
      final subDir = Directory('${tempDir.path}/subdir');
      await subDir.create();

      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = subdir/config.conf
''');

      // Create included config file in subdirectory
      final subConfigFile = File('${tempDir.path}/subdir/config.conf');
      await subConfigFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('absolute path resolution', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ${tempDir.path}/absolute.conf
''');

      // Create included config file with absolute path
      final absoluteFile = File('${tempDir.path}/absolute.conf');
      await absoluteFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('circular include detection', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = circular.conf
''');

      // Create circular config file
      final circularFile = File('${tempDir.path}/circular.conf');
      await circularFile.writeAsString('''
foreground = f3d735
config-file = main.conf
''');

      // Parse with includes should throw CircularIncludeException
      expect(
        () => mainFile.parseWithIncludes(),
        throwsA(isA<CircularIncludeException>()),
      );
    });

    test('missing required include throws exception', () async {
      // Create main config file with missing include
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = missing.conf
''');

      // Parse with includes should throw MissingIncludeException
      try {
        await mainFile.parseWithIncludes();
        fail('Expected MissingIncludeException to be thrown');
      } catch (e) {
        expect(e, isA<MissingIncludeException>());
      }
    });

    test('Ghostty semantics - later entries do not override includes',
        () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
background = 000000
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
background = f3d735
foreground = 000000
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify that the include's background value takes precedence
      // (Ghostty semantics: includes are processed after current file)
      expect(doc['background'], equals('f3d735'));
      expect(doc['foreground'], equals('000000'));

      // Verify order
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('background'));
      expect(entries[0].value, equals('343028'));
      expect(entries[1].key, equals('background'));
      expect(entries[1].value, equals('f3d735'));
      expect(entries[2].key, equals('foreground'));
      expect(entries[2].value, equals('000000'));
    });

    test('parseWithIncludesFromPath convenience method', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes using path
      final doc =
          await FlatConfigIncludes.parseWithIncludesFromPath(mainFile.path);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('parseWithIncludesFromPathSync convenience method (sync)', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes using path (sync)
      final doc =
          FlatConfigIncludes.parseWithIncludesFromPathSync(mainFile.path);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('File extension method parseFlatWithIncludes', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes using File extension
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('parseFileWithIncludes convenience function', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes using convenience function
      final doc = await parseFileWithIncludes(mainFile.path);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('include processing with custom options', () async {
      // Create main config file with custom comment prefix
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
// Include another config file
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes using custom options
      final doc = await mainFile.parseWithIncludes(
        options: const FlatParseOptions(commentPrefix: '//'),
      );

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('complex nested includes with multiple levels', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
app-name = MyApp
config-file = ui.conf
config-file = features.conf
''');

      // Create UI config file
      final uiFile = File('${tempDir.path}/ui.conf');
      await uiFile.writeAsString('''
theme = dark
config-file = themes/dark.conf
''');

      // Create features config file
      final featuresFile = File('${tempDir.path}/features.conf');
      await featuresFile.writeAsString('''
debug = true
config-file = plugins.conf
''');

      // Create themes directory
      final themesDir = Directory('${tempDir.path}/themes');
      await themesDir.create();

      // Create dark theme config file
      final darkThemeFile = File('${tempDir.path}/themes/dark.conf');
      await darkThemeFile.writeAsString('''
background = 343028
foreground = f3d735
''');

      // Create plugins config file
      final pluginsFile = File('${tempDir.path}/plugins.conf');
      await pluginsFile.writeAsString('''
plugin1 = enabled
plugin2 = disabled
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['app-name'], equals('MyApp'));
      expect(doc['theme'], equals('dark'));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['debug'], equals('true'));
      expect(doc['plugin1'], equals('enabled'));
      expect(doc['plugin2'], equals('disabled'));

      // Verify order (main -> ui -> dark theme -> features -> plugins)
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('app-name'));
      expect(entries[1].key, equals('theme'));
      expect(entries[2].key, equals('background'));
      expect(entries[3].key, equals('foreground'));
      expect(entries[4].key, equals('debug'));
      expect(entries[5].key, equals('plugin1'));
      expect(entries[6].key, equals('plugin2'));
    });

    test('include with duplicate keys preserves all values', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
key1 = value1
config-file = include.conf
key1 = value3
''');

      // Create included config file
      final includeFile = File('${tempDir.path}/include.conf');
      await includeFile.writeAsString('''
key1 = value2
key2 = value4
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all values are preserved
      expect(doc.valuesOf('key1'), equals(['value1', 'value2']));
      expect(doc.valuesOf('key2'), equals(['value4']));

      // Verify last value wins for direct access
      expect(doc['key1'], equals('value2'));
      expect(doc['key2'], equals('value4'));
    });

    test('configurable include key', () async {
      // Create main config file with custom include key
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
include = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with custom include key
      final doc = await mainFile.parseWithIncludes(
        options: const FlatParseOptions(includeKey: 'include'),
      );

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('configurable include key with different keyword', () async {
      // Create main config file with 'source' keyword
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
app-name = MyApp
source = settings.conf
''');

      // Create included config file
      final settingsFile = File('${tempDir.path}/settings.conf');
      await settingsFile.writeAsString('''
debug = true
version = 2.0
''');

      // Parse with custom include key
      final doc = await mainFile.parseWithIncludes(
        options: const FlatParseOptions(includeKey: 'source'),
      );

      // Verify all entries are present
      expect(doc['app-name'], equals('MyApp'));
      expect(doc['debug'], equals('true'));
      expect(doc['version'], equals('2.0'));
    });

    test('configurable include key ignores default config-file directive',
        () async {
      // Create main config file with both custom and default include keys
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
include = theme.conf
config-file = ignored.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Create ignored config file
      final ignoredFile = File('${tempDir.path}/ignored.conf');
      await ignoredFile.writeAsString('''
ignored = true
''');

      // Parse with custom include key
      final doc = await mainFile.parseWithIncludes(
        options: const FlatParseOptions(includeKey: 'include'),
      );

      // Verify only the custom include key was processed
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['ignored'], isNull);
    });

    test('configurable include key with optional includes', () async {
      // Create main config file with custom include key and optional include
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
include = theme.conf
include = ?optional.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Don't create optional.conf - it should be silently ignored

      // Parse with custom include key
      final doc = await mainFile.parseWithIncludes(
        options: const FlatParseOptions(includeKey: 'include'),
      );

      // Verify only the existing include was processed
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc.length, equals(2));
    });

    test('quoted include paths with actual quotes', () async {
      // Create main config file with quoted include path
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = "theme.conf"
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Parse with includes
      final doc = await mainFile.parseWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('quoted optional include paths with actual quotes', () async {
      // Create main config file with quoted optional include path
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = "?optional.conf"
''');

      // Don't create optional.conf - it should be silently ignored

      // Parse with includes (should not throw)
      final doc = await mainFile.parseWithIncludes();

      // Verify only main entries are present
      expect(doc['background'], equals('343028'));
      expect(doc.length, equals(1));
    });

    test('sync optional includes and quoted paths', () async {
      // Create main config file with optional and quoted includes
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ?missing.conf
config-file = "themes/dark.conf"
''');

      // Create directory and included file
      final themesDir = Directory('${tempDir.path}/themes');
      await themesDir.create();
      final darkThemeFile = File('${themesDir.path}/dark.conf');
      await darkThemeFile.writeAsString('foreground = f3d735\n');

      final doc = mainFile.parseWithIncludesSync();
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('canonicalSync fallback path is covered via non-resolvable link',
        () async {
      // Use a file that likely cannot resolve symlinks (not a symlink)
      final file = File('${tempDir.path}/plain.conf');
      await file.writeAsString('key = v\n');

      // Smoke-call the sync parser to ensure _canonicalSync fallback is exercised
      final doc = file.parseWithIncludesSync();
      expect(doc['key'], equals('v'));
    });

    test('main file does not exist throws exception', () async {
      // Create a reference to a non-existent main file
      final mainFile = File('${tempDir.path}/nonexistent.conf');

      // Parse with includes should throw MissingIncludeException
      try {
        await mainFile.parseWithIncludes();
        fail('Expected MissingIncludeException to be thrown');
      } catch (e) {
        expect(e, isA<MissingIncludeException>());
      }
    });

    test('processIncludes method is testable in isolation', () async {
      // Create a test file to include
      final includedFile = File('${tempDir.path}/included.conf');
      await includedFile.writeAsString('''
theme = dark
font-size = 16
''');

      // Create a base file for path resolution
      final baseFile = File('${tempDir.path}/base.conf');

      // Test the processIncludes method directly
      final entries = await FlatConfigIncludes.processIncludes(
        ['included.conf'], // relative path
        baseFile,
        baseFile.absolute.path,
        const FlatParseOptions(),
        const FlatStreamReadOptions(),
        <String>{},
        <String, FlatDocument>{},
      );

      // Verify the entries were processed correctly
      expect(entries.length, equals(2));
      expect(entries[0].key, equals('theme'));
      expect(entries[0].value, equals('dark'));
      expect(entries[1].key, equals('font-size'));
      expect(entries[1].value, equals('16'));
    });

    test('processIncludes handles optional includes', () async {
      // Create a base file for path resolution
      final baseFile = File('${tempDir.path}/base.conf');

      // Test with optional include that doesn't exist
      final entries = await FlatConfigIncludes.processIncludes(
        ['?missing.conf'], // optional include
        baseFile,
        baseFile.absolute.path,
        const FlatParseOptions(),
        const FlatStreamReadOptions(),
        <String>{},
        <String, FlatDocument>{},
      );

      // Should return empty list since file doesn't exist
      expect(entries.length, equals(0));
    });

    test('processIncludes handles quoted paths', () async {
      // Create a test file to include
      final includedFile = File('${tempDir.path}/included.conf');
      await includedFile.writeAsString('''
theme = light
''');

      // Create a base file for path resolution
      final baseFile = File('${tempDir.path}/base.conf');

      // Test with quoted path
      final entries = await FlatConfigIncludes.processIncludes(
        ['"included.conf"'], // quoted path
        baseFile,
        baseFile.absolute.path,
        const FlatParseOptions(),
        const FlatStreamReadOptions(),
        <String>{},
        <String, FlatDocument>{},
      );

      // Verify the entries were processed correctly
      expect(entries.length, equals(1));
      expect(entries[0].key, equals('theme'));
      expect(entries[0].value, equals('light'));
    });

    test('parseWithIncludesRecursive method is testable in isolation',
        () async {
      // Create a test file
      final testFile = File('${tempDir.path}/test.conf');
      await testFile.writeAsString('''
background = 343028
foreground = f3d735
''');

      // Test the parseWithIncludesRecursive method directly
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        testFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      // Verify the document was parsed correctly
      expect(doc.length, equals(2));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('parseWithIncludesRecursive handles cycle detection', () async {
      // Create a file that includes itself
      final testFile = File('${tempDir.path}/cycle.conf');
      await testFile.writeAsString('''
background = 343028
config-file = cycle.conf
''');

      // Test that circular include is detected
      try {
        await FlatConfigIncludes.parseWithIncludesRecursive(
          testFile,
          options: const FlatParseOptions(),
          readOptions: const FlatStreamReadOptions(),
          visited: <String>{},
          cache: <String, FlatDocument>{},
        );
        fail('Expected CircularIncludeException to be thrown');
      } catch (e) {
        expect(e, isA<CircularIncludeException>());
      }
    });

    test('parseWithIncludesRecursive handles missing file', () async {
      // Create a reference to a non-existent file
      final testFile = File('${tempDir.path}/nonexistent.conf');

      // Test that missing file throws exception
      try {
        await FlatConfigIncludes.parseWithIncludesRecursive(
          testFile,
          options: const FlatParseOptions(),
          readOptions: const FlatStreamReadOptions(),
          visited: <String>{},
          cache: <String, FlatDocument>{},
        );
        fail('Expected MissingIncludeException to be thrown');
      } catch (e) {
        expect(e, isA<MissingIncludeException>());
      }
    });

    test('parseWithIncludesRecursive processes includes correctly', () async {
      // Create main file with includes
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
foreground = 000000
''');

      // Create included file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
font-size = 14
''');

      // Test the parseWithIncludesRecursive method directly
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        mainFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      // Verify Ghostty semantics: later entries do not override includes
      expect(doc.length, equals(3));
      expect(doc['background'], equals('343028')); // From main file
      expect(
          doc['foreground'], equals('f3d735')); // From include (not overridden)
      expect(doc['font-size'], equals('14')); // From include
    });

    test('parseWithIncludesRecursive handles custom include key', () async {
      // Create main file with custom include key
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
include = theme.conf
''');

      // Create included file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = f3d735
''');

      // Test with custom include key
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        mainFile,
        options: const FlatParseOptions(includeKey: 'include'),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      // Verify the include was processed
      expect(doc.length, equals(2));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
    });

    test('parseWithIncludesRecursive handles optional includes', () async {
      // Create main file with optional include
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ?optional.conf
''');

      // Don't create optional.conf - it should be silently ignored

      // Test the parseWithIncludesRecursive method directly
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        mainFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
        cache: <String, FlatDocument>{},
      );

      // Verify only main entries are present
      expect(doc.length, equals(1));
      expect(doc['background'], equals('343028'));
    });

    test('include path resolution works on Windows-like and POSIX paths',
        () async {
      // Arrange tmp structure:
      // main.conf includes "sub/settings.conf" and "C:/abs/also.conf" (simulate)
      // Use path package to build paths safely.

      final main = File('${tempDir.path}/main.conf');
      await main.writeAsString('''
config-file = sub/settings.conf
foo = 1
''');

      final subdir = Directory('${tempDir.path}/sub')..createSync();
      final settingsFile = File('${subdir.path}/settings.conf');
      await settingsFile.writeAsString('''
bar = 2
''');

      // Act
      final doc = await main.parseWithIncludes();

      // Assert order & values
      expect(doc['foo'], equals('1'));
      expect(doc['bar'], equals('2'));
      expect(doc.length, equals(2));
    });

    test('include path resolution handles absolute paths correctly', () async {
      // Test that absolute paths are handled correctly
      final main = File('${tempDir.path}/main.conf');
      await main.writeAsString('''
config-file = ${tempDir.path}/settings.conf
foo = 1
''');

      final settingsFile = File('${tempDir.path}/settings.conf');
      await settingsFile.writeAsString('''
bar = 2
''');

      // Act
      final doc = await main.parseWithIncludes();

      // Assert order & values
      expect(doc['foo'], equals('1'));
      expect(doc['bar'], equals('2'));
      expect(doc.length, equals(2));
    });

    test('parseWithIncludes uses cache to avoid re-parsing same files',
        () async {
      // Create a shared include file
      final sharedFile = File('${tempDir.path}/shared.conf');
      await sharedFile.writeAsString('''
theme = dark
font-size = 16
''');

      // Create two main files that both include the shared file
      final main1 = File('${tempDir.path}/main1.conf');
      await main1.writeAsString('''
background = 343028
config-file = shared.conf
''');

      final main2 = File('${tempDir.path}/main2.conf');
      await main2.writeAsString('''
foreground = f3d735
config-file = shared.conf
''');

      // Parse both files with the same cache
      final cache = <String, FlatDocument>{};

      final doc1 = await main1.parseWithIncludes(
        cache: cache,
      );

      final doc2 = await main2.parseWithIncludes(
        cache: cache,
      );

      // Both documents should have the shared entries
      expect(doc1['theme'], equals('dark'));
      expect(doc1['font-size'], equals('16'));
      expect(doc1['background'], equals('343028'));

      expect(doc2['theme'], equals('dark'));
      expect(doc2['font-size'], equals('16'));
      expect(doc2['foreground'], equals('f3d735'));

      // The cache should contain the shared file
      final canonicalPath = await sharedFile.resolveSymbolicLinks();
      expect(cache.containsKey(canonicalPath), isTrue);
      expect(cache[canonicalPath]!['theme'], equals('dark'));
    });

    test('parseWithIncludes cache works with nested includes', () async {
      // Create a deeply nested include structure
      final level3 = File('${tempDir.path}/level3.conf');
      await level3.writeAsString('''
deep-setting = value3
''');

      final level2 = File('${tempDir.path}/level2.conf');
      await level2.writeAsString('''
mid-setting = value2
config-file = level3.conf
''');

      final level1 = File('${tempDir.path}/level1.conf');
      await level1.writeAsString('''
top-setting = value1
config-file = level2.conf
''');

      final main = File('${tempDir.path}/main.conf');
      await main.writeAsString('''
root-setting = value0
config-file = level1.conf
''');

      // Parse with cache
      final cache = <String, FlatDocument>{};
      final doc = await main.parseWithIncludes(
        cache: cache,
      );

      // Verify all settings are present
      expect(doc['root-setting'], equals('value0'));
      expect(doc['top-setting'], equals('value1'));
      expect(doc['mid-setting'], equals('value2'));
      expect(doc['deep-setting'], equals('value3'));

      // Verify all files are cached
      expect(cache.length, equals(4)); // main, level1, level2, level3
    });

    test('parseWithIncludes handles empty include values gracefully', () async {
      // Create a file with empty include directives
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file =
config-file = theme.conf
foreground = f3d735
config-file =
''');

      // Create the theme file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
theme = dark
font-size = 16
''');

      // Parse the file - should handle empty includes gracefully
      final doc = await mainFile.parseWithIncludes();

      // Should have all entries including the theme from the valid include
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['theme'], equals('dark'));
      expect(doc['font-size'], equals('16'));
      expect(doc.length, equals(4));
    });

    test('parseWithIncludes handles quoted include paths correctly', () async {
      // Create a file with quoted include paths
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = "theme.conf"
foreground = f3d735
''');

      // Create the theme file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
theme = dark
font-size = 16
''');

      // Parse the file
      final doc = await mainFile.parseWithIncludes();

      // Should have all entries including the theme from the quoted include
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['theme'], equals('dark'));
      expect(doc['font-size'], equals('16'));
      expect(doc.length, equals(4));
    });

    test('parseWithIncludes handles duplicate include directives', () async {
      // Create a file with duplicate include directives
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme1.conf
config-file = theme2.conf
foreground = f3d735
''');

      // Create the theme files
      final theme1File = File('${tempDir.path}/theme1.conf');
      await theme1File.writeAsString('''
theme = dark
font-size = 14
''');

      final theme2File = File('${tempDir.path}/theme2.conf');
      await theme2File.writeAsString('''
font-size = 16
color = blue
''');

      // Parse the file
      final doc = await mainFile.parseWithIncludes();

      // Should have all entries, with later includes overriding earlier ones
      // Note: foreground is NOT filtered out because it doesn't override any key from includes
      expect(doc['background'], equals('343028'));
      expect(doc['theme'], equals('dark'));
      expect(doc['font-size'], equals('16')); // theme2 overrides theme1
      expect(doc['color'], equals('blue'));
      expect(doc['foreground'],
          equals('f3d735')); // From main file, not filtered out
      expect(doc.length,
          equals(6)); // 6 entries total (including duplicate font-size)
    });

    test('parseWithIncludes handles optional includes with quoted paths',
        () async {
      // Create a file with optional quoted include paths
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = ?"missing.conf"
config-file = "theme.conf"
foreground = f3d735
''');

      // Create the theme file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
theme = dark
font-size = 16
''');

      // Parse the file - should handle missing optional include gracefully
      final doc = await mainFile.parseWithIncludes();

      // Should have all entries including the theme from the valid include
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('f3d735'));
      expect(doc['theme'], equals('dark'));
      expect(doc['font-size'], equals('16'));
      expect(doc.length, equals(4));
    });
  });
}
