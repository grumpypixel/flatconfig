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
      await tempDir.delete(recursive: true);
    });

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
foreground = ffffff
cursor = 00ff00
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['font-size'], equals('14'));
      expect(doc['foreground'], equals('ffffff'));
      expect(doc['cursor'], equals('00ff00'));

      // Verify order (main file entries come first, then includes)
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('background'));
      expect(entries[1].key, equals('font-size'));
      expect(entries[2].key, equals('foreground'));
      expect(entries[3].key, equals('cursor'));
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
foreground = ffffff
cursor = 00ff00
''');

      // Create keybindings config file
      final keybindingsFile = File('${tempDir.path}/keybindings.conf');
      await keybindingsFile.writeAsString('''
copy = ctrl+c
paste = ctrl+v
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
config-file = colors.conf
''');

      // Create colors config file
      final colorsFile = File('${tempDir.path}/colors.conf');
      await colorsFile.writeAsString('''
cursor = 00ff00
selection = 444444
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Don't create optional.conf - it should be silently ignored

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify only required entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

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
foreground = ffffff
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
config-file = main.conf
''');

      // Parse with includes should throw CircularIncludeException
      expect(
        () => FlatConfigIncludes.parseWithIncludes(mainFile),
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
        await FlatConfigIncludes.parseWithIncludes(mainFile);
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
background = ffffff
foreground = 000000
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify that the include's background value takes precedence
      // (Ghostty semantics: includes are processed after current file)
      expect(doc['background'], equals('ffffff'));
      expect(doc['foreground'], equals('000000'));

      // Verify order
      final entries = doc.entries.toList();
      expect(entries[0].key, equals('background'));
      expect(entries[0].value, equals('343028'));
      expect(entries[1].key, equals('background'));
      expect(entries[1].value, equals('ffffff'));
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
foreground = ffffff
''');

      // Parse with includes using path
      final doc =
          await FlatConfigIncludes.parseWithIncludesFromPath(mainFile.path);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Parse with includes using File extension
      final doc = await mainFile.parseFlatWithIncludes();

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
    });

    test('parseFlatFileWithIncludes convenience function', () async {
      // Create main config file
      final mainFile = File('${tempDir.path}/main.conf');
      await mainFile.writeAsString('''
background = 343028
config-file = theme.conf
''');

      // Create included config file
      final themeFile = File('${tempDir.path}/theme.conf');
      await themeFile.writeAsString('''
foreground = ffffff
''');

      // Parse with includes using convenience function
      final doc = await parseFlatFileWithIncludes(mainFile.path);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Parse with includes using custom options
      final doc = await FlatConfigIncludes.parseWithIncludes(
        mainFile,
        options: const FlatParseOptions(commentPrefix: '//'),
      );

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Create plugins config file
      final pluginsFile = File('${tempDir.path}/plugins.conf');
      await pluginsFile.writeAsString('''
plugin1 = enabled
plugin2 = disabled
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['app-name'], equals('MyApp'));
      expect(doc['theme'], equals('dark'));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

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
foreground = ffffff
''');

      // Parse with custom include key
      final doc = await FlatConfigIncludes.parseWithIncludes(
        mainFile,
        options: const FlatParseOptions(includeKey: 'include'),
      );

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
      final doc = await FlatConfigIncludes.parseWithIncludes(
        mainFile,
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
foreground = ffffff
''');

      // Create ignored config file
      final ignoredFile = File('${tempDir.path}/ignored.conf');
      await ignoredFile.writeAsString('''
ignored = true
''');

      // Parse with custom include key
      final doc = await FlatConfigIncludes.parseWithIncludes(
        mainFile,
        options: const FlatParseOptions(includeKey: 'include'),
      );

      // Verify only the custom include key was processed
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Don't create optional.conf - it should be silently ignored

      // Parse with custom include key
      final doc = await FlatConfigIncludes.parseWithIncludes(
        mainFile,
        options: const FlatParseOptions(includeKey: 'include'),
      );

      // Verify only the existing include was processed
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
''');

      // Parse with includes
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify all entries are present
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
      final doc = await FlatConfigIncludes.parseWithIncludes(mainFile);

      // Verify only main entries are present
      expect(doc['background'], equals('343028'));
      expect(doc.length, equals(1));
    });

    test('main file does not exist throws exception', () async {
      // Create a reference to a non-existent main file
      final mainFile = File('${tempDir.path}/nonexistent.conf');

      // Parse with includes should throw MissingIncludeException
      try {
        await FlatConfigIncludes.parseWithIncludes(mainFile);
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
        <String>{},
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
        <String>{},
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
        <String>{},
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
foreground = ffffff
''');

      // Test the parseWithIncludesRecursive method directly
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        testFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
      );

      // Verify the document was parsed correctly
      expect(doc.length, equals(2));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
foreground = ffffff
font-size = 14
''');

      // Test the parseWithIncludesRecursive method directly
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        mainFile,
        options: const FlatParseOptions(),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
      );

      // Verify Ghostty semantics: later entries do not override includes
      expect(doc.length, equals(3));
      expect(doc['background'], equals('343028')); // From main file
      expect(
          doc['foreground'], equals('ffffff')); // From include (not overridden)
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
foreground = ffffff
''');

      // Test with custom include key
      final doc = await FlatConfigIncludes.parseWithIncludesRecursive(
        mainFile,
        options: const FlatParseOptions(includeKey: 'include'),
        readOptions: const FlatStreamReadOptions(),
        visited: <String>{},
      );

      // Verify the include was processed
      expect(doc.length, equals(2));
      expect(doc['background'], equals('343028'));
      expect(doc['foreground'], equals('ffffff'));
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
      );

      // Verify only main entries are present
      expect(doc.length, equals(1));
      expect(doc['background'], equals('343028'));
    });
  });
}
