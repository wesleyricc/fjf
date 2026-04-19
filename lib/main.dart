import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart'; 

// Configurações
import 'firebase_options.dart'; 
import 'firebase_options_test.dart'; 
import 'screens/fantasy_admin_control_screen.dart';
import 'screens/fantasy_history_screen.dart';
import 'screens/fantasy_ranking_screen.dart';
import 'screens/fantasy_rules_screen.dart';
import 'screens/teams_list_screen.dart';
import 'theme/app_theme.dart';

// Services
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/championship_service.dart';
import 'services/fantasy_service.dart';      
import 'services/fantasy_auth_service.dart'; 
import 'services/team_service.dart';
import 'services/player_service.dart';
import 'services/match_service.dart';
import 'services/media_service.dart';
import 'services/disciplinary_service.dart';
import 'services/award_service.dart';

// Viewmodels
import 'viewmodels/photo_sales_viewmodel.dart';
import 'viewmodels/fantasy_home_viewmodel.dart';
import 'viewmodels/fantasy_lineup_viewmodel.dart';

// Repositories
import 'repositories/fantasy_repository.dart';

// Screens
import 'screens/splash_screen.dart';
import 'screens/fixtures_screen.dart';
import 'screens/standings_screen.dart';
import 'screens/team_stats_screen.dart';
import 'screens/player_stats_screen.dart';
import 'screens/suspension_history_screen.dart';
import 'screens/player_comparison_screen.dart';
import 'screens/report_bug_screen.dart';
import 'screens/admin_menu_screen.dart';
import 'screens/photo_sales_screen.dart';
import 'screens/fantasy_home_screen.dart';
import 'screens/fantasy_market_screen.dart';
import 'screens/fantasy_lineup_screen.dart';
import 'screens/fantasy_ranking_screen.dart';
import 'screens/fantasy_admin_control_screen.dart';
import 'screens/fantasy_rules_screen.dart';
import 'screens/fantasy_history_screen.dart';
import 'screens/about_history_screen.dart';
import 'screens/about_board_screen.dart';
import 'screens/season_summary_screen.dart';

// ---> IMPORTS DO SISTEMA DE VOTAÇÃO <---
import 'screens/voting_screen.dart';
import 'models/poll_model.dart';

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

    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false, // Desliga o IndexedDB corrompido na Web
      );
    }
    
    // --- LÓGICA DE PERSISTÊNCIA INTELIGENTE ---
    const bool enablePersistence = !kIsWeb || kReleaseMode;

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: enablePersistence, 
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    if (kIsWeb && !kReleaseMode) {
      debugPrint("⚠️ Web Debug: Persistência do Firestore DESATIVADA para evitar conflitos.");
    }
    // ------------------------------------------

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
        ChangeNotifierProvider(create: (_) => PhotoSalesViewModel()),

        Provider<FantasyRepository>(create: (_) => FantasyRepository()),

        Provider(create: (_) => TeamService()),
        Provider(create: (_) => PlayerService()),
        Provider(create: (_) => MatchService()),
        Provider(create: (_) => MediaService()),
        Provider(create: (_) => DisciplinaryService()),
        Provider(create: (_) => AwardService()),

        ChangeNotifierProvider(create: (_) => FantasyHomeViewModel()),
        ChangeNotifierProvider(create: (_) => FantasyLineupViewModel()),
        
        Provider(create: (_) => FantasyService()),
        
        ChangeNotifierProvider(
          create: (context) => FantasyAuthService(
            context.read<FantasyService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'FJF 2025',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme, 
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
          '/suspension-history': (ctx) => const SuspensionHistoryScreen(),
          '/player-comparison': (ctx) => const PlayerComparisonScreen(),
          '/report-bug': (ctx) => const ReportBugScreen(),
          '/admin-menu': (ctx) => const AdminMenuScreen(),
          '/photo-sales': (ctx) => const PhotoSalesScreen(),
          '/fantasy-home': (ctx) => const FantasyHomeScreen(),
          '/fantasy-market': (ctx) => const FantasyMarketScreen(),
          '/fantasy-lineup': (ctx) => const FantasyLineupScreen(),
          '/fantasy-rankings': (ctx) => const FantasyRankingScreen(),
          '/fantasy-admin': (ctx) => const FantasyAdminControlScreen(),
          '/fantasy-rules': (ctx) => const FantasyRulesScreen(),
          '/fantasy-history': (ctx) => const FantasyHistoryScreen(),
          '/about-history': (ctx) => const AboutHistoryScreen(),
          '/about-board': (ctx) => const AboutBoardScreen(),
          '/season-summary': (ctx) => const SeasonSummaryScreen(),
        },
        // ---> NAVEGAÇÃO DINÂMICA DA VOTAÇÃO AQUI <---
        onGenerateRoute: (settings) {
          if (settings.name == '/voting') {
            final pollArgs = settings.arguments as Poll;
            return MaterialPageRoute(
              builder: (context) => VotingScreen(poll: pollArgs),
            );
          }
          return null; 
        },
        // ---------------------------------------------
      ),
    );
  }
}