import 'dart:io';

import 'package:flatconfig/flatconfig.dart';

void main() async {
  // Create a temporary directory for our example
  final tempDir =
      await Directory.systemTemp.createTemp('flatconfig_includes_example_');

  try {
    // Create main configuration file
    final mainFile = File('${tempDir.path}/main.conf');
    await mainFile.writeAsString('''
# Main application configuration
app-name = MyAwesomeApp
version = 1.0.0
debug = false

# Include theme configuration
config-file = theme.conf

# Include user-specific settings (optional)
config-file = ?user.conf

# These settings will not override the included files
# because they come after config-file directives
theme = custom
user-name = admin
''');

    // Create theme configuration file
    final themeFile = File('${tempDir.path}/theme.conf');
    await themeFile.writeAsString('''
# Theme configuration
theme = dark
background = 343028
foreground = f3d735
cursor = 00ff00
selection = 444444

# Include color palette
config-file = colors.conf
''');

    // Create colors configuration file
    final colorsFile = File('${tempDir.path}/colors.conf');
    await colorsFile.writeAsString('''
# Color palette
primary = 007acc
secondary = 6c757d
success = 28a745
warning = ffc107
danger = dc3545
''');

    // Create user configuration file (this will be included)
    final userFile = File('${tempDir.path}/user.conf');
    await userFile.writeAsString('''
# User-specific settings
user-name = grumpypixel
preferred-editor = micro
auto-save = true
''');

    print('📁 Created example configuration files:');
    print('  - ${mainFile.path}');
    print('  - ${themeFile.path}');
    print('  - ${colorsFile.path}');
    print('  - ${userFile.path}');
    print('');

    // Parse the main configuration file with includes
    print('🔍 Parsing configuration with includes...');
    final doc = await mainFile.parseWithIncludes();

    print('✅ Configuration parsed successfully!');
    print('');

    // Display all configuration entries
    print('📋 Final configuration:');
    for (final entry in doc.entries) {
      print('  ${entry.key} = ${entry.value ?? "(empty)"}');
    }
    print('');

    // Demonstrate key features
    print('🎯 Key features demonstrated:');
    print('');

    // 1. Basic include functionality
    print('1. Basic include functionality:');
    print(
        '   - Main file entries: ${doc.firstValueOf("app-name")}, ${doc.firstValueOf("version")}');
    print('   - Theme from include: ${doc["theme"]}');
    print('   - Colors from nested include: ${doc["primary"]}');
    print('');

    // 2. Optional includes
    print('2. Optional includes (with ? prefix):');
    print('   - User settings included: ${doc["user-name"]}');
    print('   - Auto-save setting: ${doc["auto-save"]}');
    print('');

    // 3. Ghostty semantics - later entries don't override includes
    print('3. Ghostty semantics:');
    print('   - Theme setting from main file (after config-file): ignored');
    print(
        '   - Theme setting from include: ${doc["theme"]} (takes precedence)');
    print('   - User-name from main file (after config-file): ignored');
    print(
        '   - User-name from include: ${doc["user-name"]} (takes precedence)');
    print('');

    // 4. Multiple values for the same key
    print('4. Multiple values preserved:');
    final themeValues = doc.valuesOf('theme');
    print('   - All theme values: $themeValues');
    print('   - Last theme value (for direct access): ${doc["theme"]}');
    print('');

    // 5. Nested includes
    print('5. Nested includes:');
    print('   - Main file includes theme.conf');
    print('   - theme.conf includes colors.conf');
    print(
        '   - Colors are available in final config: ${doc["primary"]}, ${doc["secondary"]}');
    print('');

    // Demonstrate error handling
    print('🚨 Error handling examples:');
    print('');

    // Create a file with a missing required include
    final errorFile = File('${tempDir.path}/error.conf');
    await errorFile.writeAsString('''
setting1 = value1
config-file = missing.conf
setting2 = value2
''');

    try {
      await errorFile.parseWithIncludes();
    } on MissingIncludeException catch (e) {
      print('   - Missing required include: ${e.message}');
      print('     File: ${e.filePath}');
      print('     Include: ${e.includePath}');
    }
    print('');

    // Create a file with circular includes
    final circular1File = File('${tempDir.path}/circular1.conf');
    await circular1File.writeAsString('''
setting1 = value1
config-file = circular2.conf
''');

    final circular2File = File('${tempDir.path}/circular2.conf');
    await circular2File.writeAsString('''
setting2 = value2
config-file = circular1.conf
''');

    try {
      await circular1File.parseWithIncludes();
    } on CircularIncludeException catch (e) {
      print('   - Circular include detected: ${e.message}');
      print('     File: ${e.filePath}');
      print('     Include: ${e.includePath}');
    }
    print('');

    // Demonstrate different API methods
    print('🔧 API methods available:');
    print('');

    // Method 1: File extension method
    print('1. File.parseWithIncludes():');
    final doc1 = await mainFile.parseWithIncludes();
    print('   - Parsed ${doc1.length} entries');

    // Method 2: Convenience function (preferred)
    print('2. parseFileWithIncludes(String):');
    final doc2 = await parseFileWithIncludes(mainFile.path);
    print('   - Parsed ${doc2.length} entries');
    print('');

    // Demonstrate caching for performance
    print('⚡ Performance optimization with caching:');
    print('');

    // Create a shared cache for multiple parse operations
    final cache = <String, FlatDocument>{};

    // Parse multiple files that share common includes
    final startTime = DateTime.now();
    final docCached1 = await mainFile.parseWithIncludes(cache: cache);
    final docCached2 = await mainFile.parseWithIncludes(cache: cache);
    final endTime = DateTime.now();

    print('5. Cached parsing (shared cache):');
    print('   - First parse: ${docCached1.length} entries');
    print('   - Second parse: ${docCached2.length} entries (uses cache)');
    print('   - Cache contains ${cache.length} files');
    print('   - Parse time: ${endTime.difference(startTime).inMicroseconds}μs');
    print('');

    // Demonstrate configurable include key
    print('🔧 Configurable include key:');
    print('');

    // Create a config file with custom include key
    final customMainFile = File('${tempDir.path}/custom.conf');
    await customMainFile.writeAsString('''
app-name = CustomApp
include = theme.conf
''');

    // Parse with custom include key
    final customDoc = await customMainFile.parseWithIncludes(
      options: const FlatParseOptions(includeKey: 'include'),
    );

    print('5. Custom include key (include instead of config-file):');
    print('   - Parsed ${customDoc.length} entries');
    print('   - App name: ${customDoc["app-name"]}');
    print('   - Theme: ${customDoc["theme"]}');
    print('');

    print('🎉 Example completed successfully!');
    print('');
    print('💡 Key takeaways:');
    print(
        '   - Use config-file = path to include other config files (default)');
    print('   - Use config-file = ?path for optional includes');
    print(
        '   - Customize include key with FlatParseOptions(includeKey: "include")');
    print(
        '   - Entries after include directives don\'t override included values');
    print('   - Supports nested includes and cycle detection');
    print('   - Multiple API methods available for different use cases');
    print('   - Use caching for better performance with shared includes');
  } finally {
    // Clean up temporary files
    await tempDir.delete(recursive: true);
  }
}
