import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/interface_preset.dart';
import '../models/orion_theme_preferences.dart';
import '../models/synapse_studio_theme.dart';
import '../state/orion_controller.dart';
import '../theme/orion_theme.dart' as expressive;
import '../synapse_blue/blue_theme.dart';
import '../synapse_og/og_theme.dart';
import '../synapse_v3/synapse_v3_theme.dart';
import '../synapse_x/synapse_x_theme.dart';

class SynapseStudioWindowDescriptor {
  const SynapseStudioWindowDescriptor({
    required this.id,
    required this.label,
    required this.defaultSize,
    required this.minimumSize,
    this.hasOwnWindow = true,
  });
  final String id, label;
  final Size defaultSize, minimumSize;
  final bool hasOwnWindow;
}

class SynapseStudioElementDescriptor {
  const SynapseStudioElementDescriptor({
    required this.id,
    required this.label,
    required this.bounds,
    this.kind = 'section',
    this.fillRole,
    this.foregroundRole,
    this.borderRole,
  });
  final String id, label, kind;
  final Rect bounds;
  final String? fillRole, foregroundRole, borderRole;
}

class SynapseStudioColorRole {
  const SynapseStudioColorRole({
    required this.key,
    required this.label,
    required this.group,
  });
  final String key, label, group;
}

/// Shared role definitions, legacy migration, and non-destructive Easy themes.
abstract final class SynapseThemeCatalog {
  static const synapsePresets = [
    InterfacePreset.synapseV3,
    InterfacePreset.synapseBlue,
    InterfacePreset.synapseX,
    InterfacePreset.synapse2017,
  ];
  static const supported = [InterfacePreset.orion, ...synapsePresets];
  static const presetIds = ['original', 'midnight', 'ocean', 'ember'];
  static const _orionElements = [
    SynapseStudioElementDescriptor(
      id: 'titleBar',
      label: 'Title bar',
      kind: 'header',
      bounds: Rect.fromLTWH(0, 0, 822, 48),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'logo',
      label: 'Orion logo',
      kind: 'logo',
      bounds: Rect.fromLTWH(16, 10, 104, 28),
      foregroundRole: 'ink',
    ),
    SynapseStudioElementDescriptor(
      id: 'sidebar',
      label: 'Navigation rail',
      kind: 'sidebar',
      bounds: Rect.fromLTWH(0, 48, 84, 475),
      fillRole: 'background',
      foregroundRole: 'ink',
    ),
    SynapseStudioElementDescriptor(
      id: 'content',
      label: 'Page content',
      bounds: Rect.fromLTWH(84, 48, 738, 475),
      fillRole: 'background',
      foregroundRole: 'ink',
    ),
    SynapseStudioElementDescriptor(
      id: 'workspace',
      label: 'Workspace frame',
      bounds: Rect.fromLTWH(92, 60, 718, 451),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'libraryContent',
      label: 'Script hub page',
      kind: 'list',
      bounds: Rect.fromLTWH(92, 60, 718, 451),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'uiSelection',
      label: 'UI selection page',
      bounds: Rect.fromLTWH(92, 60, 718, 451),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'themeControls',
      label: 'Theme Control page',
      bounds: Rect.fromLTWH(92, 60, 718, 451),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'settingsControls',
      label: 'Settings page',
      bounds: Rect.fromLTWH(92, 60, 718, 451),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'tabs',
      label: 'Script tabs',
      kind: 'tabs',
      bounds: Rect.fromLTWH(92, 60, 718, 42),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'actions',
      label: 'Action toolbar',
      bounds: Rect.fromLTWH(104, 110, 694, 36),
      fillRole: 'panel',
      foregroundRole: 'ink',
    ),
    SynapseStudioElementDescriptor(
      id: 'editorTools',
      label: 'Editor tools',
      bounds: Rect.fromLTWH(104, 154, 694, 30),
      fillRole: 'panel',
      foregroundRole: 'muted',
    ),
    SynapseStudioElementDescriptor(
      id: 'editor',
      label: 'Code editor',
      kind: 'editor',
      bounds: Rect.fromLTWH(92, 190, 718, 260),
      fillRole: 'editor',
      foregroundRole: 'ink',
    ),
    SynapseStudioElementDescriptor(
      id: 'scriptList',
      label: 'Script library',
      kind: 'list',
      bounds: Rect.fromLTWH(630, 60, 180, 451),
      fillRole: 'panel',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'consoleOutput',
      label: 'Console output',
      bounds: Rect.fromLTWH(92, 350, 718, 132),
      fillRole: 'editor',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'openButton',
      label: 'Open file',
      kind: 'button',
      bounds: Rect.fromLTWH(104, 110, 96, 36),
      fillRole: 'elevated',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'saveButton',
      label: 'Save file',
      kind: 'button',
      bounds: Rect.fromLTWH(202, 110, 96, 36),
      fillRole: 'elevated',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'clearButton',
      label: 'Clear script',
      kind: 'button',
      bounds: Rect.fromLTWH(300, 110, 80, 36),
      fillRole: 'elevated',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'clientsButton',
      label: 'Clients',
      kind: 'button',
      bounds: Rect.fromLTWH(588, 110, 98, 36),
      fillRole: 'elevated',
      foregroundRole: 'accent',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'executeButton',
      label: 'Execute',
      kind: 'button',
      bounds: Rect.fromLTWH(688, 110, 110, 36),
      fillRole: 'accent',
      foregroundRole: 'ink',
      borderRole: 'border',
    ),
    SynapseStudioElementDescriptor(
      id: 'navEditor',
      label: 'Editor navigation',
      kind: 'button',
      bounds: Rect.fromLTWH(6, 56, 72, 64),
      foregroundRole: 'accent',
    ),
    SynapseStudioElementDescriptor(
      id: 'navScripts',
      label: 'Scripts navigation',
      kind: 'button',
      bounds: Rect.fromLTWH(6, 128, 72, 64),
      foregroundRole: 'muted',
    ),
    SynapseStudioElementDescriptor(
      id: 'navUis',
      label: 'UI selection navigation',
      kind: 'button',
      bounds: Rect.fromLTWH(6, 200, 72, 64),
      foregroundRole: 'muted',
    ),
    SynapseStudioElementDescriptor(
      id: 'navTheme',
      label: 'Theme Control navigation',
      kind: 'button',
      bounds: Rect.fromLTWH(6, 272, 72, 64),
      foregroundRole: 'muted',
    ),
    SynapseStudioElementDescriptor(
      id: 'navSettings',
      label: 'Settings navigation',
      kind: 'button',
      bounds: Rect.fromLTWH(6, 451, 72, 64),
      foregroundRole: 'muted',
    ),
  ];
  static final _cache = Expando<Map<InterfacePreset, _CatalogCache>>();
  static final _orionPaletteCache =
      Expando<Map<Brightness, Map<String, int>>>();

