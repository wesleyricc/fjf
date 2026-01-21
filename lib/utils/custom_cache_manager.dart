// lib/utils/custom_cache_manager.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class PlayerCacheManager {
  static const key = 'playerCacheKey';

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7), // Mantém imagens por 7 dias
      // Aumentado para 1000 para evitar que fotos de times grandes sejam 
      // excluídas prematuramente do cache em disco.
      maxNrOfCacheObjects: 1000, 
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}