import 'package:flutter/material.dart';
import '../models/fantasy_models.dart';

class FantasyPlayerCard extends StatelessWidget {
  final FantasyPlayer player;
  final VoidCallback? onTap;
  final bool isSelected;

  const FantasyPlayerCard({
    super.key,
    required this.player,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Cor da Variação
    final Color variationColor = player.lastPriceChange > 0 
        ? Colors.green 
        : (player.lastPriceChange < 0 ? Colors.red : Colors.grey);
    
    final String variationIcon = player.lastPriceChange > 0 ? "▲" : (player.lastPriceChange < 0 ? "▼" : "-");

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? BorderSide(color: Theme.of(context).primaryColor, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // 1. Foto e Escudo
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: player.photoUrl.isNotEmpty ? NetworkImage(player.photoUrl) : null,
                    child: player.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.white,
                      backgroundImage: player.teamShieldUrl.isNotEmpty ? NetworkImage(player.teamShieldUrl) : null,
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            player.position.toUpperCase(),
                            style: TextStyle(fontSize: 10, color: Colors.grey[800], fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                  Text(
                    "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  ),
                  Text(
                    "$variationIcon ${player.lastPriceChange.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: variationColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'injured': color = Colors.red; label = 'Contundido'; break;
      case 'suspended': color = Colors.red; label = 'Suspenso'; break;
      case 'doubtful': color = Colors.orange; label = 'Dúvida'; break;
      default: color = Colors.green; label = 'Provável';
    }
    
    if (status == 'probable') return const SizedBox.shrink(); // Não mostra nada se for provável

    return Icon(Icons.health_and_safety, size: 14, color: color);
  }
}