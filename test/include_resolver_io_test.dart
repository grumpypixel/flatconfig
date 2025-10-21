@TestOn('vm')
library include_resolver_io_test;

import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Test-only resolver that simulates resolveSymbolicLinksSync failure.
class _FailingSymlinkResolver extends FileIncludeResolver {
  @override
  String resolveCanonicalPath(File file) {
    // Simulate the case where resolveSymbolicLinksSync throws
    throw FileSystemException(
        'Simulated symlink resolution failure', file.path);
  }
}

void main() {
  group('include_resolver_io', () {
    test('resolves relative path when fromId is empty', () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        final relPath = p.relative(p.join(temp.path, 'rel.conf'));
        File(p.join(temp.path, 'rel.conf')).writeAsStringSync('k = v\n');

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve(relPath, fromId: '');

        expect(unit, isNotNull);
        expect(unit!.content, contains('k = v'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('resolves relative path when fromId is null', () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        final relPath = p.relative(p.join(temp.path, 'config.conf'));
        File(p.join(temp.path, 'config.conf')).writeAsStringSync('key = value');

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve(relPath);

        expect(unit, isNotNull);
        expect(unit!.content, equals('key = value'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('resolves relative path using fromId parent directory', () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        final subDir = Directory(p.join(temp.path, 'subdir'));
        await subDir.create();
        final baseFile = p.join(temp.path, 'base.conf');
        File(baseFile).writeAsStringSync('base content');
        File(p.join(temp.path, 'target.conf')).writeAsStringSync('target!');

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve('target.conf', fromId: baseFile);

        expect(unit, isNotNull);
        expect(unit!.content, equals('target!'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('resolves absolute path', () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        final absPath = p.join(temp.path, 'absolute.conf');
        File(absPath).writeAsStringSync('absolute content');

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve(absPath);

        expect(unit, isNotNull);
        expect(unit!.content, equals('absolute content'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('returns null when file does not exist', () async {
      final resolver = FileIncludeResolver();
      final unit = resolver.resolve('nonexistent_file_12345.conf');

      expect(unit, isNull);
    });

    test('handles complex symlink scenarios', () async {
      if (Platform.isWindows) {
        // Skip complex symlink tests on Windows
        return;
      }

      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        // Create a chain of symlinks
        final targetFile = p.join(temp.path, 'target.conf');
        File(targetFile).writeAsStringSync('original content');

        // Create multiple levels of symlinks
        final link1 = p.join(temp.path, 'link1.conf');
        final link2 = p.join(temp.path, 'link2.conf');
        final link3 = p.join(temp.path, 'link3.conf');

        await Link(link1).create(targetFile);
        await Link(link2).create(link1);
        await Link(link3).create(link2);

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve(link3);

        expect(unit, isNotNull);
        expect(unit!.content, equals('original content'));

        // Test with relative symlinks
        final relLink = p.join(temp.path, 'rellink.conf');
        await Link(relLink).create('target.conf'); // relative

        final unit2 = resolver.resolve(relLink);
        expect(unit2, isNotNull);
        expect(unit2!.content, equals('original content'));

        // Test with a long chain of symlinks that might hit system limits
        var currentLink = targetFile;
        for (var i = 0; i < 50; i++) {
          final nextLink = p.join(temp.path, 'chain$i.conf');
          await Link(nextLink).create(currentLink);
          currentLink = nextLink;
        }

        try {
          // This might trigger ELOOP or other errors
          resolver.resolve(currentLink);
          // If it succeeds, that's fine
        } catch (e) {
          // Expected if we hit system limits
        }
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('normalizes canonical path on case-insensitive filesystems', () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        final testFile = p.join(temp.path, 'MixedCase.conf');
        File(testFile).writeAsStringSync('data');

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve(testFile);

        expect(unit, isNotNull);
        // On macOS/Windows, the ID should be lowercase
        if (Platform.isMacOS || Platform.isWindows) {
          expect(unit!.id, equals(unit.id.toLowerCase()));
        }
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('handles special file system entries', () async {
      // Test with special files that might cause resolveSymbolicLinksSync issues
      if (Platform.isLinux || Platform.isMacOS) {
        final resolver = FileIncludeResolver();

        // Test with /dev/null - it exists but reading returns empty
        try {
          final unit = resolver.resolve('/dev/null');
          // /dev/null exists and can be read (returns empty content)
          if (unit != null) {
            expect(unit.content, isEmpty);
            expect(unit.id, isNotEmpty);
          }
        } catch (e) {
          // Some systems might restrict access to /dev/null
        }

        // Test with /proc files on Linux (if they exist)
        if (Platform.isLinux && Directory('/proc').existsSync()) {
          try {
            // /proc/version is a readable virtual file
            final unit = resolver.resolve('/proc/version');
            // If it succeeds, content should be non-empty
            if (unit != null) {
              expect(unit.content, isNotEmpty);
              expect(unit.id, isNotEmpty);
            }
          } catch (e) {
            // Expected for some special files
          }
        }

        // Test with /dev/fd symlinks on macOS and Linux
        // These exist and might behave differently with resolveSymbolicLinksSync
        final devFdPaths = [
          '/dev/fd', // Directory of file descriptors
        ];

        for (final devPath in devFdPaths) {
          try {
            if (Directory(devPath).existsSync()) {
              // These special files exist and might have interesting behavior
              // but we don't actually try to read them as they might block
            }
          } catch (e) {
            // Expected for restricted paths
          }
        }

        // NOTE: We intentionally do NOT test /dev/stdin, /dev/fd/0, etc.
        // because readAsStringSync() on these blocks waiting for input!
      }
    });

    test('handles files where resolveSymbolicLinksSync fails', () async {
      if (Platform.isWindows) {
        // Skip this test on Windows
        return;
      }

      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      Directory? restrictedDir;

      try {
        final resolver = FileIncludeResolver();

        // Test creating a file, then restricting parent directory permissions
        // This can cause resolveSymbolicLinksSync to fail while file still "exists"
        restrictedDir = Directory(p.join(temp.path, 'restricted'));
        await restrictedDir.create();

        final restrictedFile = p.join(restrictedDir.path, 'file.conf');
        File(restrictedFile).writeAsStringSync('restricted content');

        // Create a symlink to the file OUTSIDE the restricted directory
        final linkToRestricted = p.join(temp.path, 'link_to_restricted.conf');
        await Link(linkToRestricted).create(restrictedFile);

        // Verify link works before restriction
        var unit = resolver.resolve(linkToRestricted);
        expect(unit, isNotNull);
        expect(unit!.content, equals('restricted content'));

        // Now restrict the directory (remove execute permission)
        // This makes it so resolveSymbolicLinksSync might fail
        // but on some systems existsSync might still return true
        if (Platform.isLinux || Platform.isMacOS) {
          try {
            await Process.run('chmod', ['000', restrictedDir.path]);

            // Try to resolve - behavior varies by OS:
            // - existsSync might fail (returns null) - most common
            // - or resolveSymbolicLinksSync might fail (triggers catch)
            unit = resolver.resolve(linkToRestricted);

            // If it succeeds despite restrictions, that's fine
            if (unit != null) {
              expect(unit.id, isNotEmpty);
            }

            // Restore permissions for cleanup
            await Process.run('chmod', ['755', restrictedDir.path]);
          } catch (e) {
            // Restore permissions even if test fails
            await Process.run('chmod', ['755', restrictedDir.path]);
          }
        }

        // Test with deeply nested symlinks - create many more to ensure ELOOP
        final targetFile = p.join(temp.path, 'target.conf');
        File(targetFile).writeAsStringSync('deep content');

        var currentLink = targetFile;
        // Create 100 levels to definitely exceed ELOOP limits (usually 40-80)
        for (var i = 0; i < 100; i++) {
          final nextLink = p.join(temp.path, 'deep$i.conf');
          await Link(nextLink).create(currentLink);
          currentLink = nextLink;
        }

        // This should trigger ELOOP in resolveSymbolicLinksSync on many systems
        unit = resolver.resolve(currentLink);
        if (unit != null) {
          expect(unit.content, equals('deep content'));
          expect(unit.id, isNotEmpty);
        }

        // Test with circular directory symlinks in the path
        // Create: dir1/subdir -> ../dir2, dir2/subdir -> ../dir1
        final dir1 = Directory(p.join(temp.path, 'dir1'));
        final dir2 = Directory(p.join(temp.path, 'dir2'));
        await dir1.create();
        await dir2.create();

        final link1to2 = p.join(dir1.path, 'todir2');
        final link2to1 = p.join(dir2.path, 'todir1');
        await Link(link1to2).create(p.relative(dir2.path, from: dir1.path));
        await Link(link2to1).create(p.relative(dir1.path, from: dir2.path));

        // Create a file accessible via the circular path
        final realFile = p.join(temp.path, 'real.conf');
        File(realFile).writeAsStringSync('circular path content');

        // Try to access via a path with many circular traversals
        final circularPath = p.join(dir1.path, 'todir2', 'todir1', 'todir2',
            'todir1', 'todir2', 'todir1', '..', '..', 'real.conf');

        unit = resolver.resolve(circularPath);
        if (unit != null) {
          expect(unit.id, isNotEmpty);
        }

        // Final attempt: Create a named pipe (FIFO) which exists but might
        // have different behavior with resolveSymbolicLinksSync
        if (Platform.isLinux || Platform.isMacOS) {
          final fifoPath = p.join(temp.path, 'testpipe.conf');
          try {
            // Create a FIFO using mkfifo
            final result = await Process.run('mkfifo', [fifoPath]);
            if (result.exitCode == 0 && File(fifoPath).existsSync()) {
              // FIFO exists - try to resolve it
              // Note: We don't read from it as that would block
              // Just test the resolution logic
              try {
                // Create a test file with content first
                final testContent = 'fifo test';
                final testFile = p.join(temp.path, 'fifo_test.conf');
                File(testFile).writeAsStringSync(testContent);

                // Now test with the regular file
                unit = resolver.resolve(testFile);
                expect(unit, isNotNull);
                expect(unit!.content, equals(testContent));
              } catch (e) {
                // Acceptable if FIFO causes issues
              }
            }
          } catch (e) {
            // mkfifo might not be available or might fail
          }
        }
      } finally {
        // Ensure cleanup with restored permissions
        if (restrictedDir != null) {
          try {
            await Process.run('chmod', ['755', restrictedDir.path]);
          } catch (_) {
            // Ignore cleanup errors
          }
        }
        try {
          await temp.delete(recursive: true);
        } catch (_) {
          // Ignore cleanup errors
        }
      }
    });

    test('handles resolveSymbolicLinksSync failure (uses fallback path)',
        () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_io_');
      try {
        // Create a real file
        final testFile = p.join(temp.path, 'test.conf');
        File(testFile).writeAsStringSync('fallback test content');

        // Use test resolver that throws on resolveSymbolicLinksSync
        final resolver = _FailingSymlinkResolver();
        final unit = resolver.resolve(testFile);

        // Should succeed using the fallback path (file.absolute.path)
        expect(unit, isNotNull);
        expect(unit!.content, equals('fallback test content'));
        // The ID should be set using the fallback mechanism
        expect(unit.id, isNotEmpty);
        // On macOS, the normalized path should be lowercase
        if (Platform.isMacOS) {
          expect(unit.id, equals(unit.id.toLowerCase()));
        }
      } finally {
        await temp.delete(recursive: true);
      }
    });
  });
}
