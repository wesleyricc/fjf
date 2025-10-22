// lib/screens/home_screen.dart
// (Por simplicidade, vamos apenas redirecionar para a tela de jogos)
import 'package:flutter/material.dart';
import 'fixtures_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // A HomeScreen agora será a tela de Jogos
    return FixturesScreen();
  }
}