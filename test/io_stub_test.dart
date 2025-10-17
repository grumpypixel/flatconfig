@TestOn('browser')
import 'package:test/test.dart';

import 'package:flatconfig/src/io_stub.dart' as io;

void main() {
  test('parseFlatFile throws UnsupportedError on web/wasm', () async {
    expect(io.parseFlatFile('path'), throwsA(isA<UnsupportedError>()));
  });

  test('parseFileWithIncludes throws UnsupportedError on web/wasm', () async {
    expect(
      io.parseFileWithIncludes('path'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('placeholder namespace types exist', () {
    final ioNamespace = io.FlatConfigIO();
    final docNamespace = io.FlatDocumentIO();
    expect(ioNamespace, isA<io.FlatConfigIO>());
    expect(docNamespace, isA<io.FlatDocumentIO>());
  });
}
