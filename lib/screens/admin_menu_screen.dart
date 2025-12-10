// lib/screens/admin_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
//import 'package:flutter/services.dart';
//import '../services/data_uploader_service.dart';
import '../services/admin_service.dart';
import 'admin_voting_nominees_screen.dart';
import 'disciplinary_rules_screen.dart';
import 'tiebreaker_rules_screen.dart';
import '../services/firestore_service.dart';
import 'playoff_rules_screen.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'admin_media_screen.dart';
import 'voting/admin_voting_results_screen.dart';

class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({super.key});

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  bool _isSaving = false;
  bool _votingEnabled = true; // Estado local da chave

  @override
  void initState() {
    super.initState();
    _loadVotingStatus();
  }

  Future<void> _loadVotingStatus() async {
    try {
      final doc = await _firestore.collection('config').doc('app_settings').get();
      if (doc.exists) {
        setState(() {
          _votingEnabled = doc.data()?['voting_enabled'] ?? true;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar status votação: $e");
    }
  }

  Future<void> _toggleVotingStatus(bool value) async {
    // 1. Atualiza visualmente imediatamente (Otimista)
    setState(() => _votingEnabled = value);
    
    try {
      // 2. Tenta salvar no Firebase
      await _firestore.collection('config').doc('app_settings').set({
        'voting_enabled': value
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Votação LIBERADA para todos!' : 'Votação BLOQUEADA/ENCERRADA!'), 
            backgroundColor: value ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          )
        );
      }
    } catch (e) {
      // 3. Se der erro (ex: Sem Permissão), reverte o botão e avisa
      debugPrint("ERRO AO SALVAR CONFIG: $e");
      if (mounted) {
        setState(() => _votingEnabled = !value); // Volta o botão
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }
  

  String _hashPassword(String password) {
    final bytes = utf8.encode(password); 
    final digest = sha256.convert(bytes); 
    return digest.toString();
  }

  /*Future<void> _triggerMigrationV1() async {
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
       final result = await _firestoreService.migratePlayersV1();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }
  }

  Future<void> _triggerCalculateRanks() async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Calcular Ranks da 1ª Fase?'),
         content: const Text(
             'Isso ordenará todos os times com base nos resultados finais da 1ª Fase e salvará a posição (rank) em cada time. Execute APENAS após o fim da 1ª Fase.\n\nEste rank é usado para o desempate por "Melhor Classif." no mata-mata caso ocorra empate após a prorrogação.'
         ),
          actions: [
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(false),
             child: const Text('Cancelar'),
           ),
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text(
                 'Confirmar e Calcular',
                 style: TextStyle(color: Colors.deepPurple)
             ),
           ),
         ],
       ),
     );

     if (confirm == true && mounted) {
       setState(() { _isSaving = true; });
       final result = await _firestoreService.calculateAndStorePhase1Ranks();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }
  }

  Future<void> _showUploadConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        bool isLoading = false;
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
*/
  

  Future<void> _showChangeVideoIdDialog() async {
    final urlOrIdController = TextEditingController();
    bool isLoading = false;
    String currentVideoId = '';

    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
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
                      extractedId = YoutubePlayerController.convertUrlToId(input);
                      debugPrint("Input: '$input', ID Extraído: '$extractedId'");

                      if (extractedId == null || extractedId.isEmpty) {
                         throw Exception('Não foi possível extrair um ID válido da URL fornecida.');
                      }

                      await _firestore.collection('config').doc('app_settings').set({
                        'live_video_id': extractedId,
                        'live_video_timestamp': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

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

  /*Future<bool> _verifyAdminPassword(BuildContext context) async {
    final String? currentAdminUsername = AdminService.loggedInAdminUsername;
    if (currentAdminUsername == null) {
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
              title: Text('Confirmar Ação para usuário "$currentAdminUsername"'),
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
  */
  Future<void> _showChangePasswordDialog() async {
    final String? currentAdminUsername = AdminService.loggedInAdminUsername;
    if (currentAdminUsername == null) return;
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Mudar Senha ($currentAdminUsername)'),
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
                    final currentPassword = currentPasswordController.text;
                    final newPassword = newPasswordController.text;
                    final confirmPassword = confirmPasswordController.text;

                    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Preencha todos os campos.')));
                      return;
                    }
                    if (newPassword != confirmPassword) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('As novas senhas não coincidem.')));
                      return;
                    }
                     if (newPassword.length < 6) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('A nova senha deve ter pelo menos 6 caracteres.')));
                      return;
                    }

                    setDialogState(() { isLoading = true; });

                    try {
                      final currentHash = _hashPassword(currentPassword);
                      final docRef = _firestore.collection('admin_users').doc(currentAdminUsername);
                      final docSnap = await docRef.get();
                      final storedHash = docSnap.data()?['password_hash'];

                      if (currentHash != storedHash) {
                        throw Exception('Senha atual incorreta.');
                      }

                      final newHash = _hashPassword(newPassword);
                      await docRef.update({'password_hash': newHash});

                      if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada com sucesso!')));

                    } catch (e) {
                       if (Navigator.of(dialogContext).canPop()) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')));
                    } finally {
                       if (Navigator.of(dialogContext).canPop()) setDialogState(() { isLoading = false; });
                    }
                  },
                  child: isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Alterar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  /*Future<void> _triggerGenerateSemifinals() async {
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
       setState(() { _isSaving = true; });
       final result = await _firestoreService.generateSemifinals();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
     }
  }

  Future<void> _triggerGenerateFinals() async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Gerar Final e 3º Lugar?'),
         content: const Text('Isso buscará os VENCEDORES e PERDEDORES das semifinais FINALIZADAS e criará os jogos. Tem certeza?\n(Verifique se AMBAS as semifinais estão "Finalizadas" e SEM empates).'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmar', style: TextStyle(color: Colors.green))),
         ],
       ),
     );

     if (confirm == true && mounted) {
       setState(() { _isSaving = true; });
       final result = await _firestoreService.generateFinals();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }
  }*/

  // --- INÍCIO DA ALTERAÇÃO (Diálogo de Definir Padrão) ---
  Future<void> _showSetDefaultViewDialog() async {
    bool isDialogSaving = false;
    
    String selectedPhase = AdminService.defaultPhase;
    String selectedStage = AdminService.defaultStage;

    final List<DropdownMenuItem<String>> roundOptions = List.generate(
      7, (i) => DropdownMenuItem(value: (i + 1).toString(), child: Text('Rodada ${i + 1}'))
    );
    
    final List<DropdownMenuItem<String>> playoffOptions = [
      const DropdownMenuItem(value: 'semifinal', child: Text('Semifinais')),
      const DropdownMenuItem(value: 'third_place', child: Text('Disputa de 3º Lugar')),
      const DropdownMenuItem(value: 'final_game', child: Text('Final')),
    ];

    return showDialog<void>(
      context: context,
      barrierDismissible: !isDialogSaving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            void _updatePhase(String newPhase) {
              setDialogState(() {
                selectedPhase = newPhase;
                if (selectedPhase == 'first') {
                  selectedStage = '1';
                } else {
                  selectedStage = 'semifinal';
                }
              });
            }

            return AlertDialog(
              title: const Text('Definir Visualização Padrão'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Selecione a tela que os usuários verão ao abrir a Tabela de Jogos.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'first', label: Text('1ª Fase')),
                      ButtonSegment<String>(value: 'second', label: Text('Mata-Mata')),
                    ],
                    selected: {selectedPhase},
                    onSelectionChanged: (Set<String> newSelection) {
                      _updatePhase(newSelection.first);
                    },
                  ),
                  const SizedBox(height: 16),

                  if (selectedPhase == 'first')
                    DropdownButtonFormField<String>(
                      value: selectedStage,
                      items: roundOptions,
                      onChanged: isDialogSaving ? null : (value) {
                        if (value != null) setDialogState(() => selectedStage = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Rodada Padrão',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else // selectedPhase == 'second'
                    DropdownButtonFormField<String>(
                      value: selectedStage,
                      items: playoffOptions,
                      onChanged: isDialogSaving ? null : (value) {
                        if (value != null) setDialogState(() => selectedStage = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Etapa Padrão (Mata-Mata)',
                        border: OutlineInputBorder(),
                      ),
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
                    setDialogState(() { isDialogSaving = true; });
                    
                    try {
                      await _firestore.collection('config').doc('app_settings').set(
                        { 
                          'default_phase': selectedPhase,
                          'default_stage': selectedStage,
                          'default_fixtures_round': FieldValue.delete(),
                        },
                        SetOptions(merge: true)
                      );
                      
                      AdminService.defaultPhase = selectedPhase; 
                      AdminService.defaultStage = selectedStage;
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Visualização padrão atualizada.')),
                        );
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Erro ao salvar: $e')),
                        );
                    } finally {
                         setDialogState(() { isDialogSaving = false; });
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
  // --- FIM DA ALTERAÇÃO ---

  
  // --- NOVA FUNÇÃO: Resetar Cartões Amarelos ---
  Future<void> _showResetYellowsConfirmDialog() async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Zerar Cartões Amarelos?'),
         content: const Text(
             'ATENÇÃO!\n\nEsta ação zerará a contagem de cartões amarelos (suspensão) de TODOS os jogadores. Isso é recomendado apenas na mudança de fases (ex: 1ª Fase -> Semifinal).\n\nO histórico total de cartões para estatísticas SERÁ MANTIDO.\n\nDeseja continuar?'),
          actions: [
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(false),
             child: const Text('Cancelar'),
           ),
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text(
                 'Confirmar Zeramento',
                 style: TextStyle(color: Colors.red)
             ),
           ),
         ],
       ),
     );
     
     if (confirm == true && mounted) {
       setState(() { _isSaving = true; });
       final result = await _firestoreService.resetCurrentYellowCardsForPhaseChange();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 5)));
     }
  }
  // --- FIM ---

