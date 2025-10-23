// lib/services/admin_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert'; // Para utf8
import '../screens/admin_menu_screen.dart'; // <-- Tela que vamos criar

class AdminService {
  static bool isAdmin = false; // Estado global de login
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância do Firestore

  // Função para hashear (pode ser estática ou não)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // --- NOVA FUNÇÃO PARA EXIBIR DIÁLOGO DE SENHA ---
  Future<void> promptAdminPassword(BuildContext context) async {
    // Se já for admin, vai direto para o menu
    if (isAdmin) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (ctx) => const AdminMenuScreen()),
      );
      return;
    }

    // Lógica do diálogo (similar à que estava na FixturesScreen)
    final TextEditingController passwordController = TextEditingController();
    bool isLoading = false;

    // Retorna o resultado do showDialog para saber se o login foi bem-sucedido
    bool? loggedIn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) { // Usa dialogContext
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Acesso Admin'),
              content: TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
                enabled: !isLoading,
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(false), // Retorna false
                ),
                TextButton(
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                  onPressed: isLoading ? null : () async {
                    final enteredPassword = passwordController.text;
                    if (enteredPassword.isEmpty) {
                       ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Digite a senha.')));
                       return;
                    }
                    setDialogState(() { isLoading = true; });
                    try {
                      final enteredHash = _hashPassword(enteredPassword);
                      final docRef = _firestore.collection('config').doc('admin_credentials');
                      final docSnap = await docRef.get();
                      if (!docSnap.exists || !docSnap.data()!.containsKey('password_hash')) {
                         throw Exception('Configuração de senha não encontrada.');
                      }
                      final storedHash = docSnap.get('password_hash');

                      if (enteredHash == storedHash) {
                        isAdmin = true; // Seta o estado global
                        Navigator.of(dialogContext).pop(true); // Retorna true
                      } else {
                        throw Exception('Senha incorreta.');
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')),
                      );
                      setDialogState(() { isLoading = false; }); // Permite tentar de novo
                    }
                    // Não precisa do finally aqui, pois o pop(true) já fecha
                  },
                ),
              ],
            );
          }
        );
      },
    );

    // --- Se o login foi bem-sucedido (pop retornou true), navega ---
    if (loggedIn == true && Navigator.of(context).canPop()) { // Verifica contexto novamente
        Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => const AdminMenuScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modo Admin ativado!')),
        );
    }
  }

  // --- FUNÇÃO DE LOGOUT ---
  static void logoutAdmin() {
    isAdmin = false;
    // Poderia adicionar notificação aqui se necessário
  }
}