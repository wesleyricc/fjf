// lib/widgets/player_display_card.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/admin_service.dart'; // Importa o AdminService

class PlayerDisplayCard extends StatelessWidget {
  final String playerName;
  final int jerseyNumber;
  final int yellowCards;
  final int redCards;
  final bool isSuspended;
  final bool compactMode;
  final String? teamShieldUrl;
  final Color? teamColor; 

  const PlayerDisplayCard({
    super.key,
    required this.playerName,
    required this.jerseyNumber,
    this.yellowCards = 0,
    this.redCards = 0,
    this.isSuspended = false,
    this.compactMode = false,
    this.teamShieldUrl,
    this.teamColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSuspended ? Colors.grey : Colors.black;
    final textStyle = TextStyle(
      fontSize: compactMode ? 10 : 11, 
      fontWeight: FontWeight.bold,
      color: textColor,
    );
    final numberStyle = TextStyle(
      fontSize: compactMode ? 14 : 16,
      fontWeight: FontWeight.w900,
      color: textColor,
    );
    
    // Lógica de Ícones
    Widget? cardDisplay; 
    final iconSize = compactMode ? 10.0 : 14.0;

    if (isSuspended || redCards > 0) { 
      cardDisplay = Icon(
        Icons.style,
        color: Colors.red[700], 
        size: iconSize,
        semanticLabel: 'Suspenso',
      );
    } 
    else if (yellowCards >= AdminService.pendingYellowCards) {
      cardDisplay = Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          yellowCards,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.0),
            child: Icon(
              Icons.style,
              color: Colors.yellow[700], 
              size: iconSize,
              semanticLabel: 'Pendurado',
            ),
          ),
        ),
      );
    }
    
    return Container(
      width: compactMode ? 60 : 100.0, 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/player_jersey_placeholder.png',
                width: compactMode ? 40 : 50,
                height: compactMode ? 40 : 50,
                color: isSuspended ? Colors.grey[400] : (teamColor ?? Theme.of(context).primaryColor),
                colorBlendMode: BlendMode.modulate,
              ),
              Text(
                '$jerseyNumber',
                style: numberStyle.copyWith(color: Colors.white),
              ),
            ],
          ),
          
          // --- INÍCIO DA ALTERAÇÃO ---
          // Espaço reduzido de 4 para 2 no modo não compacto
          SizedBox(height: compactMode ? 1 : 2), 
          // --- FIM DA ALTERAÇÃO ---
          
          Text(
            playerName,
            textAlign: TextAlign.center,
            style: textStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (cardDisplay != null)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: cardDisplay,
            ),

          if (!compactMode && teamShieldUrl != null && teamShieldUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CachedNetworkImage(
                  imageUrl: teamShieldUrl!,
                  // PERFORMANCE: Adicionado memCacheHeight para ícone pequeno
                  memCacheHeight: 60, 
                  placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                  errorWidget: (context, url, error) => const Icon(Icons.shield, color: Colors.grey),
                  fit: BoxFit.contain,
                ),
              ),
            ),
        ],
      ),
    );
  }
}