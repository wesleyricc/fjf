import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TeamLogoWidget extends StatelessWidget {
  final String? logoUrl;
  final double radius;

  const TeamLogoWidget({super.key, this.logoUrl, this.radius = 30});

  @override
  Widget build(BuildContext context) {
    // 1. Sem logo: Escudo padrão cinza
    if (logoUrl == null || logoUrl!.trim().isEmpty) {
      return CircleAvatar(
        radius: radius, 
        backgroundColor: Colors.grey.shade300, 
        child: Icon(Icons.shield, color: Colors.grey.shade600, size: radius * 1.2)
      );
    }

    // 2. Nossos Presets Nativos (Gerados em Código)
    if (logoUrl!.startsWith('preset_')) {
      IconData iconData;
      Color bgColor;
      
      switch (logoUrl) {
        case 'preset_1': iconData = Icons.shield; bgColor = Colors.blue.shade700; break;
        case 'preset_2': iconData = Icons.local_fire_department; bgColor = Colors.red.shade600; break;
        case 'preset_3': iconData = Icons.star; bgColor = Colors.amber.shade600; break;
        case 'preset_4': iconData = Icons.sports_soccer; bgColor = Colors.green.shade700; break;
        case 'preset_5': iconData = Icons.bolt; bgColor = Colors.purple.shade600; break;
        case 'preset_6': iconData = Icons.emoji_events; bgColor = Colors.orange.shade800; break;
        default: iconData = Icons.shield; bgColor = Colors.grey.shade700;
      }

      return CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        child: Icon(iconData, color: Colors.white, size: radius * 1.2),
      );
    }

    // 3. Logo Personalizada (Upload de Foto HTTP)
    return CachedNetworkImage(
      imageUrl: logoUrl!,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(radius: radius, child: const CircularProgressIndicator()),
      errorWidget: (context, url, error) => CircleAvatar(radius: radius, child: const Icon(Icons.broken_image)),
    );
  }
}