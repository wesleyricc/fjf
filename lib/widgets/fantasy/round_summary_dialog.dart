import 'package:flutter/material.dart';
import 'dart:math' as math;

class RoundSummaryDialog extends StatefulWidget {
  final double points;
  final double appreciation;

  const RoundSummaryDialog({
    Key? key,
    required this.points,
    required this.appreciation,
  }) : super(key: key);

  static void show(BuildContext context, double points, double appreciation) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Resumo",
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return RoundSummaryDialog(points: points, appreciation: appreciation);
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
          child: child,
        );
      },
    );
  }

  @override
  State<RoundSummaryDialog> createState() => _RoundSummaryDialogState();
}

class _RoundSummaryDialogState extends State<RoundSummaryDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAppPositive = widget.appreciation >= 0;
    final color = isAppPositive ? Colors.green : Colors.red;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icone animado
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: math.sin(_controller.value * math.pi * 4) * 0.2,
                    child: Transform.scale(
                      scale: 1.0 + math.sin(_controller.value * math.pi) * 0.5,
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  isAppPositive ? Icons.monetization_on : Icons.money_off,
                  size: 80,
                  color: color,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Resumo da Rodada",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                "Seu time fez ${widget.points.toStringAsFixed(2)} pontos!",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Text(
                      isAppPositive ? "VALORIZOU" : "DESVALORIZOU",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "C\$ ${widget.appreciation.abs().toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("IR PARA O MERCADO",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
