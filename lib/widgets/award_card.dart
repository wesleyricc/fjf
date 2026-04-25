import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/award_model.dart'; 
import '../utils/custom_cache_manager.dart';

class AwardCard extends StatelessWidget {
  final Award award;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isAdmin;

  const AwardCard({
    super.key,
    required this.award,
    this.onEdit,
    this.onDelete,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (award.category) {
      case 'goalkeeper': icon = Icons.sports_handball; break;
      case 'coach': icon = Icons.psychology; break;
      case 'team': icon = Icons.groups; break;
      case 'player': default: icon = Icons.person; break;
    }

    final Color headerColor = Colors.amber[800]!;

    return Stack(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: headerColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        award.title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: headerColor,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 10),

                // ---> OTIMIZAÇÃO: LIMITADOR DE RAM NO PROVIDER <---
                CircleAvatar(
                  radius: 30,
                  backgroundColor: headerColor.withOpacity(0.1),
                  backgroundImage: (award.imageUrl != null && award.imageUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(
                          award.imageUrl!,
                          cacheManager: PlayerCacheManager.instance,
                          maxWidth: 150,
                          maxHeight: 150,
                        )
                      : null,
                  child: (award.imageUrl == null || award.imageUrl!.isEmpty)
                      ? Icon(icon, size: 28, color: headerColor)
                      : null,
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  award.winnerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                if (award.subtitle != null && award.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    award.subtitle!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]
              ],
            ),
          ),
        ),
        
        if (isAdmin)
          Positioned(
            right: 4,
            top: 4,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onSelected: (val) {
                if (val == 'edit') onEdit?.call();
                if (val == 'delete') onDelete?.call();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                const PopupMenuItem(value: 'delete', child: Text('Excluir', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
      ],
    );
  }
}