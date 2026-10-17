import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_theme.dart';

int _channelSpread(Color color) {
  final argb = color.toARGB32();
  final channels = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255];
  return channels.reduce(math.max) - channels.reduce(math.min);
}

void _expectNeutral(Map<String, Color> roles, {int tolerance = 6}) {
  for (final role in roles.entries) {
    expect(
      _channelSpread(role.value),
      lessThanOrEqualTo(tolerance),
      reason: '${role.key} introduces color into the classic graphite palette',
    );
  }
}

void main() {
  final original = OrionThemePreferences.builtInPresets
      .singleWhere((preset) => preset.id == 'original-orion')
      .preferences;

  test(
    'Original Orion uses a silver accent and retains its graphite gradient',
    () {
      expect(original.accent, const Color(0xFFD5D5D5));
      expect(original.gradientEnabled, isTrue);
      expect(original.gradientStops, [0, .37019]);
      expect(original.gradientAngle, 45);
      expect(original.outlineStrength, greaterThan(1));
      _expectNeutral({
        for (var index = 0; index < original.gradientColors.length; index++)
          'gradient $index': original.gradientColors[index],
      });
    },
  );

  for (final brightness in Brightness.values) {
    test('classic ${brightness.name} controls and surfaces remain neutral', () {
      final theme = orionTheme(
        brightness,
        OrionThemePreferences.defaults.accent,
        preferences: original,
      );
      final scheme = theme.colorScheme;
      final colors = theme.extension<OrionColors>()!;
      _expectNeutral({
        'accent': colors.accent,
        'action foreground': colors.onAccent,
        'readable accent': colors.readableAccent,
        'lavender role': colors.lavender,
        'peach role': colors.peach,
        'readable lavender': colors.readableLavender,
        'readable peach': colors.readablePeach,
        'background': colors.background,
        'panel': colors.panel,
        'elevated': colors.elevated,
        'editor': colors.editorColor,
        'border': colors.border,
        'ink': colors.ink,
        'muted': colors.muted,
        'primary': scheme.primary,
        'onPrimary': scheme.onPrimary,
        'primary container': scheme.primaryContainer,
        'onPrimaryContainer': scheme.onPrimaryContainer,
        'secondary': scheme.secondary,
        'onSecondary': scheme.onSecondary,
        'secondary container': scheme.secondaryContainer,
        'onSecondaryContainer': scheme.onSecondaryContainer,
        'tertiary': scheme.tertiary,
        'onTertiary': scheme.onTertiary,
        'tertiary container': scheme.tertiaryContainer,
        'onTertiaryContainer': scheme.onTertiaryContainer,
        'surface': scheme.surface,
        'surface lowest': scheme.surfaceContainerLowest,
        'surface low': scheme.surfaceContainerLow,
        'surface high': scheme.surfaceContainerHigh,
        'surface highest': scheme.surfaceContainerHighest,
      });
      expect(colors.onAccent, const Color(0xFF17191B));
      expect(colors.lavender, const Color(0xFFC6C6C6));
      expect(colors.peach, const Color(0xFFB8B8B8));
      expect(colors.backgroundGradient, isNotNull);
      _expectNeutral({
        for (
          var index = 0;
          index < colors.backgroundGradient!.colors.length;
          index++
        )
          'resolved gradient $index': colors.backgroundGradient!.colors[index],
      });
    });

    test('classic ${brightness.name} honors custom accent and role colors', () {
      const accent = Color(0xFF7AD5AE);
      const lavender = Color(0xFFD3A4F8);
      const peach = Color(0xFFF2AE8C);
      const panel = Color(0xFF182B34);
      final preferences = original.copyWith(
        presetId: 'custom',
        accent: accent,
        surfaceTint: .4,
        overrides: {'lavender': lavender, 'peach': peach, 'panel': panel},
      );
      final theme = orionTheme(
        brightness,
        OrionThemePreferences.defaults.accent,
        preferences: preferences,
      );
      final colors = theme.extension<OrionColors>()!;
      expect(colors.accent, accent);
      expect(colors.lavender, lavender);
      expect(colors.peach, peach);
      expect(colors.panel, panel);
      expect(theme.colorScheme.primary, colors.readableAccent);
      expect(_channelSpread(theme.colorScheme.primary), greaterThan(6));
    });

    test('Expressive ${brightness.name} keeps its blue identity', () {
      final theme = orionTheme(
        brightness,
        OrionThemePreferences.defaults.accent,
        preferences: OrionThemePreferences.defaults,
      );
      final colors = theme.extension<OrionColors>()!;
      expect(colors.accent, const Color(0xFF88B5FF));
      expect(colors.lavender, const Color(0xFFC7B9F8));
      expect(colors.peach, const Color(0xFFF3BBA1));
      expect(_channelSpread(theme.colorScheme.primary), greaterThan(6));
      expect(_channelSpread(theme.colorScheme.tertiary), greaterThan(6));
    });
  }

  test('saved version 1 Original preset upgrades its former blue accent', () {
    final legacy = {...original.toJson(), 'version': 1, 'accent': 0xFF8DB7FF};
    final migrated = OrionThemePreferences.fromJson(legacy);
    expect(migrated.accent, const Color(0xFFD5D5D5));
    expect(migrated.basePalette, 'original-orion');
    expect(migrated.gradientColors, original.gradientColors);
    expect(migrated.gradientStops, original.gradientStops);
    expect(migrated.outlineStrength, original.outlineStrength);
    expect(OrionThemePreferences.fromJson(migrated.toJson()), migrated);
  });

  test(
    'classic migration preserves custom themes and explicitly chosen colors',
    () {
      final customBlue = {
        ...original.toJson(),
        'version': 1,
        'presetId': 'custom',
        'accent': 0xFF8DB7FF,
      };
      final customAccent = {
        ...original.toJson(),
        'version': 1,
        'accent': 0xFF77DDAA,
      };
      final currentBlue = {
        ...original.toJson(),
        'version': 2,
        'accent': 0xFF8DB7FF,
      };
      expect(
        OrionThemePreferences.fromJson(customBlue).accent,
        const Color(0xFF8DB7FF),
      );
      expect(
        OrionThemePreferences.fromJson(customAccent).accent,
        const Color(0xFF77DDAA),
      );
      expect(
        OrionThemePreferences.fromJson(currentBlue).accent,
        const Color(0xFF8DB7FF),
      );
    },
  );
}
