import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:provider/provider.dart'; // <-- Importante
import '../services/auth_service.dart';   // <-- Importante
import '../services/admin_service.dart';
import 'disciplinary_rules_screen.dart';
import 'tiebreaker_rules_screen.dart';
import 'playoff_rules_screen.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'admin_media_screen.dart';
import 'manage_seasons_screen.dart';
import '../services/migration_service.dart'; // Para o botão de migração

class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({super.key});

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password); 
    final digest = sha256.convert(bytes); 
    return digest.toString();
  }

  Future<void> _showChangeVideoIdDialog() async {
    final urlOrIdController = TextEditingController();
    bool isLoading = false;

    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists && docSnap.data() != null && docSnap.data()!.containsKey('live_video_id')) {
        urlOrIdController.text = docSnap.get('live_video_id') ?? '';
      }
    } catch (e) { debugPrint("Erro config video: $e"); }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Alterar Vídeo/Live'),
              content: TextField(
                controller: urlOrIdController,
                decoration: const InputDecoration(
                  labelText: 'URL do YouTube ou ID',
                  hintText: 'Cole a URL completa ou o ID',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                TextButton(
                  onPressed: () async {
                    final String input = urlOrIdController.text.trim();
                    if (input.isEmpty) return;
                    setDialogState(() => isLoading = true);
                    
                    try {
                      final extractedId = YoutubePlayerController.convertUrlToId(input);
                      if (extractedId == null) throw Exception('ID inválido');

                      await _firestore.collection('config').doc('app_settings').set({
                        'live_video_id': extractedId,
                        'live_video_timestamp': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vídeo atualizado!')));
                      }
                    } catch (e) {
                       if (mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: $e')));
                    } finally {
                       if (mounted) setDialogState(() => isLoading = false);
                    }
                  },
                  child: isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog() async {
    // --- CORREÇÃO: Obtém o usuário do AuthService ---
    final authService = Provider.of<AuthService>(context, listen: false);
    final String? currentAdminUsername = authService.adminUsername;
    // ------------------------------------------------

    if (currentAdminUsername == null) return;
    
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    await showDialog(
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
                    TextField(controller: currentPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Senha Atual')),
                    const SizedBox(height: 10),
                    TextField(controller: newPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Nova Senha')),
                    const SizedBox(height: 10),
                    TextField(controller: confirmPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar Nova Senha')),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                TextButton(
                  onPressed: isLoading ? null : () async {
                    if (newPasswordController.text != confirmPasswordController.text) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Senhas não conferem.')));
                      return;
                    }
                    setDialogState(() => isLoading = true);

                    try {
                      final currentHash = _hashPassword(currentPasswordController.text);
                      final docRef = _firestore.collection('admin_users').doc(currentAdminUsername);
                      final docSnap = await docRef.get();
                      
                      if (currentHash != docSnap.data()?['password_hash']) {
                        throw Exception('Senha atual incorreta.');
                      }

                      await docRef.update({'password_hash': _hashPassword(newPasswordController.text)});
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada!')));
                      }
                    } catch (e) {
                       if (mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: $e')));
                    } finally {
                       if (mounted) setDialogState(() => isLoading = false);
                    }
                  },
                  child: const Text('Alterar'),
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

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Definir Visualização Padrão'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Selecione a tela inicial da Tabela de Jogos.', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedPhase,
                    items: const [
                      DropdownMenuItem(value: 'first', child: Text('1ª Fase')),
                      DropdownMenuItem(value: 'second', child: Text('Mata-Mata')),
                    ],
                    onChanged: (v) => setDialogState(() { selectedPhase = v!; if(v=='first') selectedStage='1'; else selectedStage='semifinal'; }),
                    decoration: const InputDecoration(labelText: 'Fase', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  if (selectedPhase == 'first')
                    DropdownButtonFormField<String>(
                      value: selectedStage,
                      items: roundOptions,
                      onChanged: (v) => setDialogState(() => selectedStage = v!),
                      decoration: const InputDecoration(labelText: 'Rodada', border: OutlineInputBorder()),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedStage,
                      items: playoffOptions,
                      onChanged: (v) => setDialogState(() => selectedStage = v!),
                      decoration: const InputDecoration(labelText: 'Etapa', border: OutlineInputBorder()),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                TextButton(
                  onPressed: () async {
                    setDialogState(() => isDialogSaving = true);
                    try {
                      await _firestore.collection('config').doc('app_settings').set(
                        { 'default_phase': selectedPhase, 'default_stage': selectedStage },
                        SetOptions(merge: true)
                      );
                      // Atualiza cache local
                      AdminService.defaultPhase = selectedPhase;
                      AdminService.defaultStage = selectedStage;
                      
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Padrão atualizado.')));
                      }
                    } catch (e) {
                       ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: $e')));
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Administrativo')),
      body: _isSaving
        ? const Center(child: CircularProgressIndicator())
        : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- GERENCIAR TEMPORADAS ---
          Card(
            color: Colors.amber[50],
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.orange),
              title: const Text('Gerenciar Temporadas'),
              subtitle: const Text('Criar novos anos (2026) e alternar visualização'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                 Navigator.of(context).push(MaterialPageRoute(
                   builder: (ctx) => const ManageSeasonsScreen(),
                 ));
              },
            ),
          ),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.newspaper, color: Colors.blue),
            title: const Text('Gerenciar Mídias'),
            subtitle: const Text('Adiciona/Edita notícias e vídeos da tela inicial'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AdminMediaScreen())),
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
          ListTile(
            leading: const Icon(Icons.looks_one_outlined),
            title: const Text('Definir Visualização Padrão'),
            subtitle: const Text('Define a tela inicial da Tabela de Jogos'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showSetDefaultViewDialog,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.rule_folder),
            title: const Text('Regras Disciplinares'),
            subtitle: const Text('Define limites de cartões para suspensão'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const DisciplinaryRulesScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sort_by_alpha),
            title: const Text('Ordem Critérios Desempate'),
            subtitle: const Text('Define a ordem dos critérios na classificação'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const TiebreakerRulesScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Regras Desempate Mata-Mata'),
            subtitle: const Text('Define Pênaltis, Prorrogação, etc.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const PlayoffRulesScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Alterar Senha Admin'),
            subtitle: const Text('Define uma nova senha de administrador'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _isSaving ? null : _showChangePasswordDialog,
          ),
          const SizedBox(height: 30),


          // --- BOTÃO DE MIGRAÇÃO (Uso Único/Raro) ---
          Card(
            color: Colors.red[50],
            elevation: 4,
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.red, width: 2), borderRadius: BorderRadius.circular(8)),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
              title: const Text('MIGRAR BANCO PARA 2025', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              subtitle: const Text('Move dados da Raiz para a nova estrutura.'),
              onTap: _isSaving ? null : () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('MIGRAÇÃO CRÍTICA'),
                    content: const Text('Isso moverá TODOS os times e jogos da raiz para a temporada "2025_fjf".\nCertifique-se de que ninguém está usando o app.\n\nDeseja continuar?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('MIGRAR AGORA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  setState(() => _isSaving = true);
                  final result = await MigrationService().migrateLegacyTo2025();
                  setState(() => _isSaving = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result == "Sucesso" ? "Migração Concluída!" : result), backgroundColor: result == "Sucesso" ? Colors.green : Colors.red));
                  }
                }
              },
            ),
          ),
          
        ],
      ),
    );
  }
}