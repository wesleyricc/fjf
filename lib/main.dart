// lib/main.dart
import 'dart:async'; // Necessário para runZonedGuarded
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fjf_app/firebase_options.dart'; 
import 'package:fjf_app/firebase_options_test.dart' as test_options;
import 'screens/splash_screen.dart';
import 'services/admin_service.dart';
import 'services/notification_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:fjf_app/screens/fixtures_screen.dart';
import 'package:fjf_app/screens/standings_screen.dart';
import 'package:fjf_app/screens/teams_list_screen.dart';
import 'package:fjf_app/screens/player_stats_screen.dart';
import 'package:fjf_app/screens/suspension_history_screen.dart';
import 'package:fjf_app/screens/report_bug_screen.dart';
import 'package:fjf_app/screens/admin_menu_screen.dart';
import 'package:fjf_app/screens/team_stats_screen.dart';
import 'package:fjf_app/screens/player_comparison_screen.dart';

// Função helper para ambiente
FirebaseOptions _getFirebaseOptions(String env) {
  switch (env) {
    case 'test':
      debugPrint("--- USANDO AMBIENTE DE TESTE ---");
      return test_options.DefaultFirebaseOptions.currentPlatform;
    case 'prod':
    default:
      debugPrint("--- USANDO AMBIENTE DE PRODUÇÃO ---");
      return DefaultFirebaseOptions.currentPlatform;
  }
}

Future<void> main() async {
  // Envolve a inicialização em um ZoneGuard para capturar erros silenciosos (Tela Preta)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('pt_BR', null);

    // 1. Ler a variável de ambiente
    const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');
    
    // 2. Obter as opções corretas
    final FirebaseOptions options = _getFirebaseOptions(environment);

    // 3. Inicializar o Firebase
    await Firebase.initializeApp(
      options: options,
    );

    // 4. DESABILITAR PERSISTÊNCIA OFFLINE (Correção Tela Preta)
    // Força o app a buscar dados novos sempre, evitando conflito de cache local
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    await AdminService.loadDisciplinaryRules();
    await AdminService.loadTiebreakerOrder();
    await AdminService.loadPlayoffRules();
    await AdminService.loadAppSettings();
    await NotificationService().init();

    runApp(const MyApp());
    
  }, (error, stackTrace) {
    // Se houver erro fatal na inicialização, imprime no console
    debugPrint("ERRO FATAL NA INICIALIZAÇÃO: $error");
    debugPrint(stackTrace.toString());
  });
}

// Observador do Analytics (Mantido igual)
class FjfAnalyticsObserver extends NavigatorObserver {
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  void _logScreenView(Route<dynamic> route) {
    final String? screenName = route.settings.name;
    if (screenName != null && screenName.startsWith('/')) {
      debugPrint('[Analytics] Logando tela: $screenName');
      analytics.logScreenView(screenName: screenName);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logScreenView(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _logScreenView(previousRoute);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _logScreenView(newRoute);
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FJF App',
      theme: ThemeData(
        primaryColor: const Color(0xFFC25F22),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color(0xFF333333),
          primary: const Color(0xFFC25F22),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFC25F22),
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFC25F22),
        ),
        useMaterial3: true,
      ),
      
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      locale: const Locale('pt', 'BR'),
      
      initialRoute: '/', 

      navigatorObservers: [
        FjfAnalyticsObserver(),
      ],

      routes: {
        '/': (context) => const SplashScreen(),
        '/fixtures': (context) => const FixturesScreen(),
        '/standings': (context) => StandingsScreen(),
        '/teams': (context) => const TeamsListScreen(),
        '/team-stats': (context) => const TeamStatsScreen(),
        '/player-stats': (context) => PlayerStatsScreen(),
        '/suspension-history': (context) => SuspensionHistoryScreen(),
        '/report-bug': (context) => const ReportBugScreen(),
        '/admin-menu': (context) => const AdminMenuScreen(),
        '/player-comparison': (context) => const PlayerComparisonScreen(),
      },
    );
  }
}