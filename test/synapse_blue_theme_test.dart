import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/synapse_blue/blue_intro.dart';
import 'package:orion/synapse_blue/blue_theme.dart';
import 'package:orion/synapse_blue/blue_themes.dart';

void main() {
  test('fresh Blue colors and original piecewise progress', () {
    const p = BluePalette();
    expect(p.color('topBarFrom'), const Color(0xff233da4));
    expect(p.color('pageAreaBg'), const Color(0xff222222));
    expect(p.color('editorControlBarBorder'), const Color(0xff606060));
    expect(p.color('initTheme.headerFrom'), const Color(0xff233da3));
    expect(blueProgressFill(0), 0);
    expect(blueProgressFill(1 / 6), closeTo(1 / 24, .00001));
    expect(blueProgressFill(1 / 3), closeTo(1 / 3, .00001));
    expect(blueProgressFill(2 / 3), closeTo(2 / 3, .00001));
    expect(blueProgressFill(.86), 1);
    expect(blueProgressFill(2), 1);
  });

  test('exports all source tokens and round-trips edited colors and font', () {
    final encoded = BlueThemeCodec.encode({
      'themeColors': {
        'pageAreaBg': 0xff182d47,
        'initTheme.textPrimary': '#ffeedd',
      },
      'uiFontFamily': 'SynapseRubik',
      'uiFontSizeStep': 2,
      'editorThemeId': 'tomorrow-night-eighties',
    });
    final payload = jsonDecode(encoded) as Map;
    expect((payload['theme'] as Map)['pageAreaBg'], '#182d47');
    final decoded = BlueThemeCodec.decode(encoded);
    final colors = decoded['themeColors'] as Map;
    expect(colors.length, BluePalette.defaults.length);
    expect(colors['pageAreaBg'], 0xff182d47);
    expect(colors['initTheme.textPrimary'], 0xffffeedd);
    expect(decoded['uiFontFamily'], 'SynapseRubik');
    expect(decoded['uiFontSizeStep'], 2);
    expect(decoded['editorThemeId'], 'tomorrow-night-eighties');
  });

  test('imports original nested theme and rejects unusable values', () {
    final decoded = BlueThemeCodec.decode(
      jsonEncode({
        'blue': {
          'topBarFrom': '#abcdef',
          'initTheme': {'textPrimary': '#123456'},
          'uiFontSizeStep': 999,
          'uiFontFamily': 'Unknown font',
          'editorMonacoThemeId': 'unknown-theme',
          'unknownToken': '#123456',
        },
      }),
    );
    expect(decoded['uiFontSizeStep'], 3);
    expect(decoded.containsKey('uiFontFamily'), isFalse);
    expect(decoded.containsKey('editorThemeId'), isFalse);
    expect(decoded['themeColors'], {
      'topBarFrom': 0xffabcdef,
      'initTheme.textPrimary': 0xff123456,
    });
    expect(
      () => BlueThemeCodec.decode('{"pageAreaBg":"url(script)"}'),
      throwsFormatException,
    );
    expect(() => BlueThemeCodec.decode('[]'), throwsFormatException);
    expect(() => BlueThemeCodec.decode(' ' * 256001), throwsFormatException);
  });
}
