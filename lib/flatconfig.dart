// Main barrel file for the flatconfig package.
//
// This entrypoint is Web- and WASM-safe:
// - Pure parsing APIs (FlatConfig, FlatDocument, etc.) are always available.
// - File and include APIs are conditionally exported only on dart:io platforms.
export 'src/document.dart' show FlatDocument, FlatEntry;
export 'src/document_accessors.dart' show FlatDocumentAccessors;
export 'src/document_extensions.dart'
    show CollapseOrder, FlatDocumentExtensions;

export 'src/exceptions.dart'
    show
        CircularIncludeException,
        ConfigIncludeException,
        EmptyKeyException,
        MaxIncludeDepthExceededException,
        MissingEqualsException,
        MissingIncludeException,
        TrailingCharactersAfterQuoteException,
        UnterminatedQuoteException;

// Map/List flattening → FlatDocument.fromMapData + options/hooks/utils
export 'src/from_map_data.dart'
    show
        CsvItemEncoder,
        FlatListMode,
        FlatMapDataOptions,
        FlatUnsupportedListItem,
        FlatValueEncoder,
        KeyEscaper,
        flatDocumentFromMapData,
        rfc4180CsvItemEncoder,
        rfc4180Quote;

// Conditional export: includes (export the whole file, otherwise the Extensions won't work)
export 'src/includes_stub.dart' if (dart.library.io) 'src/includes.dart';

// Conditional export: file I/O (export the whole file)
export 'src/io_stub.dart' if (dart.library.io) 'src/io.dart';

export 'src/options.dart'
    show
        FlatEncodeOptions,
        FlatParseOptions,
        FlatStreamReadOptions,
        FlatStreamWriteOptions,
        OnErrorHandler;

export 'src/parser.dart' show FlatConfig;
