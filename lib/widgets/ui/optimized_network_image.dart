import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/custom_cache_manager.dart';

/// Widget de imagem de rede ultra-otimizado para dispositivos móveis e Web (iOS Safari).
/// Garante que o decodificador de imagem respeite limites rigorosos de resolução (cacheWidth / cacheHeight),
/// evitando que fotos em alta resolução (3MB-10MB / 4000x3000px) decodifiquem em buffers
/// descompactados de 48MB na RAM, o que causava encerramento súbito do processo (Jetsam OOM Crash) no iOS.
class OptimizedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final int memCacheWidth;
  final int memCacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;
  final IconData fallbackIcon;

  const OptimizedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.memCacheWidth = 160,
    this.memCacheHeight = 200,
    this.placeholder,
    this.errorWidget,
    this.fallbackIcon = Icons.person,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildErrorWidget();
    }

    // Passar apenas uma dimensão (cacheHeight) preserva a proporção original da imagem
    // no decodificador nativo/Web do Flutter, evitando distorção (esticamento) em escudos e fotos.
    final int targetCacheHeight = memCacheHeight > 0 ? memCacheHeight : memCacheWidth;

    if (kIsWeb) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        cacheHeight: targetCacheHeight,
        filterQuality: FilterQuality.low,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ??
              Center(
                child: SizedBox(
                  width: (width != null && width! < 30) ? 12 : 16,
                  height: (height != null && height! < 30) ? 12 : 16,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              );
        },
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: PlayerCacheManager.instance,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheHeight: targetCacheHeight,
      maxHeightDiskCache: targetCacheHeight * 2,
      filterQuality: FilterQuality.low,
      placeholder: (context, url) =>
          placeholder ??
          Center(
            child: SizedBox(
              width: (width != null && width! < 30) ? 12 : 16,
              height: (height != null && height! < 30) ? 12 : 16,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      errorWidget: (context, url, error) => _buildErrorWidget(),
    );
  }

  Widget _buildErrorWidget() {
    return errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: Icon(
            fallbackIcon,
            size: (width != null && width! < 30) ? 14 : 24,
            color: Colors.grey.shade500,
          ),
        );
  }
}
