import 'dart:async';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- NOVO: Necessário para a StatusBar
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:provider/provider.dart';
import 'services/portal_service.dart';
import 'services/portal_auth_service.dart';
import 'screens/portal/portal_login_screen.dart';
import 'screens/portal/portal_dashboard_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart'; 
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; 
import 'package:firebase_analytics/firebase_analytics.dart';     

// Configurações
import 'firebase_options.dart'; 
import 'firebase_options_test.dart'; 
import 'screens/bolao/bolao_paywall_screen.dart';
import 'screens/fantasy/fantasy_admin_control_screen.dart';
import 'screens/fantasy/fantasy_history_screen.dart';
import 'screens/fantasy/fantasy_ranking_screen.dart';
import 'screens/fantasy/fantasy_scouts_screen.dart';
import 'screens/fantasy/fantasy_knockout_bracket_screen.dart';
import 'models/fantasy_league_model.dart';
import 'screens/fantasy/fantasy_rules_screen.dart';
import 'screens/player/free_agent_registration_screen.dart';
import 'screens/player/free_agents_market_screen.dart';
import 'screens/championship/teams_list_screen.dart';
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
import 'viewmodels/fantasy_league_viewmodel.dart';
import 'viewmodels/sponsor_viewmodel.dart';
import 'viewmodels/news_viewmodel.dart';
import 'viewmodels/suspension_viewmodel.dart';
import 'viewmodels/photo_banner_viewmodel.dart';

// Repositories
import 'repositories/fantasy_repository.dart';

// Screens
import 'screens/home/home_dashboard_screen.dart';
import 'screens/championship/fixtures_screen.dart';
import 'screens/championship/standings_screen.dart';
import 'screens/championship/team_stats_screen.dart';
import 'screens/player/player_stats_screen.dart';
import 'screens/player/suspension_history_screen.dart';
import 'screens/player/player_comparison_screen.dart';
import 'screens/institutional/report_bug_screen.dart';
import 'screens/admin/admin_menu_screen.dart';
import 'screens/institutional/photo_sales_screen.dart';
import 'screens/fantasy/fantasy_home_screen.dart';
import 'screens/fantasy/fantasy_market_screen.dart';
import 'screens/fantasy/fantasy_lineup_screen.dart';
import 'screens/fantasy/fantasy_ranking_screen.dart';
import 'screens/fantasy/fantasy_admin_control_screen.dart';
import 'screens/fantasy/fantasy_rules_screen.dart';
import 'screens/fantasy/fantasy_history_screen.dart';
import 'screens/institutional/about_history_screen.dart';
import 'screens/institutional/about_board_screen.dart';
import 'screens/championship/season_summary_screen.dart';
import 'screens/fantasy/fantasy_leagues_screen.dart';