  static Map<String, int> orionPalette(
    OrionThemePreferences preferences, {
    Brightness? brightness,
  }) {
    final effective =
        brightness ??
        switch (preferences.themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system =>
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
        };
    final cached = (_orionPaletteCache[preferences] ??= {})[effective];
    if (cached != null) return cached;
    final colors = expressive
        .orionTheme(effective, preferences.accent, preferences: preferences)
        .extension<expressive.OrionColors>()!;
    return _orionPaletteCache[preferences]![effective] = Map.unmodifiable({
      'background': colors.background.toARGB32(),
      'panel': colors.panel.toARGB32(),
      'elevated': colors.elevated.toARGB32(),
      'border': colors.border.toARGB32(),
      'ink': colors.ink.toARGB32(),
      'muted': colors.muted.toARGB32(),
      'editor': colors.editorColor.toARGB32(),
      'lavender': colors.lavender.toARGB32(),
      'peach': colors.peach.toARGB32(),
      'accent': colors.accent.toARGB32(),
    });
  }

  /// Materializes edited Studio roles without baking every inherited role into
  /// an override (which would make Classic Orion's clear surfaces opaque).
  static OrionThemePreferences orionPreferencesForTheme(
    SynapseStudioTheme document,
  ) {
    final preferences = document.orionTheme ?? OrionThemePreferences.defaults;
    final original = orionPalette(preferences);
    final roles = {...document.colors, ...document.window('main').colors};
    final overrides = {...preferences.overrides};
    var changed = false;
    for (final role in OrionThemePreferences.colorRoles) {
      final color = roles[role];
      if (color != null && color != original[role]) {
        overrides[role] = Color(color);
        changed = true;
      }
    }
    final accent = roles['accent'] == null
        ? preferences.accent
        : Color(roles['accent']!);
    changed = changed || accent != preferences.accent;
    return changed
        ? preferences.copyWith(
            presetId: 'custom',
            accent: accent,
            overrides: overrides,
          )
        : preferences;
  }

  static SynapseStudioTheme defaults(InterfacePreset preset) =>
      SynapseStudioTheme(
        name: preset == InterfacePreset.orion ? 'Orion Expressive' : 'Original',
        fontFamily: preset == InterfacePreset.orion
            ? expressive.OrionType.family
            : 'SynapseInter',
        orionTheme: preset == InterfacePreset.orion
            ? OrionThemePreferences.defaults
            : null,
        colors: switch (preset) {
          InterfacePreset.orion => orionPalette(OrionThemePreferences.defaults),
          InterfacePreset.synapseV3 => V3ThemePresets.colors['framework']!,
          InterfacePreset.synapseBlue => BluePalette.defaults,
          InterfacePreset.synapseX => SynapseXTheme.defaults,
          InterfacePreset.synapse2017 => {
            for (final e in OgTheme.colors.entries)
              e.key: 0xff000000 | int.parse(e.value.substring(1), radix: 16),
          },
          _ => const {},
        },
      );

