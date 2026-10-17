import 'dart:convert';
import 'dart:typed_data';

import 'orion_theme_preferences.dart';

/// Portable, non-executable Theme Studio document for Orion and source ports.
class SynapseStudioTheme {
  SynapseStudioTheme({
    String name = 'Custom',
    Map<String, int> colors = const {},
    Map<String, SynapseStudioWindow> windows = const {},
    String? fontFamily,
    this.orionTheme,
  }) : name = _text(name, 100) ?? 'Custom',
       colors = _colors(colors),
       windows = Map.unmodifiable({
         for (final e in windows.entries)
           if (windowIds.contains(e.key)) e.key: e.value,
       }),
       fontFamily = _font(fontFamily);

  static const windowIds = [
    'main',
    'settings',
    'scriptHub',
    'console',
    'undockedEditor',
  ];
  final String name;
  final Map<String, int> colors;
  final Map<String, SynapseStudioWindow> windows;
  final String? fontFamily;

  /// Orion's existing gradient/effects system remains part of portable themes.
  final OrionThemePreferences? orionTheme;
  SynapseStudioWindow window(String id) => windows[id] ?? SynapseStudioWindow();
  SynapseStudioTheme copyWith({
    String? name,
    Map<String, int>? colors,
    Map<String, SynapseStudioWindow>? windows,
    String? fontFamily,
    bool clearFontFamily = false,
    OrionThemePreferences? orionTheme,
    bool clearOrionTheme = false,
  }) => SynapseStudioTheme(
    name: name ?? this.name,
    colors: colors ?? this.colors,
    windows: windows ?? this.windows,
    fontFamily: clearFontFamily ? null : fontFamily ?? this.fontFamily,
    orionTheme: clearOrionTheme ? null : orionTheme ?? this.orionTheme,
  );
  SynapseStudioTheme withWindow(String id, SynapseStudioWindow value) =>
      copyWith(windows: {...windows, id: value});
  SynapseStudioTheme withElement(
    String windowId,
    String elementId,
    SynapseStudioElement value,
  ) => withWindow(
    windowId,
    window(
      windowId,
    ).copyWith(elements: {...window(windowId).elements, elementId: value}),
  );

