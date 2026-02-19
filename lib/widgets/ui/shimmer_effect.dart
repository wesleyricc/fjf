import 'package:flutter/material.dart';

class ShimmerEffect extends StatefulWidget {
  final double width;
  final double height;
  final ShapeBorder shape;

  // Construtor para retângulos (linhas de texto, cartões)
  const ShimmerEffect.rectangular({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.shape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  });

  // Construtor para círculos (avatares)
  const ShimmerEffect.circular({
    super.key,
    required double size,
    this.shape = const CircleBorder(),
  }) : width = size, height = size;

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Animação contínua e suave
    _controller = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1500)
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            shape: widget.shape,
            // Gradiente que se move para criar o brilho
            gradient: LinearGradient(
              colors: [
                Colors.grey[300]!, 
                Colors.grey[100]!, 
                Colors.grey[300]!
              ],
              stops: const [0.1, 0.5, 0.9],
              begin: Alignment(-1.0 + (2.0 * _controller.value), -0.3),
              end: Alignment(1.0 + (2.0 * _controller.value), 0.3),
              tileMode: TileMode.clamp,
            ),
          ),
        );
      },
    );
  }
}