// lib/utils/custom_cache_manager.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:flutter/foundation.dart';

class PlayerCacheManager {
  static const key = 'playerCacheKey';

  static CacheManager? get instance {
    if (kIsWeb) return null;
    return _instance ??= CacheManager(
      Config(
        key,
        stalePeriod: const Duration(days: 3), // Mantém imagens por 3 dias
        maxNrOfCacheObjects: 300, 
        repo: JsonCacheInfoRepository(databaseName: key),
        fileService: HttpFileService(),
      ),
    );
  }

  static CacheManager? _instance;
}