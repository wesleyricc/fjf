// lib/utils/custom_cache_manager.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PlayerCacheManager {
  static const key = 'playerCacheKey';

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7), // Mantém imagens por 7 dias
      maxNrOfCacheObjects: 500, // Aumenta o limite de arquivos (padrão é ~200)
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}