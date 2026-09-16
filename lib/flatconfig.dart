// Main barrel file for the flatconfig package.
//
// This entrypoint is Web- and WASM-safe:
// - Pure parsing APIs (FlatDocument, FlatEntry, etc.) are always available.
// - File and include APIs are conditionally exported only on dart:io platforms.
export 'src/document.dart'
    show CollapseOrder, FlatConverter, FlatDocument, FlatEntry;
export 'src/exceptions.dart'
    show
        CircularIncludeException,
        ConfigIncludeException,
        EmptyKeyException,
        FlatParseException,
        InvalidKeyException,
        MaxIncludeDepthExceededException,
        MissingEqualsException,
        MissingIncludeException,
        TrailingCharactersAfterQuoteException,
        UnterminatedQuoteException;
// Map/List flattening → FlatDocument.fromMapData + options/hooks/utils
export 'src/from_map_data.dart'
    show
        CsvItemEncoder,
        FlatDataOptions,
        FlatListMode,
        FlatUnsupportedListItem,
        FlatValueEncoder,
        KeyEscaper,
        flatDocumentFromMapData,
        rfc4180CsvItemEncoder,
        rfc4180Quote;

/// Include resolver core types and interfaces
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
// If we're on the web (dart:html), use the stub; otherwise use the IO version.
export 'src/include_resolver_io.dart'
    if (dart.library.html) 'src/include_resolver_stub.dart'
    show FileIncludeResolver;
// Conditional export: includes (export the whole file, otherwise the Extensions won't work)
export 'src/includes_stub.dart' if (dart.library.io) 'src/includes.dart';
// Conditional export: file I/O (export the whole file)
export 'src/io_stub.dart' if (dart.library.io) 'src/io.dart';
export 'src/issue.dart' show FlatIssue, FlatIssueKind, OnIssue;
export 'src/lookup.dart' show FlatAbsent, FlatLookup, FlatPresent, FlatReset;
export 'src/options.dart'
    show
        FlatEncodeOptions,
        FlatEnvOptions,
        FlatIncludeOptions,
        FlatParseOptions,
        FlatStreamReadOptions,
        FlatStreamWriteOptions,
        IncludeMergePolicy,
        MissingVariablePolicy,
        MultilineValuePolicy;
// Resolver-based include support (web-safe core + conditional IO resolver)
export 'src/parse_with_resolver.dart' show FlatConfigResolverIncludes;
