import 'package:flutter/material.dart';
import '../theme/orion_theme.dart';
import '../theme/orion_surfaces.dart';
import '../theme/expressive_motion.dart';
import 'orion_glass.dart';

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.radius = 18,
  });
  @override
  Widget build(BuildContext context) {
    final c = OrionColors.of(context);
    return OrionGlassSurface(
      enabled: !OrionGlassSurface.hasMaterialAncestor(context),
      radius: radius,
      tint: (color ?? c.panel).withValues(alpha: .09),
      child: Container(
        clipBehavior: Clip.antiAlias,
        padding: padding,
        decoration: BoxDecoration(
          color: c.chrome(
            color ?? c.panel,
            role: color == null ? 'panel' : null,
          ),
          gradient: color == null ? orionSurfaceGradient(c) : null,
          borderRadius: BorderRadius.circular(radius),
          border: c.glassEnabled ? null : Border.all(color: c.outline(.18)),
        ),
        child: child,
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: OrionType.metadata.copyWith(
      fontWeight: FontWeight.w500,
      letterSpacing: .5,
      color: OrionColors.of(
        context,
      ).readableForeground(color ?? OrionColors.of(context).muted),
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const StatusPill(this.text, {super.key, this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = OrionColors.of(context);
    final tint = color ?? c.accent;
    final foreground = c.readableForeground(tint);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.chrome(tint.withValues(alpha: .11)),
        border: c.transparentSurfaces
            ? Border.all(color: c.outline(.25), width: .6)
            : null,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: foreground)
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Text(text, style: OrionType.metadata.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget? action;
  const PageHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    final c = OrionColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(eyebrow),
                const SizedBox(height: 10),
                Text(title, style: OrionType.pageTitle),
                const SizedBox(height: 10),
                Text(subtitle, style: OrionType.body.copyWith(color: c.muted)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class HoverScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const HoverScale({super.key, required this.child, this.enabled = true});
  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: AnimatedScale(
      scale: hover && widget.enabled && !MediaQuery.disableAnimationsOf(context)
          ? 1.004
          : 1,
      duration: widget.enabled && !MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: OrionMotion.spatialFast,
      child: widget.child,
    ),
  );
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
  );
}
