import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/models/orion_theme_preferences.dart';
import 'package:orion/theme/orion_surfaces.dart';
import 'package:orion/theme/orion_theme.dart';

OrionThemePreferences _preset(String id) => OrionThemePreferences.builtInPresets
    .singleWhere((preset) => preset.id == id)
    .preferences;

ThemeData _theme(OrionThemePreferences preferences, Brightness brightness) =>
    orionTheme(brightness, preferences.accent, preferences: preferences);

void main() {
  final original = _preset('original-orion');

  for (final brightness in Brightness.values) {
    test('classic ${brightness.name} reveals one continuous background', () {
      final colors = _theme(original, brightness).extension<OrionColors>()!;

      expect(colors.transparentSurfaces, isTrue);
      expect(colors.backgroundGradient, isNotNull);
      for (final role in {
        'panel': colors.panel,
        'elevated': colors.elevated,
        'editor': colors.editorColor,
      }.entries) {
        // Semantic colors still support readable popup surfaces and contrast
        // calculation; inline chrome must not paint those colors over the root.
        expect(role.value.a, 1, reason: '${role.key} retains its usable token');
        expect(colors.chrome(role.value, role: role.key).a, 0);
      }
      expect(colors.chrome(colors.panel.withValues(alpha: .85)).a, 0);
      expect(orionSurfaceGradient(colors), isNull);
      expect(
        orionSurfaceGradient(colors, base: colors.editorColor, blend: .8),
        isNull,
      );
      expect(colors.outline(.5).a, greaterThan(0));
      expect(colors.ink.a, 1);
      expect(colors.muted.a, 1);
    });

    test('classic ${brightness.name} controls have clear idle backplates', () {
      final theme = _theme(original, brightness);
      final button = theme.filledButtonTheme.style!;
      final segment = theme.segmentedButtonTheme.style!;
      final idleButtonColor = button.backgroundColor!.resolve({})!;
      final idleSegmentColor = segment.backgroundColor!.resolve({})!;
      final selectedSegmentColor = segment.backgroundColor!.resolve({
        WidgetState.selected,
      })!;

      expect(idleButtonColor.a, 0);
      expect(idleSegmentColor.a, 0);
      expect(theme.inputDecorationTheme.fillColor!.a, 0);
      expect(theme.chipTheme.backgroundColor!.a, 0);
      expect(selectedSegmentColor.a, greaterThan(0));
      expect(selectedSegmentColor.a, lessThan(.2));
      expect(theme.chipTheme.selectedColor!.a, greaterThan(0));
      expect(theme.chipTheme.selectedColor!.a, lessThan(.2));
      // A clear primary action uses readable text rather than the dark text
      // intended for a solid silver button.
      expect(
        button.foregroundColor!.resolve({}),
        theme.extension<OrionColors>()!.readableAccent,
      );
    });

    test('classic ${brightness.name} floating surfaces remain readable', () {
      final theme = _theme(original, brightness);
      final colors = theme.extension<OrionColors>()!;
      expect(theme.dialogTheme.backgroundColor, colors.elevated);
      expect(theme.dialogTheme.backgroundColor!.a, 1);
      expect(theme.popupMenuTheme.color, colors.elevated);
      expect(theme.popupMenuTheme.color!.a, 1);
      expect(theme.snackBarTheme.backgroundColor, colors.elevated);
      expect(theme.snackBarTheme.backgroundColor!.a, 1);
      final tooltip = theme.tooltipTheme.decoration! as BoxDecoration;
      expect(tooltip.color!.a, 1);
    });
  }

  test('Easy edits retain classic transparency even after becoming custom', () {
    final edited = original.copyWith(
      presetId: 'custom',
      accent: const Color(0xff66ddaa),
      surfaceTint: .75,
      gradientColors: const [Color(0xff192f28), Color(0xff201b30)],
      gradientAngle: 180,
    );
    final colors = _theme(edited, Brightness.dark).extension<OrionColors>()!;
    expect(colors.transparentSurfaces, isTrue);
    expect(colors.backgroundGradient!.colors, edited.gradientColors);
    expect(colors.chrome(colors.panel, role: 'panel').a, 0);
    expect(colors.chrome(colors.editorColor, role: 'editor').a, 0);
    expect(orionSurfaceGradient(colors), isNull);
    final hover = colors.stateFill(.08);
    expect(hover.a, closeTo(.08, .005));
    expect(hover.withValues(alpha: 1), edited.accent);
  });

  test('manual surface colors affect only the explicitly overridden role', () {
    const panel = Color(0xff252525);
    const editor = Color(0xff181818);
    final preferences = original.copyWith(
      presetId: 'custom',
      overrides: {'panel': panel, 'editor': editor, 'border': Colors.grey},
    );
    final colors = _theme(
      preferences,
      Brightness.dark,
    ).extension<OrionColors>()!;
    expect(colors.transparentSurfaces, isTrue);
    expect(colors.chrome(colors.panel, role: 'panel'), panel);
    expect(colors.chrome(colors.editorColor, role: 'editor'), editor);
    expect(colors.chrome(colors.elevated, role: 'elevated').a, 0);
    expect(colors.chrome(colors.panel).a, 0);
    expect(orionSurfaceGradient(colors), isNull);

    final restored = _theme(
      preferences.copyWith(overrides: {'border': Colors.grey}),
      Brightness.dark,
    ).extension<OrionColors>()!;
    expect(restored.chrome(restored.panel, role: 'panel').a, 0);
    expect(restored.chrome(restored.editorColor, role: 'editor').a, 0);
  });

  test(
    'Expressive themes keep their opaque layered surfaces and gradients',
    () {
      for (final preferences in [
        OrionThemePreferences.defaults,
        _preset('aurora'),
      ]) {
        for (final brightness in Brightness.values) {
          final theme = _theme(preferences, brightness);
          final colors = theme.extension<OrionColors>()!;
          expect(colors.transparentSurfaces, isFalse);
          expect(colors.chrome(colors.panel, role: 'panel'), colors.panel);
          expect(colors.chrome(colors.editorColor), colors.editorColor);
          expect(
            colors.chrome(colors.panel.withValues(alpha: .85)),
            colors.panel.withValues(alpha: .85),
          );
          expect(
            orionSurfaceGradient(colors) != null,
            preferences.gradientEnabled,
          );
          expect(
            theme.filledButtonTheme.style!.backgroundColor!.resolve({})!.a,
            1,
          );
          expect(theme.inputDecorationTheme.fillColor!.a, 1);
          expect(colors.stateFill(.08).a, 1);
        }
      }
    },
  );

  test('theme copies and animation endpoints retain surface policy', () {
    final classic = _theme(
      original.copyWith(overrides: {'panel': const Color(0xff222222)}),
      Brightness.dark,
    ).extension<OrionColors>()!;
    final expressive = _theme(
      OrionThemePreferences.defaults,
      Brightness.dark,
    ).extension<OrionColors>()!;
    final copied = classic.copyWith(accent: Colors.white);
    expect(copied.transparentSurfaces, isTrue);
    expect(copied.chrome(copied.panel, role: 'panel'), copied.panel);
    expect(copied.chrome(copied.editorColor, role: 'editor').a, 0);
    final firstFrame = classic.lerp(expressive, 0);
    expect(firstFrame.transparentSurfaces, isTrue);
    expect(firstFrame.chrome(firstFrame.panel, role: 'panel'), classic.panel);
    final finalFrame = classic.lerp(expressive, 1);
    expect(finalFrame.transparentSurfaces, isFalse);
    expect(finalFrame.chrome(finalFrame.editorColor), expressive.editorColor);
    final returnFrame = expressive.lerp(classic, 1);
    expect(returnFrame.transparentSurfaces, isTrue);
    expect(returnFrame.chrome(returnFrame.panel, role: 'panel'), classic.panel);
    expect(returnFrame.chrome(returnFrame.editorColor, role: 'editor').a, 0);
  });
}
