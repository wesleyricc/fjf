import 'package:flutter/material.dart';

class CustomEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final String? secondaryButtonText;
  final VoidCallback? onSecondaryButtonPressed;
  final Color? iconColor;

  const CustomEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonText,
    this.onButtonPressed,
    this.secondaryButtonText,
    this.onSecondaryButtonPressed,
    this.iconColor,
  });

  // --- NOVO: Construtor específico para Modo Offline ---
  factory CustomEmptyState.offline({VoidCallback? onRetry}) {
    return CustomEmptyState(
      icon: Icons.wifi_off_rounded,
      iconColor: Colors.red[300],
      title: "Sem Conexão",
      message: "Parece que você está offline. Verifique sua internet e tente novamente.",
      buttonText: "Tentar Novamente",
      onButtonPressed: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: iconColor ?? Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: 32),
              SizedBox(
                height: 45,
                child: ElevatedButton.icon(
                  onPressed: onButtonPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.refresh, size: 20),
                  label: Text(buttonText!),
                ),
              ),
            ],
            if (secondaryButtonText != null && onSecondaryButtonPressed != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onSecondaryButtonPressed,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).primaryColor,
                ),
                child: Text(secondaryButtonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}