/// Following `config-file` directives, from anywhere a resolver can reach.
///
/// A document may name other documents to pull in. Where those live is the
/// resolver's business: a map in memory, a Flutter asset bundle, a row in a
/// database, an HTTP endpoint. For files on disk, import
/// `package:flatconfig/flatconfig_io.dart` instead, which resolves them for
/// you.
///
/// ```dart
/// import 'package:flatconfig/flatconfig_includes.dart';
///
/// final doc = parseWithIncludesSync(
///   'config-file = theme.conf\nfont-size = 14',
///   resolver: MemoryIncludeResolver({'theme.conf': 'background = 343028'}),
/// );
/// ```
///
/// Web- and WASM-safe. Re-exports `package:flatconfig/flatconfig.dart`, so one
/// import is enough.
///
/// {@canonicalFor parse_with_resolver.parseWithIncludes}
/// {@canonicalFor parse_with_resolver.parseWithIncludesSync}
/// {@canonicalFor include_resolver_core.CompositeIncludeResolver}
/// {@canonicalFor include_resolver_core.IncludeRequest}
/// {@canonicalFor include_resolver_core.IncludeResolver}
/// {@canonicalFor include_resolver_core.IncludeUnit}
/// {@canonicalFor include_resolver_core.MemoryIncludeResolver}
/// {@canonicalFor include_resolver_core.Resolvers}
/// {@canonicalFor include_resolver_core.SyncCompositeIncludeResolver}
/// {@canonicalFor include_resolver_core.SyncIncludeResolver}
/// {@canonicalFor options.FlatIncludeOptions}
/// {@canonicalFor options.IncludeMergePolicy}
/// {@canonicalFor exceptions.CircularIncludeException}
/// {@canonicalFor exceptions.ConfigIncludeException}
/// {@canonicalFor exceptions.IncludeBudgetExceededException}
/// {@canonicalFor exceptions.MaxIncludeDepthExceededException}
/// {@canonicalFor exceptions.MissingIncludeException}
library;

export 'flatconfig.dart';
export 'src/exceptions.dart'
    show
        CircularIncludeException,
        ConfigIncludeException,
        IncludeBudgetExceededException,
        MaxIncludeDepthExceededException,
        MissingIncludeException;
export 'src/include_resolver_core.dart'
    show
        CompositeIncludeResolver,
        IncludeRequest,
        IncludeResolver,
        IncludeUnit,
        MemoryIncludeResolver,
        Resolvers,
        SyncCompositeIncludeResolver,
        SyncIncludeResolver;
export 'src/options.dart' show FlatIncludeOptions, IncludeMergePolicy;
export 'src/parse_with_resolver.dart'
    show parseWithIncludes, parseWithIncludesSync;