  Map<String, Object?> toJson() => {
    'format': 'orion-theme-studio',
    'version': 1,
    'name': name,
    'colors': colors,
    'windows': {for (final e in windows.entries) e.key: e.value.toJson()},
    if (fontFamily != null) 'fontFamily': fontFamily,
    if (orionTheme != null) 'orionTheme': orionTheme!.toJson(),
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  factory SynapseStudioTheme.fromJson(Object? value) {
    final raw = value is Map ? value : const {};
    final rawWindows = raw['windows'];
    return SynapseStudioTheme(
      name: raw['name'] is String ? raw['name'] as String : 'Custom',
      colors: _colors(raw['colors']),
      fontFamily: raw['fontFamily'] is String
          ? raw['fontFamily'] as String
          : null,
      orionTheme: raw['orionTheme'] is Map
          ? OrionThemePreferences.fromJson(raw['orionTheme'])
          : null,
      windows: {
        if (rawWindows is Map)
          for (final id in windowIds)
            if (rawWindows[id] is Map)
              id: SynapseStudioWindow.fromJson(rawWindows[id]),
      },
    );
  }
  static SynapseStudioTheme decode(String source) {
    if (source.length > 64 * 1024 * 1024) {
      throw const FormatException('Theme document is too large.');
    }
    final raw = jsonDecode(source);
    if (raw is! Map ||
        (raw['format'] != null &&
            !const {
              'orion-theme-studio',
              'orion-synapse-studio',
            }.contains(raw['format'])) ||
        (raw['version'] != null && raw['version'] != 1) ||
        (!raw.containsKey('colors') && !raw.containsKey('windows'))) {
      throw const FormatException('Expected a Theme Studio document.');
    }
    return SynapseStudioTheme.fromJson(raw);
  }
}

class SynapseStudioWindow {
  SynapseStudioWindow({
    double? width,
    double? height,
    Map<String, int> colors = const {},
    Map<String, SynapseStudioElement> elements = const {},
    this.background,
    this.overlay,
    this.logo,
  }) : width = _optional(width, 320, 4096),
       height = _optional(height, 180, 2160),
       colors = _colors(colors),
       elements = Map.unmodifiable({
         for (final e in elements.entries.take(128))
           if (_identifier(e.key)) e.key: e.value,
       });
  final double? width, height;
  final Map<String, int> colors;
  final Map<String, SynapseStudioElement> elements;
  final SynapseStudioImage? background, overlay, logo;
  SynapseStudioWindow copyWith({
    double? width,
    double? height,
    Map<String, int>? colors,
    Map<String, SynapseStudioElement>? elements,
    SynapseStudioImage? background,
    SynapseStudioImage? overlay,
    SynapseStudioImage? logo,
    bool clearSize = false,
    bool clearWidth = false,
    bool clearHeight = false,
    bool clearBackground = false,
    bool clearOverlay = false,
    bool clearLogo = false,
  }) => SynapseStudioWindow(
    width: clearSize || clearWidth ? null : width ?? this.width,
    height: clearSize || clearHeight ? null : height ?? this.height,
    colors: colors ?? this.colors,
    elements: elements ?? this.elements,
    background: clearBackground ? null : background ?? this.background,
    overlay: clearOverlay ? null : overlay ?? this.overlay,
    logo: clearLogo ? null : logo ?? this.logo,
  );
  Map<String, Object?> toJson() => {
    'width': ?width,
    'height': ?height,
    'colors': colors,
    'elements': {for (final e in elements.entries) e.key: e.value.toJson()},
    if (background != null) 'background': background!.toJson(),
    if (overlay != null) 'overlay': overlay!.toJson(),
    if (logo != null) 'logo': logo!.toJson(),
  };
  factory SynapseStudioWindow.fromJson(Object? value) {
    final raw = value is Map ? value : const {};
    final elements = raw['elements'];
    return SynapseStudioWindow(
      width: _number(raw['width']),
      height: _number(raw['height']),
      colors: _colors(raw['colors']),
      elements: {
        if (elements is Map)
          for (final e in elements.entries.take(128))
            if (e.key is String && e.value is Map)
              e.key as String: SynapseStudioElement.fromJson(e.value),
      },
      background: SynapseStudioImage.fromJson(raw['background']),
      overlay: SynapseStudioImage.fromJson(raw['overlay']),
      logo: SynapseStudioImage.fromJson(raw['logo']),
    );
  }
}

class SynapseStudioElement {
  SynapseStudioElement({
    double x = 0,
    double y = 0,
    double? width,
    double? height,
    double opacity = 1,
    double? radius,
    int? fill,
    int? foreground,
    int? border,
    this.image,
  }) : x = _finite(x, 0, -4096, 4096),
       y = _finite(y, 0, -2160, 2160),
       width = _optional(width, 8, 4096),
       height = _optional(height, 8, 2160),
       opacity = _finite(opacity, 1, 0, 1),
       radius = _optional(radius, 0, 256),
       fill = _color(fill),
       foreground = _color(foreground),
       border = _color(border);
  final double x, y, opacity;
  final double? width, height, radius;
  final int? fill, foreground, border;
  final SynapseStudioImage? image;
  SynapseStudioElement copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? opacity,
    double? radius,
    int? fill,
    int? foreground,
    int? border,
    SynapseStudioImage? image,
    bool clearSize = false,
    bool clearWidth = false,
    bool clearHeight = false,
    bool clearRadius = false,
    bool clearPaint = false,
    bool clearFill = false,
    bool clearForeground = false,
    bool clearBorder = false,
    bool clearImage = false,
  }) => SynapseStudioElement(
    x: x ?? this.x,
    y: y ?? this.y,
    width: clearSize || clearWidth ? null : width ?? this.width,
    height: clearSize || clearHeight ? null : height ?? this.height,
    opacity: opacity ?? this.opacity,
    radius: clearRadius ? null : radius ?? this.radius,
    fill: clearPaint || clearFill ? null : fill ?? this.fill,
    foreground: clearPaint || clearForeground
        ? null
        : foreground ?? this.foreground,
    border: clearPaint || clearBorder ? null : border ?? this.border,
    image: clearImage ? null : image ?? this.image,
  );
  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'opacity': opacity,
    'width': ?width,
    'height': ?height,
    'radius': ?radius,
    'fill': ?fill,
    'foreground': ?foreground,
    'border': ?border,
    if (image != null) 'image': image!.toJson(),
  };
  factory SynapseStudioElement.fromJson(Object? value) {
    final raw = value is Map ? value : const {};
    return SynapseStudioElement(
      x: _number(raw['x']) ?? 0,
      y: _number(raw['y']) ?? 0,
      width: _number(raw['width']),
      height: _number(raw['height']),
      opacity: _number(raw['opacity']) ?? 1,
      radius: _number(raw['radius']),
      fill: _color(raw['fill']),
      foreground: _color(raw['foreground']),
      border: _color(raw['border']),
      image: SynapseStudioImage.fromJson(raw['image']),
    );
  }
}

