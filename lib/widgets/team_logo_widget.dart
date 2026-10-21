import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TeamLogoWidget extends StatelessWidget {
  final String? logoUrl;
  final String? shieldType;
  final double radius;

  const TeamLogoWidget({
    super.key,
    this.logoUrl,
    this.shieldType,
    this.radius = 30,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Determina a fonte da logo ou escudo
    String key = (logoUrl ?? '').trim();
    if (key.isEmpty || key == 'null') {
      key = (shieldType ?? '').trim();
    }

    if (key.isEmpty || key == 'null') {
      return _buildDefaultShield(radius);
    }

    // 2. Presets nativos em código (preset_X, shield_X ou número de 1 a 10)
    if (_isPreset(key)) {
      return _buildPresetShield(key, radius);
    }

    // 3. Validação de URL: se não for HTTP/HTTPS, não tenta carregar via rede
    if (!key.startsWith('http://') && !key.startsWith('https://')) {
      return _buildPresetShield(key, radius);
    }

    // 4. Logo personalizada via rede (Web-safe)
    if (kIsWeb) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(radius * 0.12),
          child: Image.network(
            key,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: SizedBox(
                  width: (radius < 20) ? 10 : 16,
                  height: (radius < 20) ? 10 : 16,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                _buildDefaultShield(radius),
          ),
        ),
      );
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(radius * 0.12),
        child: CachedNetworkImage(
          imageUrl: key,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.contain,
          placeholder: (context, url) => Center(
            child: SizedBox(
              width: (radius < 20) ? 10 : 16,
              height: (radius < 20) ? 10 : 16,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => _buildDefaultShield(radius),
        ),
      ),
    );
  }

  static bool _isPreset(String key) {
    if (key.startsWith('preset_') || key.startsWith('shield_')) return true;
    final intVal = int.tryParse(key);
    return intVal != null && intVal >= 1 && intVal <= 10;
  }

  static Widget _buildPresetShield(String key, double radius) {
    IconData iconData;
    Color bgColor;

    // Normaliza 'shield_1' ou '1' para o equivalente do preset
    String normalized = key;
    if (normalized.startsWith('shield_')) {
      normalized = normalized.replaceFirst('shield_', 'preset_');
    } else if (int.tryParse(normalized) != null) {
      normalized = 'preset_$normalized';
    }

    switch (normalized) {
      case 'preset_1':
        iconData = Icons.shield;
        bgColor = Colors.blue.shade700;
        break;
      case 'preset_2':
        iconData = Icons.local_fire_department;
        bgColor = Colors.red.shade600;
        break;
      case 'preset_3':
        iconData = Icons.star;
        bgColor = Colors.amber.shade600;
        break;
      case 'preset_4':
        iconData = Icons.sports_soccer;
        bgColor = Colors.green.shade700;
        break;
      case 'preset_5':
        iconData = Icons.bolt;
        bgColor = Colors.purple.shade600;
        break;
      case 'preset_6':
        iconData = Icons.emoji_events;
        bgColor = Colors.orange.shade800;
        break;
      case 'preset_7':
        iconData = Icons.military_tech;
        bgColor = Colors.teal.shade700;
        break;
      case 'preset_8':
        iconData = Icons.workspace_premium;
        bgColor = Colors.indigo.shade700;
        break;
      default:
        iconData = Icons.shield;
        bgColor = Colors.grey.shade700;
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(iconData, color: Colors.white, size: radius * 1.15),
      ),
    );
  }

  static Widget _buildDefaultShield(double radius) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.shield,
          color: Colors.grey.shade600,
          size: radius * 1.15,
        ),
      ),
    );
  }
}