// lib/services/admin_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert'; // Para utf8
import '../screens/admin_menu_screen.dart'; // <-- Tela que vamos criar

class AdminService {
  static bool isAdmin = false;
  static String? loggedInAdminUsername; //Guarda o ID/username do admin logado


  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- REGRAS DISCIPLINARES (com valores padrão) ---
  static int pendingYellowCards = 2; // Padrão: Pendurado com 2
  static int suspensionYellowCards = 3; // Padrão: Suspenso com 3
  static bool suspensionOnRed = true; // Padrão: Vermelho suspende
  static bool resetYellowsOnSuspension = true; // Zerar amarelos ao ser suspenso por amarelos
  static bool resetYellowsOnRed = false;        // Zerar amarelos ao receber cartão vermelho direto
  static bool resetYellowsOnRedWhilePending = false; // Se levar vermelho estando pendurado, zera os amarelos
  // --- FIM REGRAS ---

  // --- REGRAS DE DESEMPATE PLAYOFF (com padrões) ---
  static String semifinalTiebreaker = 'extra_time_penalties'; // Padrão
  static String thirdPlaceTiebreaker = 'penalties';         // Padrão
  static String finalTiebreaker = 'extra_time_penalties';      // Padrão
  // Possíveis valores: 'penalties', 'extra_time_penalties', 'extra_time_standing'
  // --- FIM REGRAS PLAYOFF ---

  // --- ORDEM DOS CRITÉRIOS DE DESEMPATE (com padrão) ---
  static List<String> tiebreakerOrder = [
    "head_to_head",
    "disciplinary_points",
    "wins",
    "goal_difference",
    "goals_against",
    "draw_sort"
  ];
  // --- FIM ORDEM ---

