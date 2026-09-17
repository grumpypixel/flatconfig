@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flatconfig/flatconfig_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What a traversal refuses, and how it says so: the budgets that bound an
/// include graph, and the difference between an include that is missing and
/// one that merely cannot be read.

/// A graph where each level includes the one below it twice. Acyclic, shallow,
/// and tiny as text: `levels` of it expand to 2^levels entries.
Map<String, String> _doublingGraph(int levels) => {
  'l0.conf': 'leaf = x',
  for (var n = 1; n <= levels; n++)
    'l$n.conf': 'config-file = l${n - 1}.conf\nconfig-file = l${n - 1}.conf',
};

/// A resolver that answers nothing and records the targets it was handed.
final class _EchoResolver extends SyncIncludeResolver {
  final seen = <String>[];

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    seen.add(request.target);

    return IncludeUnit(id: request.target, content: '');
  }
}

/// A resolver that counts what it was asked to read.
final class _CountingMemoryResolver extends SyncIncludeResolver {
  _CountingMemoryResolver(this.units);

  final Map<String, String> units;
  var calls = 0;

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    calls++;
    final content = units[request.target];

    return content == null
        ? null
        : IncludeUnit(id: request.target, content: content);
  }
}

void main() {
  group('maxIncludedEntries', () {
    test('a doubling graph is stopped long before it is assembled', () {
      // 20 levels is 1,048,576 entries from roughly 900 characters of source.
      final resolver = _CountingMemoryResolver(_doublingGraph(20));

      expect(
        () => parseWithIncludesSync(
          'config-file = l20.conf',
          resolver: resolver,
          originId: 'main.conf',
        ),
        throwsA(
          isA<IncludeBudgetExceededException>()
              .having((e) => e.budget, 'budget', 'maxIncludedEntries')
              .having((e) => e.limit, 'limit', 100000),
        ),
      );
    });

    test('it is charged as entries are handed up, not at the end', () {
      // The point of the budget is to refuse before the allocation, so a limit
      // of 1 must stop at the first include rather than after expansion.
      final resolver = _CountingMemoryResolver(_doublingGraph(20));

      expect(
        () => parseWithIncludesSync(
          'config-file = l20.conf',
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludedEntries: 1),
          originId: 'main.conf',
        ),
        throwsA(isA<IncludeBudgetExceededException>()),
      );
      // One read per level on the way down, and no deeper: the doubling
      // happens while unwinding, which the budget never reaches.
      expect(resolver.calls, lessThan(25));
    });

    test('a graph inside the budget still assembles', () {
      final doc = parseWithIncludesSync(
        'config-file = l8.conf',
        resolver: _CountingMemoryResolver(_doublingGraph(8)),
        originId: 'main.conf',
      );

      expect(doc.length, 256);
    });

    test('the including document\'s own entries are not charged', () {
      final source = [for (var i = 0; i < 50; i++) 'k$i = v'].join('\n');

      expect(
        parseWithIncludesSync(
          '$source\nconfig-file = one.conf',
          resolver: _CountingMemoryResolver(const {'one.conf': 'a = 1'}),
          includeOptions: const FlatIncludeOptions(maxIncludedEntries: 1),
          originId: 'main.conf',
        ).length,
        51,
      );
    });
  });

  group('maxIncludes', () {
    test('it bounds how many directives a traversal follows', () {
      // Distinct targets, so the cache never spares a read. This is the shape
      // that costs a network resolver a request per directive.
      final units = {for (var i = 0; i < 40; i++) 'u$i.conf': 'k$i = v'};
      final source = [
        for (var i = 0; i < 40; i++) 'config-file = u$i.conf',
      ].join('\n');
      final resolver = _CountingMemoryResolver(units);

      expect(
        () => parseWithIncludesSync(
          source,
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludes: 10),
          originId: 'main.conf',
        ),
        throwsA(
          isA<IncludeBudgetExceededException>().having(
            (e) => e.budget,
            'budget',
            'maxIncludes',
          ),
        ),
      );
      expect(resolver.calls, 11);
    });

    test('the root document is not counted as an include', () {
      expect(
        parseWithIncludesSync(
          'a = 1',
          resolver: _CountingMemoryResolver(const {}),
          includeOptions: const FlatIncludeOptions(maxIncludes: 0),
          originId: 'main.conf',
        ).toMap(),
        {'a': '1'},
      );
    });
  });

  group('a symlinked include resolves the same way everywhere', () {
    // The File API resolved a nested relative include against the directory
    // the symlink sits in, while FileIncludeResolver used the target's
    // canonical path as the unit id and so resolved against the directory the
    // symlink points at. Same files, two documented-as-equivalent APIs, two
    // different documents.

    /// A directory holding a symlink to `real/theme.conf`, where both
    /// directories carry a different `colors.conf`. Which one is read says
    /// which directory the nested include was resolved against.
    ({File main, Directory root})? buildLinkedTree() {
      final root = Directory.systemTemp.createTempSync('flatconfig_link_');
      final real = Directory(p.join(root.path, 'real'))..createSync();
      final linked = Directory(p.join(root.path, 'linked'))..createSync();

      File(
        p.join(real.path, 'theme.conf'),
      ).writeAsStringSync('config-file = colors.conf\n');
      File(
        p.join(real.path, 'colors.conf'),
      ).writeAsStringSync('from = target directory\n');
      File(
        p.join(linked.path, 'colors.conf'),
      ).writeAsStringSync('from = link directory\n');

      try {
        Link(
          p.join(linked.path, 'theme.conf'),
        ).createSync(p.join(real.path, 'theme.conf'));
      } on FileSystemException {
        root.deleteSync(recursive: true);

        return null;
      }

      return (
        main: File(p.join(linked.path, 'main.conf'))
          ..writeAsStringSync('config-file = theme.conf\n'),
        root: root,
      );
    }

    test('both APIs resolve against the directory the link points at', () {
      final tree = buildLinkedTree();
      if (tree == null) {
        markTestSkipped('this platform does not allow creating symlinks');

        return;
      }
      addTearDown(() => tree.root.deleteSync(recursive: true));

      // A configuration file symlinked out of a dotfiles repository has to
      // find its neighbours there, which is the case this rule is chosen for.
      const expected = {'from': 'target directory'};

      expect(tree.main.parseWithIncludesSync().toMap(), expected);
      expect(
        parseWithIncludesSync(
          tree.main.readAsStringSync(),
          resolver: FileIncludeResolver(),
          originId: tree.main.path,
        ).toMap(),
        expected,
      );
    });
  });

  group('an unreadable include is not a missing one', () {
    // The implementation asked whether a file existed and then read it. Any
    // failure other than absence — no permission, a directory in the way —
    // came back as `false`, so a required include reported "missing" and an
    // optional one was skipped without a word.

    test('a permission failure propagates rather than reading as absent', () {
      if (Platform.isWindows) {
        markTestSkipped('chmod does not describe Windows permissions');

        return;
      }

      final dir = Directory.systemTemp.createTempSync('flatconfig_perm_');
      addTearDown(() {
        Process.runSync('chmod', ['700', dir.path]);
        dir.deleteSync(recursive: true);
      });

      final secret = File(p.join(dir.path, 'secret.conf'))
        ..writeAsStringSync('k = v\n');
      Process.runSync('chmod', ['000', secret.path]);

      try {
        secret.readAsStringSync();
        markTestSkipped('this user can read a mode-000 file');

        return;
      } on FileSystemException {
        // Good: unreadable for this user, which is the situation under test.
      }

      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('config-file = ?secret.conf\n');

      // Optional, so being treated as missing would mean silence.
      expect(main.parseWithIncludesSync, throwsA(isA<FileSystemException>()));
    });

    test('a directory named as an include is not reported as missing', () {
      final dir = Directory.systemTemp.createTempSync('flatconfig_dir_');
      addTearDown(() => dir.deleteSync(recursive: true));

      Directory(p.join(dir.path, 'theme.conf')).createSync();
      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('config-file = ?theme.conf\n');

      // Optional, so "missing" would mean silence. It is not missing; it is
      // unreadable, and that has to surface.
      expect(
        main.parseWithIncludesSync,
        throwsA(
          isA<FileSystemException>().having(
            (e) => e,
            'not a PathNotFoundException',
            isNot(isA<PathNotFoundException>()),
          ),
        ),
      );
    });

    test('a genuinely missing optional include is still skipped', () {
      final dir = Directory.systemTemp.createTempSync('flatconfig_absent_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('a = 1\nconfig-file = ?nope.conf\n');

      expect(main.parseWithIncludesSync().toMap(), {'a': '1'});
    });

    test('a genuinely missing required include still throws', () {
      final dir = Directory.systemTemp.createTempSync('flatconfig_req_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('config-file = nope.conf\n');

      expect(
        main.parseWithIncludesSync,
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('a missing root file still throws MissingIncludeException', () {
      final dir = Directory.systemTemp.createTempSync('flatconfig_root_');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(
        File(p.join(dir.path, 'nope.conf')).parseWithIncludesSync,
        throwsA(isA<MissingIncludeException>()),
      );
    });
  });

  group('an include path is decoded inside quotes and nowhere else', () {
    // Every path was escape-decoded, quoted or not, so a bare Windows UNC
    // path arrived at the resolver with one leading backslash instead of two.
    // An unquoted value is literal (SPEC.md 5).
    final echo = _EchoResolver();

    String target(String value, {bool decodeEscapes = true}) {
      echo.seen.clear();
      parseWithIncludesSync(
        'config-file = ?$value',
        resolver: echo,
        options: FlatParseOptions(decodeEscapesInQuoted: decodeEscapes),
      );

      return echo.seen.single;
    }

    test('an unquoted path keeps its backslashes', () {
      expect(target(r'\\server\share\x.conf'), r'\\server\share\x.conf');
      expect(target(r'C:\temp\x.conf'), r'C:\temp\x.conf');
    });

    test('the option does not apply to an unquoted path', () {
      expect(
        target(r'\\server\share\x.conf', decodeEscapes: false),
        r'\\server\share\x.conf',
      );
    });

    test('a quoted path is decoded once, and follows the option', () {
      expect(target(r'"\\server\share\x.conf"'), r'\server\share\x.conf');
      expect(
        target(r'"\\server\share\x.conf"', decodeEscapes: false),
        r'\\server\share\x.conf',
      );
    });

    test('the marker does not change what a quoted path means', () {
      // Without `?` the parser unquotes the value; with it the parser sees no
      // quotes and this does. The two used to disagree once the option was off.
      for (final decode in const [true, false]) {
        echo.seen.clear();
        parseWithIncludesSync(
          'config-file = "\\\\server\\share\\x.conf"',
          resolver: echo,
          options: FlatParseOptions(decodeEscapesInQuoted: decode),
        );
        final unmarked = echo.seen.single;

        expect(
          target(r'"\\server\share\x.conf"', decodeEscapes: decode),
          unmarked,
          reason: 'with decodeEscapesInQuoted: $decode',
        );
      }
    });
  });

  group('a resolver decodes its own units', () {
    test('FileIncludeResolver reads in the encoding it was given', () {
      // readOptions cannot reach here: a resolver hands the traversal text, so
      // by the time a unit exists the decoding has already happened.
      final dir = Directory.systemTemp.createTempSync('flatconfig_enc_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final theme = File(p.join(dir.path, 'theme.conf'))
        ..writeAsBytesSync(latin1.encode('name = Grüße\n'));

      expect(
        parseWithIncludesSync(
          'config-file = theme.conf',
          resolver: FileIncludeResolver(encoding: latin1),
          originId: p.join(dir.path, 'main.conf'),
        )['name'],
        'Grüße',
      );

      // The default reads the same bytes as UTF-8 and fails on them, which is
      // what makes the parameter worth having.
      expect(
        () => parseWithIncludesSync(
          'config-file = theme.conf',
          resolver: FileIncludeResolver(),
          originId: p.join(dir.path, 'main.conf'),
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('decode'),
          ),
        ),
      );

      expect(theme.existsSync(), isTrue);
    });
  });

  group('the budgets are checked where they are used', () {
    // A literal would be caught by the constructor's assertion at compile
    // time. Computing the value defers it to run time, where a debug build
    // asserts and a release build has to reach the traversal's own check.
    final negative = int.parse('-1');

    test('a negative maxIncludes is rejected', () {
      expect(
        () => parseWithIncludesSync(
          'a = 1',
          resolver: _CountingMemoryResolver(const {}),
          includeOptions: FlatIncludeOptions(maxIncludes: negative),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });

    test('a negative maxIncludedEntries is rejected', () {
      expect(
        () => parseWithIncludesSync(
          'a = 1',
          resolver: _CountingMemoryResolver(const {}),
          includeOptions: FlatIncludeOptions(maxIncludedEntries: negative),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });
  });
}
