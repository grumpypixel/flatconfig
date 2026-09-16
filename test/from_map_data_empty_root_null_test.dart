import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  test('an empty root key with null is rejected', () {
    // An empty key has no wire form (SPEC.md 3), and there is no lenient mode
    // left that would drop it quietly instead.
    expect(
      () => FlatDocument.fromData({'': null}),
      throwsA(isA<ArgumentError>()),
    );
  });
}
