import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class YoutubeUtils {
  /// Extrai o ID de 11 caracteres de qualquer formato de link do YouTube.
  static String? extractVideoId(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final cleanUrl = url.trim();

    // 1. Tenta usar o helper nativo do pacote
    final idFromPkg = YoutubePlayerController.convertUrlToId(cleanUrl);
    if (idFromPkg != null && idFromPkg.isNotEmpty && idFromPkg.length == 11) {
      return idFromPkg;
    }

    // 2. Regex abrangente para cobrir Shorts, Live, Embeds e query strings variadas
    final RegExp regExp = RegExp(
      r'^(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|v\/|shorts\/|live\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})(?:[?&].*)?$',
      caseSensitive: false,
    );

    final match = regExp.firstMatch(cleanUrl);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }

    // 3. Fallback: Se o usuário colou diretamente o ID de 11 caracteres
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(cleanUrl)) {
      return cleanUrl;
    }

    return null;
  }

  /// Verifica se a URL informada é um link válido do YouTube
  static bool isValidYoutubeUrl(String? url) {
    return extractVideoId(url) != null;
  }

  /// Retorna a URL da miniatura (thumbnail) do vídeo gerada pelo YouTube
  static String? getThumbnailUrl(String? videoIdOrUrl, {bool highQuality = true}) {
    final videoId = extractVideoId(videoIdOrUrl);
    if (videoId == null) return null;
    final quality = highQuality ? 'hqdefault' : 'mqdefault';
    return 'https://img.youtube.com/vi/$videoId/$quality.jpg';
  }
}
