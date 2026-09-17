import 'package:flatconfig/flatconfig.dart';

/// The three ways a malformed line can be handled, side by side.
///
/// Strict mode throws, an `onIssue` handler reports, and the default does
/// neither. The same four broken lines go through all three, so the difference
/// is the mode and nothing else.
void main() {
  print('🚨 Error handling examples:');
  print('');

  _strictThrows();
  _lenientReports();
  _lenientIsSilent();
  _handlerDecides();

  print('💡 Key takeaways:');
  print('   - The same input is an exception, a report, or nothing at all,');
  print('     depending only on how you asked for it to be parsed.');
  print('   - Every parse exception extends FlatParseException, which');
  print('     extends FormatException.');
  print('   - Issues carry the kind, the 1-based line and column, and the');
  print('     raw line, which is what an editor needs to point at it.');
  print('   - Throwing from an onIssue handler stops the parse, which is how');
  print('     you build a policy between the two modes.');
  print('');
  print('🎉 Example completed successfully!');
}

/// Each malformed line, with the exception strict mode raises for it.
const _broken = <String, String>{
  'missing equals': 'app-name = MyApp\nversion 1.0.0\n',
  'empty key': 'app-name = MyApp\n= 1.0.0\n',
  'unterminated quote': 'app-name = MyApp\nversion = "1.0.0\n',
  'trailing characters': 'app-name = MyApp\nversion = "1.0.0" extra\n',
  'invalid key': 'app-name = MyApp\nver"sion = 1.0.0\n',
};

void _strictThrows() {
  print('1. Strict mode throws, one exception type per rule:');

  for (final entry in _broken.entries) {
    try {
      FlatDocument.parse(
        entry.value,
        options: const FlatParseOptions(strict: true),
      );
      print('   - ${entry.key}: nothing thrown');
    } on FlatParseException catch (e) {
      print('   - ${entry.key}: ${e.runtimeType} at line ${e.lineNumber}');
    }
  }

  print('');
}

void _lenientReports() {
  print('2. Lenient mode with a handler reports the same lines:');

  final issues = <FlatIssue>[];
  final doc = FlatDocument.parse(
    _broken.values.join(),
    options: FlatParseOptions(onIssue: issues.add),
  );

  for (final issue in issues) {
    print(
      '   - line ${issue.line}, column ${issue.column}: '
      '${issue.kind.name} in «${issue.rawLine.trim()}»',
    );
  }
  print('   ${doc.length} entries survived, ${issues.length} lines reported.');
  print('');
}

void _lenientIsSilent() {
  print('3. Lenient mode without a handler says nothing at all:');

  final doc = FlatDocument.parse(_broken.values.join());

  print('   Parsed ${doc.length} entries, and nothing reported a problem:');
  for (final entry in doc.entries) {
    print('   - ${entry.key} = ${entry.value}');
  }
  print('');
}

void _handlerDecides() {
  print(
    '4. A handler that throws makes one rule strict and forgives the rest:',
  );

  try {
    FlatDocument.parse(
      _broken.values.join(),
      options: FlatParseOptions(
        onIssue: (issue) {
          if (issue.kind == FlatIssueKind.invalidKey) {
            throw FormatException(issue.message, issue.rawLine, issue.column);
          }
        },
      ),
    );
    print('   - nothing was strict enough to stop the parse');
  } on FormatException catch (e) {
    print('   - stopped on the invalid key: ${e.message}');
  }

  print('');
}