  static SynapseStudioTheme current(
    OrionController controller,
    InterfacePreset preset,
  ) {
    final preferences = controller.getInterfacePreferences(preset);
    final v3 = preset == InterfacePreset.orion
        ? controller.orionTheme
        : controller.synapsePreferences;
    final brightness =
        preset == InterfacePreset.orion &&
            controller.orionTheme.themeMode == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness
        : null;
    final cached = (_cache[controller] ??= {})[preset];
    if (cached != null &&
        identical(cached.preferences, preferences) &&
        identical(cached.v3, v3) &&
        cached.brightness == brightness) {
      return cached.theme;
    }
    final original = defaults(preset);
    final raw = preferences['themeStudio'];
    final SynapseStudioTheme result;
    if (preset == InterfacePreset.orion) {
      final document = raw is Map ? SynapseStudioTheme.fromJson(raw) : original;
      result = document.copyWith(
        colors: orionPalette(controller.orionTheme, brightness: brightness),
        orionTheme: controller.orionTheme,
        windows: {
          for (final e in document.windows.entries)
            e.key: e.key == 'main'
                ? e.value.copyWith(colors: const {})
                : e.value,
        },
      );
    } else if (raw is Map) {
      final document = SynapseStudioTheme.fromJson(raw);
      result = document.copyWith(
        colors: {
          ...original.colors,
          for (final e in document.colors.entries)
            if (original.colors.containsKey(e.key)) e.key: e.value,
        },
      );
    } else {
      final colors = <String, int>{...original.colors};
      String? font;
      final windows = <String, SynapseStudioWindow>{};
      if (preset == InterfacePreset.synapseV3) {
        final preferences = controller.synapsePreferences;
        colors.addAll(
          V3ThemePresets.colors[preferences.themePreset] ?? original.colors,
        );
        colors.addAll(preferences.themeColors);
        font = preferences.uiFontFamily;
      } else if (preset == InterfacePreset.synapseBlue) {
        final palette = BluePalette(
          preferences['themeColors'] is Map
              ? Map<String, Object?>.from(preferences['themeColors'] as Map)
              : const {},
        );
        for (final key in colors.keys.toList()) {
          colors[key] = palette.color(key).toARGB32();
        }
        font = preferences['uiFontFamily'] is String
            ? preferences['uiFontFamily'] as String
            : null;
        final background = _legacyFileImage(
          preferences['backgroundImagePath'],
          opacity: preferences['backgroundOpacity'],
        );
        if (background != null) {
          windows['main'] = preferences['backgroundLayer'] == 'above'
              ? SynapseStudioWindow(overlay: background)
              : SynapseStudioWindow(background: background);
        }
      } else if (preset == InterfacePreset.synapseX) {
        final palette = SynapseXTheme(preferences);
        for (final key in colors.keys.toList()) {
          colors[key] = palette.color(key).toARGB32();
        }
      } else if (preset == InterfacePreset.synapse2017) {
        final palette = OgTheme(preferences);
        for (final key in colors.keys.toList()) {
          colors[key] = palette.color(key).toARGB32();
        }
        final overlay = SynapseStudioImage.fromJson({
          'data': palette.data['overlayDataUrl'],
          'opacity': palette.data['overlayOpacity'],
        });
        final logo = SynapseStudioImage.fromJson(palette.data['logoDataUrl']);
        if (overlay != null || logo != null) {
          windows['main'] = SynapseStudioWindow(
            logo: logo,
            background: palette.overlayAbove ? null : overlay,
            overlay: palette.overlayAbove ? overlay : null,
          );
        }
      }
      result = SynapseStudioTheme(
        name: 'Current',
        colors: colors,
        windows: windows,
        fontFamily: font,
      );
    }
    final normalized = normalizeForPreset(result, preset);
    _cache[controller]![preset] = _CatalogCache(
      preferences,
      v3,
      normalized,
      brightness,
    );
    return normalized;
  }

  static Map<String, int> colors(
    OrionController controller,
    InterfacePreset preset,
    String windowId,
  ) => colorsForTheme(current(controller, preset), preset, windowId);

  static bool hasStudio(OrionController controller, InterfacePreset preset) =>
      controller.getInterfacePreferences(preset)['themeStudio'] is Map;

