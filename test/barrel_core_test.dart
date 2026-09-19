/// Imports nothing but the core barrel, so a type that appears in one of its
/// public signatures but is not exported fails here rather than downstream.
library barrel_core_test;

import 'dart:convert';

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
      multilineValue: MultilineValuePolicy.skip,
      interpolation: const EnvInterpolation(
        onMissing: MissingVariablePolicy.empty,
      ),
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
    expect(FlatDocument.fromData(const {'a': 1}, options: data)['a'], '1');
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

  test('every way into a document is reachable from the core barrel', () async {
    // A source is text, lines, lines over time, or bytes. Each shape needs its
    // own entry point, and the asynchronous line one went unexported once
    // already while its synchronous twin stayed public.
    const source = 'a = 1\nb = 2\n';
    const lines = ['a = 1', 'b = 2'];
    final expected = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

    expect(FlatDocument.parse(source), expected);
    expect(FlatDocument.parseLines(lines), expected);
    expect(
      await FlatDocument.parseLineStream(Stream.fromIterable(lines)),
      expected,
    );
    expect(
      await FlatDocument.parseBytes(Stream.value(utf8.encode(source))),
      expected,
    );
    expect(
      await FlatDocument.streamEntries(
        Stream.value(utf8.encode(source)),
      ).toList(),
      expected.entries,
    );
  });

  test('the parse exceptions are reachable from the core barrel', () {
    const strict = FlatParseOptions(strict: true);

    expect(
      () => FlatDocument.parse('no equals\n', options: strict),
      throwsA(
        isA<FlatParseException>().having(
          (e) => e.kind,
          'kind',
          FlatIssueKind.missingEquals,
        ),
      ),
    );
    expect(
      () => FlatDocument.parse(' = v\n', options: strict),
      throwsA(
        isA<FlatParseException>().having(
          (e) => e.kind,
          'kind',
          FlatIssueKind.emptyKey,
        ),
      ),
    );
    expect(
      () => FlatDocument.parse('a = "open\n', options: strict),
      throwsA(
        isA<FlatParseException>().having(
          (e) => e.kind,
          'kind',
          FlatIssueKind.unterminatedQuote,
        ),
      ),
    );
    expect(
      () => FlatDocument.parse('a = "v" junk\n', options: strict),
      throwsA(
        isA<FlatParseException>().having(
          (e) => e.kind,
          'kind',
          FlatIssueKind.trailingAfterQuote,
        ),
      ),
    );
    expect(
      () => FlatDocument.parse('a"b = v\n', options: strict),
      throwsA(
        isA<FlatParseException>().having(
          (e) => e.kind,
          'kind',
          FlatIssueKind.invalidKey,
        ),
      ),
    );
    expect(
      () => FlatDocument.parse('no equals\n', options: strict),
      throwsA(isA<FlatParseException>()),
    );
  });
}