/*
  Future<void> _showSyncLogosConfirmDialog() async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Sincronizar URLs de Logos?'),
         content: const Text(
             'Esta ação verificará TODOS os jogadores, partidas e logs de suspensão, e atualizará as URLs dos logos para corresponder à URL principal na coleção "teams".\n\nIsto pode usar muitas operações de leitura/escrita.\n\nDeseja continuar?'),
          actions: [
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(false),
             child: const Text('Cancelar'),
           ),
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text(
                 'Confirmar Sincronização',
                 style: TextStyle(color: Colors.orange)
             ),
           ),
         ],
       ),
     );
     
     if (confirm == true && mounted) {
       setState(() { _isSaving = true; });
       final result = await _firestoreService.syncTeamLogosToAllCollections();
       setState(() { _isSaving = false; });
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), duration: const Duration(seconds: 4)));
     }
  }
*/

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Administrativo')),
      body: _isSaving
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Executando operação... Por favor, aguarde.'),
              ],
            ),
          )
        : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.newspaper, color: Colors.blue),
            title: const Text('Gerenciar Mídias'),
            subtitle: const Text('Adiciona/Edita notícias e vídeos da tela inicial'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
               Navigator.of(context).push(MaterialPageRoute(
                 builder: (ctx) => const AdminMediaScreen(),
               ));
            },
          ),
          const Divider(),
          Card(
            color: _votingEnabled ? Colors.green[50] : Colors.red[50],
            elevation: 2,
            child: SwitchListTile(
              title: Text(
                _votingEnabled ? "Votação ABERTA" : "Votação ENCERRADA", 
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: _votingEnabled ? Colors.green[800] : Colors.red[800]
                )
              ),
              subtitle: const Text("Controla o acesso dos usuários à tela de votação."),
              value: _votingEnabled,
              activeColor: Colors.green,
              onChanged: _toggleVotingStatus, // Chama a função corrigida
            ),
          ),
          const Divider(),

          // --- RESULTADOS DA VOTAÇÃO ---
          ListTile(
            leading: const Icon(Icons.poll, color: Colors.deepPurple),
            title: const Text('Resultados Parciais (Votação)'),
            subtitle: const Text('Veja o ranking de votos de todas as categorias.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
               Navigator.of(context).push(MaterialPageRoute(
                 builder: (ctx) => const AdminVotingResultsScreen(),
               ));
            },
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.how_to_vote, color: Colors.purple),
            title: const Text('Gerenciar Candidatos Manuais'),
            subtitle: const Text('Cadastrar Vídeos e Revelação'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
               Navigator.of(context).push(MaterialPageRoute(
                 builder: (ctx) => const AdminVotingNomineesScreen(),
               ));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.live_tv, color: Colors.red),
            title: const Text('Alterar Vídeo Ao Vivo'),
            subtitle: const Text('Muda o ID do vídeo na tela inicial'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showChangeVideoIdDialog,
          ),
          const Divider(),

          // --- INÍCIO DA ALTERAÇÃO (Chamada do novo diálogo) ---
          ListTile(
            leading: const Icon(Icons.looks_one_outlined),
            title: const Text('Definir Visualização Padrão'),
            subtitle: const Text('Define a tela inicial da Tabela de Jogos'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showSetDefaultViewDialog,
          ),
          // --- FIM DA ALTERAÇÃO ---

          const Divider(),
          ListTile(
            leading: const Icon(Icons.rule_folder),
            title: const Text('Regras Disciplinares'),
            subtitle: const Text('Define limites de cartões para suspensão'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const DisciplinaryRulesScreen()),
              );
            },
          ),
          const Divider(),
          // --- NOVO BOTÃO DE ZERAR CARTÕES ---
          ListTile(
            leading: const Icon(Icons.cleaning_services, color: Colors.orange),
            title: const Text('Zerar Cartões Amarelos'),
            subtitle: const Text('Reseta contagem de CA para suspensão (mantém estatísticas). Útil na virada de fase.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showResetYellowsConfirmDialog,
          ),
          const Divider(),
          // --- FIM DO BOTÃO ---
          ListTile(
            leading: const Icon(Icons.sort_by_alpha),
            title: const Text('Ordem Critérios Desempate'),
            subtitle: const Text('Define a ordem dos critérios na classificação'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const TiebreakerRulesScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Regras Desempate Mata-Mata'),
            subtitle: const Text('Define Pênaltis, Prorrogação, etc.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const PlayoffRulesScreen()),
              );
            },
          ),
          
          /*const Divider(),
          ListTile(
            leading: const Icon(Icons.format_list_numbered, color: Colors.purple),
            title: const Text('Calcular Ranks da 1ª Fase'),
            subtitle: const Text('Salva a posição final da 1ª Fase nos times (p/ desempate)'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerCalculateRanks,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.emoji_events_outlined, color: Colors.blue[600]),
            title: const Text('Gerar Jogos da Semifinal'),
            subtitle: const Text('Cria os jogos (1ºx4º, 2ºx3º) baseado na classificação final'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerGenerateSemifinals,
          ),
          const Divider(),
           ListTile(
            leading: Icon(Icons.emoji_events, color: Colors.amber[700]),
            title: const Text('Gerar Final e 3º Lugar'),
            subtitle: const Text('Cria os jogos com vencedores e perdedores das semis'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerGenerateFinals,
          ),*/
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Alterar Senha Admin'),
            subtitle: const Text('Define uma nova senha de administrador'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showChangePasswordDialog,
          ),
          const Divider(),
          /*
          // --- NOVO: Botão de Sincronização de Logos ---
          ListTile(
            leading: const Icon(Icons.sync, color: Colors.green),
            title: const Text('Sincronizar Logos das Equipas'),
            subtitle: const Text('Atualiza logos em jogos, jogadores e suspensões'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () async {
              final bool passwordConfirmed = await _verifyAdminPassword(context);
              if (passwordConfirmed && mounted) {
                _showSyncLogosConfirmDialog();
              } else if (!passwordConfirmed && mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Operação cancelada ou senha incorreta.')),
                 );
              }
            },
          ),
          const Divider(),
          // --- FIM ---
          
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.orange),
            title: const Text('Carregar Dados Iniciais'),
            subtitle: const Text('Apaga e recarrega Times, Jogadores e Jogos'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () async {
              final bool passwordConfirmed = await _verifyAdminPassword(context);
              if (passwordConfirmed && mounted) {
                _showUploadConfirmDialog(context);
              } else if (!passwordConfirmed && mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Operação cancelada ou senha incorreta.')),
                 );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upgrade, color: Colors.teal),
            title: const Text('Atualizar Estrutura Jogadores (V1)'),
            subtitle: const Text('Adiciona campos (is_staff, jersey_number) em jogadores antigos. Execute 1 vez.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _triggerMigrationV1,
          ),
          const Divider(),
          */
        ],
      ),
    );
  }
}