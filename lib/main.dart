// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 
import 'screens/home_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

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
      home: const HomeScreen(),
    );
  }
}