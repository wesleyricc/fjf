import 'package:flutter/material.dart';

class AppTheme {
  // Paleta de Cores Oficial da Seleção Brasileira (Tema Copa do Mundo)
  static const Color primaryColor = Color(0xFF00873E);      // Verde Bandeira Oficial
  static const Color secondaryColor = Color(0xFF002776);    // Azul Anil para Contrastes
  static const Color yellowColor = Color(0xFFFFDF00);       // Amarelo Canarinho para Destaques
  static const Color scaffoldBackground = Color(0xFFFAFAFA); // Cinza muito suave
  static const Color errorColor = Color(0xFFD32F2F);

  // Gradiente Global para Botões Especiais e Cards de Destaque
  // Pode ser acessado em qualquer tela chamando: AppTheme.brazilGradient
  static const LinearGradient brazilGradient = LinearGradient(
    colors: [
      Color(0xFF00873E), // Verde Bandeira
      Color(0xFFC5A814), // Ouro/Amarelo Canarinho
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: false, 
      primaryColor: primaryColor,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: 'Roboto',

      // --- Esquema de Cores ---
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: yellowColor,
        surface: Colors.white,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: secondaryColor,
      ),

      // --- AppBar ---
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // --- Botões Elevados ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // --- Botões de Texto/Outline ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      // --- Botão de Ação Flutuante (FAB) ---
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: yellowColor,
        foregroundColor: secondaryColor,
        elevation: 4,
      ),

      // --- Inputs (TextField) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: errorColor),
        ),
        labelStyle: TextStyle(color: Colors.grey.shade700),
        floatingLabelStyle: const TextStyle(color: primaryColor),
      ),

      // --- Ícones ---
      iconTheme: const IconThemeData(
        color: primaryColor,
        size: 24,
      ),

      // --- Divisores ---
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade300,
        thickness: 1,
        space: 1,
      ),
      
      // --- SnackBar ---
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: secondaryColor,
        contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
    );
  }
}