/// Validated raster image. Data is a normalized data URI; no paths/URLs or SVG.
class SynapseStudioImage {
  factory SynapseStudioImage({
    required String data,
    double opacity = 1,
    String fit = 'cover',
  }) {
    final decoded = _image(data);
    return SynapseStudioImage._(
      decoded?.$1 ?? '',
      decoded?.$2,
      _finite(opacity, 1, 0, 1),
      fits.contains(fit) ? fit : 'cover',
    );
  }
  SynapseStudioImage._(this.data, this._bytes, this.opacity, this.fit);
  static const maximumBytes = 8 * 1024 * 1024;
  static const fits = [
    'cover',
    'contain',
    'fill',
    'fitWidth',
    'fitHeight',
    'none',
    'scaleDown',
  ];
  final String data, fit;
  final double opacity;
  final Uint8List? _bytes;
  Uint8List? get bytes => _bytes;
  bool get isValid => _bytes != null;
  SynapseStudioImage copyWith({String? data, double? opacity, String? fit}) =>
      data == null
      ? SynapseStudioImage._(
          this.data,
          _bytes,
          _finite(opacity ?? this.opacity, 1, 0, 1),
          fits.contains(fit) ? fit! : this.fit,
        )
      : SynapseStudioImage(
          data: data,
          opacity: opacity ?? this.opacity,
          fit: fit ?? this.fit,
        );
  Map<String, Object?> toJson() => {
    'data': data,
    'opacity': opacity,
    'fit': fit,
  };
  static SynapseStudioImage? fromJson(Object? value) {
    if (value == null) return null;
    final raw = value is Map ? value : {'data': value};
    if (raw['data'] is! String) return null;
    final image = SynapseStudioImage(
      data: raw['data'] as String,
      opacity: _number(raw['opacity']) ?? 1,
      fit: raw['fit'] is String ? raw['fit'] as String : 'cover',
    );
    return image.isValid ? image : null;
  }
}

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
double? _optional(double? value, double minimum, double maximum) =>
    value != null && value.isFinite ? value.clamp(minimum, maximum) : null;
double _finite(double value, double fallback, double minimum, double maximum) =>
    value.isFinite ? value.clamp(minimum, maximum) : fallback;
String? _text(String? value, int limit) {
  final clean = value?.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  return clean == null || clean.isEmpty
      ? null
      : clean.substring(0, clean.length.clamp(0, limit));
}

bool _identifier(String value) =>
    RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,95}$').hasMatch(value);
int? _color(Object? value) {
  if (value is int && value >= 0 && value <= 0xffffffff) return value;
  if (value is String &&
      RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)) {
    return int.parse(value.substring(1), radix: 16) |
        (value.length == 7 ? 0xff000000 : 0);
  }
  return null;
}

String? _font(String? value) {
  final clean = _text(value, 64);
  return clean != null &&
          RegExp(r'^[A-Za-z][A-Za-z0-9 _,\-]{0,63}$').hasMatch(clean)
      ? clean
      : null;
}

Map<String, int> _colors(Object? value) => Map.unmodifiable({
  if (value is Map)
    for (final e in value.entries.take(512))
      if (e.key is String &&
          _identifier(e.key as String) &&
          _color(e.value) != null)
        e.key as String: _color(e.value)!,
});
(String, Uint8List)? _image(String source) {
  if (source.length > ((SynapseStudioImage.maximumBytes + 2) ~/ 3) * 4 + 64) {
    return null;
  }
  var encoded = source.trim();
  if (encoded.startsWith('data:')) {
    final prefix = RegExp(
      r'^data:image/(png|jpeg|webp);base64,',
    ).firstMatch(encoded);
    if (prefix == null) return null;
    encoded = encoded.substring(prefix.end);
  }
  try {
    final bytes = base64Decode(encoded);
    if (bytes.length > SynapseStudioImage.maximumBytes) return null;
    final String mime;
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10) {
      if (bytes.length >= 24) {
        final header = ByteData.sublistView(bytes);
        if (header.getUint32(16) > 16384 || header.getUint32(20) > 16384) {
          return null;
        }
      }
      mime = 'png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      mime = 'jpeg';
    } else if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      mime = 'webp';
    } else {
      return null;
    }
    return (
      'data:image/$mime;base64,${base64Encode(bytes)}',
      bytes.asUnmodifiableView(),
    );
  } on FormatException {
    return null;
  }
}
