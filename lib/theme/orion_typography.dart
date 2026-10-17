import 'package:flutter/material.dart';

/// One restrained desktop type scale. UI text uses real Roboto Flex weights;
/// source code keeps JetBrains Mono in the editor. The family is inherited
/// from the app theme so Theme Studio can change UI type consistently.
abstract final class OrionType {
  static const family = 'RobotoFlex';
  static const pageTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
  );
  static const sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0,
  );
  static const body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
  );
  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0,
  );
  static const metadata = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0,
  );
}
