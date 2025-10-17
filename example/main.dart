import 'package:flatconfig/flatconfig.dart';

void main() {
  // Sample configuration (could come from a file or network)
  const configText = '''
# FlatConfig Example - Game Settings
fullscreen = true
resolution = 1920x1080
volume = 80
theme = "dark"

music.enabled = yes
music.tracks = "main, intro, menu"
# duplicate key (last write wins)
music.tracks = "bonus"

player.name = "Guest"
player.score = 4200
player.active = on

# New features
auto-save = true
difficulty = "normal"
''';

  // Parse configuration text into a FlatDocument
  final doc = FlatConfig.parse(configText);

  print('🔍 Parsed document:');
  print(doc.debugDump());
  print('');

  // Access as Map using `toMap()`
  final map = doc.toMap();

  // Convenience accessors (with fallbacks)
  final fullscreen = doc.getBool('fullscreen') ?? false;
  final resolution = map['resolution'] ?? 'unknown';
  final volume = doc.getInt('volume') ?? 0;
  final playerName = map['player.name'] ?? 'Unknown';
  final score = doc.getInt('player.score') ?? 0;
  final musicTracks = (doc.valuesOf('music.tracks')).join(', ');
  final autoSave = doc.getBool('auto-save') ?? false;
  final difficulty = map['difficulty'] ?? 'normal';

  print('🎯 Accessed values:');
  print('Fullscreen: $fullscreen');
  print('Resolution: $resolution');
  print('Volume: $volume');
  print('Player: $playerName ($score points)');
  print('Music tracks: $musicTracks');
  print('Auto-save: $autoSave');
  print('Difficulty: $difficulty');

  // Collapse duplicate keys (keep last values)
  final collapsed = doc.collapse(order: CollapseOrder.lastWrite);

  print('\n🗜️ Collapsed document:');
  print(collapsed.toPrettyString(alignColumns: true));

  // Encode back to text
  final encoded = collapsed.encode();
  print('\n📝 Encoded text:');
  print(encoded);
}
