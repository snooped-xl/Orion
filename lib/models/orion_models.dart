import 'package:flutter/material.dart';

enum OrionAccent { blue, lime, lavender, coral }

extension OrionAccentDetails on OrionAccent {
  String get label => switch (this) {
    OrionAccent.blue => 'Orion blue',
    OrionAccent.lime => 'Orbit lime',
    OrionAccent.lavender => 'Soft lavender',
    OrionAccent.coral => 'Solar coral',
  };

  Color get color => switch (this) {
    OrionAccent.blue => const Color(0xFF88B5FF),
    OrionAccent.lime => const Color(0xFFD5F58D),
    OrionAccent.lavender => const Color(0xFFC7B9F8),
    OrionAccent.coral => const Color(0xFFF3BBA1),
  };
}

class EditorDocument {
  const EditorDocument({
    required this.id,
    required this.name,
    required this.content,
    required this.savedContent,
    this.filePath,
  });

  final String id;
  final String name;
  final String content;
  final String savedContent;
  final String? filePath;

  bool get isDirty => content != savedContent;
  static final _lineCounts = Expando<int>('editor-document-line-count');
  int get lineCount => _lineCounts[this] ??= content.split('\n').length;
  String get title => name;

  EditorDocument copyWith({
    String? name,
    String? content,
    String? savedContent,
    String? filePath,
  }) => EditorDocument(
    id: id,
    name: name ?? this.name,
    content: content ?? this.content,
    savedContent: savedContent ?? this.savedContent,
    filePath: filePath ?? this.filePath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'content': content,
    'savedContent': savedContent,
    'filePath': filePath,
  };

  static EditorDocument? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final name = value['name'];
    final content = value['content'];
    final savedContent = value['savedContent'];
    if (id is! String || name is! String || content is! String) return null;
    if (id.isEmpty || name.isEmpty) return null;
    return EditorDocument(
      id: id,
      name: name,
      content: content,
      savedContent: savedContent is String ? savedContent : content,
      filePath: value['filePath'] is String
          ? value['filePath'] as String
          : null,
    );
  }
}

class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.title,
    required this.description,
    required this.collection,
    required this.tags,
    required this.source,
  });

  final String id;
  final String title;
  final String description;
  final String collection;
  final List<String> tags;
  final String source;

  int get lineCount => source.split('\n').length;
  String get fileName => '${id.replaceAll('-', '_')}.lua';
  String get language => 'Lua';
}

enum ActivityKind { workspace, file, library, execution, settings }

enum ActivitySeverity { info, success, warning, error }

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.title,
    required this.detail,
    required this.kind,
    required this.severity,
    required this.timestamp,
  });

  final String id;
  final String title;
  final String detail;
  final ActivityKind kind;
  final ActivitySeverity severity;
  final DateTime timestamp;

  String get message => detail;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'detail': detail,
    'kind': kind.name,
    'severity': severity.name,
    'timestamp': timestamp.toIso8601String(),
  };

  static ActivityEntry? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    // Retire old simulated session records when upgrading a local workspace.
    if (value['kind'] == 'demo') return null;
    final id = value['id'];
    final title = value['title'];
    final detail = value['detail'];
    final time = value['timestamp'];
    if (id is! String ||
        title is! String ||
        detail is! String ||
        time is! String) {
      return null;
    }
    final timestamp = DateTime.tryParse(time);
    if (timestamp == null) return null;
    return ActivityEntry(
      id: id,
      title: title,
      detail: detail,
      kind: ActivityKind.values.firstWhere(
        (kind) => kind.name == value['kind'],
        orElse: () => ActivityKind.workspace,
      ),
      severity: ActivitySeverity.values.firstWhere(
        (severity) => severity.name == value['severity'],
        orElse: () => ActivitySeverity.info,
      ),
      timestamp: timestamp,
    );
  }
}

const constellationSource = '''-- ORION / a little room for big ideas
-- A Lua scene sketch: data and geometry for an interface.

local scene = {
  name = "Constellation",
  background = "#141713",
  accent = "#C6F27B",
  stars = 48,
}

local function orbit(angle, radius)
  return {
    x = math.cos(angle) * radius,
    y = math.sin(angle) * radius,
  }
end

local function createStar(index)
  local progress = index / scene.stars
  local position = orbit(progress * math.pi * 2, 160)

  return {
    id = "star_" .. index,
    position = position,
    size = 2 + (index % 4),
    opacity = 0.35 + progress * 0.65,
  }
end

local constellation = {}

for index = 1, scene.stars do
  constellation[index] = createStar(index)
end

local function welcome(name)
  return "Welcome to " .. name .. ". Make something brilliant."
end

print(welcome("Orion"))
print("Scene ready: " .. scene.name)
print("Stars in orbit: " .. #constellation)
''';

