import 'dart:async'; // Import necessário para runZonedGuarded
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart'; // Para inicializar datas em pt_BR

// Configurações do Firebase (Geradas pelo FlutterFire)
import 'firebase_options.dart'; 
import 'firebase_options_test.dart'; 

// Services
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/admin_service.dart';
import 'services/championship_service.dart';
import 'services/firestore_service.dart'; // Para acessar constantes se necessário

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
// import 'screens/manage_seasons_screen.dart'; // Acessada via AdminMenu

// --- FUNÇÃO AUXILIAR PARA DETECTAR ERRO DE ÍNDICE ---
void _logFirestoreIndexError(Object error) {
  final e = error.toString();
  if (e.contains('failed-precondition') || e.contains('requires an index')) {
    debugPrint('\n🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥');
    debugPrint('🔥 FALTA DE ÍNDICE DETECTADA NO FIRESTORE! 🔥');
    debugPrint('👉 CLIQUE NESTE LINK PARA CRIAR AUTOMATICAMENTE:');
    
    // Tenta extrair o link da mensagem de erro
    final linkRegex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
    final match = linkRegex.firstMatch(e);
    if (match != null) {
       debugPrint(match.group(0));
    } else {
       debugPrint(e); // Se não achar o link limpo, imprime tudo
    }
    
    debugPrint('🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥\n');
  }
}

void main() async {
  // Envolvemos tudo no runZonedGuarded para capturar erros de Streams (Assíncronos)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Configuração de Ambiente
    const String environment = String.fromEnvironment('ENV', defaultValue: 'prod');
    FirebaseOptions firebaseOptions;

    if (environment == 'test') {
      debugPrint("⚠️ INICIANDO EM AMBIENTE DE TESTE (fjfapp-test) ⚠️");
      firebaseOptions = TestFirebaseOptions.currentPlatform;
    } else {
      debugPrint("✅ INICIANDO EM AMBIENTE DE PRODUÇÃO");
      firebaseOptions = DefaultFirebaseOptions.currentPlatform;
    }

    // 2. Inicializa Firebase
    await Firebase.initializeApp(options: firebaseOptions);

    // 3. Inicializa Serviços Auxiliares
    await NotificationService().init();
    
    // Inicializa formatação de data para Português
    await initializeDateFormatting('pt_BR', null);

    // Carrega regras iniciais (opcional, pois o ChampionshipService faz isso, mas mal não faz)
    // await AdminService.loadAllRules(FirestoreService.LEGACY_ID); 

    // 4. Intercepta erros síncronos do Flutter
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('failed-precondition')) {
         _logFirestoreIndexError(details.exception);
      }
      // Chama o handler padrão para mostrar o erro na tela (em debug) ou logar
      FlutterError.presentError(details); 
    };

    runApp(const FjfApp());
  
  }, (error, stack) {
    // 5. Intercepta erros assíncronos (Streams, Futures soltos)
    _logFirestoreIndexError(error);
    debugPrint("Erro assíncrono capturado no Zone: $error");
  });
}

class FjfApp extends StatelessWidget {
  const FjfApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Verifica ambiente novamente para exibir o Banner
    const bool isTestEnv = String.fromEnvironment('ENV') == 'test';

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChampionshipService()),
      ],
      child: MaterialApp(
        title: 'FJF 2025',
        debugShowCheckedModeBanner: false,
        
        // Configura Banner de Teste se necessário
        builder: (context, child) {
          if (isTestEnv) {
            return Banner(
              message: "TESTE",
              location: BannerLocation.topStart,
              color: Colors.red,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1),
              child: child!,
            );
          }
          return child!;
        },

        // Internacionalização
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
        
        // Tema
        theme: ThemeData(
          primaryColor: const Color(0xFFC25F22),
          colorScheme: ColorScheme.fromSwatch().copyWith(
            primary: const Color(0xFFC25F22),
            secondary: Colors.black,
          ),
          scaffoldBackgroundColor: Colors.grey[50], // Fundo levemente cinza é mais moderno
          fontFamily: 'Roboto', 
          useMaterial3: false, // Mantém estilo clássico por enquanto para não quebrar layout
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFC25F22),
            foregroundColor: Colors.white,
            centerTitle: true,
            elevation: 0,
          ),
        ),

        // Rotas
        initialRoute: '/', // Rota inicial padrão
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
        },
      ),
    );
  }
}