import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

// Configurações
import 'firebase_options.dart'; 
import 'firebase_options_test.dart'; 
import 'theme/app_theme.dart'; // <-- Import do Tema

// Services
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/championship_service.dart';

// Screens
import 'screens/splash_screen.dart';
import 'screens/fixtures_screen.dart';
import 'screens/standings_screen.dart';
import 'screens/teams_list_screen.dart';
import 'screens/team_stats_screen.dart';
import 'screens/player_stats_screen.dart';
import 'screens/suspension_history_screen.dart';
import 'screens/player_comparison_screen.dart';
import 'screens/report_bug_screen.dart';
import 'screens/admin_menu_screen.dart';
import 'screens/photo_sales_screen.dart';

void _logFirestoreIndexError(Object error) {
  final e = error.toString();
  if (e.contains('failed-precondition') || e.contains('requires an index')) {
    debugPrint('\n🔥🔥🔥 FALTA DE ÍNDICE DETECTADA! 🔥🔥🔥');
    final linkRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
    final match = linkRegex.firstMatch(e);
    if (match != null) debugPrint(match.group(0)); else debugPrint(e);
    debugPrint('🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥\n');
  }
}

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');
    FirebaseOptions firebaseOptions = (environment == 'test')
        ? TestFirebaseOptions.currentPlatform
        : DefaultFirebaseOptions.currentPlatform;

    if (environment == 'test') debugPrint("⚠️ AMBIENTE DE TESTE ⚠️");

    await Firebase.initializeApp(options: firebaseOptions);
    await NotificationService().init();
    await initializeDateFormatting('pt_BR', null);

    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('failed-precondition')) {
         _logFirestoreIndexError(details.exception);
      }
      FlutterError.presentError(details); 
    };

    runApp(const FjfApp());
  
  }, (error, stack) {
    _logFirestoreIndexError(error);
    debugPrint("Erro assíncrono: $error");
  });
}

class FjfApp extends StatelessWidget {
  const FjfApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bool isTestEnv = String.fromEnvironment('ENV') == 'test';

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChampionshipService()),
      ],
      child: MaterialApp(
        title: 'FJF 2025',
        debugShowCheckedModeBanner: false,
        
        // --- APLICAÇÃO DO TEMA CENTRALIZADO ---
        theme: AppTheme.lightTheme, 
        // --------------------------------------

        builder: (context, child) {
          if (isTestEnv) {
            return Banner(
              message: "TESTE",
              location: BannerLocation.topStart,
              color: Colors.red,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              child: child!,
            );
          }
          return child!;
        },

        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
        
        initialRoute: '/',
        routes: {
          '/': (ctx) => const SplashScreen(),
          '/fixtures': (ctx) => const FixturesScreen(),
          '/standings': (ctx) => const StandingsScreen(),
          '/teams': (ctx) => const TeamsListScreen(),
          '/team-stats': (ctx) => const TeamStatsScreen(),
          '/player-stats': (ctx) => const PlayerStatsScreen(),
          '/suspension-history': (ctx) => SuspensionHistoryScreen(),
          '/player-comparison': (ctx) => const PlayerComparisonScreen(),
          '/report-bug': (ctx) => const ReportBugScreen(),
          '/admin-menu': (ctx) => const AdminMenuScreen(),
          '/photo-sales': (ctx) => const PhotoSalesScreen(),
        },
      ),
    );
  }
}