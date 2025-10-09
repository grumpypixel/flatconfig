// example/basic.dart
//
// Run with: dart run example/basic.dart

import 'package:flatconfig/flatconfig.dart';

void main() {
  // Sample configuration (could come from a file)
  const configText = '''
# FlatConfig Example
fullscreen = true
resolution = 1920x1080
volume = 80
theme = "dark"
music.enabled = yes
music.tracks = "main, intro, menu"
music.tracks = "bonus" # duplicate key
player.name = "Guest"
player.score = 4200
player.active = on
''';

  // Parse configuration text into a FlatDocument
  final doc = FlatConfig.parse(configText);

  print('--- Parsed document ---');
  print(doc.debugDump());

  // Access values using convenience accessors
  final fullscreen = doc.getBool('fullscreen') ?? false;
  final resolution = doc['resolution'];
  final volume = doc.getInt('volume') ?? 0;
  final playerName = doc['player.name'];
  final score = doc.getInt('player.score');
  final musicTracks = doc.valuesOf('music.tracks');

  print('\n--- Accessed values ---');
  print('Fullscreen: $fullscreen');
  print('Resolution: $resolution');
  print('Volume: $volume');
  print('Player: $playerName ($score points)');
  print('Music tracks: $musicTracks');

  // Collapse duplicate keys (keep last values)
  final collapsed = doc.collapse(order: CollapseOrder.lastWrite);

  print('\n--- Collapsed document ---');
  print(collapsed.toPrettyString(alignColumns: true));

  // Encode back to text
  final encoded = collapsed.encode();
  print('\n--- Encoded text ---');
  print(encoded);
}