  static Map<String, int> colorsForTheme(
    SynapseStudioTheme document,
    InterfacePreset preset,
    String windowId,
  ) {
    final original = defaults(preset).colors;
    final window = document.window(windowId);
    final result = {
      ...original,
      if (preset == InterfacePreset.orion)
        ...orionPalette(orionPreferencesForTheme(document)),
      for (final e in document.colors.entries)
        if (preset != InterfacePreset.orion && original.containsKey(e.key))
          e.key: e.value,
      for (final e in window.colors.entries)
        if (preset != InterfacePreset.orion && original.containsKey(e.key))
          e.key: e.value,
    };
    // Legacy shells normally paint opaque structural surfaces. Open these
    // surfaces only when an image was explicitly selected for this window.
    if (window.background?.isValid == true && window.background!.opacity > 0) {
      for (final key in switch (preset) {
        InterfacePreset.orion => ['background', 'panel', 'elevated', 'editor'],
        InterfacePreset.synapseV3 => [
          'shell.windowBg',
          'shell.pageBg',
          'shell.contentBg',
          'editor.workAreaBg',
        ],
        InterfacePreset.synapseBlue => [
          'shellBg',
          'pageAreaBg',
          'surfaceElementsTheme.editorWorkAreaBackground',
        ],
        _ => ['windowBg', 'editorBg'],
      }) {
        if (result.containsKey(key)) result[key] = result[key]! & 0x00ffffff;
      }
    }
    _elementColors(result, preset, window);
    return Map.unmodifiable(result);
  }

  static void _elementColors(
    Map<String, int> colors,
    InterfacePreset preset,
    SynapseStudioWindow window,
  ) {
    if (preset == InterfacePreset.orion) return;
    final v3 = preset == InterfacePreset.synapseV3,
        blue = preset == InterfacePreset.synapseBlue;
    void apply(
      String id,
      List<String> fills,
      List<String> foregrounds,
      List<String> borders,
    ) {
      final element = window.elements[id];
      if (element == null) return;
      for (final role in fills) {
        if (!colors.containsKey(role)) continue;
        if (element.fill != null) colors[role] = element.fill!;
        if (element.image?.isValid == true && element.image!.opacity > 0) {
          colors[role] = colors[role]! & 0x00ffffff;
        }
      }
      for (final role in foregrounds) {
        if (colors.containsKey(role) && element.foreground != null) {
          colors[role] = element.foreground!;
        }
      }
      for (final role in borders) {
        if (colors.containsKey(role) && element.border != null) {
          colors[role] = element.border!;
        }
      }
    }

    if (v3) {
      apply(
        'content',
        ['shell.pageBg', 'shell.contentBg'],
        [],
        ['shell.shellBorder'],
      );
      apply('titleBar', ['topBar.bg'], ['topBar.text', 'topBar.navIcon'], [
        'shell.shellBorder',
      ]);
      apply('logo', [], ['branding.logoTextColor'], []);
      apply(
        'tabs',
        ['editor.tabBarBg', 'editor.tabInactiveBg', 'editor.tabActiveBg'],
        ['editor.tabText'],
        ['editor.tabBorder'],
      );
      apply('editor', ['editor.workAreaBg'], [], []);
      apply(
        'consoleOutput',
        ['editor.workAreaBg', 'shell.contentBg'],
        ['topBar.text'],
        [],
      );
      apply(
        'scriptList',
        [
          'scriptList.sectionHeaderBg',
          'scriptList.searchBg',
          'scriptList.rowHoverBg',
        ],
        [
          'scriptList.rowText',
          'scriptList.sectionHeaderText',
          'scriptList.rowMutedText',
        ],
        ['scriptList.sectionDivider'],
      );
      apply(
        'actions',
        ['actionBar.barBg', 'actionBar.buttonBg', 'actionBar.buttonHover'],
        ['actionBar.buttonText', 'actionBar.buttonIcon'],
        ['actionBar.buttonBorder'],
      );
      apply(
        'settingsControls',
        [
          'settingsChrome.controlBg',
          'settingsChrome.fieldBg',
          'settingsChrome.sectionHeaderBg',
        ],
        ['settingsChrome.labelText', 'settingsChrome.controlText'],
        ['settingsChrome.controlBorder', 'settingsChrome.fieldBorder'],
      );
      apply(
        'scriptCards',
        ['scriptHub.cardGlassBg'],
        ['scriptHub.cardTitleText', 'scriptHub.cardSubtitleText'],
        ['scriptHub.cardGlassBorder'],
      );
    } else if (blue) {
      apply('content', ['pageAreaBg'], [], []);
      apply('titleBar', ['topBarFrom', 'topBarTo'], ['logoTextColor'], []);
      apply('logo', [], ['logoTextColor'], []);
      apply(
        'sidebar',
        ['sidebarBg', 'sidebarNavInactiveBg', 'sidebarNavActiveBg'],
        ['sidebarIconStrokeActive', 'sidebarIconStrokeInactive'],
        [],
      );
      apply(
        'editor',
        ['surfaceElementsTheme.editorWorkAreaBackground'],
        [],
        [],
      );
      apply(
        'tabs',
        ['surfaceElementsTheme.surfaceHeaderBackground'],
        ['surfaceElementsTheme.surfaceHeaderText'],
        ['surfaceElementsTheme.surfaceHeaderBorder'],
      );
      apply(
        'scriptList',
        ['surfaceElementsTheme.surfacePanelBackground'],
        ['surfaceElementsTheme.surfaceListText'],
        ['surfaceElementsTheme.surfacePanelBorder'],
      );
      apply(
        'actions',
        ['editorControlBarButtonFrom', 'editorControlBarButtonTo'],
        ['editorControlBarText'],
        ['editorControlBarBorder'],
      );
      apply(
        'settingsControls',
        ['toolPanelsTheme.cardBackground', 'toolPanelsTheme.sectionBackground'],
        ['toolPanelsTheme.cardTitle', 'toolPanelsTheme.sectionBody'],
        ['toolPanelsTheme.cardBorder'],
      );
      apply(
        'scriptCards',
        ['scriptHubTheme.cardBackground'],
        ['scriptHubTheme.titleColor', 'scriptHubTheme.subtitleColor'],
        ['scriptHubTheme.cardBorderColor'],
      );
      apply(
        'consoleOutput',
        ['pageAreaBg', 'surfaceElementsTheme.surfacePanelBackground'],
        ['surfaceElementsTheme.surfaceListText'],
        ['surfaceElementsTheme.surfacePanelBorder'],
      );
    } else {
      apply('content', ['panelBg'], ['text'], []);
      apply('titleBar', ['windowBg'], ['text', 'iconColor'], []);
      apply('logo', [], ['logoTextColor'], []);
      apply('editor', ['editorBg'], [], []);
      apply('tabs', ['tabBg', 'tabActiveBg'], ['tabText'], [
        'tabBorder',
        'tabActiveBorder',
      ]);
      apply('scriptList', ['panelBg'], ['listText'], []);
      apply('actions', ['buttonBg', 'buttonHoverBg'], ['buttonText'], [
        'buttonBorder',
      ]);
      apply('settingsControls', ['panelBg'], ['text'], []);
      apply('scriptCards', ['panelBg'], ['text'], []);
      apply('consoleOutput', ['panelBg'], ['text'], []);
    }
  }

