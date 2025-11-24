import 'dart:async'; // Import necessário para runZonedGuarded
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart'; 
import 'firebase_options_test.dart'; 

// Services
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/admin_service.dart';
import 'services/championship_service.dart'; // Import do novo serviço

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
import 'screens/manage_seasons_screen.dart'; // Se já tiver criado

// --- FUNÇÃO AUXILIAR PARA DETECTAR ERRO DE ÍNDICE ---
void _logFirestoreIndexError(Object error) {
  final e = error.toString();
  if (e.contains('failed-precondition') || e.contains('requires an index')) {
    debugPrint('\n🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥');
    debugPrint('🔥 FALTA DE ÍNDICE DETECTADA NO FIRESTORE! 🔥');
    debugPrint('👉 CLIQUE NESTE LINK PARA CRIAR AUTOMATICAMENTE:');
    debugPrint(e); // O link estará aqui dentro
    debugPrint('🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥\n');
  }
}

void main() async {
  // Envolvemos tudo no runZonedGuarded para capturar erros de Streams (Assíncronos)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');
    FirebaseOptions firebaseOptions;

    if (environment == 'test') {
      debugPrint("⚠️ INICIANDO EM AMBIENTE DE TESTE (fjfapp-test) ⚠️");
      firebaseOptions = TestFirebaseOptions.currentPlatform;
    } else {
      debugPrint("✅ INICIANDO EM AMBIENTE DE PRODUÇÃO");
      firebaseOptions = DefaultFirebaseOptions.currentPlatform;
    }

    await Firebase.initializeApp(options: firebaseOptions);

    // Inicializações
    await NotificationService().init();
    await AdminService.loadAllRules('legacy_2025'); 

    // Intercepta erros síncronos do Flutter
    FlutterError.onError = (FlutterErrorDetails details) {
      _logFirestoreIndexError(details.exception);
      FlutterError.presentError(details); // Continua mostrando o erro na tela vermelha (em debug)
    };

    runApp(const FjfApp());
  
  }, (error, stack) {
    // Intercepta erros assíncronos (Streams, Futures soltos)
    _logFirestoreIndexError(error);
    debugPrint("Erro assíncrono capturado: $error");
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
        builder: (context, child) {
          if (isTestEnv) {
            return Banner(
              message: "TESTE",
              location: BannerLocation.topStart,
              color: Colors.red,
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
        
        theme: ThemeData(
          primaryColor: const Color(0xFFC25F22),
          colorScheme: ColorScheme.fromSwatch().copyWith(
            primary: const Color(0xFFC25F22),
            secondary: Colors.black,
          ),
          scaffoldBackgroundColor: Colors.grey[50],
          fontFamily: 'Roboto', 
          useMaterial3: false,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFC25F22),
            foregroundColor: Colors.white,
            centerTitle: false,
            elevation: 2,
          ),
        ),

        // 6. Rotas
        initialRoute: SplashScreen.routeName,
        routes: {
          '/': (ctx) => const SplashScreen(), // Rota raiz para evitar erro
          SplashScreen.routeName: (ctx) => const SplashScreen(),
          '/fixtures': (ctx) => const FixturesScreen(),
          '/standings': (ctx) => const StandingsScreen(),
          '/teams': (ctx) => const TeamsListScreen(),
          '/team-stats': (ctx) => const TeamStatsScreen(),
          '/player-stats': (ctx) => PlayerStatsScreen(),
          '/suspension-history': (ctx) => SuspensionHistoryScreen(),
          '/player-comparison': (ctx) => const PlayerComparisonScreen(),
          '/report-bug': (ctx) => const ReportBugScreen(),
          '/admin-menu': (ctx) => const AdminMenuScreen(),
        },
      ),
    );
  }
}