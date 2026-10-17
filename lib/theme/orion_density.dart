import 'package:flutter/material.dart';

/// Density belongs to Orion's Expressive shell and leaves editor text sizing
/// and the separate GUI scale preference intact.
class OrionDensity extends ThemeExtension<OrionDensity> {
  const OrionDensity({required this.amount});

  static const comfortable = OrionDensity(amount: 0);
  static const compact = OrionDensity(amount: 1);
  final double amount;

  static OrionDensity of(BuildContext context) =>
      Theme.of(context).extension<OrionDensity>() ?? comfortable;

  double mix(double comfortable, double compact) =>
      comfortable + (compact - comfortable) * amount;

  bool get isCompact => amount >= .5;

  @override
  OrionDensity copyWith({double? amount}) =>
      OrionDensity(amount: amount ?? this.amount);

  @override
  OrionDensity lerp(covariant OrionDensity? other, double t) => other == null
      ? this
      : OrionDensity(amount: amount + (other.amount - amount) * t);
}
