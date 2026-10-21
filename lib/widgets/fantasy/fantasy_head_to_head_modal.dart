import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/fantasy_models.dart';
import '../../services/analytics_service.dart';
import '../team_logo_widget.dart';

class FantasyHeadToHeadModal {
  static void show(
    BuildContext context, {
    required FantasyTeam myTeam,
    required String rivalTeamName,
    required String rivalOwnerName,
    required double rivalTotalPoints,
    required double rivalTeamValue,
    required double rivalLastScore,
    String? rivalShieldType,
    String? rivalCustomLogoUrl,
  }) {
    AnalyticsService.logCustomScreenView('Fantasy_Head_To_Head_Modal');
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final double pointsDiff = myTeam.totalPoints - rivalTotalPoints;
        final double valueDiff = myTeam.teamValue - rivalTeamValue;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.compare_arrows_rounded,
                      color: Colors.deepOrange, size: 22),
                  SizedBox(width: 8),
                  Text(
                    "CONFRONTO DIRETO (1x1)",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Arena de Duelo 1x1
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Meu Time
                    Expanded(
                      child: Column(
                        children: [
                          TeamLogoWidget(
                            shieldType: myTeam.shieldType,
                            logoUrl: myTeam.customLogoUrl,
                            radius: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            myTeam.teamName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            "Você",
                            style: TextStyle(
                              color: Colors.greenAccent.shade400,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // VS Badge
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Text(
                        "VS",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),

                    // Time Rival
                    Expanded(
                      child: Column(
                        children: [
                          TeamLogoWidget(
                            shieldType: rivalShieldType ?? '1',
                            logoUrl: rivalCustomLogoUrl,
                            radius: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            rivalTeamName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            rivalOwnerName,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Métricas Comparativas
              _buildComparisonMetric(
                label: "Pontuação Geral",
                myValue: "${myTeam.totalPoints.toStringAsFixed(1)} pts",
                rivalValue: "${rivalTotalPoints.toStringAsFixed(1)} pts",
                isMyWinning: pointsDiff >= 0,
                diffLabel:
                    "${pointsDiff >= 0 ? '+' : ''}${pointsDiff.toStringAsFixed(1)} pts",
              ),
              const SizedBox(height: 8),
              _buildComparisonMetric(
                label: "Patrimônio",
                myValue: "C\$ ${myTeam.teamValue.toStringAsFixed(2)}",
                rivalValue: "C\$ ${rivalTeamValue.toStringAsFixed(2)}",
                isMyWinning: valueDiff >= 0,
                diffLabel:
                    "${valueDiff >= 0 ? '+' : ''}C\$ ${valueDiff.toStringAsFixed(2)}",
              ),
              const SizedBox(height: 8),
              _buildComparisonMetric(
                label: "Última Rodada",
                myValue: "${myTeam.lastScore.toStringAsFixed(1)} pts",
                rivalValue: "${rivalLastScore.toStringAsFixed(1)} pts",
                isMyWinning: myTeam.lastScore >= rivalLastScore,
                diffLabel:
                    "${(myTeam.lastScore - rivalLastScore) >= 0 ? '+' : ''}${(myTeam.lastScore - rivalLastScore).toStringAsFixed(1)} pts",
              ),
              const SizedBox(height: 20),

              // Botão Compartilhar Desafio no WhatsApp
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    AnalyticsService.logShare('fantasy_h2h_challenge', rivalTeamName);

                    final message =
                        "⚔️ *DESAFIO 1x1 NO FANTASY CARTOLA FJF!* ⚽🔥\n\n"
                        "🛡️ *${myTeam.teamName}* (${myTeam.totalPoints.toStringAsFixed(1)} pts)\n"
                        "⚡ *VERSUS*\n"
                        "🛡️ *$rivalTeamName* (${rivalTotalPoints.toStringAsFixed(1)} pts)\n\n"
                        "Quem vai mitar na próxima rodada? Monte seu time no app:\n"
                        "👉 https://acefjf.web.app\n\n#CartolaFJF #Duelo1x1";

                    await SharePlus.instance.share(
                      ShareParams(
                        text: message,
                        subject: "Desafio 1x1: ${myTeam.teamName} vs $rivalTeamName",
                      ),
                    );
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text("Desafiar no WhatsApp"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildComparisonMetric({
    required String label,
    required String myValue,
    required String rivalValue,
    required bool isMyWinning,
    required String diffLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              myValue,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isMyWinning ? Colors.green.shade700 : Colors.black87,
              ),
            ),
          ),
          Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                diffLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isMyWinning ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ),
          Expanded(
            child: Text(
              rivalValue,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: !isMyWinning ? Colors.green.shade700 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
