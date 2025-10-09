// test/document_accessors_test.dart

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

enum Mode { auto, off }

void main() {
  FlatDocument docOf(Map<String, String?> m) =>
      FlatDocument([for (final e in m.entries) FlatEntry(e.key, e.value)]);

  group('FlatDocumentAccessors', () {
    test('getDuration parses ms/s/m/h/d', () {
      final d = docOf({
        'a': '150ms',
        'b': '2s',
        'c': '3m',
        'd': '1h',
        'e': '1d',
        'x': 'bad',
      });
      expect(d.getDuration('a')!.inMilliseconds, 150);
      expect(d.getDuration('b')!.inSeconds, 2);
      expect(d.getDuration('c')!.inMinutes, 3);
      expect(d.getDuration('d')!.inHours, 1);
      expect(d.getDuration('e')!.inDays, 1);
      expect(d.getDuration('x'), isNull);
    });

    test('getBytes supports SI and IEC (incl. PB/PiB)', () {
      final d = docOf({
        'a': '10KB',
        'b': '1MiB',
        'c': '2',
        'd': '1GiB',
        'e': '2PiB',
      });
      expect(d.getBytes('a'), 10000);
      expect(d.getBytes('b'), 1024 * 1024);
      expect(d.getBytes('c'), 2);
      expect(d.getBytes('d'), 1024 * 1024 * 1024);
      expect(d.getBytes('e'), 2 * 1024 * 1024 * 1024 * 1024 * 1024);
    });

    test('requireInt/Double/Bool throw with key context', () {
      final d = docOf({'i': 'x', 'd': 'y', 'b': 'maybe'});
      expect(() => d.requireInt('i'), throwsFormatException);
      expect(() => d.requireDouble('d'), throwsFormatException);
      expect(() => d.requireBool('b'), throwsFormatException);
    });

    test('getEnum / requireEnum', () {
      final map = {'auto': Mode.auto, 'off': Mode.off};
      final d = docOf({'m1': 'AUTO', 'm2': 'off'});
      expect(d.getEnum('m1', map), Mode.auto);
      expect(d.requireEnum('m2', map), Mode.off);
      expect(() => d.requireEnum('missing', map), throwsFormatException);
    });

    test('getHexColor supports #rgb/#rgba/#rrggbb/#aarrggbb', () {
      final d = docOf({
        'rgb': '#0f8',
        'rgba': '#0f8a',
        'rrggbb': '00ff88',
        'aarrggbb': 'aa00ff88',
      });
      expect(d.getHexColor('rgb'), 0xFF00FF88); // expands + FF alpha
      expect(d.getHexColor('rgba'), 0xAA00FF88); // shorthand rgba -> aarrggbb
      expect(d.getHexColor('rrggbb'), 0xFF00FF88);
      expect(d.getHexColor('aarrggbb', cssAlphaAtEnd: false),
          0xAA00FF88); // traditional AARRGGBB format
    });

    test('getHexColor cssAlphaAtEnd parameter controls 8-digit interpretation',
        () {
      final d = docOf({
        'css_style': '11223344', // RRGGBBAA format
        'traditional': '44112233', // AARRGGBB format
      });

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      expect(d.getHexColor('css_style'), 0x44112233);
      expect(d.getHexColor('css_style', cssAlphaAtEnd: true), 0x44112233);

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      expect(d.getHexColor('traditional', cssAlphaAtEnd: false), 0x44112233);
    });

    test('getHexColor works without # prefix', () {
      final d = docOf({
        'no_hash_3': '0f8',
        'no_hash_4': '0f8a',
        'no_hash_6': '00ff88',
        'no_hash_8': '11223344',
      });
      expect(d.getHexColor('no_hash_3'), 0xFF00FF88);
      expect(d.getHexColor('no_hash_4'), 0xAA00FF88);
      expect(d.getHexColor('no_hash_6'), 0xFF00FF88);
      expect(d.getHexColor('no_hash_8'), 0x44112233); // CSS style by default
    });

    test('getList/getSet/getMap basics', () {
      final d = docOf({
        'list': ' a, b , ,c ',
        'set': 'A,a,B',
        'map': 'a:1, b:2 ,c: 3',
      });
      expect(d.getList('list'), ['a', 'b', 'c']);
      expect(d.getSet('set'), {'a', 'b'});
      expect(d.getMap('map'), {'a': '1', 'b': '2', 'c': '3'});
    });

    test('getMap trim=false preserves whitespace around keys/values', () {
      final d = docOf({'m': ' a: 1 , b : 2 '});
      expect(d.getMap('m', trim: false), {' a': ' 1 ', ' b ': ' 2 '});
    });

    test('ranges', () {
      final d = docOf({'i': '10', 'x': 'oops', 'f': '1.5'});
      expect(d.getIntInRange('i', min: 5, max: 10), 10);
      expect(d.getIntInRange('i', min: 11), isNull);
      expect(() => d.requireIntInRange('i', min: 11), throwsFormatException);
      expect(d.getDoubleInRange('f', min: 1, max: 2), 1.5);
      expect(d.getDoubleInRange('x', min: 1, max: 2), isNull);
    });

    test('duration bare number treated as ms', () {
      final d = docOf({'x': '150'});
      expect(d.getDuration('x')!.inMilliseconds, 150);
    });

    test('bytes invalid and missing return null', () {
      final d = docOf({'neg': '-1MB', 'unk': '10XB'});
      expect(d.getBytes('neg'), isNull);
      expect(d.getBytes('unk'), isNull);
      expect(d.getBytes('missing'), isNull);
    });

    test('requireBool parses true/false and throws on missing/invalid', () {
      final d1 = docOf({'t': 'true', 'f': '0'});
      expect(d1.requireBool('t'), isTrue);
      expect(d1.requireBool('f'), isFalse);
      final d2 = docOf({'u': 'maybe'});
      expect(() => d2.requireBool('u'), throwsFormatException);
      expect(() => d2.requireBool('missing'), throwsFormatException);
    });

    test('getColor returns ARGB components', () {
      final d = docOf({'c': '#336699'});
      final c = d.getColor('c')!;
      expect(c['a'], 0xFF);
      expect(c['r'], 0x33);
      expect(c['g'], 0x66);
      expect(c['b'], 0x99);
    });

    test('getColor cssAlphaAtEnd parameter controls 8-digit interpretation',
        () {
      final d = docOf({
        'css_style': '11223344', // RRGGBBAA format
        'traditional': '44112233', // AARRGGBB format
      });

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      final cssColor = d.getColor('css_style')!;
      expect(cssColor['a'], 0x44);
      expect(cssColor['r'], 0x11);
      expect(cssColor['g'], 0x22);
      expect(cssColor['b'], 0x33);

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      final tradColor = d.getColor('traditional', cssAlphaAtEnd: false)!;
      expect(tradColor['a'], 0x44);
      expect(tradColor['r'], 0x11);
      expect(tradColor['g'], 0x22);
      expect(tradColor['b'], 0x33);
    });

    test('hex invalid lengths and non-hex return null', () {
      final d = docOf({'short': '#12', 'long': '123456789', 'nonhex': '#ggg'});
      expect(d.getHexColor('short'), isNull);
      expect(d.getHexColor('long'), isNull);
      expect(d.getHexColor('nonhex'), isNull);
    });

    test('getHexColor returns null for empty string', () {
      final d = docOf({'empty': ''});
      expect(d.getHexColor('empty'), isNull);
    });

    test('getSet custom separator and list keep empties', () {
      final d = docOf({'s': 'A| |b||B|'});
      expect(d.getSet('s', separator: '|'), {'a', 'b'});
      final l = d.getList('s', separator: '|', skipEmpty: false)!;
      expect(l.length, 6);
    });

    test('getList honors custom separator and keeps empties', () {
      final d = docOf({'l': 'a|  |b||c|'});
      expect(
        d.getList('l', separator: '|', skipEmpty: false),
        ['a', '', 'b', '', 'c', ''],
      );
    });

    test('getBytes returns null for empty string', () {
      final d = docOf({'empty': ''});
      expect(d.getBytes('empty'), isNull);
    });

    test('enum case-sensitive mode exact match only', () {
      final d = docOf({'m': 'A'});
      final map = {'A': 1, 'B': 2};
      expect(d.getEnum('m', map, caseInsensitive: false), 1);
      expect(d.getEnum('m', {'a': 1}, caseInsensitive: false), isNull);
    });

    test('getStringTrimmed and requireString', () {
      final d = docOf({'a': '  x  '});
      expect(d.getTrimmed('a'), 'x');
      expect(() => d.requireString('missing'), throwsFormatException);
    });

    test('getStringOr falls back on missing and unquoted empty; keeps quoted',
        () {
      final d = docOf({
        'present': 'value',
        'empty_unquoted':
            null, // simulated by parser when value is unquoted empty
        'empty_quoted': '', // simulated by parser when value is ""
      });

      expect(d.getStringOr('missing', 'def'), 'def');
      expect(d.getStringOr('empty_unquoted', 'def'), 'def');
      expect(d.getStringOr('present', 'def'), 'value');
      expect(d.getStringOr('empty_quoted', 'def'), '');
    });

    test(
        'requireString returns string incl. empty quoted; throws on missing/unquoted empty',
        () {
      final d = docOf({
        'present': 'x',
        'empty_unquoted': null,
        'empty_quoted': '',
      });

      expect(d.requireString('present'), 'x');
      expect(d.requireString('empty_quoted'), '');
      expect(() => d.requireString('missing'), throwsFormatException);
      expect(() => d.requireString('empty_unquoted'), throwsFormatException);
    });

    test('getIntOr / getDoubleOr fall back', () {
      final d = docOf({'i': 'x', 'd': 'y'});
      expect(d.getIntOr('i', 7), 7);
      expect(d.getDoubleOr('d', 3.5), 3.5);
    });

    test('requireEnum and getEnum', () {
      final d = docOf({'m1': 'Alpha', 'm2': 'b'});
      final map = {'alpha': 1, 'b': 2};
      expect(d.getEnum('m1', map), 1);
      expect(d.requireEnum('m2', map), 2);
      expect(() => d.requireEnum('missing', map), throwsFormatException);
    });

    test('requireDuration and requireBytes', () {
      final d = docOf({'t': '2s', 'b': '1MiB'});
      expect(d.requireDuration('t').inMilliseconds, 2000);
      expect(d.requireBytes('b'), 1024 * 1024);
      expect(() => d.requireDuration('missing'), throwsFormatException);
      expect(() => d.requireBytes('missing'), throwsFormatException);
    });

    test('getDateTime / requireDateTime', () {
      final d = docOf({'ts': '2024-01-02T03:04:05Z'});
      expect(d.getDateTime('ts')!.toUtc().year, 2024);
      expect(() => d.requireDateTime('missing'), throwsFormatException);
    });

    test('getUri / requireUri', () {
      final d = docOf({'u': 'https://example.com/path?q=1'});
      expect(d.getUri('u')!.host, 'example.com');
      expect(() => d.requireUri('missing'), throwsFormatException);
    });

    test('isEnabled with default fallback', () {
      final d = docOf({'b': 'yes'});
      expect(d.isEnabled('b'), isTrue);
      expect(d.isEnabled('missing', defaultValue: true), isTrue);
    });

    test('isEnabled default (false) when missing', () {
      final d = docOf({});
      expect(d.isEnabled('missing'), isFalse);
    });

    test('getSet caseSensitive preserves distinct cases', () {
      final d = docOf({'s': 'A, a, B'});
      expect(d.getSet('s', caseInsensitive: false), {'A', 'a', 'B'});
    });

    test('getList without trimming preserves whitespace', () {
      final d = docOf({'l': ' a ,  b  ,c '});
      expect(
        d.getList('l', trimItems: false, skipEmpty: false),
        [' a ', '  b  ', 'c '],
      );
    });

    test('getStringTrimmed returns null when missing', () {
      final d = docOf({});
      expect(d.getTrimmed('missing'), isNull);
    });

    test('getDateTime returns null for invalid', () {
      final d = docOf({'ts': 'not-a-date'});
      expect(d.getDateTime('ts'), isNull);
    });

    test('getUri returns null for invalid', () {
      final d = docOf({'u': ':::/not-a-uri'});
      expect(d.getUri('u'), isNull);
    });

    test('getMap ignores items with empty key', () {
      final d = docOf({'m': ':1,  :2 , x:3'});
      expect(d.getMap('m'), {'x': '3'});
    });

    test('getIntOr / getDoubleOr parse valid values', () {
      final d = docOf({'i': '42', 'd': '2.25'});
      expect(d.getIntOr('i', 7), 42);
      expect(d.getDoubleOr('d', 3.5), closeTo(2.25, 1e-9));
    });

    test('getDuration parses ms/s/m/h/d and bare ms', () {
      final doc = FlatDocument(const [
        FlatEntry('ms', '150'),
        FlatEntry('s', '2s'),
        FlatEntry('m', '2.5m'),
        FlatEntry('h', '0.5h'),
        FlatEntry('d', '1d'),
        FlatEntry('bad', 'xs'),
      ]);
      expect(doc.getDuration('ms')!.inMilliseconds, 150);
      expect(doc.getDuration('s')!.inMilliseconds, 2000);
      expect(doc.getDuration('m')!.inMilliseconds, 150000);
      expect(doc.getDuration('h')!.inMilliseconds, 1800000);
      expect(doc.getDuration('d')!.inMilliseconds, 86400000);
      expect(doc.getDuration('bad'), isNull);
      expect(doc.getDuration('missing'), isNull);
    });

    test('getBytes parses SI and IEC units', () {
      final doc = FlatDocument(const [
        FlatEntry('b', '42'),
        FlatEntry('kb', '2KB'),
        FlatEntry('mb', '1.5MB'),
        FlatEntry('tb', '1TB'),
        FlatEntry('pb', '1.2PB'),
        FlatEntry('mib', '2MiB'),
        FlatEntry('gib', '1GiB'),
        FlatEntry('tib', '1TiB'),
        FlatEntry('pib', '2PiB'),
        FlatEntry('bad', 'xMB'),
      ]);
      expect(doc.getBytes('b'), 42);
      expect(doc.getBytes('kb'), 2000);
      expect(doc.getBytes('mb'), 1500000);
      expect(doc.getBytes('tb'), 1000 * 1000 * 1000 * 1000);
      expect(doc.getBytes('pb'), 1200000000000000);
      expect(doc.getBytes('mib'), 2 * 1024 * 1024);
      expect(doc.getBytes('gib'), 1024 * 1024 * 1024);
      expect(doc.getBytes('tib'), 1024 * 1024 * 1024 * 1024);
      expect(doc.getBytes('pib'), 2 * 1024 * 1024 * 1024 * 1024 * 1024);
      expect(doc.getBytes('bad'), isNull);
      expect(doc.getBytes('missing'), isNull);
    });

    test('getEnum maps string to value with case-insensitive matching', () {
      // Define a local enum-like mapping for the test
      // (Dart enums can't be declared inside functions prior to certain SDKs)
      final mode = {
        'a': 'A',
        'b': 'B',
      };
      final doc = FlatDocument(const [
        FlatEntry('m1', 'A'),
        FlatEntry('m2', 'b'),
        FlatEntry('m3', 'C'),
      ]);
      final map = {'a': mode['a']!, 'b': mode['b']!};
      expect(doc.getEnum('m1', map), mode['a']);
      expect(doc.getEnum('m2', map), mode['b']);
      expect(doc.getEnum('m3', map), isNull);
      expect(doc.getEnum('missing', map), isNull);
    });

    test('requireInt/requireDouble throw on missing/invalid', () {
      final doc = FlatDocument(const [
        FlatEntry('i', '2'),
        FlatEntry('d', '3.14'),
      ]);
      expect(doc.requireInt('i'), 2);
      expect(doc.requireDouble('d'), closeTo(3.14, 1e-9));
      expect(() => doc.requireInt('missing'), throwsFormatException);
      expect(() => doc.requireDouble('missing'), throwsFormatException);
    });

    test('requireBool throws on missing/invalid and returns parsed value', () {
      final doc = FlatDocument(const [
        FlatEntry('t', 'true'),
        FlatEntry('f', '0'),
      ]);
      expect(doc.requireBool('t'), isTrue);
      expect(doc.requireBool('f'), isFalse);
      expect(() => doc.requireBool('missing'), throwsFormatException);
      final doc2 = FlatDocument(const [FlatEntry('u', 'maybe')]);
      expect(() => doc2.requireBool('u'), throwsFormatException);
    });

    test('getHexColor parses #rgb/#rgba/#rrggbb/#aarrggbb and no-#', () {
      final doc = FlatDocument(const [
        FlatEntry('rgb', '#0f8'), // -> FF00FF88
        // -> 00 FF 88 -> 00FF88 with alpha 00? expand -> 00 FF 88
        FlatEntry('rgba', '#0f88'),
        FlatEntry('rrggbb', '112233'),
        FlatEntry('aarrggbb', '80112233'),
        FlatEntry('bad', '#xyz'),
      ]);
      expect(doc.getHexColor('rgb'), 0xFF00FF88);
      // #rgba -> rrggbbaa -> aarrggbb => alpha comes from the last nibble
      expect(doc.getHexColor('rgba'), 0x8800FF88);
      expect(doc.getHexColor('rrggbb'), 0xFF112233);
      expect(doc.getHexColor('aarrggbb', cssAlphaAtEnd: false),
          0x80112233); // traditional AARRGGBB format
      expect(doc.getHexColor('bad'), isNull);
      expect(doc.getHexColor('missing'), isNull);
    });

    test('getHexColor cssAlphaAtEnd parameter for FlatDocument', () {
      final doc = FlatDocument(const [
        FlatEntry('css_8', '11223344'), // RRGGBBAA format
        FlatEntry('trad_8', '44112233'), // AARRGGBB format
      ]);

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      expect(doc.getHexColor('css_8'), 0x44112233);
      expect(doc.getHexColor('css_8', cssAlphaAtEnd: true), 0x44112233);

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      expect(doc.getHexColor('trad_8', cssAlphaAtEnd: false), 0x44112233);
    });

    test('getColor returns ARGB components', () {
      final doc = FlatDocument(const [
        FlatEntry('c', '#336699'),
      ]);
      final c = doc.getColor('c')!;
      expect(c['a'], 0xFF);
      expect(c['r'], 0x33);
      expect(c['g'], 0x66);
      expect(c['b'], 0x99);
    });

    test(
        'getColor cssAlphaAtEnd parameter controls 8-digit interpretation for FlatDocument',
        () {
      final doc = FlatDocument(const [
        FlatEntry('css_style', '11223344'), // RRGGBBAA format
        FlatEntry('traditional', '44112233'), // AARRGGBB format
      ]);

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      final cssColor = doc.getColor('css_style')!;
      expect(cssColor['a'], 0x44);
      expect(cssColor['r'], 0x11);
      expect(cssColor['g'], 0x22);
      expect(cssColor['b'], 0x33);

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      final tradColor = doc.getColor('traditional', cssAlphaAtEnd: false)!;
      expect(tradColor['a'], 0x44);
      expect(tradColor['r'], 0x11);
      expect(tradColor['g'], 0x22);
      expect(tradColor['b'], 0x33);
    });

    test('getHexColor invalid lengths and non-hex return null', () {
      final doc = FlatDocument(const [
        FlatEntry('short', '#12'),
        FlatEntry('long', '123456789'),
        FlatEntry('nonhex', '#ggg'),
      ]);
      expect(doc.getHexColor('short'), isNull);
      expect(doc.getHexColor('long'), isNull);
      expect(doc.getHexColor('nonhex'), isNull);
    });

    test('getList splits, trims and skips empties by default', () {
      final doc = FlatDocument(const [
        FlatEntry('l', 'a,  b , , c  '),
      ]);
      expect(doc.getList('l'), ['a', 'b', 'c']);
      expect(doc.getList('missing'), isNull);
    });

    test('getSet builds a set; case-insensitive option', () {
      final doc = FlatDocument(const [
        FlatEntry('s', 'A, b, a, B '),
      ]);
      expect(doc.getSet('s')!.length, 2);
      expect(doc.getSet('s'), {'a', 'b'});
    });

    test('getSet custom separator and keep empties=false/true', () {
      final doc = FlatDocument(const [
        FlatEntry('s', 'A| |b||B|'),
      ]);
      // Default caseInsensitive=true
      expect(doc.getSet('s', separator: '|'), {'a', 'b'});
      // Keep empties -> empties are dropped by Set but we ensure parsing path
      // hit
      final l = doc.getList('s', separator: '|', skipEmpty: false)!;
      expect(l.length, 6);
    });

    test('getList honors custom separator and keeps empties when configured',
        () {
      final doc = FlatDocument(const [
        FlatEntry('l', 'a|  |b||c|'),
      ]);
      expect(
        doc.getList('l', separator: '|', skipEmpty: false),
        ['a', '', 'b', '', 'c', ''],
      );
    });

    test('getBytes negatives and unknown unit return null', () {
      final doc = FlatDocument(const [
        FlatEntry('neg', '-1MB'),
        FlatEntry('unk', '10XB'),
      ]);
      expect(doc.getBytes('neg'), isNull);
      expect(doc.getBytes('unk'), isNull);
    });

    test('getEnum works in case-sensitive mode only on exact match', () {
      final doc = FlatDocument(const [
        FlatEntry('m', 'A'),
      ]);
      final map = {'A': 1, 'B': 2};
      expect(doc.getEnum('m', map, caseInsensitive: false), 1);
      expect(doc.getEnum('m', {'a': 1}, caseInsensitive: false), isNull);
    });

    test('getStringTrimmed and requireString', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '  x  '),
      ]);
      expect(doc.getTrimmed('a'), 'x');
      expect(() => doc.requireString('missing'), throwsFormatException);
    });

    test('getIntOr / getDoubleOr fall back', () {
      final doc =
          FlatDocument(const [FlatEntry('i', 'x'), FlatEntry('d', 'y')]);
      expect(doc.getIntOr('i', 7), 7);
      expect(doc.getDoubleOr('d', 3.5), 3.5);
    });

    test('requireEnum and getEnum', () {
      final doc = FlatDocument(const [
        FlatEntry('m1', 'Alpha'),
        FlatEntry('m2', 'b'),
      ]);
      final map = {'alpha': 1, 'b': 2};
      expect(doc.getEnum('m1', map), 1);
      expect(doc.requireEnum('m2', map), 2);
      expect(() => doc.requireEnum('missing', map), throwsFormatException);
    });

    test('requireEnum with preNormalizedLowerMapping', () {
      final doc = FlatDocument(const [
        FlatEntry('m1', 'Alpha'),
        FlatEntry('m2', 'BETA'),
      ]);
      final map = {'alpha': 1, 'beta': 2};
      final preNormalized = {'alpha': 1, 'beta': 2};

      expect(
          doc.requireEnum('m1', map, preNormalizedLowerMapping: preNormalized),
          1);
      expect(
          doc.requireEnum('m2', map, preNormalizedLowerMapping: preNormalized),
          2);
      expect(
          () => doc.requireEnum('missing', map,
              preNormalizedLowerMapping: preNormalized),
          throwsFormatException);
    });

    test('requireDuration and requireBytes', () {
      final doc = FlatDocument(const [
        FlatEntry('t', '2s'),
        FlatEntry('b', '1MiB'),
      ]);
      expect(doc.requireDuration('t').inMilliseconds, 2000);
      expect(doc.requireBytes('b'), 1024 * 1024);
      expect(() => doc.requireDuration('missing'), throwsFormatException);
      expect(() => doc.requireBytes('missing'), throwsFormatException);
    });

    test('getDateTime / requireDateTime', () {
      final doc = FlatDocument(const [
        FlatEntry('ts', '2024-01-02T03:04:05Z'),
      ]);
      expect(doc.getDateTime('ts')!.toUtc().year, 2024);
      expect(() => doc.requireDateTime('missing'), throwsFormatException);
    });

    test('getUri / requireUri', () {
      final doc = FlatDocument(const [
        FlatEntry('u', 'https://example.com/path?q=1'),
      ]);
      expect(doc.getUri('u')!.host, 'example.com');
      expect(() => doc.requireUri('missing'), throwsFormatException);
    });

    test('getMap parses key:value pairs', () {
      final doc = FlatDocument(const [
        FlatEntry('m', 'a:1, b:2 ,invalid, c: 3'),
      ]);
      final m = doc.getMap('m');
      expect(m, {'a': '1', 'b': '2', 'c': '3'});
      expect(doc.getMap('missing'), isEmpty);
    });

    test('ranged getters and requires', () {
      final doc = FlatDocument(const [
        FlatEntry('i', '5'),
        FlatEntry('d', '2.5'),
      ]);
      expect(doc.getIntInRange('i', min: 1, max: 10), 5);
      expect(doc.getDoubleInRange('d', min: 1, max: 3), 2.5);
      expect(() => doc.requireIntInRange('i', min: 6), throwsFormatException);
      expect(
        () => doc.requireDoubleInRange('d', max: 2),
        throwsFormatException,
      );
    });

    test('isEnabled with default fallback', () {
      final doc = FlatDocument(const [FlatEntry('b', 'yes')]);
      expect(doc.isEnabled('b'), isTrue);
      expect(doc.isEnabled('missing', defaultValue: true), isTrue);
    });

    test('getKeyValue parses single pair from value', () {
      final d = docOf({'bind': 'ctrl+z=close_surface'});
      final pair = d.getKeyValue('bind')!;
      expect(pair.$1, 'ctrl+z');
      expect(pair.$2, 'close_surface');
    });

    test('getKeyValue respects quoted value with = and spaces', () {
      final d = docOf({'bind': 'action = "x = y"'});
      final pair = d.getKeyValue('bind', decodeEscapesInQuoted: true)!;
      expect(pair.$1, 'action');
      expect(pair.$2, 'x = y');
    });

    test('getKeyValue returns null on missing/invalid/empty-key', () {
      final d = docOf({'a': 'novalue', 'b': ' = v', 'c': ''});
      expect(d.getKeyValue('a'), isNull); // no '='
      expect(d.getKeyValue('b'), isNull); // empty key after trimRight
      expect(d.getKeyValue('missing'), isNull);
      expect(d.getKeyValue('c'), isNull);
    });

    test('getKeyValue trimKey=false preserves trailing spaces in key', () {
      final d = docOf({'k': 'key  =value'});
      final kv = d.getKeyValue('k', trimKey: false)!;
      expect(kv.$1, 'key  ');
      expect(kv.$2, 'value');
    });

    test('getDocument parses comma-separated pairs', () {
      final d = docOf({'map': 'a=1, b=2 , c= 3'});
      final sub = d.getDocument('map');
      expect(sub.entries, [
        const FlatEntry('a', '1'),
        const FlatEntry('b', '2'),
        const FlatEntry('c', '3'),
      ]);
    });

    test('getDocument ignores invalid items and empty keys', () {
      final d = docOf({'map': 'a=1, invalid,  =x , :y, x=, ='});
      final sub = d.getDocument('map');
      expect(sub.entries, [
        const FlatEntry('a', '1'),
        const FlatEntry('x', null),
      ]);
    });

    test('getDocument supports custom sep and quoted values', () {
      final d = docOf({'pairs': 'k1="v=1"| k2 = v2 |k3= "" '});
      final sub = d.getDocument(
        'pairs',
        itemSep: '|',
        decodeEscapesInQuoted: true,
      );
      expect(sub.entries, [
        const FlatEntry('k1', 'v=1'),
        const FlatEntry('k2', 'v2'),
        const FlatEntry('k3', ''),
      ]);
    });

    test('getDocument trim options false preserve whitespace in keys', () {
      final d = docOf({'pairs': ' a = 1 , b = " 2 " '});
      final sub = d.getDocument(
        'pairs',
        trimItems: false,
        trimKey: false,
        decodeEscapesInQuoted: true,
      );
      expect(sub.entries, [
        const FlatEntry(' a ', '1'),
        const FlatEntry(' b ', ' 2 '),
      ]);
    });

    test('getDocument returns empty for missing and empty', () {
      final d = docOf({'empty': ''});
      expect(d.getDocument('missing'), FlatDocument.empty());
      expect(d.getDocument('empty'), FlatDocument.empty());
    });

    test('getDateTime returns null when missing', () {
      final d = docOf({});
      expect(d.getDateTime('missing'), isNull);
    });

    test('getColor returns null when hex invalid', () {
      final d = docOf({'c': '#ggg'});
      expect(d.getColor('c'), isNull);
    });

    test('requireHexColor returns value and throws on missing/invalid', () {
      final d1 = docOf({'c': '00ff88'});
      expect(d1.requireHexColor('c'), 0xFF00FF88);
      final d2 = docOf({'bad': '#xyz'});
      expect(() => d2.requireHexColor('missing'), throwsFormatException);
      expect(() => d2.requireHexColor('bad'), throwsFormatException);
    });

    test('requireHexColor supports cssAlphaAtEnd parameter', () {
      final d = docOf({
        'css_8': '11223344', // RRGGBBAA format
        'trad_8': '44112233', // AARRGGBB format
      });

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      expect(d.requireHexColor('css_8'), 0x44112233);
      expect(d.requireHexColor('css_8', cssAlphaAtEnd: true), 0x44112233);

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      expect(d.requireHexColor('trad_8', cssAlphaAtEnd: false), 0x44112233);
    });

    test('requireColor returns value and throws on missing/invalid', () {
      final d1 = docOf({'c': '#00ff88'});
      final color = d1.requireColor('c');
      expect(color['a'], 0xFF);
      final d2 = docOf({'bad': '#xyz'});
      expect(() => d2.requireColor('missing'), throwsFormatException);
      expect(() => d2.requireColor('bad'), throwsFormatException);
    });

    test('requireColor cssAlphaAtEnd parameter controls 8-digit interpretation',
        () {
      final d = docOf({
        'css_style': '11223344', // RRGGBBAA format
        'traditional': '44112233', // AARRGGBB format
      });

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      final cssColor = d.requireColor('css_style');
      expect(cssColor['a'], 0x44);
      expect(cssColor['r'], 0x11);
      expect(cssColor['g'], 0x22);
      expect(cssColor['b'], 0x33);

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      final tradColor = d.requireColor('traditional', cssAlphaAtEnd: false);
      expect(tradColor['a'], 0x44);
      expect(tradColor['r'], 0x11);
      expect(tradColor['g'], 0x22);
      expect(tradColor['b'], 0x33);
    });

    test('getIntInRange returns null when parse fails', () {
      final d = docOf({'ix': 'oops'});
      expect(d.getIntInRange('ix'), isNull);
    });

    test('containsKey/hasKey/hasNonNull basics', () {
      final d = docOf({'a': '1', 'b': null});
      expect(d.has('a'), isTrue);
      expect(d.has('b'), isTrue);
      expect(d.hasNonNull('a'), isTrue);
      expect(d.hasNonNull('b'), isFalse);
      expect(d.has('missing'), isFalse);
    });

    test('getTrimmedOrEmpty returns trimmed or empty', () {
      final d = docOf({'a': '  x  '});
      expect(d.getTrimmedOrEmpty('a'), 'x');
      expect(d.getTrimmedOrEmpty('missing'), '');
    });

    test('getDurationOr uses default on missing/invalid', () {
      final d = docOf({'t': 'xs'});
      expect(
          d.getDurationOr('missing', const Duration(seconds: 2)).inSeconds, 2);
      expect(
          d
              .getDurationOr('t', const Duration(milliseconds: 150))
              .inMilliseconds,
          150);
    });

    test('getNum parses int/double and returns null on invalid/missing', () {
      final d = docOf({'i': '42', 'd': '3.14', 'x': 'nope'});
      expect(d.getNum('i'), 42);
      expect(d.getNum('d'), closeTo(3.14, 1e-9));
      expect(d.getNum('x'), isNull);
      expect(d.getNum('missing'), isNull);
    });

    test('getPercent and requirePercent', () {
      final d = docOf(
          {'p1': '50%', 'p2': ' 80 % ', 'p3': '0.25', 'p4': '80', 'neg': '-1'});
      expect(d.getPercent('p1'), closeTo(0.5, 1e-9));
      expect(d.getPercent('p2'), closeTo(0.8, 1e-9));
      expect(d.getPercent('p3'), closeTo(0.25, 1e-9));
      expect(d.getPercent('p4'), closeTo(0.8, 1e-9));
      expect(d.getPercent('neg'), isNull);
      expect(() => d.requirePercent('missing'), throwsFormatException);
    });

    test('getPercent with clamp01 parameter', () {
      final d = docOf({
        'p1': '50%', // 0.5 -> 0.5 (no change)
        'p2': '150%', // 1.5 -> 1.0 (clamped)
        'p3': '0.25', // 0.25 -> 0.25 (no change)
        'p4': '200', // 2.0 -> 1.0 (clamped)
        'p5': '-10%', // -0.1 -> null (negative values return null)
        'p6': '80%', // 0.8 -> 0.8 (no change)
      });

      // Without clamping (default behavior)
      expect(d.getPercent('p1'), closeTo(0.5, 1e-9));
      expect(d.getPercent('p2'), closeTo(1.5, 1e-9));
      expect(d.getPercent('p3'), closeTo(0.25, 1e-9));
      expect(d.getPercent('p4'), closeTo(2.0, 1e-9));
      expect(d.getPercent('p5'),
          closeTo(-0.1, 1e-9)); // negative percentages are allowed
      expect(d.getPercent('p6'), closeTo(0.8, 1e-9));

      // With clamping
      expect(d.getPercent('p1', clamp01: true), closeTo(0.5, 1e-9));
      expect(d.getPercent('p2', clamp01: true), closeTo(1.0, 1e-9));
      expect(d.getPercent('p3', clamp01: true), closeTo(0.25, 1e-9));
      expect(d.getPercent('p4', clamp01: true), closeTo(1.0, 1e-9));
      expect(d.getPercent('p5', clamp01: true),
          closeTo(0.0, 1e-9)); // negative values are clamped to 0.0
      expect(d.getPercent('p6', clamp01: true), closeTo(0.8, 1e-9));
    });

    test('isDisabled complements isEnabled', () {
      final d = docOf({'flag': 'no'});
      expect(d.isEnabled('flag'), isFalse);
      expect(d.isDisabled('flag'), isTrue);
      expect(d.isDisabled('missing', defaultValue: true), isFalse);
    });

    test('getJson parses valid JSON values and returns null on invalid/missing',
        () {
      final d = docOf({
        'obj': '{"a":1, "b":[2,3]}',
        'arr': '[1,2,3]',
        'bad': '{not json}',
      });
      final obj = d.getJson('obj') as Map<String, dynamic>;
      expect(obj['a'], 1);
      expect((obj['b'] as List).length, 2);
      final arr = d.getJson('arr') as List<dynamic>;
      expect(arr, [1, 2, 3]);
      expect(d.getJson('bad'), isNull);
      expect(d.getJson('missing'), isNull);
    });

    test('requireJson throws on missing/invalid and returns decoded value', () {
      final d = docOf({'x': '{"k":"v"}'});
      final j = d.requireJson('x') as Map<String, dynamic>;
      expect(j['k'], 'v');
      expect(() => d.requireJson('missing'), throwsFormatException);
      expect(
          () => docOf({'bad': 'x'}).requireJson('bad'), throwsFormatException);
    });

    test('isOneOf supports case-insensitive matching by default', () {
      final d = docOf({'mode': 'Dark'});
      expect(d.isOneOf('mode', {'dark', 'light'}), isTrue);
      expect(d.isOneOf('mode', {'dark'}, caseInsensitive: false), isFalse);
      expect(d.isOneOf('missing', {'dark'}), isFalse);
    });

    test('requireKeys throws when any key is missing', () {
      final d = docOf({'a': '1', 'b': null});
      // present: 'a', 'b'; missing: 'c'
      expect(() => d.requireKeys(['a', 'b', 'c']), throwsFormatException);
      // should not throw when all present (null allowed)
      d.requireKeys(['a', 'b']);
    });

    test('getRatio parses w:h to double', () {
      final d = docOf({
        'r1': '16:9',
        'r2': '4:3',
        'bad1': '16-',
        'bad2': 'x:y',
        'bad3': '1:0'
      });
      expect(d.getRatio('r1')!, closeTo(16 / 9, 1e-9));
      expect(d.getRatio('r2')!, closeTo(4 / 3, 1e-9));
      expect(d.getRatio('bad1'), isNull);
      expect(d.getRatio('bad2'), isNull);
      expect(d.getRatio('bad3'), isNull);
      expect(d.getRatio('missing'), isNull);
    });

    test('getClampedInt parses and clamps into range', () {
      final d = docOf({'a': '5', 'b': '-2', 'c': '100', 'x': 'no'});
      expect(d.getClampedInt('a', min: 1, max: 10), 5);
      expect(d.getClampedInt('b', min: 0, max: 10), 0);
      expect(d.getClampedInt('c', min: 0, max: 10), 10);
      expect(d.getClampedInt('x', min: 0, max: 10), isNull);
      expect(d.getClampedInt('missing', min: 0, max: 10), isNull);
      // inverted bounds are handled
      expect(d.getClampedInt('a', min: 10, max: 1), 5);
    });

    test(
        'getListOfDocuments parses list of mini-documents with default separators',
        () {
      final d = docOf({
        'servers': 'host=foo,port=8080 | host=bar,port=9090 | invalid | ,',
      });
      final list = d.getListOfDocuments('servers')!;
      expect(list.length, 2);
      expect(list[0].entries, [
        const FlatEntry('host', 'foo'),
        const FlatEntry('port', '8080'),
      ]);
      expect(list[1].entries, [
        const FlatEntry('host', 'bar'),
        const FlatEntry('port', '9090'),
      ]);
    });

    test(
        'getListOfDocuments supports custom list/item separators and quoted values',
        () {
      final d = docOf({
        'cfg': 'k1="v=1";k2=2  /  x=3;y=" a , b "',
      });
      final list = d.getListOfDocuments(
        'cfg',
        listSep: '/',
        itemSep: ';',
        decodeEscapesInQuoted: true,
      )!;
      expect(list.length, 2);
      expect(list[0].entries, [
        const FlatEntry('k1', 'v=1'),
        const FlatEntry('k2', '2'),
      ]);
      expect(list[1].entries, [
        const FlatEntry('x', '3'),
        const FlatEntry('y', ' a , b '),
      ]);
    });

    test(
        'getListOfDocuments returns null when key missing and empty list for only invalid/empty',
        () {
      final d1 = docOf({});
      expect(d1.getListOfDocuments('missing'), isNull);
      final d2 = docOf({'s': ' | | '});
      expect(d2.getListOfDocuments('s')!, isEmpty);
    });

    test('getHostPort parses host, host:port and IPv6 bracket forms', () {
      final d = docOf({
        'h1': 'localhost',
        'h2': 'localhost:8080',
        'h3': '[::1]',
        'h4': '[::1]:443',
        'bad1': '[::1',
        'bad2': '[::1]x80',
        'bad3': 'host:port',
        'bad4': 'host:-1',
        'bad5': 'host:70000',
      });
      expect(d.getHostPort('h1')!, ('localhost', null));
      expect(d.getHostPort('h2')!, ('localhost', 8080));
      expect(d.getHostPort('h3')!, ('::1', null));
      expect(d.getHostPort('h4')!, ('::1', 443));
      expect(d.getHostPort('bad1'), isNull);
      expect(d.getHostPort('bad2'), isNull);
      expect(d.getHostPort('bad3'), isNull);
      expect(d.getHostPort('bad4'), isNull);
      expect(d.getHostPort('bad5'), isNull);
      expect(d.getHostPort('missing'), isNull);
    });

    test('debugDump formats entries with and without indexes', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', null),
      ]);
      final withIdx = doc.debugDump();
      expect(withIdx.split('\n'), ['[0] a = 1', '[1] b = null']);
      final noIdx = doc.debugDump(includeIndexes: false);
      expect(noIdx.split('\n'), ['a = 1', 'b = null']);
    });

    test('getListOrEmpty returns empty list when key is missing', () {
      final d = docOf({});
      expect(d.getListOrEmpty('missing'), isEmpty);
      expect(d.getListOrEmpty('missing'), isA<List<String>>());
    });

    test('getListOrEmpty returns parsed list when key exists', () {
      final d = docOf({'list': 'a, b, c'});
      expect(d.getListOrEmpty('list'), ['a', 'b', 'c']);
    });

    test('getListOrEmpty respects custom separator and options', () {
      final d = docOf({'list': 'a|b||c|'});
      expect(d.getListOrEmpty('list', separator: '|', skipEmpty: false),
          ['a', 'b', '', 'c', '']);
      expect(d.getListOrEmpty('list', separator: '|', skipEmpty: true),
          ['a', 'b', 'c']);
    });

    test('getSetOrEmpty returns empty set when key is missing', () {
      final d = docOf({});
      expect(d.getSetOrEmpty('missing'), isEmpty);
      expect(d.getSetOrEmpty('missing'), isA<Set<String>>());
    });

    test('getSetOrEmpty returns parsed set when key exists', () {
      final d = docOf({'set': 'A, a, B, b'});
      expect(d.getSetOrEmpty('set'), {'a', 'b'});
    });

    test('getSetOrEmpty respects custom separator and options', () {
      final d = docOf({'set': 'A|a||B|'});
      expect(d.getSetOrEmpty('set', separator: '|', skipEmpty: false),
          {'a', 'b', ''});
      expect(
          d.getSetOrEmpty('set', separator: '|', skipEmpty: true), {'a', 'b'});
    });

    test('getMapOrEmpty returns empty map when key is missing', () {
      final d = docOf({});
      expect(d.getMapOrEmpty('missing'), isEmpty);
      expect(d.getMapOrEmpty('missing'), isA<Map<String, String>>());
    });

    test('getMapOrEmpty returns parsed map when key exists', () {
      final d = docOf({'map': 'a:1, b:2, c:3'});
      expect(d.getMapOrEmpty('map'), {'a': '1', 'b': '2', 'c': '3'});
    });

    test('getMapOrEmpty respects custom separators and trim option', () {
      final d = docOf({'map': ' a : 1 , b : 2 '});
      expect(d.getMapOrEmpty('map', trim: true), {'a': '1', 'b': '2'});
      expect(d.getMapOrEmpty('map', trim: false), {' a ': ' 1 ', ' b ': ' 2 '});
    });

    test('getMapOrEmpty handles empty value gracefully', () {
      final d = docOf({'map': ''});
      expect(d.getMapOrEmpty('map'), isEmpty);
    });

    test('getMapOrEmpty ignores items without pair separator', () {
      final d = docOf({'map': 'a:1, invalid, b:2'});
      expect(d.getMapOrEmpty('map'), {'a': '1', 'b': '2'});
    });

    test('getColorTuple returns ARGB tuple components', () {
      final d = docOf({'c': '#336699'});
      final tuple = d.getColorTuple('c')!;
      expect(tuple.$1, 0xFF); // alpha
      expect(tuple.$2, 0x33); // red
      expect(tuple.$3, 0x66); // green
      expect(tuple.$4, 0x99); // blue
    });

    test(
        'getColorTuple cssAlphaAtEnd parameter controls 8-digit interpretation',
        () {
      final d = docOf({
        'css_style': '11223344', // RRGGBBAA format
        'traditional': '44112233', // AARRGGBB format
      });

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      final cssTuple = d.getColorTuple('css_style')!;
      expect(cssTuple.$1, 0x44); // alpha
      expect(cssTuple.$2, 0x11); // red
      expect(cssTuple.$3, 0x22); // green
      expect(cssTuple.$4, 0x33); // blue

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      final tradTuple = d.getColorTuple('traditional', cssAlphaAtEnd: false)!;
      expect(tradTuple.$1, 0x44); // alpha
      expect(tradTuple.$2, 0x11); // red
      expect(tradTuple.$3, 0x22); // green
      expect(tradTuple.$4, 0x33); // blue
    });

    test('getColorTuple returns null when hex invalid', () {
      final d = docOf({'c': '#ggg'});
      expect(d.getColorTuple('c'), isNull);
    });

    test('getColorTuple returns null when missing', () {
      final d = docOf({});
      expect(d.getColorTuple('missing'), isNull);
    });

    test('requireColorTuple returns value and throws on missing/invalid', () {
      final d1 = docOf({'c': '#00ff88'});
      final tuple = d1.requireColorTuple('c');
      expect(tuple.$1, 0xFF); // alpha
      expect(tuple.$2, 0x00); // red
      expect(tuple.$3, 0xFF); // green
      expect(tuple.$4, 0x88); // blue

      final d2 = docOf({'bad': '#xyz'});
      expect(() => d2.requireColorTuple('missing'), throwsFormatException);
      expect(() => d2.requireColorTuple('bad'), throwsFormatException);
    });

    test(
        'requireColorTuple cssAlphaAtEnd parameter controls 8-digit interpretation',
        () {
      final d = docOf({
        'css_style': '11223344', // RRGGBBAA format
        'traditional': '44112233', // AARRGGBB format
      });

      // Default behavior (cssAlphaAtEnd = true): RRGGBBAA -> AARRGGBB
      final cssTuple = d.requireColorTuple('css_style');
      expect(cssTuple.$1, 0x44); // alpha
      expect(cssTuple.$2, 0x11); // red
      expect(cssTuple.$3, 0x22); // green
      expect(cssTuple.$4, 0x33); // blue

      // Traditional behavior (cssAlphaAtEnd = false): AARRGGBB -> AARRGGBB (no change)
      final tradTuple =
          d.requireColorTuple('traditional', cssAlphaAtEnd: false);
      expect(tradTuple.$1, 0x44); // alpha
      expect(tradTuple.$2, 0x11); // red
      expect(tradTuple.$3, 0x22); // green
      expect(tradTuple.$4, 0x33); // blue
    });

    test('requireNum throws on missing/invalid and returns parsed value', () {
      final d1 = docOf({'i': '42', 'd': '3.14'});
      expect(d1.requireNum('i'), 42);
      expect(d1.requireNum('d'), closeTo(3.14, 1e-9));

      final d2 = docOf({'bad': 'not-a-number'});
      expect(() => d2.requireNum('missing'), throwsFormatException);
      expect(() => d2.requireNum('bad'), throwsFormatException);
    });

    test('requireRatio throws on missing/invalid and returns parsed value', () {
      final d1 = docOf({'r1': '16:9', 'r2': '4:3'});
      expect(d1.requireRatio('r1'), closeTo(16 / 9, 1e-9));
      expect(d1.requireRatio('r2'), closeTo(4 / 3, 1e-9));

      final d2 = docOf({'bad': '16-'});
      expect(() => d2.requireRatio('missing'), throwsFormatException);
      expect(() => d2.requireRatio('bad'), throwsFormatException);
    });
  });
}
