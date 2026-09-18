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

/// A file resolver that records which half of its contract was used.
final class _WatchingFileResolver extends FileIncludeResolver {
  var asyncCalls = 0;
  var syncCalls = 0;

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) {
    asyncCalls++;

    return super.resolve(request);
  }

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    syncCalls++;

    return super.resolveSync(request);
  }
}

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

    test('the limit is the size of the result, not the work to build it', () {
      // A running total charged at each hand-off counts a unit again at every
      // ancestor it passes through. Sixteen levels of doubling assemble to
      // 65,536 entries and accumulated 131,070 charges, so a limit of 100,000
      // refused a result that never came near it.
      final resolver = _CountingMemoryResolver(_doublingGraph(16));

      expect(
        parseWithIncludesSync(
          'config-file = l16.conf',
          resolver: resolver,
          originId: 'main.conf',
        ).length,
        65536,
      );
    });

    test('one level further is refused', () {
      expect(
        () => parseWithIncludesSync(
          'config-file = l17.conf',
          resolver: _CountingMemoryResolver(_doublingGraph(17)),
          originId: 'main.conf',
        ),
        throwsA(isA<IncludeBudgetExceededException>()),
      );
    });

    test('it refuses before the allocation, not after it', () {
      // A limit of 1 must stop at the first include rather than after
      // expansion.
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
    /// A source naming [count] distinct targets, so the cache spares no
    /// request. This is the shape that costs a network resolver one round trip
    /// per directive.
    String directives(int count, {bool optional = false}) => [
      for (var i = 0; i < count; i++)
        'config-file = ${optional ? '?' : ''}u$i.conf',
    ].join('\n');

    test('it bounds how many requests a traversal makes', () {
      final resolver = _CountingMemoryResolver({
        for (var i = 0; i < 40; i++) 'u$i.conf': 'k$i = v',
      });

      expect(
        () => parseWithIncludesSync(
          directives(40),
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
      // Ten, not eleven: the budget is charged before the request, so the one
      // that breaches it is never made.
      expect(resolver.calls, 10);
    });

    test('a directive nobody answers still costs its request', () {
      // Charging on the way into the resolved unit let every unanswered
      // directive through for free, so this resolver was asked fifty times
      // under a limit of zero.
      final resolver = _CountingMemoryResolver(const {});

      expect(
        () => parseWithIncludesSync(
          directives(50, optional: true),
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludes: 0),
          originId: 'main.conf',
        ),
        throwsA(isA<IncludeBudgetExceededException>()),
      );
      expect(resolver.calls, isZero);
    });

    test('an optional include inside the budget is still skipped quietly', () {
      final resolver = _CountingMemoryResolver(const {});

      expect(
        parseWithIncludesSync(
          'a = 1\n${directives(3, optional: true)}',
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludes: 3),
          originId: 'main.conf',
        ).toMap(),
        {'a': '1'},
      );
      expect(resolver.calls, 3);
    });

    test('a directive naming nothing is free', () {
      // It reaches no resolver, so there is no request to charge for.
      final resolver = _CountingMemoryResolver(const {});

      expect(
        parseWithIncludesSync(
          'a = 1\nconfig-file =\nconfig-file = ?""',
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludes: 0),
          originId: 'main.conf',
        ).toMap(),
        {'a': '1'},
      );
      expect(resolver.calls, isZero);
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

    test('the rule holds when the root itself is the link', () {
      // The first fix only followed links for included children. A symlinked
      // root still parted ways: the File API resolved it, while the resolver
      // took the directory straight off the lexical originId.
      final root = Directory.systemTemp.createTempSync('flatconfig_root_link_');
      addTearDown(() => root.deleteSync(recursive: true));

      final real = Directory(p.join(root.path, 'real'))..createSync();
      final linked = Directory(p.join(root.path, 'linked'))..createSync();

      File(
        p.join(real.path, 'main.conf'),
      ).writeAsStringSync('config-file = colors.conf\n');
      File(
        p.join(real.path, 'colors.conf'),
      ).writeAsStringSync('from = target directory\n');
      File(
        p.join(linked.path, 'colors.conf'),
      ).writeAsStringSync('from = link directory\n');

      final linkedMain = File(p.join(linked.path, 'main.conf'));
      try {
        Link(linkedMain.path).createSync(p.join(real.path, 'main.conf'));
      } on FileSystemException {
        markTestSkipped('this platform does not allow creating symlinks');

        return;
      }

      const expected = {'from': 'target directory'};

      expect(linkedMain.parseWithIncludesSync().toMap(), expected);
      expect(
        parseWithIncludesSync(
          linkedMain.readAsStringSync(),
          resolver: FileIncludeResolver(),
          originId: linkedMain.path,
        ).toMap(),
        expected,
      );
    });

    test('an origin that is not a path falls back to its lexical form', () {
      // A resolver origin may be anything the caller chose, so resolving it
      // must not be a precondition for resolving relative targets.
      final dir = Directory.systemTemp.createTempSync('flatconfig_origin_');
      addTearDown(() => dir.deleteSync(recursive: true));

      File(p.join(dir.path, 'theme.conf')).writeAsStringSync('a = 1\n');

      expect(
        parseWithIncludesSync(
          'config-file = theme.conf',
          resolver: FileIncludeResolver(),
          originId: p.join(dir.path, 'no-such-main.conf'),
        ).toMap(),
        {'a': '1'},
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

    test('a filename that really contains quotes keeps them', () {
      // Without a marker the parser has already removed the outer layer and
      // decoded \" to ", leaving a name whose first and last characters are
      // quotes. Deciding by appearance took a second layer off and asked for a
      // different file. The helper above adds a marker, so this goes direct.
      echo.seen.clear();
      parseWithIncludesSync(
        r'config-file = "\"quoted path.conf\""',
        resolver: echo,
        originId: 'main.conf',
      );

      expect(echo.seen.single, '"quoted path.conf"');
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

  group('an awaited parse does not block on its includes', () {
    // FileIncludeResolver extends SyncIncludeResolver, whose asynchronous
    // method is derived from the synchronous one. Inheriting that made every
    // include of an awaited File.parseWithIncludes a blocking read, which an
    // event loop notices and no test noticed. Both halves are genuine now.

    test('the async entry point uses the async resolver method', () async {
      final dir = Directory.systemTemp.createTempSync('flatconfig_async_');
      addTearDown(() => dir.deleteSync(recursive: true));

      File(p.join(dir.path, 'theme.conf')).writeAsStringSync('a = 1\n');
      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('config-file = theme.conf\n');

      final watcher = _WatchingFileResolver();

      expect(
        (await parseWithIncludes(
          main.readAsStringSync(),
          resolver: watcher,
          originId: main.path,
        )).toMap(),
        {'a': '1'},
      );
      expect(watcher.syncCalls, isZero, reason: 'resolveSync was used');
      expect(watcher.asyncCalls, 1);
    });

    test('the sync entry point still uses the sync one', () {
      final dir = Directory.systemTemp.createTempSync('flatconfig_sync_');
      addTearDown(() => dir.deleteSync(recursive: true));

      File(p.join(dir.path, 'theme.conf')).writeAsStringSync('a = 1\n');
      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('config-file = theme.conf\n');

      final watcher = _WatchingFileResolver();

      expect(
        parseWithIncludesSync(
          main.readAsStringSync(),
          resolver: watcher,
          originId: main.path,
        ).toMap(),
        {'a': '1'},
      );
      expect(watcher.asyncCalls, isZero);
      expect(watcher.syncCalls, 1);
    });

    test('both halves resolve to the same unit', () async {
      final dir = Directory.systemTemp.createTempSync('flatconfig_both_');
      addTearDown(() => dir.deleteSync(recursive: true));

      File(p.join(dir.path, 'theme.conf')).writeAsStringSync('a = 1\n');
      final main = File(p.join(dir.path, 'main.conf'))
        ..writeAsStringSync('config-file = theme.conf\n');

      final request = IncludeRequest('theme.conf', fromId: main.path);
      final resolver = FileIncludeResolver();

      final viaAsync = await resolver.resolve(request);
      final viaSync = resolver.resolveSync(request);

      expect(viaAsync!.id, viaSync!.id);
      expect(viaAsync.content, viaSync.content);
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