  static List<SynapseStudioWindowDescriptor> windows(InterfacePreset preset) {
    if (preset == InterfacePreset.orion) {
      return const [
        SynapseStudioWindowDescriptor(
          id: 'main',
          label: 'Orion window',
          defaultSize: Size(822, 523),
          minimumSize: Size(720, 480),
        ),
      ];
    }
    final main = switch (preset) {
      InterfacePreset.synapseV3 => const Size(961, 461),
      InterfacePreset.synapseBlue => const Size(714, 393),
      InterfacePreset.synapseX => const Size(801, 355),
      _ => const Size(838, 372),
    };
    return List.unmodifiable([
      SynapseStudioWindowDescriptor(
        id: 'main',
        label: 'Main editor',
        defaultSize: main,
        minimumSize: preset == InterfacePreset.synapseV3
            ? const Size(720, 400)
            : const Size(480, 280),
      ),
      SynapseStudioWindowDescriptor(
        id: 'settings',
        label: 'Settings',
        hasOwnWindow: [
          InterfacePreset.synapseX,
          InterfacePreset.synapse2017,
        ].contains(preset),
        defaultSize: preset == InterfacePreset.synapseX
            ? const Size(528, 460)
            : preset == InterfacePreset.synapse2017
            ? const Size(649, 705)
            : main,
        minimumSize: const Size(320, 240),
      ),
      SynapseStudioWindowDescriptor(
        id: 'scriptHub',
        label: 'Script hub',
        hasOwnWindow: [
          InterfacePreset.synapseX,
          InterfacePreset.synapse2017,
        ].contains(preset),
        defaultSize:
            [
              InterfacePreset.synapseX,
              InterfacePreset.synapse2017,
            ].contains(preset)
            ? const Size(612, 384)
            : main,
        minimumSize: const Size(400, 280),
      ),
      SynapseStudioWindowDescriptor(
        id: 'console',
        label: 'Console',
        hasOwnWindow: ![
          InterfacePreset.synapseBlue,
          InterfacePreset.synapseV3,
        ].contains(preset),
        defaultSize: preset == InterfacePreset.synapseV3
            ? const Size(961, 160)
            : [
                InterfacePreset.synapseX,
                InterfacePreset.synapse2017,
              ].contains(preset)
            ? const Size(520, 300)
            : main,
        minimumSize: preset == InterfacePreset.synapseV3
            ? const Size(320, 80)
            : const Size(320, 180),
      ),
      if (preset == InterfacePreset.synapseV3)
        const SynapseStudioWindowDescriptor(
          id: 'undockedEditor',
          label: 'Undocked editor',
          defaultSize: Size(720, 446),
          minimumSize: Size(480, 300),
        ),
    ]);
  }

