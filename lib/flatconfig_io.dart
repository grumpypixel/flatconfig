/// Reading and writing flat configuration files on disk.
///
/// Everything here hangs off [File], so a path is spelled the same way it is
/// everywhere else in Dart:
///
/// ```dart
/// import 'dart:io';
/// import 'package:flatconfig/flatconfig_io.dart';
///
/// final doc = await File('main.conf').parseWithIncludes();
/// await File('out.conf').writeFlat(doc.withValue('font-size', '16'));
/// ```
///
/// Needs `dart:io`, so this is the one library a web or WASM program cannot
/// import — there, use `package:flatconfig/flatconfig.dart` and resolve
/// includes through `package:flatconfig/flatconfig_includes.dart`.
///
/// Re-exports the core and include libraries, so one import is enough.
library;

export 'flatconfig.dart';
export 'flatconfig_includes.dart';
export 'src/include_resolver_io.dart' show FileIncludeResolver;
export 'src/io.dart' show FlatConfigIO;
