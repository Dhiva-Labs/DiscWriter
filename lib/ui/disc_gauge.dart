import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A disc seen from above that fills from the hub outward, the way data is
/// actually laid down on optical media.
///
/// * [existingFraction] — data already on the disc (earlier sessions)
/// * [newFraction] — what this job will add; past 1.0 the rim turns red
/// * [progress] — while burning, how much of [newFraction] is written; the
///   laser line sits at the write position and the disc spins
class DiscGauge extends StatefulWidget {
  final double size;
  final double existingFraction;
  final double newFraction;
  final double? progress;
  final bool spinning;
  final bool verified;
  final Widget? center;

  const DiscGauge({
    super.key,
    this.size = 220,
    this.existingFraction = 0,
    this.newFraction = 0,
    this.progress,
    this.spinning = false,
    this.verified = false,
    this.center,
  });

  @override
  State<DiscGauge> createState() => _DiscGaugeState();
}

class _DiscGaugeState extends State<DiscGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(DiscGauge old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_spin.isAnimating) _spin.repeat();
    if (!widget.spinning && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = DiscColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: widget.newFraction),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, fill, _) => AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _DiscPainter(
                  existing: widget.existingFraction,
                  fill: fill,
                  progress: widget.progress,
                  rotation: _spin.value * 2 * math.pi,
                  verified: widget.verified,
                  colors: colors,
                  error: scheme.error,
                  hub: scheme.surface,
                  rim: scheme.outlineVariant,
                ),
              ),
            ),
          ),
          if (widget.center != null) SizedBox(width: widget.size * 0.42, child: widget.center),
        ],
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  final double existing;
  final double fill;
  final double? progress;
  final double rotation;
  final bool verified;
  final DiscColors colors;
  final Color error;
  final Color hub;
  final Color rim;

  _DiscPainter({
    required this.existing,
    required this.fill,
    required this.progress,
    required this.rotation,
    required this.verified,
    required this.colors,
    required this.error,
    required this.hub,
    required this.rim,
  });

  /// Radius at which [fraction] of the data area is used. Area grows with
  /// r², so equal amounts of data make thinner rings further out.
  static double radiusFor(double fraction, double inner, double outer) =>
      math.sqrt(inner * inner + fraction.clamp(0.0, 1.0) * (outer * outer - inner * inner));

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final dataInner = r * 0.36;
    final dataOuter = r * 0.95;

    // Disc face.
    canvas.drawCircle(c, r, Paint()..color = colors.discFace);
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = rim,
    );

    // Iridescent sheen, rotated with the disc.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotation);
    final sheen = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0x00FFFFFF),
          const Color(0x14A0E9FF),
          const Color(0x00FFFFFF),
          const Color(0x12FFB86B),
          const Color(0x00FFFFFF),
          const Color(0x10C29BFF),
          const Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    canvas.drawCircle(Offset.zero, r, sheen);
    canvas.restore();

    // Grooves.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = colors.discGroove;
    for (var gr = dataInner; gr < dataOuter; gr += math.max(4.0, r * 0.035)) {
      canvas.drawCircle(c, gr, groove);
    }

    Path ring(double from, double to) => Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: c, radius: to))
      ..addOval(Rect.fromCircle(center: c, radius: from));

    // Existing sessions, then this job's data (planned or written so far).
    final total = existing + fill;
    final rExisting = radiusFor(existing, dataInner, dataOuter);
    if (existing > 0) {
      canvas.drawPath(ring(dataInner, rExisting), Paint()..color = colors.existing.withValues(alpha: 0.55));
    }
    final over = total > 1.0;
    final rPlanned = radiusFor(total, dataInner, dataOuter);
    final newColor = over ? error : (verified ? colors.verified : colors.laser);
    if (fill > 0) {
      if (progress == null) {
        canvas.drawPath(ring(rExisting, rPlanned), Paint()..color = newColor.withValues(alpha: 0.35));
      } else {
        // Planned area faint, written area solid.
        canvas.drawPath(ring(rExisting, rPlanned), Paint()..color = newColor.withValues(alpha: 0.14));
        final rWritten = radiusFor(existing + fill * progress!.clamp(0.0, 1.0), dataInner, dataOuter);
        canvas.drawPath(ring(rExisting, rWritten), Paint()..color = newColor.withValues(alpha: 0.55));
        // The laser line at the write position.
        if (!verified && progress! < 1) {
          canvas.drawCircle(
            c,
            rWritten,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = colors.laser
              ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
          );
        }
      }
      canvas.drawCircle(
        c,
        rPlanned,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = newColor.withValues(alpha: 0.9),
      );
    }
    if (over) {
      canvas.drawCircle(
        c,
        r - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = error,
      );
    }

    // Hub.
    canvas.drawCircle(c, dataInner * 0.92, Paint()..color = colors.discFace);
    canvas.drawCircle(
      c,
      dataInner * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = rim,
    );
    canvas.drawCircle(c, r * 0.11, Paint()..color = hub);
    canvas.drawCircle(
      c,
      r * 0.11,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = rim,
    );
  }

  @override
  bool shouldRepaint(_DiscPainter old) =>
      old.existing != existing ||
      old.fill != fill ||
      old.progress != progress ||
      old.rotation != rotation ||
      old.verified != verified ||
      old.colors != colors;
}