  /// Applies the same minimums used by the native window host to imported data.
  /// Embedded pages share their main frame and cannot own default dimensions.
  static SynapseStudioTheme normalizeForPreset(
    SynapseStudioTheme document,
    InterfacePreset preset,
  ) {
    final descriptors = {
      for (final descriptor in windows(preset)) descriptor.id: descriptor,
    };
    return document.copyWith(
      windows: {
        for (final e in document.windows.entries)
          e.key: descriptors[e.key] == null
              ? e.value
              : !descriptors[e.key]!.hasOwnWindow
              ? e.value.copyWith(clearSize: true)
              : e.value.copyWith(
                  width: e.value.width?.clamp(
                    descriptors[e.key]!.minimumSize.width,
                    4096,
                  ),
                  height: e.value.height?.clamp(
                    descriptors[e.key]!.minimumSize.height,
                    2160,
                  ),
                ),
      },
    );
  }

  static Size windowSize(
    SynapseStudioTheme document,
    InterfacePreset preset,
    String windowId, {
    double? consoleHeight,
    bool compactMode = false,
    bool enlargedMode = false,
  }) {
    final normalized = normalizeForPreset(document, preset);
    final descriptors = windows(preset);
    final descriptor = descriptors.firstWhere(
      (w) => w.id == windowId,
      orElse: () => descriptors.first,
    );
    final main = normalized.window('main');
    final originalMain = descriptors.first.defaultSize;
    if (!descriptor.hasOwnWindow) {
      if (preset == InterfacePreset.synapseV3 && windowId == 'console') {
        final requestedHeight =
            normalized.window('console').elements['consoleOutput']?.height ??
            consoleHeight ??
            160;
        return Size(
          main.width ?? originalMain.width,
          requestedHeight.isFinite ? requestedHeight.clamp(80, 400) : 160,
        );
      }
      return Size(
        main.width ?? originalMain.width,
        main.height ?? originalMain.height,
      );
    }
    final window = normalized.window(windowId);
    final size = Size(
      window.width ?? descriptor.defaultSize.width,
      window.height ?? descriptor.defaultSize.height,
    );
    if (preset == InterfacePreset.orion && enlargedMode) {
      return const Size(1045, 648);
    }
    return preset == InterfacePreset.orion && compactMode
        ? Size(
            (size.width * 740 / 822).roundToDouble().clamp(680, 4096),
            (size.height * 470 / 523).roundToDouble().clamp(420, 2160),
          )
        : size;
  }

