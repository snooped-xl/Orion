/// The original V3 editor metrics, including its compact settings.
class V3EditorLayout {
  const V3EditorLayout({
    required this.compactTabs,
    required this.compactButtons,
  });
  final bool compactTabs, compactButtons;
  double get tabTop => compactTabs ? 48 : 50;
  double get tabHeight => compactTabs ? 24 : 32;
  double get tabWidth => compactTabs ? 120 : 159;
  double get tabRadius => compactTabs ? 0 : 5;
  double get tabGap => compactTabs ? 2 : 5;
  double get tabFontSize => compactTabs ? 11 : 12;
  double get editorTop => compactTabs ? 76 : 87;
  double get actionHeight => compactButtons ? 32 : 46;
  double get buttonWidth => compactButtons ? 72 : 91;
  double get buttonHeight => compactButtons ? 26 : 33;
  double get buttonFontSize => compactButtons ? 12 : 14;
  double get buttonIconSize => compactButtons ? 11 : 14;
  double get buttonGap => 4;
  double get buttonBottom => compactButtons ? 4 : 6;
  double get utilitySize => compactButtons ? 17 : 20;
  double get utilityGap => compactButtons ? 7 : 9;
}