  // --- NOVA FUNÇÃO PARA CARREGAR REGRAS ---
  static Future<void> loadDisciplinaryRules() async {
    try {
      final docSnap = await FirebaseFirestore.instance // Usa instância estática aqui
          .collection('config')
          .doc('disciplinary_rules')
          .get();

      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null) {
          pendingYellowCards = data['pending_yellow_cards'] ?? pendingYellowCards; // Usa padrão se nulo
          suspensionYellowCards = data['suspension_yellow_cards'] ?? suspensionYellowCards;
          suspensionOnRed = data['suspension_on_red'] ?? suspensionOnRed;
          resetYellowsOnSuspension = data['reset_yellows_on_suspension'] ?? resetYellowsOnSuspension;
          resetYellowsOnRed = data['reset_yellows_on_red'] ?? resetYellowsOnRed;
          resetYellowsOnRedWhilePending = data['reset_yellows_on_red_while_pending'] ?? resetYellowsOnRedWhilePending;
          debugPrint("Regras carregadas: Pend:$pendingYellowCards, SuspCA:$suspensionYellowCards, SuspCV:$suspensionOnRed, ResetSusp:$resetYellowsOnSuspension, ResetRed:$resetYellowsOnRed, ResetRedPend:$resetYellowsOnRedWhilePending");
        }
      } else {
        debugPrint("Documento 'disciplinary_rules' não encontrado. Usando regras padrão.");
      }
    } catch (e) {
      debugPrint("Erro ao carregar regras disciplinares: $e. Usando regras padrão.");
      // Mantém os valores padrão definidos acima
    }
  }
  // --- FIM CARREGAR REGRAS ---

  // --- NOVA FUNÇÃO PARA CARREGAR ORDEM DE DESEMPATE ---
  static Future<void> loadTiebreakerRules() async {
     try {
      final docSnap = await FirebaseFirestore.instance
          .collection('config')
          .doc('tiebreaker_rules')
          .get();

      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null && data['tiebreaker_order'] is List) {
           // Converte List<dynamic> para List<String>
           final loadedOrder = List<String>.from(data['tiebreaker_order']);
           // Validação básica (opcional): Verifica se contém chaves esperadas
           if (loadedOrder.isNotEmpty) { // Poderia validar mais a fundo
              tiebreakerOrder = loadedOrder;
              debugPrint("Ordem de desempate carregada: $tiebreakerOrder");
           } else {
              debugPrint("Ordem de desempate no Firestore está vazia. Usando padrão.");
           }
        }
      } else {
        debugPrint("Documento 'tiebreaker_rules' não encontrado. Usando ordem padrão.");
      }
    } catch (e) {
      debugPrint("Erro ao carregar ordem de desempate: $e. Usando ordem padrão.");
      // Mantém a ordem padrão definida acima
    }
  }
  // --- FIM CARREGAR ORDEM ---

  // --- NOVA FUNÇÃO PARA CARREGAR REGRAS PLAYOFF ---
  static Future<void> loadPlayoffRules() async {
     try {
      final docSnap = await FirebaseFirestore.instance
          .collection('config')
          .doc('playoff_rules')
          .get();

      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null) {
          semifinalTiebreaker = data['semifinal_tiebreaker'] ?? semifinalTiebreaker;
          thirdPlaceTiebreaker = data['third_place_tiebreaker'] ?? thirdPlaceTiebreaker;
          finalTiebreaker = data['final_tiebreaker'] ?? finalTiebreaker;
          debugPrint("Regras Playoff carregadas: Semi=$semifinalTiebreaker, 3rd=$thirdPlaceTiebreaker, Final=$finalTiebreaker");
        }
      } else {
        debugPrint("Documento 'playoff_rules' não encontrado. Usando regras padrão.");
      }
    } catch (e) {
      debugPrint("Erro ao carregar regras playoff: $e. Usando regras padrão.");
    }
  }
  // --- FIM CARREGAR REGRAS PLAYOFF ---


  // Função para hashear (pode ser estática ou não)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // --- FUNÇÃO DE LOGIN ATUALIZADA (promptAdminPassword) ---
  Future<void> promptAdminPassword(BuildContext context) async {
    // Se já for admin, vai direto para o menu
    if (isAdmin) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (ctx) => const AdminMenuScreen()),
      );
      return;
    }

    // Controladores para os DOIS campos
    final TextEditingController usernameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    bool isLoading = false;

    // Retorna o resultado do showDialog para saber se o login foi bem-sucedido
    bool? loggedIn = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Acesso Admin'),
              content: Column( // Usa Column para dois campos
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Usuário'),
                    enabled: !isLoading,
                    textCapitalization: TextCapitalization.none, // Evita maiúsculas
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    enabled: !isLoading,
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(false),
                ),
                TextButton(
                  child: isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Entrar'),
                  onPressed: isLoading ? null : () async {
                    final String username = usernameController.text.trim().toLowerCase(); // Força minúsculo
                    final String password = passwordController.text;
                    if (username.isEmpty || password.isEmpty) {
                       ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Preencha usuário e senha.')));
                       return;
                    }
                    
                    setDialogState(() { isLoading = true; });
                    try {
                      // 1. Busca o documento do usuário
                      final docRef = _firestore.collection('admin_users').doc(username);
                      final docSnap = await docRef.get();

                      if (!docSnap.exists) {
                         throw Exception('Usuário Admin não encontrado.');
                      }
                      
                      // 2. Calcula o hash da senha digitada
                      final enteredHash = _hashPassword(password);
                      
                      // 3. Compara com o hash armazenado
                      final storedHash = docSnap.data()?['password_hash'];
                      if (storedHash == null) {
                         throw Exception('Erro de configuração no usuário admin.');
                      }

                      if (enteredHash == storedHash) {
                        // SUCESSO
                        isAdmin = true; // Seta estado global
                        loggedInAdminUsername = username; // Salva quem logou
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
    // Navega se o login foi bem-sucedido
    if (loggedIn == true && (context as Element).mounted) {
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
    loggedInAdminUsername = null; // Limpa o usuário
  }
}