  static List<SynapseStudioElementDescriptor> elements(
    InterfacePreset preset,
    String windowId,
  ) {
    if (preset == InterfacePreset.orion) {
      return windowId == 'main' ? _orionElements : const [];
    }
    final window = windows(preset).where((w) => w.id == windowId).firstOrNull;
    if (window == null) return const [];
    final w = window.defaultSize.width, h = window.defaultSize.height;
    final header = preset == InterfacePreset.synapseBlue ? 55.0 : 30.0;
    final blue = preset == InterfacePreset.synapseBlue,
        v3 = preset == InterfacePreset.synapseV3;
    final bg = v3
        ? 'shell.windowBg'
        : blue
        ? 'shellBg'
        : 'windowBg';
    final text = v3
        ? 'topBar.text'
        : blue
        ? 'logoTextColor'
        : 'text';
    final panel = v3
        ? 'shell.contentBg'
        : blue
        ? 'pageAreaBg'
        : 'panelBg';
    final button = v3
        ? 'actionBar.buttonBg'
        : blue
        ? 'editorControlBarButtonFrom'
        : 'buttonBg';
    final buttonText = v3
        ? 'actionBar.buttonText'
        : blue
        ? 'editorControlBarText'
        : 'buttonText';
    final editor = v3
        ? 'editor.workAreaBg'
        : blue
        ? 'surfaceElementsTheme.editorWorkAreaBackground'
        : 'editorBg';
    final border = v3
        ? 'shell.shellBorder'
        : blue
        ? 'surfaceElementsTheme.surfacePanelBorder'
        : 'buttonBorder';
    SynapseStudioElementDescriptor descriptor(
      String id,
      String label,
      String kind,
      Rect bounds, {
      String? fill,
      String? foreground,
    }) => SynapseStudioElementDescriptor(
      id: id,
      label: label,
      kind: kind,
      bounds: bounds,
      fillRole: fill ?? panel,
      foregroundRole: foreground ?? text,
      borderRole: border,
    );
    if (v3 && windowId == 'console') {
      return [
        descriptor(
          'consoleOutput',
          'Docked console output',
          'editor',
          Rect.fromLTWH(0, 0, w, h),
          fill: editor,
        ),
      ];
    }
    final result = <SynapseStudioElementDescriptor>[
      descriptor(
        'content',
        'Page content',
        'section',
        Rect.fromLTWH(0, header, w, h - header),
        fill: panel,
      ),
      descriptor(
        'titleBar',
        'Title bar',
        'header',
        Rect.fromLTWH(0, 0, w, header),
        fill: bg,
      ),
      descriptor(
        'logo',
        'Logo',
        'logo',
        Rect.fromLTWH(12, 6, blue ? 130 : 122, header - 10),
        fill: bg,
      ),
    ];
    if (windowId == 'main' || windowId == 'undockedEditor') {
      final side = blue ? 55.0 : 0.0, listWidth = blue ? 0.0 : 180.0;
      result.addAll([
        descriptor(
          'tabs',
          'Script tabs',
          'tabs',
          Rect.fromLTWH(side + 8, header + 5, w - side - listWidth - 16, 26),
        ),
        descriptor(
          'editor',
          'Code editor',
          'editor',
          Rect.fromLTWH(
            side + 8,
            header + 31,
            w - side - listWidth - 16,
            h - header - 77,
          ),
          fill: editor,
        ),
        descriptor(
          'actions',
          'Action toolbar',
          'section',
          Rect.fromLTWH(side + 8, h - 38, w - side - 16, 30),
        ),
        if (windowId != 'undockedEditor')
          descriptor(
            'scriptList',
            'Script library',
            'list',
            Rect.fromLTWH(w - 176, header + 5, 168, h - header - 48),
          ),
        if (blue)
          descriptor(
            'sidebar',
            'Navigation sidebar',
            'sidebar',
            Rect.fromLTWH(0, header, side, h - header),
          ),
      ]);
      final buttons = {
        'executeButton': 'Execute',
        'clearButton': 'Clear editor',
        'openButton': 'Open file',
        'executeFileButton': 'Execute file',
        'saveButton': 'Save file',
        if (!blue && !v3) 'settingsButton': 'Settings',
        'attachButton': 'Orion Bridge',
        if (!blue && !v3) 'hubButton': 'Script hub',
        'clientsButton': 'Clients',
        if (windowId == 'undockedEditor')
          'redockButton': 'Return to main window',
      };
      var index = 0;
      final buttonWidth = (w - side - 16) / buttons.length;
      for (final e in buttons.entries) {
        result.add(
          descriptor(
            e.key,
            e.value,
            'button',
            Rect.fromLTWH(
              side + 8 + index++ * buttonWidth,
              h - 38,
              buttonWidth - 4,
              30,
            ),
            fill: button,
            foreground: buttonText,
          ),
        );
      }
    } else {
      final id = switch (windowId) {
        'settings' => 'settingsControls',
        'scriptHub' => 'scriptCards',
        _ => 'consoleOutput',
      };
      result.add(
        descriptor(
          id,
          switch (windowId) {
            'settings' => 'Settings controls',
            'scriptHub' => 'Script cards',
            _ => 'Console output',
          },
          windowId == 'scriptHub'
              ? 'list'
              : windowId == 'console'
              ? 'editor'
              : 'section',
          Rect.fromLTWH(12, header + 12, w - 24, h - header - 24),
        ),
      );
      if (blue) {
        result.add(
          descriptor(
            'sidebar',
            'Navigation sidebar',
            'sidebar',
            Rect.fromLTWH(0, header, blue ? 55 : 180, h - header),
          ),
        );
      }
    }
    final removed = <String>{
      if (windowId == 'undockedEditor') ...[
        'logo',
        'tabs',
        'scriptList',
        'sidebar',
        'attachButton',
      ],
      if (preset == InterfacePreset.synapse2017 && windowId == 'main') ...[
        'saveButton',
        'executeFileButton',
        'clientsButton',
      ],
    };
    return List.unmodifiable(
      result.where((element) => !removed.contains(element.id)),
    );
  }

