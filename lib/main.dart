import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void main() {
  runApp(const FjfLegacyApp());
}

class FjfLegacyApp extends StatelessWidget {
  const FjfLegacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FJF App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFC25F22),
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const RedirectScreen(),
    );
  }
}

class RedirectScreen extends StatelessWidget {
  const RedirectScreen({super.key});

  void _redirectToNewApp() {
    // Força o redirecionamento direto no navegador/PWA
    html.window.location.href = 'https://acefjf.web.app';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ícone de destaque
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC25F22).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded, 
                    size: 80, 
                    color: Color(0xFFC25F22),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Título Chamativo
                const Text(
                  "O APP DA FJF\nESTÁ DE CASA NOVA!",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFC25F22),
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                
                // Texto Explicativo focado na curiosidade
                const Text(
                  "Preparamos uma versão completamente nova, muito mais rápida e recheada de novidades incríveis que vão transformar a sua experiência!\n\n"
                  "Para não ficar de fora, desinstale este aplicativo antigo e clique no botão abaixo para mergulhar no novo portal.",
                  style: TextStyle(
                    fontSize: 16, 
                    color: Colors.black87, 
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                
                // Botão de Redirecionamento (Call to Action mais atrativa)
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: _redirectToNewApp,
                    icon: const Icon(Icons.auto_awesome, color: Colors.white),
                    label: const Text(
                      "DESCOBRIR O NOVO APP",
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC25F22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                const Text(
                  "Novo link oficial:\nacefjf.web.app",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Colors.grey, 
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}