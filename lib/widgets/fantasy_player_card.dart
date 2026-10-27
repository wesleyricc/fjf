import 'package:flutter/material.dart';
import '../models/fantasy_models.dart';
import 'ui/sparkline_widget.dart';
import 'ui/optimized_network_image.dart';

class FantasyPlayerCard extends StatelessWidget {
  final FantasyPlayer player;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final String? nextOpponentName;
  final String? nextOpponentShieldUrl;
  final bool isStarter;
  final bool isBench;
  final bool isCurrentSlot;

  const FantasyPlayerCard({
    super.key,
    required this.player,
    this.onTap,
    this.isSelected = false,
    this.isFavorite = false,
    this.onFavorite,
    this.nextOpponentName,
    this.nextOpponentShieldUrl,
    this.isStarter = false,
    this.isBench = false,
    this.isCurrentSlot = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color variationColor = player.lastPriceChange > 0
        ? Colors.green
        : (player.lastPriceChange < 0 ? Colors.red : Colors.grey);

    final String variationIcon = player.lastPriceChange > 0
        ? "▲"
        : (player.lastPriceChange < 0 ? "▼" : "-");

    final bool isFielded = isCurrentSlot || isStarter || isBench;

    final Color? cardColor = isCurrentSlot
        ? Colors.blue.shade50.withValues(alpha: 0.4)
        : (isStarter
            ? Colors.green.shade50.withValues(alpha: 0.35)
            : (isBench
                ? Colors.amber.shade50.withValues(alpha: 0.35)
                : null));

    final BorderSide cardSide = isSelected
        ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
        : (isCurrentSlot
            ? BorderSide(color: Colors.blue.shade400, width: 1.5)
            : (isStarter
                ? BorderSide(color: Colors.green.shade600, width: 1.5)
                : (isBench
                    ? BorderSide(color: Colors.amber.shade700, width: 1.5)
                    : BorderSide.none)));

    // Layout compacto: uma única linha com foto, nome/detalhes, forma e preço.
    return RepaintBoundary(
      child: Card(
        elevation: isFielded ? 2 : 1,
        color: cardColor,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: cardSide,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // 1. Foto e Escudo (OTIMIZADOS)
                    Stack(
                      children: [
                        Container(
                          width: 40,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: OptimizedNetworkImage(
                              imageUrl: player.photoUrl,
                              width: 40,
                              height: 48,
                              memCacheWidth: 100,
                              memCacheHeight: 120,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: OptimizedNetworkImage(
                              imageUrl: player.teamShieldUrl,
                              width: 16,
                              height: 16,
                              memCacheWidth: 40,
                              memCacheHeight: 40,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              errorWidget: const SizedBox.shrink(),
                            ),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(width: 10),

                    // 2. Nome + posição, status e próximo adversário
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            player.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildPositionChip(player.position),
                              if (player.secondaryPosition != null &&
                                  player.secondaryPosition!.isNotEmpty)
                                _buildPositionChip(player.secondaryPosition!),
                              _buildStatusBadge(player.status),
                              if (isCurrentSlot)
                                _buildFieldedBadge(
                                  label: "NESTA VAGA",
                                  color: Colors.blue.shade800,
                                  bgColor: Colors.blue.shade100,
                                  icon: Icons.check_circle_outline,
                                )
                              else if (isStarter)
                                _buildFieldedBadge(
                                  label: "ESCALADO",
                                  subLabel: "TITULAR",
                                  color: Colors.green.shade800,
                                  bgColor: Colors.green.shade100,
                                  icon: Icons.shield,
                                )
                              else if (isBench)
                                _buildFieldedBadge(
                                  label: "ESCALADO",
                                  subLabel: "RESERVA",
                                  color: Colors.amber.shade900,
                                  bgColor: Colors.amber.shade100,
                                  icon: Icons.event_seat,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 3. Gráfico de Forma (Últimas 5 rodadas)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SparklineWidget(
                        data: _extractLastScores(player.history),
                        width: 40,
                        height: 24,
                      ),
                    ),

                    // 4. Preço e Variação
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onFavorite != null)
                          GestureDetector(
                            onTap: onFavorite,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6.0),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite
                                    ? Colors.red
                                    : Colors.grey.shade400,
                                size: 18,
                              ),
                            ),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black87),
                            ),
                            Text(
                              "$variationIcon ${player.lastPriceChange.abs().toStringAsFixed(2)}",
                              style: TextStyle(
                                color: variationColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                // 5. Rodapé: próximo adversário (legendado) e mínimo para valorizar
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text("Próx. adversário:",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    Container(
                      width: 16,
                      height: 16,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black12,
                      ),
                      child: nextOpponentShieldUrl != null &&
                              nextOpponentShieldUrl!.isNotEmpty
                          ? OptimizedNetworkImage(
                              imageUrl: nextOpponentShieldUrl!,
                              width: 16,
                              height: 16,
                              memCacheWidth: 40,
                              memCacheHeight: 40,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              errorWidget: const Icon(Icons.shield,
                                  size: 10, color: Colors.black38),
                            )
                          : const Icon(Icons.shield,
                              size: 10, color: Colors.black38),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        nextOpponentName ?? "A definir",
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Text(
                        "Mín. valorizar: ${(player.currentPrice * 0.35).toStringAsFixed(1)} pts",
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildPositionChip(String position) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      position.toUpperCase(),
      style: TextStyle(
          fontSize: 9, color: Colors.grey[800], fontWeight: FontWeight.bold),
    ),
  );
}

// Extrai as últimas 5 pontuações
List<double> _extractLastScores(List<Map<String, dynamic>> history) {
  if (history.isEmpty) {
    // Retorna mock para visualizar a UI se não houver histórico
    return [0.0, 0.0, 0.0, 0.0, 0.0];
  }

  List<double> scores = [];
  int count = history.length > 5 ? 5 : history.length;
  final reversed = history.reversed.toList();

  for (int i = 0; i < count; i++) {
    final doc = reversed[i];
    final score = doc['points'] ?? doc['total_score'] ?? doc['score'] ?? 0.0;
    scores.add((score is num) ? score.toDouble() : 0.0);
  }

  return scores.reversed.toList();
}

Widget _buildStatusBadge(String status) {
  Color color;
  IconData icon;
  String label;

  switch (status.toLowerCase()) {
    case 'injured':
      color = Colors.red;
      icon = Icons.local_hospital;
      label = 'Contundido';
      break;
    case 'eternal':
      color = Colors.yellow;
      icon = Icons.star;
      label = 'Eterno';
      break;
    case 'suspended':
      color = Colors.red;
      icon = Icons.block;
      label = 'Suspenso';
      break;
    case 'doubt':
    case 'doubtful':
      color = Colors.orange;
      icon = Icons.help_outline;
      label = 'Dúvida';
      break;
    case 'probable':
    default:
      color = Colors.green;
      icon = Icons.check_circle;
      label = 'Provável';
      break;
  }

  // Versão minimalista: apenas o ícone colorido (rótulo no tooltip).
  return Tooltip(
    message: label,
    child: Icon(icon, size: 14, color: color),
  );
}

Widget _buildFieldedBadge({
  required String label,
  String? subLabel,
  required Color color,
  required Color bgColor,
  required IconData icon,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          subLabel != null ? "$label ($subLabel)" : label,
          style: TextStyle(
            fontSize: 9,
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.1,
          ),
        ),
      ],
    ),
  );
}
