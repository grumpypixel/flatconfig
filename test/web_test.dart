@TestOn('browser')
import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  test('file APIs throw UnsupportedError on web', () async {
    expect(parseFlatFile('x'), throwsA(isA<UnsupportedError>()));
    expect(parseFileWithIncludes('x'), throwsA(isA<UnsupportedError>()));
  });

  test('core parsing works on web', () {
    final doc = FlatConfig.parse('a = 1\n');
    expect(doc.getInt('a'), 1);
  });
}
