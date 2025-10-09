/// A Dart library for parsing and manipulating flat configuration files.
///
/// This library provides a simple and efficient way to work with flat configuration
/// files that use the `key = value` format. It supports:
///
/// - Parsing configuration files with comments and quoted values
/// - Preserving duplicate keys and their order
/// - Type-safe accessors for common data types
/// - File I/O operations for reading and writing config files
/// - Flexible encoding and parsing options
///
/// Example usage:
/// ```dart
/// import 'package:flatconfig/flatconfig.dart';
///
/// void main() {
///   const config = '''
///   # Application settings
///   background = 282c34
///   font-size = 14
///   debug = true
///   ''';
///
///   final doc = FlatConfig.parse(config);
///   print(doc['background']); // 282c34
///   print(doc.getInt('font-size')); // 14
///   print(doc.getBool('debug')); // true
/// }
/// ```
library flatconfig;

export 'src/document.dart' show FlatDocument, FlatEntry;
export 'src/document_accessors.dart' show FlatDocumentAccessors;
export 'src/document_extensions.dart'
    show CollapseOrder, FlatDocumentExtensions;
export 'src/exceptions.dart'
    show
        EmptyKeyException,
        MissingEqualsException,
        TrailingCharactersAfterQuoteException,
        UnterminatedQuoteException;
export 'src/io.dart' show FlatConfigIO, FlatDocumentIO, parseFlatFile;
export 'src/options.dart'
    show
        FlatEncodeOptions,
        FlatParseOptions,
        FlatStreamReadOptions,
        FlatStreamWriteOptions,
        OnErrorHandler;
export 'src/parser.dart' show FlatConfig;
