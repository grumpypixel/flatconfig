import 'package:flatconfig/src/io_stub.dart' as io;
import 'package:test/test.dart';

void main() {
  test('io_stub.parseFlatFile throws UnsupportedError (VM import)', () async {
    expect(io.parseFlatFile('x'), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub.parseFileWithIncludes throws UnsupportedError (VM import)',
      () async {
    expect(io.parseFileWithIncludes('x'), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub placeholder types are instantiable (VM import)', () {
    final a = io.FlatConfigIO();
    final b = io.FlatDocumentIO();
    expect(a, isA<io.FlatConfigIO>());
    expect(b, isA<io.FlatDocumentIO>());
  });
}
