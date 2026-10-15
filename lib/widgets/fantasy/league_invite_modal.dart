import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/fantasy_league_model.dart';
import '../../services/analytics_service.dart';

/// Modal e utilitário para visualização e compartilhamento de códigos de acesso de ligas privadas.
class LeagueInviteModal {
  /// Gera a mensagem padronizada de convite para envio em redes sociais e mensageiros.
  static String generateInviteMessage(FantasyLeague league) {
    final typeName =
        league.type == 'knockout' ? 'Mata-Mata' : 'Clássica (Pontos Corridos)';
    return "🏆 Convite para o Fantasy Cartola FJF!\n\n"
        "Você foi convidado para a liga:\n"
        "⚽ *${league.name}* ($typeName)\n\n"
        "🔑 *Código de Acesso:* ${league.inviteCode}\n\n"
        "📲 *Como participar:*\n"
        "1. Abra o app Força Jovem Fumacense (acefjf.web.app)\n"
        "2. Acesse a aba *Fantasy* > *Ligas*\n"
        "3. Toque no botão *'Entrar'* e digite o código: *${league.inviteCode}*\n\n"
        "Monte seu time e venha disputar com a galera!";
  }

  /// Aciona o compartilhamento nativo do dispositivo (WhatsApp, Telegram, etc).
  static Future<void> share(BuildContext context, FantasyLeague league,
      {bool showSnackBar = true}) async {
    final message = generateInviteMessage(league);
    AnalyticsService.logShare('league_invite_code', league.id);

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: "Convite para a Liga ${league.name} no Fantasy FJF",
        ),
      );
    } catch (_) {
      // Fallback para clipboard em navegadores desktop ou ambientes sem Web Share API
      if (context.mounted) {
        await copyCode(context, league.inviteCode, showSnackBar: showSnackBar);
      }
    }
  }

  /// Copia somente o código de 6 dígitos para a área de transferência.
  static Future<void> copyCode(BuildContext context, String inviteCode,
      {bool showSnackBar = true}) async {
    await Clipboard.setData(ClipboardData(text: inviteCode));
    AnalyticsService.logShare('league_invite_code_copied', inviteCode);

    if (showSnackBar && context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Código $inviteCode copiado com sucesso!",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.fixed,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Copia o texto completo com o passo a passo para a área de transferência.
  static Future<void> copyFullMessage(
      BuildContext context, FantasyLeague league,
      {bool showSnackBar = true}) async {
    final message = generateInviteMessage(league);
    await Clipboard.setData(ClipboardData(text: message));
    AnalyticsService.logShare('league_invite_message_copied', league.id);

    if (showSnackBar && context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Mensagem de convite completa copiada!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.fixed,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Exibe a BottomSheet com o código em destaque e opções de compartilhamento.
  static void show(BuildContext context, FantasyLeague league,
      {bool isOwner = false}) {
    final primaryColor = Theme.of(context).primaryColor;
    bool codeCopied = false;
    bool messageCopied = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void handleCopyCode() {
              copyCode(context, league.inviteCode, showSnackBar: false);
              setModalState(() {
                codeCopied = true;
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (ctx.mounted) {
                  setModalState(() {
                    codeCopied = false;
                  });
                }
              });
            }

            void handleCopyFullMessage() {
              copyFullMessage(context, league, showSnackBar: false);
              setModalState(() {
                messageCopied = true;
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (ctx.mounted) {
                  setModalState(() {
                    messageCopied = false;
                  });
                }
              });
            }

            Future<void> handleShare() async {
              try {
                await SharePlus.instance.share(
                  ShareParams(
                    text: generateInviteMessage(league),
                    subject: "Convite para a Liga ${league.name} no Fantasy FJF",
                  ),
                );
              } catch (_) {
                handleCopyCode();
              }
            }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Barra puxador superior
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Selo de Dono / Liga
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOwner
                        ? Colors.amber.shade100
                        : primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOwner ? Icons.star_rounded : Icons.emoji_events,
                        size: 16,
                        color: isOwner ? Colors.amber.shade900 : primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOwner ? "Você é o Dono da Liga" : "Liga Privada",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isOwner ? Colors.amber.shade900 : primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Nome da Liga
                Text(
                  league.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Compartilhe o código de acesso com seus amigos para eles entrarem nesta liga:",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),

                // Card do Código de Acesso
                InkWell(
                  onTap: handleCopyCode,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                    decoration: BoxDecoration(
                      color: codeCopied
                          ? Colors.green.shade50
                          : primaryColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: codeCopied
                            ? Colors.green.shade600
                            : primaryColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              league.inviteCode,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: codeCopied
                                    ? Colors.green.shade700
                                    : primaryColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              codeCopied
                                  ? Icons.check_circle
                                  : Icons.copy_rounded,
                              color: codeCopied
                                  ? Colors.green.shade700
                                  : primaryColor,
                              size: 22,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          codeCopied
                              ? "✓ Código copiado com sucesso!"
                              : "Toque para copiar",
                          style: TextStyle(
                            fontSize: 11,
                            color: codeCopied
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Botões de Ação
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: handleCopyCode,
                        icon: Icon(
                          codeCopied ? Icons.check : Icons.copy,
                          size: 18,
                          color: codeCopied ? Colors.green.shade700 : null,
                        ),
                        label: Text(
                          codeCopied ? "Copiado!" : "Copiar Código",
                          style: TextStyle(
                            color: codeCopied ? Colors.green.shade700 : null,
                            fontWeight: codeCopied ? FontWeight.bold : null,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: codeCopied
                                ? Colors.green.shade600
                                : Colors.grey.shade400,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: handleShare,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text("Compartilhar"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Botão de Copiar Texto Completo
                TextButton.icon(
                  onPressed: handleCopyFullMessage,
                  icon: Icon(
                    messageCopied ? Icons.check_circle : Icons.chat_outlined,
                    size: 16,
                    color: messageCopied
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                  label: Text(
                    messageCopied
                        ? "✓ Mensagem completa copiada!"
                        : "Copiar mensagem completa para WhatsApp",
                    style: TextStyle(
                      fontSize: 12,
                      color: messageCopied
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Instruções Rápidas
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Para entrar, seus amigos devem acessar Fantasy > Ligas, tocar no botão laranja 'Entrar' e colar este código.",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  },
);
}
}
