import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/custom_cache_manager.dart';
import '../models/fantasy_models.dart';
import 'ui/sparkline_widget.dart';

class FantasyPlayerCard extends StatelessWidget {
  final FantasyPlayer player;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback? onFavorite;
  final String? nextOpponentName;
  final String? nextOpponentShieldUrl;

  const FantasyPlayerCard({
    super.key,
    required this.player,
    this.onTap,
    this.isSelected = false,
    this.isFavorite = false,
    this.onFavorite,
    this.nextOpponentName,
    this.nextOpponentShieldUrl,
  });

  @override
  Widget build(BuildContext context) {
    final Color variationColor = player.lastPriceChange > 0
        ? Colors.green
        : (player.lastPriceChange < 0 ? Colors.red : Colors.grey);

    final String variationIcon = player.lastPriceChange > 0
        ? "▲"
        : (player.lastPriceChange < 0 ? "▼" : "-");

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // 1. Foto e Escudo (OTIMIZADOS COM CACHE)
                  Stack(
                    children: [
                      Container(
                        width: 48,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: player.photoUrl.isNotEmpty
                              ? (kIsWeb
                                  ? Image.network(
                                      player.photoUrl,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.person, color: Colors.grey),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: player.photoUrl,
                                      cacheManager: PlayerCacheManager.instance,
                                      memCacheWidth: 200,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      placeholder: (context, url) =>
                                          const Center(
                                            child: SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          ),
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.person, color: Colors.grey),
                                    ))
                              : const Icon(Icons.person, color: Colors.grey),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: player.teamShieldUrl.isNotEmpty
                              ? (kIsWeb
                                  ? Image.network(
                                      player.teamShieldUrl,
                                      fit: BoxFit.contain,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: player.teamShieldUrl,
                                      cacheManager: PlayerCacheManager.instance,
                                      memCacheWidth: 60,
                                      fit: BoxFit.contain,
                                    ))
                              : null,
                        ),
                      )
                    ],
                  ),
                  const SizedBox(width: 16),

                  // 2. Dados Principais
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                player.position.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[800],
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (player.secondaryPosition != null &&
                                player.secondaryPosition!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  player.secondaryPosition!.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[800],
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            _buildStatusBadge(player.status),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 3. Preço e Variação
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          if (onFavorite != null)
                            GestureDetector(
                              onTap: onFavorite,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite
                                      ? Colors.red
                                      : Colors.grey.shade400,
                                  size: 20,
                                ),
                              ),
                            ),
                          Text(
                            "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87),
                          ),
                        ],
                      ),
                      Text(
                        "$variationIcon ${player.lastPriceChange.toStringAsFixed(2)}",
                        style: TextStyle(
                          color: variationColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
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

              // 4. Nova Seção UI/UX: Gráfico de Fase e Próximo Jogo
              if (player.history.isNotEmpty || true) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  child: Divider(height: 1, color: Colors.black12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Próximo Adversário (Com Avaliação de Dificuldade)
                      Row(
                        children: [
                          const Text("Próx:",
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          // Escudo adversário
                          CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.black12,
                              backgroundImage: nextOpponentShieldUrl != null &&
                                      nextOpponentShieldUrl!.isNotEmpty
                                  ? NetworkImage(nextOpponentShieldUrl!)
                                  : null,
                              child: nextOpponentShieldUrl == null ||
                                      nextOpponentShieldUrl!.isEmpty
                                  ? const Icon(Icons.shield,
                                      size: 10, color: Colors.black38)
                                  : null),

                        ],
                      ),

                      // Gráfico de Forma (Últimas 5 rodadas)
                      Row(
                        children: [
                          const Text("Fase:",
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          SparklineWidget(
                            data: _extractLastScores(player.history),
                            width: 50,
                            height: 18,
                          ),
                        ],
                      )
                    ],
                  ),
                )
              ] // end if spread
            ],
          ), // end Column
        ), // end Padding
      ), // end InkWell
    ); // end Card
  }
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

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