  static List<SynapseStudioColorRole> roles(InterfacePreset preset) =>
      List.unmodifiable([
        for (final key in defaults(preset).colors.keys)
          SynapseStudioColorRole(
            key: key,
            label: roleLabel(key),
            group: roleGroup(key),
          ),
      ]);
  static String roleLabel(String key) => key
      .split('.')
      .map(
        (part) => part.replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        ),
      )
      .join(' · ');
  static String roleGroup(String key) => key.contains('.')
      ? key.split('.').first
      : switch (key) {
          'background' || 'panel' || 'elevated' || 'editor' => 'Surfaces',
          'ink' || 'muted' => 'Text',
          'accent' || 'lavender' || 'peach' => 'Accents',
          'border' => 'Outlines',
          _ => 'General',
        };

  static SynapseStudioTheme easy(
    InterfacePreset preset, {
    required int base,
    required int accent,
    required int text,
    String name = 'Easy theme',
    SynapseStudioTheme? current,
  }) {
    final old = current ?? defaults(preset);
    if (preset == InterfacePreset.orion) {
      int mix(int a, int b, double amount) =>
          Color.lerp(Color(a), Color(b), amount)!.toARGB32();
      final roles = {
        'background': base,
        'panel': mix(base, text, .035),
        'elevated': mix(base, text, .075),
        'editor': base,
        'border': mix(base, text, .2),
        'ink': text,
        'muted': mix(base, text, .65),
        'lavender': mix(accent, text, .35),
        'peach': mix(accent, text, .5),
        'accent': accent,
      };
      final preferences = (old.orionTheme ?? OrionThemePreferences.defaults)
          .copyWith(
            presetId: 'custom',
            accent: Color(accent),
            overrides: {
              for (final role in OrionThemePreferences.colorRoles)
                role: Color(roles[role]!),
            },
          );
      return old.copyWith(
        name: name,
        colors: orionPalette(preferences),
        orionTheme: preferences,
        windows: {
          for (final e in old.windows.entries)
            e.key: e.value.copyWith(
              colors: const {},
              elements: {
                for (final element in e.value.elements.entries)
                  element.key: element.value.copyWith(
                    fill: element.value.fill == null ? null : base,
                    foreground: element.value.foreground == null ? null : text,
                    border: element.value.border == null
                        ? null
                        : roles['border'],
                  ),
              },
            ),
        },
      );
    }
    final originals = defaults(preset).colors;
    int mix(int a, int b, double amount) =>
        Color.lerp(Color(a), Color(b), amount)!.toARGB32();
    final generated = <String, int>{};
    for (final e in originals.entries) {
      final key = e.key.toLowerCase();
      final alpha = e.value & 0xff000000;
      int value;
      if (key.contains('error') || key.contains('removed')) {
        value = mix(0xffdb8a8a, text, .15);
      } else if (key.contains('border') ||
          key.contains('stroke') ||
          key.contains('divider')) {
        value = mix(base, text, .2);
      } else if (key.contains('text') ||
          key.contains('icon') ||
          key.contains('placeholder') ||
          key.contains('title') ||
          key.contains('label') ||
          key.contains('body') ||
          key.contains('hint')) {
        value =
            [
              'muted',
              'inactive',
              'placeholder',
              'secondary',
              'description',
              'hint',
              'subtitle',
            ].any(key.contains)
            ? mix(base, text, .58)
            : text;
      } else if (key.contains('accent') ||
          key.contains('focus') ||
          key.contains('selected') ||
          key.contains('cta') ||
          key.contains('progressbar') ||
          key.contains('dotactive') ||
          key.contains('rangebackground') ||
          key.contains('topbarfrom') ||
          key.contains('topbarto') ||
          key.contains('headerfrom') ||
          key.contains('headerto') ||
          key.contains('activeunderline')) {
        value = key.endsWith('to') ? mix(accent, base, .25) : accent;
      } else {
        final lightness = Color(e.value).computeLuminance();
        value = mix(base, text, (lightness * .18).clamp(0, .12));
      }
      generated[e.key] = alpha | (value & 0x00ffffff);
    }
    return old.copyWith(
      name: name,
      colors: generated,
      windows: {
        for (final e in old.windows.entries)
          e.key: e.value.copyWith(
            colors: {
              for (final role in e.value.colors.keys)
                if (generated.containsKey(role)) role: generated[role]!,
            },
            elements: {
              for (final element in e.value.elements.entries)
                element.key: element.value.copyWith(
                  fill: element.value.fill == null ? null : base,
                  foreground: element.value.foreground == null ? null : text,
                  border: element.value.border == null
                      ? null
                      : mix(base, text, .2),
                ),
            },
          ),
      },
    );
  }

  static SynapseStudioTheme preset(InterfacePreset preset, String id) =>
      switch (id) {
        'midnight' => easy(
          preset,
          base: 0xff11141d,
          accent: 0xffa6bcff,
          text: 0xffeef0fa,
          name: 'Midnight',
        ),
        'ocean' => easy(
          preset,
          base: 0xff10212a,
          accent: 0xff62c4e5,
          text: 0xffe2f4fb,
          name: 'Ocean',
        ),
        'ember' => easy(
          preset,
          base: 0xff251b1b,
          accent: 0xffffad86,
          text: 0xffffeee7,
          name: 'Ember',
        ),
        _ => defaults(preset),
      };

  static SynapseStudioImage? _legacyFileImage(Object? path, {Object? opacity}) {
    if (path is! String || path.isEmpty) return null;
    try {
      final file = File(path);
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.file ||
          file.lengthSync() > SynapseStudioImage.maximumBytes) {
        return null;
      }
      final image = SynapseStudioImage(
        data: base64Encode(file.readAsBytesSync()),
        opacity: opacity is num && opacity.isFinite ? opacity.toDouble() : 1,
      );
      return image.isValid ? image : null;
    } on FileSystemException {
      return null;
    }
  }
}

class _CatalogCache {
  _CatalogCache(this.preferences, this.v3, this.theme, this.brightness);
  final Object preferences, v3;
  final SynapseStudioTheme theme;
  final Brightness? brightness;
}
