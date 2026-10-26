import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../services/match_service.dart';
import '../../services/championship_service.dart';
import '../../models/match_model.dart';
import '../../viewmodels/admin_match_viewmodel.dart';
import '../../utils/youtube_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'edit_match_screen.dart';
import '../championship/match_live_scout_screen.dart';

class AdminMatchScreen extends StatelessWidget {
  final DocumentSnapshot match;
  const AdminMatchScreen({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    // 🚨 OTIMIZAÇÃO: Isolamos a lógica pesada num ViewModel local da Tela
    return ChangeNotifierProvider(
      create: (ctx) => AdminMatchViewModel(
        matchService: Provider.of<MatchService>(ctx, listen: false),
        championshipService: Provider.of<ChampionshipService>(ctx, listen: false),
        seasonId: Provider.of<ChampionshipService>(ctx, listen: false).currentSeasonId,
        matchSnap: match,
      ),
      child: const _AdminMatchScreenContent(),
    );
  }
}

class _AdminMatchScreenContent extends StatefulWidget {
  const _AdminMatchScreenContent();

  @override
  State<_AdminMatchScreenContent> createState() => _AdminMatchScreenContentState();
}

class _AdminMatchScreenContentState extends State<_AdminMatchScreenContent> {
  
  Future<void> _handleDelete(AdminMatchViewModel vm) async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Partida?', style: TextStyle(color: Colors.red)), 
        content: const Text('Essa ação é irreversível e excluirá todo o histórico deste jogo.\n\nDeseja continuar?'), 
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), 
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('EXCLUIR', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
        ]
      )
    );

    if (confirm == true && mounted) {
      final result = await vm.deleteMatch();
      if (mounted) {
        if (result.startsWith('Sucesso')) {
           Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
           Navigator.of(context).pop();
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partida excluída com sucesso.'))); 
        } else {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result))); 
        }
      }
    }
  }

  Future<void> _handleSave(AdminMatchViewModel vm) async {
    final result = await vm.saveStats();
    if (mounted) {
      if (result.startsWith('Sucesso')) {
        Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados da partida salvos!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminMatchViewModel>(
      builder: (context, vm, child) {
        final matchData = vm.matchSnap.data() as Map<String, dynamic>? ?? {};
        
        final motmCandidates = vm.allPlayers.where((p) { 
          final d = p.data() as Map<String, dynamic>? ?? {}; 
          return d['is_staff'] != true; 
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Administrar Partida'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_calendar_outlined), 
                tooltip: "Editar Detalhes",
                onPressed: vm.isSaving ? null : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => EditMatchScreen(
                      match: MatchModel.fromFirestore(vm.matchSnap)
                    ))
                  );
                  vm.reloadMatchData(preserveLineup: true);
                }
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever), 
                tooltip: "Excluir Partida",
                onPressed: vm.isSaving ? null : () => _handleDelete(vm)
              ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildLiveScoutButton(context, vm),
                    const SizedBox(height: 24),
                    _buildScoreCard(matchData, vm),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: vm.selectedStatus, 
                      items: const [
                        DropdownMenuItem(value: 'pending', child: Text('Pendente (Não Iniciado)')), 
                        DropdownMenuItem(value: 'in_progress', child: Text('Em Andamento')), 
                        DropdownMenuItem(value: 'finished', child: Text('Finalizado'))
                      ], 
                      onChanged: (v) { if(v!=null) vm.updateStatus(v); }, 
                      decoration: const InputDecoration(labelText: 'Status da Partida', border: OutlineInputBorder())
                    ),
                    if (vm.showTiebreakerSection) ...[const SizedBox(height: 12), _buildTiebreakerSection(vm)],
                    const SizedBox(height: 24),
                    const Divider(),
                    const Text("SÚMULA DE PRESENÇA (JOGARAM)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blue, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    const Text("Marque os jogadores que entraram em campo (titulares e reservas utilizados) para computar a partida disputada no Fantasy.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),

              if (vm.isLoadingPlayers)
                const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))),

              if (!vm.isLoadingPlayers) ...[
                _buildTeamHeaderSliver(context, matchData['team_home_name'] ?? 'Casa', vm.homePlayers, vm),
                _buildPlayerListSliver(vm.homePlayers, vm),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                _buildTeamHeaderSliver(context, matchData['team_away_name'] ?? 'Fora', vm.awayPlayers, vm),
                _buildPlayerListSliver(vm.awayPlayers, vm),
              ],

              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 24),
                    const Divider(),
                    const Text("FECHAMENTO", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: motmCandidates.any((p) => p.id == vm.selectedManOfTheMatchId) ? vm.selectedManOfTheMatchId : null, 
                      items: motmCandidates.map((p) { final d = p.data() as Map<String, dynamic>; return DropdownMenuItem(value: p.id, child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis)); }).toList(), 
                      onChanged: vm.updateMotm, 
                      decoration: const InputDecoration(labelText: 'Craque do Jogo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.star, color: Colors.amber))
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text("Upload da Súmula (PDF)"), 
                      subtitle: vm.existingSumulaUrl != null ? const Text("Arquivo já enviado", style: TextStyle(color: Colors.green)) : (vm.pickedFileBytes != null ? const Text("Pronto para enviar", style: TextStyle(color: Colors.blue)) : const Text("Nenhum arquivo")),
                      trailing: const Icon(Icons.upload_file), 
                      onTap: vm.pickSumulaFile, 
                      shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(4))
                    ),
                    const SizedBox(height: 16),
                    _buildMediaSection(context, vm),
                    const SizedBox(height: 30),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: vm.isSaving ? null : () => _handleSave(vm),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                        child: vm.isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("SALVAR ALTERAÇÕES", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTiebreakerSection(AdminMatchViewModel vm) {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text('Desempate (Pênaltis)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 50, child: TextField(controller: vm.penaltyHomeScoreController, textAlign: TextAlign.center, keyboardType: TextInputType.number)),
                const Text(' x '),
                SizedBox(width: 50, child: TextField(controller: vm.penaltyAwayScoreController, textAlign: TextAlign.center, keyboardType: TextInputType.number)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamHeaderSliver(BuildContext context, String teamName, List<DocumentSnapshot> teamPlayers, AdminMatchViewModel vm) {
    final int presentCount = teamPlayers.where((p) => vm.lineupPlayed.contains(p.id)).length;
    final int totalCount = teamPlayers.length;
    final bool allSelected = totalCount > 0 && presentCount == totalCount;

    return SliverToBoxAdapter(
      child: Container(
        color: Colors.grey[200],
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "${teamName.toUpperCase()} ($presentCount/$totalCount)",
              style: TextStyle(
                color: Theme.of(context).primaryColor, 
                fontWeight: FontWeight.bold, 
                letterSpacing: 1.1,
                fontSize: 13,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
                size: 16,
              ),
              label: Text(
                allSelected ? "Desmarcar Todos" : "Marcar Todos",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (allSelected) {
                  vm.clearTeamPlayers(teamPlayers);
                } else {
                  vm.selectTeamPlayers(teamPlayers);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerListSliver(List<DocumentSnapshot> players, AdminMatchViewModel vm) {
    if (players.isEmpty) {
      return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Text("Sem jogadores.")));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final player = players[index];
          final pid = player.id;
          final data = player.data() as Map<String, dynamic>? ?? {};
          
          final bool isStaff = data['is_staff'] ?? false;
          final name = data['name'] ?? '?';
          final num = data['jersey_number'];

          final int g = vm.goals[pid] ?? 0;
          final int a = vm.assists[pid] ?? 0;
          final int y = vm.yellowCards[pid] ?? 0;
          final int r = vm.redCards[pid] ?? 0;

          return Container(
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: Checkbox(
                    value: vm.lineupPlayed.contains(pid),
                    onChanged: (val) => vm.togglePlayerInLineup(pid),
                    activeColor: Colors.blue,
                  ),
                  title: Row(
                    children: [
                      isStaff 
                          ? const Icon(Icons.assignment_ind, color: Colors.grey, size: 20)
                          : CircleAvatar(
                              backgroundColor: Colors.grey[100],
                              radius: 12,
                              child: Text("${num ?? '-'}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                            ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                    ],
                  ),
                  trailing: _buildStatIcons(g, a, y, r),
                ),
                const Divider(height: 1, indent: 60),
              ],
            ),
          );
        },
        childCount: players.length,
      ),
    );
  }

  Widget _buildLiveScoutButton(BuildContext context, AdminMatchViewModel vm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        icon: const Icon(Icons.flash_on, size: 28),
        label: const Text(
          "GERENCIAR LANCES (LIVE SCOUT)",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => MatchLiveScoutScreen(match: vm.matchSnap))
          );
          await vm.reloadMatchData(preserveLineup: true);
          await vm.saveStats(); // Salva as presenças automaticamente (solicitação de melhoria)
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Partida e escalações sincronizadas!')));
          }
        },
      ),
    );
  }

  Widget _buildScoreCard(Map<String, dynamic> matchData, AdminMatchViewModel vm) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("PLACAR GERAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: Text(matchData['team_home_name'] ?? 'Casa', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                SizedBox(width: 50, child: TextField(controller: vm.homeScoreController, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none))),
                const Text('x', style: TextStyle(fontSize: 20, color: Colors.grey)),
                SizedBox(width: 50, child: TextField(controller: vm.awayScoreController, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none))),
                Expanded(child: Text(matchData['team_away_name'] ?? 'Fora', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatIcons(int goals, int assists, int yellows, int reds) {
    if (goals == 0 && assists == 0 && yellows == 0 && reds == 0) return const SizedBox(width: 1);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (goals > 0) _buildBadge(Icons.sports_soccer, Colors.black, goals),
        if (assists > 0) _buildBadge(Icons.assistant, Colors.blue, assists),
        if (yellows > 0) _buildBadge(Icons.style, Colors.amber[700]!, yellows),
        if (reds > 0) _buildBadge(Icons.style, Colors.red, reds),
      ],
    );
  }

  Widget _buildBadge(IconData icon, Color color, int count) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          if (count > 1) ...[
            const SizedBox(width: 2),
            Text("$count", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ]
        ],
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context, AdminMatchViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.smart_display, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Text(
                  "VÍDEOS DA PARTIDA (YOUTUBE)",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.red,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text("Adicionar Vídeo"),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _showAddEditMediaDialog(context, vm),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          "Insira links do YouTube (gols, melhores momentos, jogos completos) para reprodução na guia de Mídias.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (vm.mediaLinks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.video_library_outlined, color: Colors.grey[400], size: 36),
                  const SizedBox(height: 8),
                  const Text(
                    "Nenhum vídeo do YouTube vinculado a esta partida.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: vm.mediaLinks.length,
            itemBuilder: (ctx, idx) {
              final media = vm.mediaLinks[idx];
              final String title = media['title'] ?? 'Vídeo ${idx + 1}';
              final String videoUrl = media['videoUrl'] ?? '';
              final String? ytThumb = YoutubeUtils.getThumbnailUrl(videoUrl);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: ListTile(
                  dense: true,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 56,
                      height: 36,
                      child: ytThumb != null
                          ? CachedNetworkImage(
                              imageUrl: ytThumb,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[800],
                                child: const Icon(Icons.broken_image, size: 16, color: Colors.white),
                              ),
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: const Icon(Icons.video_file, size: 20, color: Colors.white),
                            ),
                    ),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(
                    videoUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Editar',
                        onPressed: () => _showAddEditMediaDialog(context, vm, editIndex: idx),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        tooltip: 'Remover',
                        onPressed: () => _confirmRemoveMedia(context, vm, idx),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showAddEditMediaDialog(
    BuildContext context,
    AdminMatchViewModel vm, {
    int? editIndex,
  }) async {
    final isEditing = editIndex != null;
    final initialTitle = isEditing ? (vm.mediaLinks[editIndex]['title'] ?? '') : '';
    final initialUrl = isEditing ? (vm.mediaLinks[editIndex]['videoUrl'] ?? '') : '';

    final titleCtrl = TextEditingController(text: initialTitle);
    final urlCtrl = TextEditingController(text: initialUrl);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentUrl = urlCtrl.text.trim();
            final videoId = YoutubeUtils.extractVideoId(currentUrl);
            final isValid = videoId != null;
            final thumbUrl = isValid ? YoutubeUtils.getThumbnailUrl(videoId) : null;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.smart_display, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(isEditing ? 'Editar Vídeo' : 'Adicionar Vídeo (YouTube)'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Título do Vídeo *',
                        hintText: 'Ex: Melhores Momentos, Gols do Jogo...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Link do YouTube *',
                        hintText: 'https://youtu.be/... ou youtube.com/watch?v=...',
                        border: const OutlineInputBorder(),
                        suffixIcon: isValid
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : (currentUrl.isNotEmpty
                                ? const Icon(Icons.error_outline, color: Colors.amber)
                                : null),
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (isValid && thumbUrl != null) ...[
                      const Text(
                        "Pré-visualização do YouTube:",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: thumbUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: Colors.black12,
                              child: const Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[300],
                              child: const Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
                        ),
                      ),
                    ] else if (currentUrl.isNotEmpty) ...[
                      const Text(
                        "⚠️ Link do YouTube inválido ou formato não reconhecido.",
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: (titleCtrl.text.trim().isNotEmpty && isValid)
                      ? () {
                          if (isEditing) {
                            vm.updateMediaLink(editIndex, titleCtrl.text, urlCtrl.text);
                          } else {
                            vm.addMediaLink(titleCtrl.text, urlCtrl.text);
                          }
                          Navigator.of(ctx).pop();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isEditing ? 'Atualizar' : 'Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    urlCtrl.dispose();
  }

  void _confirmRemoveMedia(BuildContext context, AdminMatchViewModel vm, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Vídeo?'),
        content: Text('Deseja remover "${vm.mediaLinks[index]['title']}" da lista de mídias desta partida?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              vm.removeMediaLink(index);
              Navigator.of(ctx).pop();
            },
            child: const Text('Remover', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}