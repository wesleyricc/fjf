import 'package:flutter/material.dart';
import '../models/team_model.dart'; // Import do Model

class TeamStatsSummary extends StatelessWidget {
  final Team team; // <-- Uso do Model

  const TeamStatsSummary({super.key, required this.team});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.query_stats, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text('Desempenho', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),
            _buildStatRow('Pontos (P)', '${team.points}', icon: Icons.star, isHighlight: true),
            _buildStatRow('Jogos (J)', '${team.gamesPlayed}', icon: Icons.event),
            _buildStatRow('Vitórias (V)', '${team.wins}', icon: Icons.emoji_events),
            _buildStatRow('Empates (E)', '${team.draws}', icon: Icons.drag_handle),
            _buildStatRow('Derrotas (D)', '${team.losses}', icon: Icons.thumb_down_alt_outlined),
            const SizedBox(height: 8),
            _buildStatRow('Gols Pró (GP)', '${team.goalsFor}', icon: Icons.add_circle_outline),
            _buildStatRow('Gols Contra (GC)', '${team.goalsAgainst}', icon: Icons.remove_circle_outline),
            _buildStatRow('Saldo (SG)', '${team.goalDifference}', icon: Icons.swap_horiz, isHighlight: true),
            const SizedBox(height: 8),
            _buildStatRow('Disciplinar (PD)', '${team.disciplinaryPoints}', icon: Icons.style, iconColor: Colors.orange[800]),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {IconData? icon, Color? iconColor, bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? Colors.grey[600]),
              const SizedBox(width: 12)
            ],
            Text(label, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          ]),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold,
              color: isHighlight ? Colors.black : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}