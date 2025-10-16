import 'package:flatconfig/flatconfig.dart';

void main() {
  print('🚨 Error handling examples:');
  print('');

  // Example 1: Missing equals separator
  print('1. Missing equals separator:');
  try {
    FlatConfig.parse('''
app-name = MyApp
version 1.0.0
debug = true
''');
  } on MissingEqualsException catch (e) {
    print('   - Error: ${e.message}');
    print('   - Content: "${e.rawLine}"');
  }
  print('');

  // Example 2: Empty key
  print('2. Empty key:');
  try {
    FlatConfig.parse('''
app-name = MyApp
= 1.0.0
debug = true
''');
  } on EmptyKeyException catch (e) {
    print('   - Error: ${e.message}');
    print('   - Content: "${e.rawLine}"');
  }
  print('');

  // Example 3: Unterminated quote
  print('3. Unterminated quote:');
  try {
    FlatConfig.parse('''
app-name = MyApp
version = "1.0.0
debug = true
''');
  } on UnterminatedQuoteException catch (e) {
    print('   - Error: ${e.message}');
    print('   - Content: "${e.rawLine}"');
  }
  print('');

  // Example 4: Trailing characters after quote
  print('4. Trailing characters after quote:');
  try {
    FlatConfig.parse('''
app-name = MyApp
version = "1.0.0" extra
debug = true
''');
  } on TrailingCharactersAfterQuoteException catch (e) {
    print('   - Error: ${e.message}');
    print('   - Content: "${e.rawLine}"');
  }
  print('');

  // Example 5: Non-strict mode (default) - shows warnings instead of errors
  print('5. Non-strict mode (default behavior):');
  final doc = FlatConfig.parse('''
app-name = MyApp
version 1.0.0    # missing equals - ignored
= 2.0.0          # empty key - ignored
debug = true
theme = "dark" extra  # trailing chars - treated as unquoted
''');

  print('   Parsed successfully with ${doc.length} entries:');
  for (final entry in doc.entries) {
    print('   - ${entry.key} = ${entry.value}');
  }
  print('');

  // Example 6: Strict mode - throws exceptions
  print('6. Strict mode (throws exceptions):');
  try {
    FlatConfig.parse('''
app-name = MyApp
version 1.0.0
debug = true
''', options: const FlatParseOptions(strict: true));
  } on MissingEqualsException catch (e) {
    print('   - Strict mode caught: ${e.message}');
  }
  print('');

  print('💡 Key takeaways:');
  print(
      '   - Error messages now include column information for precise location');
  print('   - Non-strict mode (default) ignores malformed lines with warnings');
  print('   - Strict mode throws exceptions for better error handling');
  print(
      '   - All parsing errors extend FormatException for consistent handling');
  print('   - Use try-catch blocks to handle specific error types');
  print('');
  print('🎉 Example completed successfully!');
}
