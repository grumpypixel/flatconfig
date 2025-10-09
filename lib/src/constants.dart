import 'package:meta/meta.dart';

@internal
class Constants {
  /// Character codes
  static const backslashCharCode = 0x5C;
  static const blankCharCode = 0x20;
  static const carriageReturnCharCode = 0x0D;
  static const newlineCharCode = 0x0A;
  static const quoteCharCode = 0x22;
  static const tabCharCode = 0x09;

  /// Byte Order Mark (BOM) character code
  static const bomCharCode = 0xFEFF;

  static const backslash = '\\';
  static const carriageReturn = '\r';
  static const commentPrefix = '#';
  static const newline = '\n';
  static const pairSeparator = '=';
  static const quote = '"';

  static final bytesRegex =
      RegExp(r'^([+-]?\d+(?:\.\d+)?)(b|kb|mb|gb|tb|pb|kib|mib|gib|tib|pib)?$');
  static final durationRegex = RegExp(r'^([+-]?\d+(?:\.\d+)?)(ms|s|m|h|d)?$');

  static final hexColorRegex = RegExp(r'^[0-9a-f]+$');
}
