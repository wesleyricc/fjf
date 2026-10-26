import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';

import '../services/pwa_install_service.dart';
import '../services/analytics_service.dart';

class PwaInstallSheet extends StatelessWidget {
  const PwaInstallSheet({super.key});

  static Future<void> show(BuildContext context) {
    AnalyticsService.logCustomScreenView('Pwa_Install_Modal_Opened');

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PwaInstallSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pwaService = Provider.of<PwaInstallService>(context);
    final bool isIOS = pwaService.isIOS;
    final primaryColor = Theme.of(context).primaryColor;

    return PointerInterceptor(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra superior de puxar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              height: 4,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Cabeçalho
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      backgroundColor: Colors.white,
                      backgroundImage: AssetImage('assets/logo3_fjf.png'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isIOS ? "Instalar no iPhone / iPad" : "Instalar Aplicativo FJF",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isIOS
                              ? "Adicione à tela de início em 3 passos rápidos"
                              : "Tenha a melhor experiência em tela cheia",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Conteúdo dos passos
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  children: [
                    // Banner de benefícios
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bolt, color: Colors.green.shade700, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Abre em tela cheia instantaneamente, sem consumir memória da loja de apps.",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Passos conforme a plataforma
                    if (isIOS) ...[
                      _buildStepCard(
                        stepNumber: "1",
                        icon: Icons.ios_share,
                        iconColor: Colors.blue,
                        title: "Toque em Compartilhar",
                        description: "Na barra inferior do Safari, clique no ícone de compartilhamento (o quadrado com uma seta para cima).",
                        tipText: "Dica: Fica bem no centro inferior da tela do seu iPhone.",
                      ),
                      const SizedBox(height: 12),
                      _buildStepCard(
                        stepNumber: "2",
                        icon: Icons.add_box_outlined,
                        iconColor: Colors.green,
                        title: "Adicionar à Tela de Início",
                        description: "Role a lista de ações para baixo até encontrar a opção 'Adicionar à Tela de Início'.",
                      ),
                      const SizedBox(height: 12),
                      _buildStepCard(
                        stepNumber: "3",
                        icon: Icons.check_circle_outline,
                        iconColor: Colors.amber.shade800,
                        title: "Toque em 'Adicionar'",
                        description: "No canto superior direito da tela, confirme tocando em 'Adicionar'.",
                        tipText: "Pronto! O ícone do FJF estará na sua tela inicial como um app nativo.",
                      ),
                    ] else ...[
                      if (pwaService.hasPromptEvent) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.download_rounded, color: Colors.white),
                            label: const Text(
                              "Instalar Agora com 1 Clique",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              pwaService.promptInstallOrShowGuide(context);
                            },
                          ),
                        ),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text("OU MANUALMENTE", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildStepCard(
                        stepNumber: "1",
                        icon: Icons.more_vert,
                        iconColor: Colors.blue,
                        title: "Abra o Menu do Navegador",
                        description: "Toque nos três pontinhos (⋮) no canto superior direito do seu navegador.",
                      ),
                      const SizedBox(height: 12),
                      _buildStepCard(
                        stepNumber: "2",
                        icon: Icons.install_mobile,
                        iconColor: Colors.green,
                        title: "Instalar Aplicativo",
                        description: "Selecione a opção 'Instalar aplicativo' ou 'Adicionar à tela inicial'.",
                      ),
                      const SizedBox(height: 12),
                      _buildStepCard(
                        stepNumber: "3",
                        icon: Icons.touch_app,
                        iconColor: Colors.amber.shade800,
                        title: "Confirmar Instalação",
                        description: "Confirme a instalação para criar o atalho direto no seu celular.",
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Botão Fechar / Concluir
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          "Entendi",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildStepCard({
    required String stepNumber,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    String? tipText,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge do ícone
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Textos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (tipText != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tipText,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
