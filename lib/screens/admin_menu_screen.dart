// lib/screens/admin_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/data_uploader_service.dart';
import '../services/admin_service.dart';
import 'disciplinary_rules_screen.dart';
import 'tiebreaker_rules_screen.dart';
import '../services/firestore_service.dart';
import 'playoff_rules_screen.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({super.key});

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService(); // Instância do serviço

  bool _isSaving = false;
  // --- FUNÇÕES DE DIÁLOGO (MOVIDAS E ADAPTADAS) ---

  // Função para gerar o hash SHA-256 de uma string
  String _hashPassword(String password) {
    final bytes = utf8.encode(password); 
    final digest = sha256.convert(bytes); 
    return digest.toString();
  }

  // --- NOVA FUNÇÃO PARA CHAMAR A MIGRAÇÃO ---
  Future<void> _triggerMigrationV1() async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Executar Migração de Dados?'),
         content: const Text('Isso verificará TODOS os jogadores e adicionará os campos faltantes (como "is_staff" e "jersey_number").\n\nExecute isso APENAS UMA VEZ após uma atualização.\n\nDeseja continuar?'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar', style: TextStyle(color: Colors.orange))),
         ],
       ),
     );

     if (confirm == true && mounted) {
       setState(() { _isSaving = true; });
       final result = await _firestoreService.migratePlayersV1(); // Chama a nova função
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }
  }
  // --- FIM ---

  // --- NOVA FUNÇÃO PARA CHAMAR CÁLCULO DE RANKS ---
  Future<void> _triggerCalculateRanks() async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Calcular Ranks da 1ª Fase?'),
         content: const Text(
             'Isso ordenará todos os times com base nos resultados finais da 1ª Fase e salvará a posição (rank) em cada time. Execute APENAS após o fim da 1ª Fase.\n\nEste rank é usado para o desempate por "Melhor Classif." no mata-mata caso ocorra empate após a prorrogação.'
         ), // Texto explicativo
          actions: [
           TextButton(
             // Botão Cancelar: Fecha o diálogo retornando false
             onPressed: () => Navigator.of(ctx).pop(false),
             child: const Text('Cancelar'),
           ),
           TextButton(
             // Botão Confirmar: Fecha o diálogo retornando true
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text(
                 'Confirmar e Calcular', // Texto mais explícito
                 style: TextStyle(color: Colors.deepPurple) // Cor para destacar
             ),
           ),
         ],
       ),
     );

     if (confirm == true && mounted) {
       setState(() { _isSaving = true; }); // Reusa flag _isSaving
       final result = await _firestoreService.calculateAndStorePhase1Ranks(); // Chama a nova função
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }
  }
  // --- FIM ---