// ---> IMPORTS DO SISTEMA DE VOTAÇÃO <---
import 'screens/institutional/voting_screen.dart';
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

    // 🚨 NOVO: Força a barra de status do celular a ficar transparente com ícones claros
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // Deixa o gradiente da AppBar aparecer
      statusBarIconBrightness: Brightness.light, // Ícones brancos (hora/bateria)
    ));

    const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');
    FirebaseOptions firebaseOptions = (environment == 'test')
        ? TestFirebaseOptions.currentPlatform
        : DefaultFirebaseOptions.currentPlatform;

    if (environment == 'test') debugPrint("⚠️ AMBIENTE DE TESTE ⚠️");

    await Firebase.initializeApp(options: firebaseOptions);

    PlatformDispatcher.instance.onError = (error, stack) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
      return true;
    };

    FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider('6LfdwM4sAAAAACPNPfvuk5uW_c2FVt93yr1jQ1NH'),
      androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
      appleProvider: AppleProvider.deviceCheck,
    );
    
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false, 
      );
    }
    
    const bool enablePersistence = !kIsWeb || kReleaseMode;

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: enablePersistence, 
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    if (kIsWeb && !kReleaseMode) {
      debugPrint("⚠️ Web Debug: Persistência do Firestore DESATIVADA para evitar conflitos.");
    }

    NotificationService().init();
    initializeDateFormatting('pt_BR', null);

    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('failed-precondition')) {
         _logFirestoreIndexError(details.exception);
      }
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
      FlutterError.presentError(details); 
    };

    runApp(const FjfApp());
  
  }, (error, stack) {
    _logFirestoreIndexError(error);
    debugPrint("Erro assíncrono: $error");
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

class FjfApp extends StatelessWidget {
  const FjfApp({super.key});

  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context) {
    const bool isTestEnv = String.fromEnvironment('ENV') == 'test';

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChampionshipService()),
        ChangeNotifierProvider(create: (_) => SponsorViewModel()),
        ChangeNotifierProvider(create: (_) => NewsViewModel()), 
        ChangeNotifierProvider(create: (_) => PhotoBannerViewModel()),

        Provider<FantasyRepository>(create: (_) => FantasyRepository()),

        Provider(create: (_) => TeamService()),
        Provider(create: (_) => PlayerService()),
        Provider(create: (_) => MatchService()),
        Provider(create: (_) => MediaService()),
        Provider(create: (_) => DisciplinaryService()),
        Provider(create: (_) => AwardService()),

        
        Provider(create: (_) => FantasyService()),
        Provider(create: (_) => PortalService()),
        ChangeNotifierProvider(create: (_) => PortalAuthService()),
        
        ChangeNotifierProvider(
          create: (context) => FantasyAuthService(
            context.read<FantasyService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'FJF App - Força Jovem Fumacense',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme, 
        
        navigatorObservers: [
          FirebaseAnalyticsObserver(analytics: analytics),
        ],

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
          '/portal': (ctx) => Consumer<PortalAuthService>(
                builder: (context, auth, _) => auth.isAuthenticated
                    ? const PortalDashboardScreen()
                    : const PortalLoginScreen(),
              ),
          '/team-stats': (ctx) => const TeamStatsScreen(),
          '/player-stats': (ctx) => const PlayerStatsScreen(),
          '/suspension-history': (ctx) => ChangeNotifierProvider(
            create: (_) => SuspensionViewModel(),
            child: const SuspensionHistoryScreen(),
          ),
          '/player-comparison': (ctx) => const PlayerComparisonScreen(),
          '/report-bug': (ctx) => const ReportBugScreen(),
          '/admin-menu': (ctx) => const AdminMenuScreen(),
          '/photo-sales': (ctx) => ChangeNotifierProvider(
            create: (_) => PhotoSalesViewModel(),
            child: const PhotoSalesScreen(),
          ),
          '/fantasy-home': (ctx) => ChangeNotifierProvider(
            create: (_) => FantasyHomeViewModel(),
            child: const FantasyHomeScreen(),
          ),
          '/fantasy-market': (ctx) => const FantasyMarketScreen(),
          '/fantasy-lineup': (ctx) => ChangeNotifierProvider(
            create: (_) => FantasyLineupViewModel(),
            child: const FantasyLineupScreen(),
          ),
          '/fantasy-rankings': (ctx) => const FantasyRankingScreen(),
          '/fantasy-admin': (ctx) => const FantasyAdminControlScreen(),
          '/fantasy-rules': (ctx) => const FantasyRulesScreen(),
          '/fantasy-history': (ctx) => const FantasyHistoryScreen(),
          '/fantasy-scouts': (ctx) => const FantasyScoutsScreen(),
          '/fantasy-knockout': (ctx) {
            final args = ModalRoute.of(ctx)!.settings.arguments as FantasyLeague;
            return FantasyKnockoutBracketScreen(league: args);
          },
          '/about-history': (ctx) => const AboutHistoryScreen(),
          '/about-board': (ctx) => const AboutBoardScreen(),
          '/fantasy-leagues': (ctx) => ChangeNotifierProvider(
            create: (_) => FantasyLeagueViewModel(),
            child: const FantasyLeaguesScreen(),
          ),
          '/free-agents-registration': (ctx) => const FreeAgentRegistrationScreen(),
          '/free-agents-market': (ctx) => const FreeAgentsMarketScreen(),
          '/wordcup-pool': (ctx) => const BolaoPaywallScreen(),
        },
        onGenerateRoute: (settings) {
          WidgetBuilder? builder;
          switch (settings.name) {
            case '/': builder = (ctx) => const HomeDashboardScreen(); break;
            case '/fixtures': builder = (ctx) => const FixturesScreen(); break;
            case '/standings': builder = (ctx) => const StandingsScreen(); break;
            case '/season-summary': builder = (ctx) => const SeasonSummaryScreen(); break;
            case '/teams': builder = (ctx) => const TeamsListScreen(); break;
          }

          if (builder != null) {
            return PageRouteBuilder(
              settings: settings,
              pageBuilder: (context, animation, secondaryAnimation) => builder!(context),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
              transitionDuration: const Duration(milliseconds: 250),
            );
          }

          if (settings.name == '/voting') {
            final pollArgs = settings.arguments as Poll;
            return MaterialPageRoute(
              builder: (context) => VotingScreen(poll: pollArgs),
            );
          }
          return null; 
        },
      ),
    );
  }
}
