import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';

/// The three gold threads from the Urban Thread mark, drawn as gentle
/// S-curves running corner to corner. Used once per screen at most.
class ThreadStripes extends StatelessWidget {
  final double strokeWidth;
  final double gap;
  final Color color;

  const ThreadStripes({
    super.key,
    this.strokeWidth = 7,
    this.gap = 6,
    this.color = AppTheme.gold,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ThreadPainter(strokeWidth, gap, color),
    size: Size.infinite,
  );
}

class _ThreadPainter extends CustomPainter {
  final double w;
  final double gap;
  final Color color;
  _ThreadPainter(this.w, this.gap, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.butt;
    final step = w + gap;
    for (var i = 0; i < 3; i++) {
      final o = i * step;
      final path = Path()
        ..moveTo(-w, size.height * 0.92 - o)
        ..cubicTo(
          size.width * 0.35,
          size.height * 0.92 - o,
          size.width * 0.55,
          size.height * 0.08 - o,
          size.width + w,
          size.height * 0.08 - o,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.w != w || old.gap != gap || old.color != color;
}
