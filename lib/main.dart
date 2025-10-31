// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fjf_app/firebase_options.dart'; 
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


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

   // --- 2. HABILITAR PERSISTÊNCIA OFFLINE ---
  try {
    // Tenta habilitar o cache de dados offline do Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    debugPrint("Persistência offline do Firestore habilitada.");
  } catch (e) {
    debugPrint("Erro ao habilitar persistência offline: $e");
    // Isso geralmente falha em modos de navegação privada ou se
    // várias abas estiverem abertas. O app continuará online.
  }
  // --- FIM DA ADIÇÃO ---

  await AdminService.loadDisciplinaryRules();
  await AdminService.loadTiebreakerRules();
  await AdminService.loadPlayoffRules();
  await AdminService.loadDefaultRound();
  await NotificationService().init();

  runApp(const MyApp());
}

// --- 2. CLASSE DO OBSERVADOR DO ANALYTICS ---
// Esta classe escuta a navegação e envia eventos de 'screen_view'
class FjfAnalyticsObserver extends NavigatorObserver {
  final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  // Função auxiliar para logar a tela
  void _logScreenView(Route<dynamic> route) {
    final String? screenName = route.settings.name;
    // Só loga se o nome não for nulo (evita logar rotas internas do Flutter)
    if (screenName != null && screenName.startsWith('/')) {
      debugPrint('[Analytics] Logando tela: $screenName');
      analytics.logScreenView(screenName: screenName);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logScreenView(route); // Loga a tela que foi "empurrada" (ex: /report-bug)
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      _logScreenView(previousRoute); // Loga a tela para a qual "voltamos"
    }
  }

  // --- ESTA É A FUNÇÃO QUE FALTAVA ---
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _logScreenView(newRoute); // Loga a tela que "substituiu" (ex: /fixtures)
    }
  }
  // --- FIM DA ADIÇÃO ---
}
// --- FIM DO OBSERVADOR ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FJF App',
      theme: ThemeData(
        // --- CORES DO TEMA ---
        primaryColor: const Color(0xFFC25F22), // Laranja/Terracota da logo (aproximado)
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color(0xFF333333), // Um cinza escuro/preto para acentuação
          primary: const Color(0xFFC25F22), // Definindo primary color no ColorScheme
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F0F0), // Um cinza bem claro para o fundo das telas
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFC25F22), // Mesma cor principal para a AppBar
          foregroundColor: Colors.white, // Texto da AppBar branco
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFC25F22), // Cor principal para o Drawer também
        ),
        // --- FIM DAS CORES DO TEMA ---
        useMaterial3: true,
      ),
      //home: const SplashScreen(),


// --- 2. ADICIONAR DELEGATES E LOCALES ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate, // Para widgets Material
        GlobalWidgetsLocalizations.delegate,  // Para direção do texto, etc.
        GlobalCupertinoLocalizations.delegate, // Para widgets Cupertino (iOS style)
      ],
      supportedLocales: const [
        Locale('pt', 'BR'), // Português (Brasil)
        // Locale('en', ''), // Adicione outros idiomas se precisar
      ],
      // Define o locale padrão (opcional, mas bom ter)
      locale: const Locale('pt', 'BR'),
      
      // --- FIM DAS ADIÇÕES ---

      // --- 3. ATUALIZAÇÃO DO MATERIALAPP ---
      
      // Remove 'home' e usa 'initialRoute'
      // home: const SplashScreen(), 
      initialRoute: '/', // Define a rota inicial

      // Adiciona o observador do Analytics
      navigatorObservers: [
        FjfAnalyticsObserver(),
      ],

      // Define as rotas nomeadas
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
      },
      // --- FIM DA ATUALIZAÇÃO ---

    );
  }
}