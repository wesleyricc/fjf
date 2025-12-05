import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/custom_cache_manager.dart';

class RankHighlightCard extends StatelessWidget {
  final int rank;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String statValue;
  final String statLabel;
  final IconData statIcon;
  final Color? customColor;
  final VoidCallback onTap;
  final bool isPlayer;
  
  // Novo parâmetro para informações extras (ex: detalhe dos cartões)
  final Widget? extraInfoWidget;

  const RankHighlightCard({
    super.key,
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.statValue,
    required this.statLabel,
    required this.statIcon,
    required this.onTap,
    this.customColor,
    this.isPlayer = false,
    this.extraInfoWidget, // <-- Novo
  });

  @override
  Widget build(BuildContext context) {
    // Definição de Cores do Pódio
    Color bgColor;
    Color textColor;
    Color iconColor;
    double scale;

    switch (rank) {
      case 1:
        bgColor = const Color(0xFFFFD700); // Ouro
        textColor = Colors.black87;
        iconColor = Colors.black54;
        scale = 1.05;
        break;
      case 2:
        bgColor = const Color(0xFFC0C0C0); // Prata
        textColor = Colors.black87;
        iconColor = Colors.black54;
        scale = 1.0;
        break;
      case 3:
        bgColor = const Color(0xFFCD7F32); // Bronze
        textColor = Colors.white;
        iconColor = Colors.white70;
        scale = 0.95;
        break;
      default:
        bgColor = Colors.white;
        textColor = Colors.black;
        iconColor = Colors.grey;
        scale = 1.0;
    }

    return Transform.scale(
      scale: scale,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: rank == 1 ? 6 : 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [bgColor, bgColor.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // 1. Posição (Rank)
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      "$rankº",
                      style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 14),
                    ),
                  ),
                  
                  const SizedBox(width: 12),

                  // 2. Imagem (Lógica Diferenciada para Time vs Jogador)
                  Hero(
                    tag: 'rank_${rank}_$title',
                    child: isPlayer
                        ? _buildPlayerImage() // Jogador: Círculo com foto
                        : _buildTeamImage(),  // Time: Logo solta (contain)
                  ),

                  const SizedBox(width: 16),

                  // 3. Dados
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // 4. Valor
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(statIcon, color: customColor ?? iconColor, size: 24),
                      const SizedBox(height: 2),
                      Text(
                        statValue,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: customColor ?? textColor,
                        ),
                      ),
                      Text(
                        statLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: textColor.withOpacity(0.7),
                        ),
                      ),
                      // Exibe o widget extra se fornecido (Ex: Detalhe de cartões)
                      if (extraInfoWidget != null) ...[
                        const SizedBox(height: 4),
                        extraInfoWidget!,
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Lógica Visual para Jogador (Mantém Círculo)
  Widget _buildPlayerImage() {
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.white.withOpacity(0.3),
      child: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: imageUrl.isNotEmpty
            ? CachedNetworkImageProvider(
                imageUrl,
                cacheManager: PlayerCacheManager.instance,
              )
            : null,
        child: imageUrl.isEmpty
            ? const Icon(Icons.person, size: 30, color: Colors.grey)
            : null,
      ),
    );
  }

  // Lógica Visual para Time (Logo inteira, sem corte)
  Widget _buildTeamImage() {
    return Container(
      width: 60,
      height: 60,
      // Sombra sutil para destacar o logo do fundo colorido
      decoration: BoxDecoration(
         shape: BoxShape.circle,
         boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
         ]
      ),
      child: imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain, // Garante que o escudo apareça inteiro
              placeholder: (c, u) => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              errorWidget: (c, u, e) => const Icon(Icons.shield, size: 30, color: Colors.white54),
            )
          : const Icon(Icons.shield, size: 40, color: Colors.white54),
    );
  }
}