const sampleLibraryItems = <LibraryItem>[
  LibraryItem(
    id: 'orbit-canvas',
    title: 'Orbit canvas',
    description: 'A quiet constellation built from a little trigonometry.',
    collection: 'Templates',
    tags: ['Starter', 'Canvas', 'Featured'],
    source: constellationSource,
  ),
  LibraryItem(
    id: 'glass-panel',
    title: 'Glass panel',
    description:
        'Explore layers, soft corners, and a considered color palette.',
    collection: 'Interface',
    tags: ['Layout', 'Design'],
    source: '''-- GLASS PANEL / interface data sketch
local panel = {
  title = "A little clarity",
  width = 420,
  padding = 24,
  radius = 28,
  surface = "#20251F",
  border = "#3E4837",
}

local sections = {
  { title = "Workspace", description = "Everything in its place" },
  { title = "Explore", description = "Leave room for discovery" },
  { title = "Create", description = "Start with one good idea" },
}

for index, section in ipairs(sections) do
  print(index .. ". " .. section.title .. " — " .. section.description)
end

print("Panel width: " .. panel.width)
''',
  ),
  LibraryItem(
    id: 'radial-menu',
    title: 'Radial menu',
    description: 'Arrange a handful of actions around a shared center.',
    collection: 'Interface',
    tags: ['Interaction', 'Geometry'],
    source: '''-- RADIAL MENU / geometry sketch
local actions = { "Create", "Open", "Save", "Explore", "Settings" }
local radius = 96
local center = { x = 200, y = 200 }

local function position(index, count)
  local angle = ((index - 1) / count) * math.pi * 2 - math.pi / 2
  return {
    x = center.x + math.cos(angle) * radius,
    y = center.y + math.sin(angle) * radius,
  }
end

for index, label in ipairs(actions) do
  local point = position(index, #actions)
  print(string.format("%s → %.1f, %.1f", label, point.x, point.y))
end
''',
  ),
  LibraryItem(
    id: 'palette-studio',
    title: 'Palette studio',
    description: 'Three expressive palettes for your next experiment.',
    collection: 'Templates',
    tags: ['Color', 'Starter'],
    source: '''-- PALETTE STUDIO / color collection
local palettes = {
  orbit = { "#C6F27B", "#293321", "#F3F6EA" },
  dusk = { "#C6B7FF", "#312A42", "#F2EDFF" },
  solar = { "#FFB19E", "#402A25", "#FFF1EA" },
}

local function describe(name, colors)
  return name .. ": " .. table.concat(colors, ", ")
end

for name, colors in pairs(palettes) do
  print(describe(name, colors))
end

print("Try a color. Follow your curiosity.")
''',
  ),
  LibraryItem(
    id: 'easing-curves',
    title: 'Easing curves',
    description: 'Give small movements a softer beginning and ending.',
    collection: 'Utilities',
    tags: ['Motion', 'Math'],
    source: '''-- EASING CURVES / motion math
local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function smoothstep(t)
  t = clamp(t, 0, 1)
  return t * t * (3 - 2 * t)
end

local function easeOutCubic(t)
  return 1 - (1 - clamp(t, 0, 1)) ^ 3
end

for frame = 0, 10 do
  local t = frame / 10
  print(string.format("%.1f  smooth %.3f  cubic %.3f", t, smoothstep(t), easeOutCubic(t)))
end
''',
  ),
  LibraryItem(
    id: 'focus-timer',
    title: 'Focus timer',
    description: 'A tiny formatter for making time feel a little calmer.',
    collection: 'Utilities',
    tags: ['Tools', 'Strings'],
    source: '''-- FOCUS TIMER / a simple time formatter
local session = {
  label = "Make space to create",
  minutes = 25,
  breakMinutes = 5,
}

local function formatTime(seconds)
  local minutes = math.floor(seconds / 60)
  local remaining = seconds % 60
  return string.format("%02d:%02d", minutes, remaining)
end

local remaining = session.minutes * 60

print(session.label)
print("Focus: " .. formatTime(remaining))
print("Rest:  " .. formatTime(session.breakMinutes * 60))
''',
  ),
];
