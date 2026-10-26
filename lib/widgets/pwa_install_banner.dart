import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/pwa_install_service.dart';

class PwaInstallBanner extends StatelessWidget {
  const PwaInstallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PwaInstallService>(
      builder: (context, pwaService, _) {
        if (!pwaService.canShowBanner) {
          return const SizedBox.shrink();
        }

        final bool isIOS = pwaService.isIOS;
        final bool hasPrompt = pwaService.hasPromptEvent;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8F5E9), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Logo do App
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green.shade200, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: AssetImage('assets/logo3_fjf.png'),
                ),
              ),
              const SizedBox(width: 12),

              // Textos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Instale o App FJF",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isIOS ? "iOS" : "GRÁTIS",
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIOS
                          ? "Adicione à tela inicial do seu iPhone."
                          : "Acesso rápido e direto da tela inicial.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // Botão de Ação
              ElevatedButton(
                onPressed: () => pwaService.promptInstallOrShowGuide(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasPrompt ? Icons.download_rounded : (isIOS ? Icons.phone_iphone : Icons.info_outline),
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasPrompt ? "Instalar" : "Como Instalar",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Botão Fechar
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: "Lembrar mais tarde",
                onPressed: () {
                  pwaService.dismissBanner(days: 7);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Você pode instalar a qualquer momento pelo menu principal."),
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
