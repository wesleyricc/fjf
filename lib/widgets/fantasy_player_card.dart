import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/custom_cache_manager.dart';
import '../models/fantasy_models.dart';

class FantasyPlayerCard extends StatelessWidget {
  final FantasyPlayer player;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  const FantasyPlayerCard({
    super.key,
    required this.player,
    this.onTap,
    this.isSelected = false,
    this.isFavorite = false,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
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
              // 1. Foto e Escudo (OTIMIZADOS COM CACHE)
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: player.photoUrl.isNotEmpty 
                        ? CachedNetworkImageProvider(
                            player.photoUrl, 
                            cacheManager: PlayerCacheManager.instance,
                            maxWidth: 150, 
                            maxHeight: 150,
                          ) 
                        : null,
                    child: player.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.white,
                      backgroundImage: player.teamShieldUrl.isNotEmpty 
                          ? CachedNetworkImageProvider(
                              player.teamShieldUrl, 
                              cacheManager: PlayerCacheManager.instance,
                              maxWidth: 60, 
                              maxHeight: 60,
                            ) 
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
                  Row(
                    children: [
                      if (onFavorite != null)
                        GestureDetector(
                          onTap: onFavorite,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Icon(
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: isFavorite ? Colors.red : Colors.grey.shade400,
                              size: 20,
                            ),
                          ),
                        ),
                      Text(
                        "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Text(
                      "Mín. valorizar: ${(player.currentPrice * 0.35).toStringAsFixed(1)} pts",
                      style: TextStyle(fontSize: 9, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
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
    switch (status) {
      case 'injured': color = Colors.red; break;
      case 'suspended': color = Colors.red; break;
      case 'doubtful': color = Colors.orange; break;
      default: color = Colors.green;
    }
    
    if (status == 'probable') return const SizedBox.shrink();

    return Icon(Icons.health_and_safety, size: 14, color: color);
  }
}