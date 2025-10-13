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
/// - Config file includes with Ghostty-compatible semantics
///
/// Example usage:
/// ```dart
/// import 'package:flatconfig/flatconfig.dart';
///
/// void main() async {
///   // Basic parsing
///   const config = '''
///   # Application settings
///   background = 343028
///   font-size = 14
///   debug = true
///   ''';
///
///   final doc = FlatConfig.parse(config);
///   print(doc['background']); // 343028
///   print(doc.getInt('font-size')); // 14
///   print(doc.getBool('debug')); // true
///
///   // Config file includes (Ghostty compatible)
///   final file = File('main.conf');
///   final docWithIncludes = await FlatConfig.parseWithIncludes(file);
///   print(docWithIncludes['theme']); // From included file
///
///   // Custom include key
///   final docCustom = await FlatConfig.parseWithIncludes(
///     file,
///     options: const FlatParseOptions(includeKey: 'include'),
///   );
/// }
/// ```
library flatconfig;

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
export 'src/includes.dart' show FileIncludes, FlatConfigIncludes;
export 'src/io.dart'
    show FlatConfigIO, FlatDocumentIO, parseFlatFile, parseFlatFileWithIncludes;
export 'src/options.dart'
    show
        FlatEncodeOptions,
        FlatParseOptions,
        FlatStreamReadOptions,
        FlatStreamWriteOptions,
        OnErrorHandler;
export 'src/parser.dart' show FlatConfig;
