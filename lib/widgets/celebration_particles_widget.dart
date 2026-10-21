import 'dart:math';
import 'package:flutter/material.dart';

class CelebrationParticlesWidget extends StatefulWidget {
  final Widget child;
  final bool isPlaying;

  const CelebrationParticlesWidget({
    super.key,
    required this.child,
    this.isPlaying = false,
  });

  @override
  State<CelebrationParticlesWidget> createState() =>
      _CelebrationParticlesWidgetState();
}

class _CelebrationParticlesWidgetState
    extends State<CelebrationParticlesWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final Random _random = Random();

  final List<Color> _colors = const [
    Color(0xFFFFD700), // Ouro
    Color(0xFFFF4500), // Laranja
    Color(0xFF32CD32), // Verde Lima
    Color(0xFF1E90FF), // Azul Dodger
    Color(0xFFFF1493), // Rosa Choque
    Color(0xFF9370DB), // Roxo
    Color(0xFF00CED1), // Turquesa
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() => setState(() {}));

    if (widget.isPlaying) {
      _startCelebration();
    }
  }

  @override
  void didUpdateWidget(covariant CelebrationParticlesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _startCelebration();
    }
  }

  void _startCelebration() {
    _particles.clear();
    for (int i = 0; i < 60; i++) {
      _particles.add(_ConfettiParticle(
        color: _colors[_random.nextInt(_colors.length)],
        startAngle: _random.nextDouble() * 2 * pi,
        speed: 100 + _random.nextDouble() * 260,
        size: 5 + _random.nextDouble() * 8,
        spinSpeed: (_random.nextDouble() - 0.5) * 10,
        isCircle: _random.nextBool(),
      ));
    }
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_controller.isAnimating)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConfettiPainter(
                  progress: _controller.value,
                  particles: _particles,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfettiParticle {
  final Color color;
  final double startAngle;
  final double speed;
  final double size;
  final double spinSpeed;
  final bool isCircle;

  _ConfettiParticle({
    required this.color,
    required this.startAngle,
    required this.speed,
    required this.size,
    required this.spinSpeed,
    required this.isCircle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.35);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final t = progress;
      // Expansão radial inicial com desaceleração e gravidade
      final distance = p.speed * (1 - exp(-3 * t));
      final gravity = 280 * (t * t);

      final dx = center.dx + cos(p.startAngle) * distance;
      final dy = center.dy + sin(p.startAngle) * distance * 0.7 + gravity;

      final opacity = (1.0 - t).clamp(0.0, 1.0);
      paint.color = p.color.withOpacity(opacity);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.spinSpeed * t * 2 * pi);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
