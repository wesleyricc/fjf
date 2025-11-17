// lib/services/admin_service.dart
//import 'package:fjf_app/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert'; // Para utf8
// (O import do admin_menu_screen.dart não é necessário aqui)

class AdminService {
  static bool isAdmin = false;
  static String? loggedInAdminUsername;
  
  // --- INÍCIO DA ALTERAÇÃO ---
  // Substituído 'defaultRound'
  static String defaultPhase = 'first'; // 'first' ou 'second'
  static String defaultStage = '1';     // '1'-'7' ou 'semifinal', 'third_place', 'final_game'
  // --- FIM DA ALTERAÇÃO ---

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- REGRAS DISCIPLINARES (com valores padrão) ---
  static int pendingYellowCards = 2;
  static int suspensionYellowCards = 3;
  static bool suspensionOnRed = true;
  static bool resetYellowsOnSuspension = true;
  static bool resetYellowsOnRed = false;
  // --- FIM REGRAS ---

  // --- REGRAS DE DESEMPATE PLAYOFF (com padrões) ---
  static String semifinalTiebreaker = 'extra_time_penalties';
  static String thirdPlaceTiebreaker = 'penalties';
  static String finalTiebreaker = 'extra_time_penalties';
  // --- FIM REGRAS ---
  
  // --- ORDEM DE DESEMPATE 1ª FASE ---
  static List<String> tiebreakerOrder = [
    'head_to_head',
    'disciplinary_points',
    'wins',
    'goal_difference',
    'goals_against',
    'draw_sort',
  ];
  // --- FIM ORDEM ---

  // --- Função para carregar configurações do App ---
  static Future<void> loadAppSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('app_settings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        
        // --- INÍCIO DAALTERAÇÃO ---
        // Lê os novos campos (com fallbacks para o campo antigo, se existir)
        defaultPhase = data.containsKey('default_phase') 
                        ? data['default_phase'] 
                        : 'first';
                        
        defaultStage = data.containsKey('default_stage') 
                        ? data['default_stage']
                        : (data.containsKey('default_fixtures_round') // Fallback
                            ? data['default_fixtures_round'].toString()
                            : '1');
        
        // Converte o 'defaultRound' antigo para o novo formato, se necessário
        if (data.containsKey('default_fixtures_round') && !data.containsKey('default_phase')) {
          defaultPhase = 'first';
          defaultStage = data['default_fixtures_round'].toString();
        }
        
        debugPrint("AdminService: Visualização Padrão carregada: $defaultPhase / $defaultStage");
        // --- FIM DA ALTERAÇÃO ---
        
        // (O resto da função, ex: live_video_id, permanece igual)
        
      }
    } catch (e) {
      debugPrint("Erro ao carregar app_settings: $e");
    }
  }

  // --- Função para carregar regras disciplinares ---
  static Future<void> loadDisciplinaryRules() async {
     try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('disciplinary_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        pendingYellowCards = data['pendingYellowCards'] ?? 2;
        suspensionYellowCards = data['suspensionYellowCards'] ?? 3;
        suspensionOnRed = data['suspensionOnRed'] ?? true;
        resetYellowsOnSuspension = data['resetYellowsOnSuspension'] ?? true;
        resetYellowsOnRed = data['resetYellowsOnRed'] ?? false;
      }
    } catch (e) {
      debugPrint("Erro ao carregar disciplinary_rules: $e");
    }
  }

  // --- Função para carregar regras de desempate (Playoff) ---
  static Future<void> loadPlayoffRules() async {
     try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('playoff_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        semifinalTiebreaker = data['semifinal'] ?? 'extra_time_penalties';
        thirdPlaceTiebreaker = data['third_place'] ?? 'penalties';
        finalTiebreaker = data['final'] ?? 'extra_time_penalties';
      }
    } catch (e) {
      debugPrint("Erro ao carregar playoff_rules: $e");
    }
  }
  
  // --- Função para carregar ordem de desempate (1ª Fase) ---
  static Future<void> loadTiebreakerOrder() async {
     try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('tiebreaker_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Converte List<dynamic> para List<String>
        tiebreakerOrder = List<String>.from(data['order'] ?? tiebreakerOrder);
      }
    } catch (e) {
      debugPrint("Erro ao carregar tiebreaker_rules: $e");
    }
  }

  // --- Função de Hash (Sem alteração) ---
  String _hashPassword(String password) {
    final bytes = utf8.encode(password); 
    final digest = sha256.convert(bytes); 
    return digest.toString();
  }
  
  // --- Função de Login (Sem alteração) ---
  Future<bool> promptAdminPassword(BuildContext context) async {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController usernameController = TextEditingController();
    bool isLoading = false;

    // 'loggedIn' irá capturar o 'true' ou 'false' do pop do diálogo
    final bool? loggedIn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Acesso Administrativo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Usuário'),
                      enabled: !isLoading,
                    ),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Senha'),
                      enabled: !isLoading,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(false),
                ),
                TextButton(
                  child: isLoading ? const CircularProgressIndicator() : const Text('Entrar'),
                  onPressed: isLoading ? null : () async {
                    final username = usernameController.text.trim();
                    final password = passwordController.text;
                    if (username.isEmpty || password.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Usuário e senha são obrigatórios.')));
                      return;
                    }

                    setDialogState(() { isLoading = true; });

                    try {
                      final enteredHash = _hashPassword(password);
                      final docRef = _firestore.collection('admin_users').doc(username);
                      final docSnap = await docRef.get();

                      if (!docSnap.exists) {
                        throw Exception('Usuário Admin não encontrado.');
                      }

                      final storedHash = docSnap.data()?['password_hash'];
                      
                      if (enteredHash == storedHash) {
                        // Define as variáveis ESTÁTICAS globais
                        AdminService.isAdmin = true;
                        AdminService.loggedInAdminUsername = username; 
                        
                        Navigator.of(dialogContext).pop(true); // Retorna true
                      } else {
                        throw Exception('Senha incorreta.');
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')),
                      );
                      setDialogState(() { isLoading = false; });
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );

    return loggedIn ?? false;
  }

  static void logoutAdmin() {
    isAdmin = false;
    loggedInAdminUsername = null;
  }
}