// Diálogo de confirmação para o upload
  Future<void> _showUploadConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        bool isLoading = false;
        // Usamos um StatefulBuilder para atualizar o estado do diálogo
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Carregar Dados Iniciais'),
              content: Text(
                isLoading
                    ? 'Carregando... Por favor, aguarde.'
                    : 'ATENÇÃO!\n\nIsso irá sobrescrever quaisquer times e jogadores com IDs correspondentes.\n\nUse apenas para a configuração inicial. Deseja continuar?',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                ),
                TextButton(
                    child: isLoading ? const CircularProgressIndicator() : const Text('Confirmar Carga', style: TextStyle(color: Colors.red)),
                    onPressed: isLoading ? null : () async {
                      setDialogState(() { isLoading = true; });
                      final uploader = DataUploaderService();
                      final String result = await uploader.uploadInitialData();
                      setDialogState(() { isLoading = false; });

                          if (mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 5)));
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  

  Future<void> _showChangeVideoIdDialog() async {
    final urlOrIdController = TextEditingController();
    bool isLoading = false;
    String currentVideoId = '';

    // Busca o ID atual para preencher o campo
    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      // Verifica se o doc e o campo existem antes de ler
      if (docSnap.exists && docSnap.data() != null && docSnap.data()!.containsKey('live_video_id')) {
        currentVideoId = docSnap.get('live_video_id') ?? '';
        urlOrIdController.text = currentVideoId;
      }
    } catch (e) {
       debugPrint("Erro ao buscar ID de vídeo atual: $e");
    }

    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: !isLoading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Alterar Vídeo/Live da Tela Inicial'),
              content: TextField(
                controller: urlOrIdController,
                decoration: const InputDecoration(
                  labelText: 'URL do YouTube ou ID do Vídeo',
                  hintText: 'Cole a URL completa ou apenas o ID',
                  border: OutlineInputBorder(),
                ),
                enabled: !isLoading,
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isLoading ? null : () async {
                    final String input = urlOrIdController.text.trim();

                    if (input.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('O campo não pode ser vazio.')));
                      return;
                    }

                    setDialogState(() { isLoading = true; });

                    String? extractedId;

                    try {
                      // Lógica de Extração (como antes)
                      extractedId = YoutubePlayerController.convertUrlToId(input);
                      debugPrint("Input: '$input', ID Extraído: '$extractedId'");

                      if (extractedId == null || extractedId.isEmpty) {
                         throw Exception('Não foi possível extrair um ID válido da URL fornecida.');
                      }

                      // --- ATUALIZAÇÃO: Salva o ID E o Timestamp ---
                      await _firestore.collection('config').doc('app_settings').set({ // Use .set com merge:true para criar/atualizar
                        'live_video_id': extractedId, // Salva o ID
                        'live_video_timestamp': FieldValue.serverTimestamp(), // Salva a hora atual
                      }, SetOptions(merge: true)); // 'merge: true' garante que outros campos (ex: regulation_pdf_url) não sejam apagados
                      // --- FIM DA ATUALIZAÇÃO ---

                      if (mounted) Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vídeo/Live atualizado! Válido por 24h.')));

                    } catch (e) {
                       if (mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')),
                          );
                       }
                    } finally {
                       if (Navigator.of(dialogContext).canPop()){
                         setDialogState(() { isLoading = false; });
                       }
                    }
                  },
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- NOVA FUNÇÃO: VERIFICAR SENHA ADMIN ---
  Future<bool> _verifyAdminPassword(BuildContext context) async {
    final String? currentAdminUsername = AdminService.loggedInAdminUsername;
    if (currentAdminUsername == null) {
       // Se não houver admin logado (bug?), cancela
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro: Admin não identificado. Tente relogar.')));
       return false;
    }
    
    final TextEditingController passwordController = TextEditingController();
    bool isLoading = false;

    final bool? passwordConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Confirmar Ação para usuário "$currentAdminUsername"'), // Mostra quem está confirmando
              content: TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Digite sua senha'),
                enabled: !isLoading,
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(false),
                ),
                TextButton(
                  child: isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Confirmar'),
                  onPressed: isLoading ? null : () async {
                    final enteredPassword = passwordController.text;
                    if (enteredPassword.isEmpty) {
                       ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Digite a senha.')));
                       return;
                    } 
                    setDialogState(() { isLoading = true; });
                    try {
                      final enteredHash = _hashPassword(enteredPassword);
                      // Busca o documento do admin LOGADO
                      final docRef = _firestore.collection('admin_users').doc(currentAdminUsername);
                      final docSnap = await docRef.get();
                      
                      if (!docSnap.exists) throw Exception('Usuário Admin não encontrado.');
                      
                      final storedHash = docSnap.data()?['password_hash'];
                      if (enteredHash == storedHash) {
                        Navigator.of(dialogContext).pop(true); // Sucesso
                      } else {
                        throw Exception('Senha incorreta.');
                      }
                    } catch (e) {
                       ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')));
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
    return passwordConfirmed ?? false;
  }
  Future<void> _showChangePasswordDialog() async {
    final String? currentAdminUsername = AdminService.loggedInAdminUsername;
    if (currentAdminUsername == null) return; // Segurança
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    // Mostra o diálogo
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Não fechar clicando fora
      builder: (dialogContext) { // Usar um contexto diferente para o diálogo
        return StatefulBuilder( // Permite atualizar o estado do diálogo (loading)
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Mudar Senha ($currentAdminUsername)'), // Mostra qual usuário
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: currentPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Senha Atual'), enabled: !isLoading),
                    const SizedBox(height: 10),
                    TextField(controller: newPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Nova Senha'), enabled: !isLoading),
                    const SizedBox(height: 10),
                    TextField(controller: confirmPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar Nova Senha'), enabled: !isLoading),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isLoading ? null : () async {
                    // Pega os valores dos campos
                    final currentPassword = currentPasswordController.text;
                    final newPassword = newPasswordController.text;
                    final confirmPassword = confirmPasswordController.text;

                    // --- Validações ---
                    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Preencha todos os campos.')));
                      return; // Impede o envio
                    }
                    if (newPassword != confirmPassword) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('As novas senhas não coincidem.')));
                      return;
                    }
                     if (newPassword.length < 6) { // Regra de força mínima
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('A nova senha deve ter pelo menos 6 caracteres.')));
                      return;
                    }
                    // --- Fim Validações ---

                    // Inicia o estado de carregamento
                    setDialogState(() { isLoading = true; });

                    try {
                      // 1. Verifica a senha atual
                      final currentHash = _hashPassword(currentPassword);
                      final docRef = _firestore.collection('admin_users').doc(currentAdminUsername);
                      final docSnap = await docRef.get();
                      final storedHash = docSnap.data()?['password_hash'];

                      if (currentHash != storedHash) {
                        throw Exception('Senha atual incorreta.');
                      }

                      // 2. Calcula o hash da nova senha
                      final newHash = _hashPassword(newPassword);

                      // 3. Atualiza o hash no Firestore
                      await docRef.update({'password_hash': newHash});

                      // Fecha o diálogo ANTES de mostrar o SnackBar de sucesso
                      if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();

                      // Mostra mensagem de sucesso (usando o context principal se o dialogContext não for mais válido)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada com sucesso!')));

                    } catch (e) {
                       if (Navigator.of(dialogContext).canPop()) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')));
                    } finally {
                       if (Navigator.of(dialogContext).canPop()) setDialogState(() { isLoading = false; });
                    }
                  },
                  // Exibe o indicador de carregamento ou o texto do botão
                  child: isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Alterar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Future<void> _triggerGenerateSemifinals() async {
     // Diálogo de confirmação extra
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Gerar Semifinais?'),
         content: const Text('Isso buscará os 4 primeiros da classificação ATUAL e criará os jogos da semifinal. Tem certeza?\n(Verifique se a 1ª Fase realmente terminou).'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar', style: TextStyle(color: Colors.orange))),
         ],
       ),
     );

     if (confirm == true && mounted) {
       setState(() { _isSaving = true; }); // Reutiliza flag de saving
       final result = await _firestoreService.generateSemifinals();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
     }
  }
  // --- FIM ---

  // --- FUNÇÃO ATUALIZADA PARA CHAMAR generateFinals ---
  Future<void> _triggerGenerateFinals() async { // Nome mudou
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Gerar Final e 3º Lugar?'), // Texto mudou
         content: const Text('Isso buscará os VENCEDORES e PERDEDORES das semifinais FINALIZADAS e criará os jogos. Tem certeza?\n(Verifique se AMBAS as semifinais estão "Finalizadas" e SEM empates).'), // Texto mudou
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar', style: TextStyle(color: Colors.green))),
         ],
       ),
     );

     if (confirm == true && mounted) {
       setState(() { _isSaving = true; });
       final result = await _firestoreService.generateFinals(); // Chama a nova função
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }else if (mounted) {
        // Opcional: Mensagem se o usuário cancelou
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(content: Text('Cálculo de ranks cancelado.')),
        // );
     }
  }
  // --- FIM ---

  // --- 2. ADICIONE A NOVA FUNÇÃO DO DIÁLOGO ---
  Future<void> _showSetDefaultRoundDialog() async {
    // Controlado pré-preenchido com a rodada atual
    final roundController = TextEditingController(
      text: AdminService.defaultRound.toString(),
    );
    bool isDialogSaving = false; // Estado de loading local

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder( // Necessário para o loading
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Definir Rodada Padrão'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Informe a rodada que deve ser exibida ao abrir a "Tabela de Jogos". Isso afetará todos os usuários.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: roundController,
                    decoration: const InputDecoration(
                      labelText: 'Número da Rodada',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !isDialogSaving,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDialogSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isDialogSaving ? null : () async {
                    final int? newRound = int.tryParse(roundController.text);
                    // (Ajuste o limite de 7 se necessário)
                    if (newRound != null && newRound > 0 && newRound <= 7) { 
                      
                      setDialogState(() { isDialogSaving = true; });
                      
                      try {
                        // --- 1. Salva no Firestore ---
                        await _firestore.collection('config').doc('app_settings').set(
                          { 'default_fixtures_round': newRound },
                          SetOptions(merge: true) // merge:true NÃO apaga outros campos
                        );
                        
                        // --- 2. Salva no AdminService (para sessão atual) ---
                        AdminService.defaultRound = newRound; 
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Rodada padrão definida como $newRound.')),
                          );
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (e) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Erro ao salvar no Firestore: $e')),
                          );
                      } finally {
                          // Garante que o loading pare mesmo se 'mounted' for falso
                          // (embora o 'canPop' seja mais seguro)
                           setDialogState(() { isDialogSaving = false; });
                      }
                    } else {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Por favor, insira um número de rodada válido (1-7).')),
                      );
                    }
                  },
                  child: isDialogSaving 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Text('Salvar'),
                ),
              ],
            );
          }
        );
      },
    );
  }
  // --- FIM DA NOVA FUNÇÃO ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Administrativo')),
      // drawer: const AppDrawer(), // Opcional: manter o drawer aqui?
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.live_tv),
            title: const Text('Alterar Vídeo Ao Vivo'),
            subtitle: const Text('Muda o ID do vídeo na tela inicial'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _showChangeVideoIdDialog, // Chama a função movida
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.looks_one_outlined), // Ícone de número
            title: const Text('Definir Rodada Padrão'),
            subtitle: const Text('Define a rodada da Tabela de Jogos'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showSetDefaultRoundDialog,
          ),
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.rule_folder), // Ícone de regras
            title: const Text('Regras Disciplinares'),
            subtitle: const Text('Define limites de cartões para suspensão'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const DisciplinaryRulesScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sort_by_alpha), // Ícone de ordenação
            title: const Text('Ordem Critérios Desempate'),
            subtitle: const Text('Define a ordem dos critérios na classificação'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const TiebreakerRulesScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline), // Ícone de interrogação/regra
            title: const Text('Regras Desempate Mata-Mata'),
            subtitle: const Text('Define Pênaltis, Prorrogação, etc.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const PlayoffRulesScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.format_list_numbered, color: Colors.purple), // Ícone de lista numerada
            title: const Text('Calcular Ranks da 1ª Fase'),
            subtitle: const Text('Salva a posição final da 1ª Fase nos times (p/ desempate)'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerCalculateRanks, // Chama a nova função
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.emoji_events_outlined, color: Colors.blue[600]), // Ícone de playoff/troféu
            title: const Text('Gerar Jogos da Semifinal'),
            subtitle: const Text('Cria os jogos (1ºx4º, 2ºx3º) baseado na classificação final'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerGenerateSemifinals, // Chama a nova função
          ),
          const Divider(),
           ListTile(
            leading: Icon(Icons.emoji_events, color: Colors.amber[700]),
            title: const Text('Gerar Final e 3º Lugar'), // Texto mudou
            subtitle: const Text('Cria os jogos com vencedores e perdedores das semis'), // Texto mudou
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerGenerateFinals, // Chama a função atualizada
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Alterar Senha Admin'),
            subtitle: const Text('Define uma nova senha de administrador'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _showChangePasswordDialog, // Chama a função movida
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.orange),
            title: const Text('Carregar Dados Iniciais'),
            subtitle: const Text('Apaga e recarrega Times, Jogadores e Jogos'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () async { // <-- Torna o onTap async
              // 1. Pede a senha
              final bool passwordConfirmed = await _verifyAdminPassword(context);

              // 2. Se confirmada (e widget ainda montado), mostra diálogo de upload
              if (passwordConfirmed && mounted) {
                _showUploadConfirmDialog(context);
              } else if (!passwordConfirmed && mounted) {
                 // Opcional: Mostrar mensagem se a senha estiver errada ou cancelada
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Operação cancelada ou senha incorreta.')),
                 );
              }
            },
          ),
          const Divider(),
          // --- NOVO BOTÃO DE MIGRAÇÃO (Coloque no final) ---
          ListTile(
            leading: const Icon(Icons.upgrade, color: Colors.teal),
            title: const Text('Atualizar Estrutura Jogadores (V1)'),
            subtitle: const Text('Adiciona campos (is_staff, jersey_number) em jogadores antigos. Execute 1 vez.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerMigrationV1,
          ),
          const Divider(),
          // --- FIM ---
          // Adicione mais opções administrativas aqui, se necessário
        ],
      ),
    );
  }
}
