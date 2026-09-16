/// Imports nothing but the core barrel, so a type that appears in one of its
/// public signatures but is not exported fails here rather than downstream.
library barrel_core_test;

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

enum _Mood { calm }

void main() {
  test('the core barrel carries its own signatures', () {
    const parse = FlatParseOptions();
    const encode = FlatEncodeOptions();
    const read = FlatStreamReadOptions();
    const write = FlatStreamWriteOptions();
    final env = FlatEnvOptions(
      missingVariable: MissingVariablePolicy.empty,
      multilineValue: MultilineValuePolicy.skip,
    );
    const data = FlatDataOptions(listMode: FlatListMode.csv);

    final doc = FlatDocument([FlatEntry('a', '1')]);
    final issues = <FlatIssue>[];
    final reported = FlatDocument.parse(
      'broken line\n',
      options: FlatParseOptions(onIssue: issues.add),
    );

    expect(doc.lookup('a'), isA<FlatPresent>());
    expect(doc.lookup('b'), isA<FlatAbsent>());
    expect(FlatDocument.parse('a = \n').lookup('a'), isA<FlatReset>());
    expect(reported.length, 0);
    expect(issues.single.kind, FlatIssueKind.missingEquals);

    expect(doc.getAs('a', int.tryParse), 1);
    expect(doc.collapse(order: CollapseOrder.firstOccurrence).length, 1);
    expect(
      FlatDocument.fromEnvironment(const {'A': '1'}, options: env)['A'],
      '1',
    );
    expect(flatDocumentFromMapData(const {'a': 1}, options: data)['a'], '1');
    expect(splitRespectingQuotes('a,b', ','), ['a', 'b']);
    expect(indexOfUnquoted('a,b', ','), 1);
    expect(doc.encode(options: encode).trim(), 'a = 1');
    expect(read.encoding.name, isNotEmpty);
    expect(write.lineTerminator, isNotEmpty);
    expect(parse.commentPrefix, isNotEmpty);
    expect(_Mood.calm.name, 'calm');

    expect(
      () => FlatDocument.parse('= v\n', options: const FlatParseOptions()),
      returnsNormally,
    );
    expect(() => FlatEntry('a=b', 'v'), throwsA(isA<ArgumentError>()));
  });

  test('the parse exceptions are reachable from the core barrel', () {
    const strict = FlatParseOptions(strict: true);

    expect(
      () => FlatDocument.parse('no equals\n', options: strict),
      throwsA(isA<MissingEqualsException>()),
    );
    expect(
      () => FlatDocument.parse(' = v\n', options: strict),
      throwsA(isA<EmptyKeyException>()),
    );
    expect(
      () => FlatDocument.parse('a = "open\n', options: strict),
      throwsA(isA<UnterminatedQuoteException>()),
    );
    expect(
      () => FlatDocument.parse('a = "v" junk\n', options: strict),
      throwsA(isA<TrailingCharactersAfterQuoteException>()),
    );
    expect(
      () => FlatDocument.parse('a"b = v\n', options: strict),
      throwsA(isA<InvalidKeyException>()),
    );
    expect(
      () => FlatDocument.parse('no equals\n', options: strict),
      throwsA(isA<FlatParseException>()),
    );
  });
}
