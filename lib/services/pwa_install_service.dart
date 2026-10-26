import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

import 'analytics_service.dart';
import '../widgets/pwa_install_dialog.dart';

extension type BeforeInstallPromptEvent._(JSObject _) implements web.Event {
  external void prompt();
}

extension type NavigatorPwaExt(web.Navigator _) implements web.Navigator {
  external bool? get standalone;
}

class PwaInstallService extends ChangeNotifier {
  static final PwaInstallService _instance = PwaInstallService._internal();
  factory PwaInstallService() => _instance;

  static const String _dismissedPrefKey = 'pwa_install_dismissed_until';

  BeforeInstallPromptEvent? _installPromptEvent;
  bool _isInstalled = false;
  bool _isDismissed = false;
  bool _isInitialized = false;

  bool get isWeb => kIsWeb;
  bool get isInstalled => _isInstalled;
  bool get isDismissed => _isDismissed;
  bool get hasPromptEvent => _installPromptEvent != null;

  bool get isIOS => _detectIOS();
  bool get isAndroid => _detectAndroid();

  /// Se o banner pode ser exibido na tela inicial (apenas Web, não instalado e não dispensado)
  bool get canShowBanner => kIsWeb && !_isInstalled && !_isDismissed;

  /// Se o item de menu pode aparecer no menu principal (apenas Web e não instalado)
  bool get canShowMenuItem => kIsWeb && !_isInstalled;

  PwaInstallService._internal() {
    _init();
  }

  void _init() {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!kIsWeb) {
      _isInstalled = true;
      return;
    }

    // 1. Verifica se já está rodando em modo standalone (PWA instalado)
    _isInstalled = _detectStandalone();

    // 2. Carrega preferência de "Dispensar por X dias"
    _loadDismissedState();

    // 3. Ouve o evento nativo beforeinstallprompt (Android / Chrome / Edge)
    try {
      web.window.addEventListener(
        'beforeinstallprompt',
        ((web.Event e) {
          final event = e as BeforeInstallPromptEvent;
          event.preventDefault(); // Evita a barra nativa invasiva do navegador
          _installPromptEvent = event;
          notifyListeners();
        }).toJS,
      );

      // 4. Ouve quando o app é instalado com sucesso
      web.window.addEventListener(
        'appinstalled',
        ((web.Event e) {
          _isInstalled = true;
          _installPromptEvent = null;
          AnalyticsService.logCustomScreenView('Pwa_App_Installed_Success');
          notifyListeners();
        }).toJS,
      );
    } catch (e) {
      debugPrint('[PWA] Erro ao registrar listeners PWA: $e');
    }
  }

  bool _detectStandalone() {
    if (!kIsWeb) return true;
    try {
      // 1. Padrão W3C (Android Chrome, Edge, Desktop)
      final mediaMatches = web.window.matchMedia('(display-mode: standalone)').matches;
      if (mediaMatches) return true;

      // 2. iOS Safari (navigator.standalone)
      final nav = web.window.navigator as NavigatorPwaExt;
      if (nav.standalone == true) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  bool _detectIOS() {
    if (!kIsWeb) return defaultTargetPlatform == TargetPlatform.iOS;
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    } catch (_) {
      return defaultTargetPlatform == TargetPlatform.iOS;
    }
  }

  bool _detectAndroid() {
    if (!kIsWeb) return defaultTargetPlatform == TargetPlatform.android;
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      return ua.contains('android');
    } catch (_) {
      return defaultTargetPlatform == TargetPlatform.android;
    }
  }

  Future<void> _loadDismissedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final untilMs = prefs.getInt(_dismissedPrefKey) ?? 0;
      if (untilMs > 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now < untilMs) {
          _isDismissed = true;
          notifyListeners();
        } else {
          await prefs.remove(_dismissedPrefKey);
        }
      }
    } catch (e) {
      debugPrint('[PWA] Erro ao carregar dismissal: $e');
    }
  }

  /// Dispensa o banner pelo número de dias especificado (padrão 7 dias)
  Future<void> dismissBanner({int days = 7}) async {
    _isDismissed = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch;
      await prefs.setInt(_dismissedPrefKey, until);
    } catch (_) {}
  }

  /// Dispara a instalação automática (Android/Chrome) ou abre o guia visual (iOS)
  Future<void> promptInstallOrShowGuide(BuildContext context) async {
    AnalyticsService.logCustomScreenView('Pwa_Install_Action_Triggered');

    if (_installPromptEvent != null) {
      // Dispara o prompt nativo no Android/Chrome com 1 clique
      try {
        _installPromptEvent!.prompt();
        _installPromptEvent = null;
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('[PWA] Falha ao disparar prompt nativo: $e');
      }
    }

    // Se for iOS ou se o prompt nativo não disparou, mostra o guia passo a passo
    if (context.mounted) {
      PwaInstallSheet.show(context);
    }
  }

  /// Exibe diretamente o guia visual passo a passo
  void showGuide(BuildContext context) {
    PwaInstallSheet.show(context);
  }
}
