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

  // --- NOVA FUNÇÃO: Migrar Dados Overall ---
  Future<void> _runOverallMigration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migrar Dados Overall?'),
        content: const Text(
            'Esta ação recalculará as estatísticas de TODOS os times, somando todos os jogos (Fase 1 + Mata-Mata) para criar os novos campos de estatísticas gerais.\n\nExecute isso UMA VEZ para corrigir os dados antigos.\n\nDeseja continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Iniciar Migração', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() { _isSaving = true; });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Iniciando migração... aguarde.')),
    );

    try {
      final teamsSnapshot = await _firestore.collection('teams').get();
      int count = 0;
      
      for (var doc in teamsSnapshot.docs) {
        // Chama a função pública do service para cada time
        await _firestoreService.recalculateTeamStats(doc.id);
        count++;
        // debugPrint("Time $count/${teamsSnapshot.docs.length} migrado.");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sucesso! $count times atualizados.')),
        );
      }
    } catch (e) {
      debugPrint("Erro na migração: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }
  // --- FIM ---

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
          
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Alterar Senha Admin'),
            subtitle: const Text('Define uma nova senha de administrador'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showChangePasswordDialog,
          ),
          const Divider(),

          // --- NOVO BOTÃO DE MIGRAÇÃO (MANUTENÇÃO) ---
          ListTile(
            leading: const Icon(Icons.build_circle, color: Colors.teal),
            title: const Text('Migrar Dados Overall (Manutenção)'),
            subtitle: const Text('Recalcula estatísticas de todos os times.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _runOverallMigration,
          ),
          const Divider(),
          // --- FIM ---
        ],
      ),
    );
  }
}