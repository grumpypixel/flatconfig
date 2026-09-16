/// Reading, editing and writing the flat configuration format: one
/// `key = value` per line, no nesting, duplicates kept in order.
///
/// ```dart
/// import 'package:flatconfig/flatconfig.dart';
///
/// final doc = FlatDocument.parse('background = 343028\nfont-size = 14');
/// print(doc.requireInt('font-size')); // 14
/// ```
///
/// Web- and WASM-safe: nothing here touches `dart:io`. The rest of the package
/// is in three further libraries, each of which re-exports this one:
///
/// - `package:flatconfig/flatconfig_io.dart` — reading and writing files. Needs
///   `dart:io`, so it is the one library a web program cannot import.
/// - `package:flatconfig/flatconfig_includes.dart` — following `config-file`
///   directives through a resolver, from memory, a bundle or the network.
/// - `package:flatconfig/flatconfig_accessors.dart` — accessors for `DateTime`,
///   `Duration`, `Uri`, JSON and enums.
library;

export 'src/document.dart'
    show CollapseOrder, FlatConverter, FlatDocument, FlatEntry;
export 'src/exceptions.dart'
    show
        EmptyKeyException,
        FlatParseException,
        InvalidKeyException,
        MissingEqualsException,
        TrailingCharactersAfterQuoteException,
        UnterminatedQuoteException;
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
export 'src/issue.dart' show FlatIssue, FlatIssueKind, OnIssue;
export 'src/lookup.dart' show FlatAbsent, FlatLookup, FlatPresent, FlatReset;
export 'src/options.dart'
    show
        FlatEncodeOptions,
        FlatEnvOptions,
        FlatParseOptions,
        FlatStreamReadOptions,
        FlatStreamWriteOptions,
        MissingVariablePolicy,
        MultilineValuePolicy;
export 'src/parser_utils.dart' show indexOfUnquoted, splitRespectingQuotes;
