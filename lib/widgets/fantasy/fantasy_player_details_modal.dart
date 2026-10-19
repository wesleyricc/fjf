import 'package:flutter/material.dart';
import '../../models/fantasy_models.dart';
import '../ui/sparkline_widget.dart';
import '../ui/optimized_network_image.dart';

class FantasyPlayerDetailsModal extends StatelessWidget {
  final FantasyPlayer player;
  final String? nextOpponentShieldUrl;
  final Widget? actionButton;
  final Widget? extraContent;

  const FantasyPlayerDetailsModal({
    super.key,
    required this.player,
    this.nextOpponentShieldUrl,
    this.actionButton,
    this.extraContent,
  });

  Widget _buildStatColumn(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
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
                fontSize: 9, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  List<double> _extractLastScores(List<Map<String, dynamic>> history) {
    if (history.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                if (player.photoUrl.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: OptimizedNetworkImage(
                          imageUrl: player.photoUrl,
                          memCacheWidth: 350,
                          memCacheHeight: 350,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorWidget: const Icon(Icons.person,
                              size: 120, color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.person,
                            size: 120, color: Colors.grey),
                      ),
                    ),
                  ),
                if (player.teamShieldUrl.isNotEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: OptimizedNetworkImage(
                        imageUrl: player.teamShieldUrl,
                        width: 56,
                        height: 56,
                        memCacheWidth: 80,
                        memCacheHeight: 80,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            player.position.toUpperCase(),
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(player.status),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "${player.lastPriceChange > 0 ? '▲' : (player.lastPriceChange < 0 ? '▼' : '-')} ${player.lastPriceChange.abs().toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: player.lastPriceChange > 0
                            ? Colors.green
                            : (player.lastPriceChange < 0
                                ? Colors.red
                                : Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Text(
                  "Mín. valorizar: ${(player.currentPrice * 0.35).toStringAsFixed(1)} pts",
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn(
                    "Média", player.averageScore.toStringAsFixed(2)),
                _buildStatColumn("Última", player.lastScore.toStringAsFixed(2)),
                _buildStatColumn("Jogos", player.matchesPlayed.toString()),
              ],
            ),
            const SizedBox(height: 16),
            if (player.history.isNotEmpty || true)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text("Próx:",
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black12,
                          backgroundImage: nextOpponentShieldUrl != null &&
                                  nextOpponentShieldUrl!.isNotEmpty
                              ? NetworkImage(nextOpponentShieldUrl!)
                              : null,
                          child: nextOpponentShieldUrl == null ||
                                  nextOpponentShieldUrl!.isEmpty
                              ? const Icon(Icons.shield,
                                  size: 14, color: Colors.black38)
                              : null,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text("Fase:",
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        SparklineWidget(
                          data: _extractLastScores(player.history),
                          width: 80,
                          height: 24,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (extraContent != null) ...[
              const SizedBox(height: 16),
              extraContent!,
            ],
            if (actionButton != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: actionButton!,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
