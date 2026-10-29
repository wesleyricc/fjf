import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'fantasy_service.dart';
import 'fantasy_auth_service.dart';
import 'championship_service.dart';
import '../repositories/fantasy_repository.dart';
import '../viewmodels/fantasy_home_viewmodel.dart';

class FantasyPreloadService {
  static final FantasyPreloadService _instance =
      FantasyPreloadService._internal();
  factory FantasyPreloadService() => _instance;
  FantasyPreloadService._internal();

  bool _isWarmingUp = false;
  bool _hasWarmedUp = false;
  DateTime? _lastWarmUpTime;
  static const Duration _warmUpValidity = Duration(minutes: 5);

  bool get isReady =>
      _hasWarmedUp &&
      (_lastWarmUpTime != null &&
          DateTime.now().difference(_lastWarmUpTime!) < _warmUpValidity);

  /// Dispara o pré-aquecimento de dados essenciais do Fantasy em segundo plano.
  /// Executado durante a SplashScreen e na Home sem travar a thread principal da UI.
  Future<void> warmUp(BuildContext context) async {
    if (_isWarmingUp) return;
    if (isReady) return;

    _isWarmingUp = true;
    try {
      // 1. Pré-cache de imagens essenciais na GPU
      if (context.mounted) {
        try {
          precacheImage(
              const AssetImage('assets/logo_fjf_fantasy.webp'), context);
        } catch (_) {}
      }

      final repo = FantasyRepository();
      final fantasyService = FantasyService();

      String? userId;
      String? seasonId;

      try {
        final authService =
            Provider.of<FantasyAuthService>(context, listen: false);
        userId = authService.user?.uid;
      } catch (_) {}
      
      // Fallback para FirebaseAuth nativo se o AuthService ainda estiver em transição
      userId ??= FirebaseAuth.instance.currentUser?.uid;

      try {
        final champService =
            Provider.of<ChampionshipService>(context, listen: false);
        if (champService.currentSeasonId.isEmpty) {
          await champService.ensureInitialized();
        }
        seasonId = champService.currentSeasonId;
      } catch (_) {}

      // 2. Dispara aquecimento em paralelo com timeout generoso (aproveitando os 5 segundos de Splash)
      await Future.wait([
        // Carrega jogadores do mercado para a memória RAM
        repo.getAllPlayers(),
        // Carrega configurações / regras
        fantasyService.getGameConfig(),
        // Se usuário autenticado, carrega o time dele
        if (userId != null && userId.isNotEmpty) repo.getUserTeam(userId),
      ]).timeout(const Duration(seconds: 4), onTimeout: () => []);

      // 3. Se temos o ViewModel do Fantasy registrado globalmente e usuário autenticado,
      // já inicializa o ViewModel para que quando o usuário abrir a tela, esteja 100% pronto
      if (context.mounted && userId != null && userId.isNotEmpty && seasonId != null && seasonId.isNotEmpty) {
        try {
          final vm =
              Provider.of<FantasyHomeViewModel>(context, listen: false);
          if (!vm.isDisposed && vm.team == null) {
            vm.init(userId, seasonId);
          }
        } catch (_) {}
      }

      _hasWarmedUp = true;
      _lastWarmUpTime = DateTime.now();
      debugPrint("⚡ [FantasyPreloadService] Aquecimento em background concluído com sucesso!");
    } catch (e) {
      debugPrint("Aviso: Falha no pré-aquecimento do Fantasy: $e");
    } finally {
      _isWarmingUp = false;
    }
  }
}
