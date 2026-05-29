import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart'; 
import 'admin_bolao_screen.dart';
import 'fantasy_admin_control_screen.dart'; 
import 'disciplinary_rules_screen.dart';
import 'tiebreaker_rules_screen.dart';
import 'playoff_rules_screen.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'admin_media_screen.dart';
import 'manage_seasons_screen.dart';
import '../services/migration_service.dart';
import 'admin_upload_photo_screen.dart';
import 'tournament_format_screen.dart'; 
import 'admin_polls_screen.dart'; 
import 'admin_sponsors_screen.dart';

class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({super.key});

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;
  bool _isProcessingStorage = false;

  // --- LÓGICA DE NEGÓCIO ---

  Future<void> _handleStorageMigration() async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Migrar URLs do Storage"),
        content: Text("Isso irá varrer todos os documentos da temporada '$seasonId' e atualizar os links das imagens do bucket antigo para o novo ('acefjf'). Deseja continuar?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("MIGRAR AGORA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessingStorage = true);
    final result = await MigrationService().migrateStorageUrls(seasonId);
    setState(() => _isProcessingStorage = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result),
        backgroundColor: result.startsWith("Sucesso") ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  Future<void> _showChangeVideoIdDialog() async {
    final urlOrIdController = TextEditingController();
    bool isLoading = false;
    
    // Obtém ID da temporada
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      // LEITURA: Agora busca da temporada específica
      final docSnap = await _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('settings')
          .doc('app_settings')
          .get();

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
                  prefixIcon: Icon(Icons.video_library),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    final String input = urlOrIdController.text.trim();
                    if (input.isEmpty) return;
                    setDialogState(() => isLoading = true);
                    
                    try {
                      final extractedId = YoutubePlayerController.convertUrlToId(input);
                      if (extractedId == null) throw Exception('ID inválido');

                      // ESCRITA: Salva na temporada específica
                      await _firestore
                          .collection('championships')
                          .doc(seasonId)
                          .collection('settings')
                          .doc('app_settings')
                          .set({
                            'live_video_id': extractedId,
                            'live_video_timestamp': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vídeo atualizado para esta temporada!')));
                      }
                    } catch (e) {
                        if (mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Erro: $e')));
                    } finally {
                        if (mounted) setDialogState(() => isLoading = false);
                    }
                  },
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSetDefaultViewDialog() async {
    bool isDialogSaving = false;
    
    // Obtém o ID da temporada atual do Provider
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    String selectedPhase = AdminService.defaultPhase;
    String selectedStage = AdminService.defaultStage;

    final List<DropdownMenuItem<String>> roundOptions = List.generate(
      7, (i) => DropdownMenuItem(value: (i + 1).toString(), child: Text('Rodada ${i + 1}'))
    );
    
    final List<DropdownMenuItem<String>> playoffOptions = [
      const DropdownMenuItem(value: 'quarter_final', child: Text('Playoff / Quartas')), 
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
                  const Text('Selecione a tela que o usuário verá ao abrir a tabela.', style: TextStyle(fontSize: 14, color: Colors.grey)),
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
                ElevatedButton(
                  onPressed: () async {
                    setDialogState(() => isDialogSaving = true);
                    try {
                      await _firestore
                          .collection('championships')
                          .doc(seasonId)
                          .collection('settings')
                          .doc('app_settings')
                          .set(
                            { 'default_phase': selectedPhase, 'default_stage': selectedStage },
                            SetOptions(merge: true)
                          );
                      
                      // Atualiza cache local
                      AdminService.defaultPhase = selectedPhase;
                      AdminService.defaultStage = selectedStage;
                      
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Padrão atualizado para esta temporada.')));
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

  // --- BUILD UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        title: const Text('Menu Administrativo', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isSaving
        ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Processando...", style: TextStyle(color: Colors.grey))
            ],
          ))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader("Gestão Principal"),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildBigCard(
                        icon: Icons.calendar_month,
                        color: Colors.orange,
                        title: "Temporadas",
                        subtitle: "Criar/Editar Anos",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const ManageSeasonsScreen())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildBigCard(
                        icon: Icons.sports_soccer,
                        color: Colors.blue,
                        title: "Fantasy",
                        subtitle: "Painel de Controle",
                        isHighlight: true,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FantasyAdminControlScreen())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildBigCard(
                        icon: Icons.settings_applications,
                        color: Colors.blue,
                        title: "Bolão",
                        subtitle: "Painel de Controle",
                        isHighlight: true,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminBolaoScreen())),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                _buildSectionHeader("Mídia e Conteúdo"),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      _buildActionTile(
                        icon: Icons.how_to_vote,
                        color: Colors.amber[700]!,
                        title: "Gerenciar Votações",
                        subtitle: "Enquetes e Craques",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AdminPollsScreen())),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.newspaper,
                        color: Colors.indigo,
                        title: "Gerenciar Notícias",
                        subtitle: "Feed e banners da Home",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AdminMediaScreen())),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.monetization_on,
                        color: Colors.green.shade700,
                        title: "Patrocinadores (Banners)",
                        subtitle: "Controle de Cotas e Espaços",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AdminSponsorsScreen())),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.camera_enhance,
                        color: Colors.purple,
                        title: "Área do Fotógrafo",
                        subtitle: "Upload para Loja de Fotos",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AdminUploadPhotoScreen())),
                      ),
                       const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.live_tv,
                        color: Colors.red,
                        title: "Vídeo Ao Vivo",
                        subtitle: "Configurar Live do Youtube",
                        onTap: _showChangeVideoIdDialog,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader("Regras e Configurações"),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      _buildActionTile(
                        icon: Icons.looks_one_outlined,
                        color: Colors.teal,
                        title: "Padrão de Visualização",
                        subtitle: "Tela inicial da Tabela",
                        onTap: _showSetDefaultViewDialog,
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.account_tree_outlined,
                        color: Colors.deepPurple,
                        title: "Forma de Disputa",
                        subtitle: "Modelo do Campeonato",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const TournamentFormatScreen())),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.rule_folder,
                        color: Colors.brown,
                        title: "Disciplina",
                        subtitle: "Regras de cartões",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const DisciplinaryRulesScreen())),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.sort_by_alpha,
                        color: Colors.blueGrey,
                        title: "Critérios de Desempate",
                        subtitle: "Ordem da classificação",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const TiebreakerRulesScreen())),
                      ),
                      const Divider(height: 1, indent: 56),
                      _buildActionTile(
                        icon: Icons.emoji_events_outlined,
                        color: Colors.amber[800]!,
                        title: "Mata-Mata",
                        subtitle: "Regras de playoffs",
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const PlayoffRulesScreen())),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                _buildSectionHeader("Segurança e Sistema"),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      const Divider(height: 1, indent: 56),
                      
                      // ---> NOVO BOTÃO: MIGRAÇÃO DE STORAGE <---
                      if (_isProcessingStorage)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: SizedBox(
                              width: 24, height: 24, 
                              child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2)
                            )
                          ),
                        )
                      else
                        _buildActionTile(
                          icon: Icons.cloud_sync,
                          color: Colors.orange,
                          title: "Migrar URLs do Storage",
                          subtitle: "Atualiza bucket antigo para o novo",
                          textColor: Colors.orange[800],
                          onTap: _handleStorageMigration,
                        ),
                      // ------------------------------------------

                      // ZONA DE PERIGO (Migração de banco legado)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          )
                        ),
                        child: _buildActionTile(
                          icon: Icons.warning_amber_rounded,
                          color: Colors.red,
                          title: "Migração de Banco",
                          subtitle: "Mover dados (Avançado)",
                          textColor: Colors.red[900],
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('⚠️ MIGRAÇÃO CRÍTICA'),
                                content: const Text('Isso moverá TODOS os times e jogos da raiz para a temporada "2025_fjf".\nCertifique-se de que ninguém está usando o app.\n\nDeseja continuar?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.of(ctx).pop(true), 
                                    child: const Text('MIGRAR AGORA', style: TextStyle(color: Colors.white))
                                  ),
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
                ),
                
                const SizedBox(height: 40),
                const Center(
                  child: Text(
                    "FJF Admin v2.0.0",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.blueGrey[600],
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.0
        ),
      ),
    );
  }

  Widget _buildBigCard({
    required IconData icon, 
    required Color color, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap,
    bool isHighlight = false,
  }) {
    return Card(
      elevation: isHighlight ? 4 : 2,
      shadowColor: isHighlight ? color.withOpacity(0.4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isHighlight ? BorderSide(color: color.withOpacity(0.5), width: 1.5) : BorderSide.none
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                subtitle, 
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon, 
    required Color color, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }
}