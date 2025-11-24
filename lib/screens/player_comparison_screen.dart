import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart'; // <-- Importante
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../services/firestore_service.dart';
import '../services/championship_service.dart'; // <-- Importante

class PlayerComparisonScreen extends StatefulWidget {
  const PlayerComparisonScreen({super.key});

  @override
  State<PlayerComparisonScreen> createState() => _PlayerComparisonScreenState();
}

class _PlayerComparisonScreenState extends State<PlayerComparisonScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<DocumentSnapshot> _allTeams = [];
  bool _isLoadingTeams = true;

  DocumentSnapshot? _player1;
  DocumentSnapshot? _player2;

  @override
  void initState() {
    super.initState();
    // Chamada inicial sem contexto (será carregado no didChangeDependencies ou build)
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Carrega times quando as dependências (Provider) estiverem prontas
    _fetchAllTeams();
  }

  Future<void> _fetchAllTeams() async {
    // 1. Pega a Temporada
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    try {
      Query query;
      if (seasonId == FirestoreService.LEGACY_ID) {
        query = _firestore.collection('teams').orderBy('name');
      } else {
        query = _firestore.collection('championships').doc(seasonId).collection('teams_participation').orderBy('name');
      }

      final snapshot = await query.get();
      
      if (mounted) {
        setState(() {
          _allTeams = snapshot.docs;
          _isLoadingTeams = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar times: $e");
      if (mounted) setState(() => _isLoadingTeams = false);
    }
  }

  Future<void> _showSelectionFlow(int slot) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        int step = 0;
        List<DocumentSnapshot> teamPlayers = [];
        bool isLoadingPlayers = false;
        String selectedTeamName = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                step == 0 ? '1. Escolha o Time' : '2. Escolha o Jogador',
                style: TextStyle(fontSize: 18, color: Theme.of(context).primaryColor),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (step == 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () {
                                setDialogState(() {
                                  step = 0;
                                  teamPlayers = [];
                                });
                              },
                            ),
                            Expanded(
                              child: Text(selectedTeamName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: isLoadingPlayers 
                        ? const Center(child: CircularProgressIndicator())
                        : step == 0 
                            ? ListView.builder(
                                itemCount: _allTeams.length,
                                itemBuilder: (ctx, index) {
                                  final team = _allTeams[index];
                                  final data = team.data() as Map<String, dynamic>;
                                  return ListTile(
                                    leading: SizedBox(
                                      width: 30, height: 30,
                                      child: CachedNetworkImage(
                                        imageUrl: data['shield_url'] ?? '',
                                        placeholder: (c, u) => const Icon(Icons.shield),
                                        errorWidget: (c, u, e) => const Icon(Icons.shield),
                                      ),
                                    ),
                                    title: Text(data['name'] ?? 'Time'),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                    onTap: () async {
                                      setDialogState(() {
                                        isLoadingPlayers = true;
                                        selectedTeamName = data['name'];
                                      });
                                      
                                      try {
                                        // Jogadores ainda são Globais na arquitetura atual
                                        // Então buscamos na coleção raiz filtrando pelo ID do time
                                        final pSnaps = await _firestore
                                            .collection('players')
                                            .where('team_id', isEqualTo: team.id)
                                            .where('isActive', isEqualTo: true)
                                            .where('is_staff', isEqualTo: false)
                                            .orderBy('jersey_number')
                                            .get();

                                        if (context.mounted) {
                                          setDialogState(() {
                                            teamPlayers = pSnaps.docs;
                                            step = 1;
                                            isLoadingPlayers = false;
                                          });
                                        }
                                      } catch (e) {
                                        debugPrint("Erro buscar players: $e");
                                        setDialogState(() => isLoadingPlayers = false);
                                      }
                                    },
                                  );
                                },
                              )
                            : teamPlayers.isEmpty 
                                ? const Center(child: Text('Nenhum jogador encontrado.'))
                                : ListView.builder(
                                    itemCount: teamPlayers.length,
                                    itemBuilder: (ctx, index) {
                                      final player = teamPlayers[index];
                                      final pData = player.data() as Map<String, dynamic>;
                                      final bool isAlreadySelected = (player.id == _player1?.id) || (player.id == _player2?.id);
                                      final int? number = pData['jersey_number'];
                                      final String name = pData['name'] ?? 'Nome';

                                      return ListTile(
                                        enabled: !isAlreadySelected,
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: Colors.grey[200],
                                          backgroundImage: (pData['photo_url'] != null && pData['photo_url'] != '')
                                              ? CachedNetworkImageProvider(pData['photo_url'])
                                              : null,
                                          child: (pData['photo_url'] == null || pData['photo_url'] == '')
                                              ? const Icon(Icons.person, size: 20, color: Colors.grey)
                                              : null,
                                        ),
                                        title: Text(
                                          number != null ? '#$number - $name' : name,
                                          style: TextStyle(fontWeight: FontWeight.w500, color: isAlreadySelected ? Colors.grey : Colors.black),
                                        ),
                                        subtitle: Text(pData['position'] ?? 'Jogador'),
                                        onTap: isAlreadySelected ? null : () {
                                          setState(() {
                                            if (slot == 1) _player1 = player;
                                            else _player2 = player;
                                          });
                                          Navigator.of(ctx).pop();
                                        },
                                      );
                                    },
                                  ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Consome o serviço apenas para mostrar o nome na AppBar (opcional)
    final seasonName = Provider.of<ChampionshipService>(context).currentSeasonName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comparador de Atletas'),
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: _isLoadingTeams
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.amber[50],
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: const Text('Estatísticas - Temporada Selecionada', textAlign: TextAlign.center, style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Expanded(child: _buildPlayerHeader(1, _player1)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("VS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.grey))),
                      Expanded(child: _buildPlayerHeader(2, _player2)),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 2),
                Expanded(
                  child: (_player1 == null || _player2 == null)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.compare_arrows, size: 60, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              const Text('Selecione dois atletas para comparar.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Column(
                            children: [
                               _buildComparisonRow('Gols', 'goals', higherIsBetter: true),
                               _buildComparisonRow('Assistências', 'assists', higherIsBetter: true),
                               _buildComparisonRow('Participações', 'goals', secondaryField: 'assists', labelOverride: 'Participações em Gols', higherIsBetter: true),
                               _buildComparisonRow('Cartões Amarelos', 'total_yellow_cards', higherIsBetter: false),
                               _buildComparisonRow('Cartões Vermelhos', 'total_red_cards', higherIsBetter: false),
                               _buildComparisonRow('Craque do Jogo', 'man_of_the_match_awards', higherIsBetter: true),
                               if ((_player1!['is_goalkeeper'] ?? false) || (_player2!['is_goalkeeper'] ?? false))
                                 _buildComparisonRow('Gols Sofridos', 'goals_conceded', higherIsBetter: false),
                            ],
                          ),
                        ),
                ),
              ],
            ),
            bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  Widget _buildPlayerHeader(int slot, DocumentSnapshot? player) {
    if (player == null) {
      return Column(
        children: [
          GestureDetector(
            onTap: () => _showSelectionFlow(slot),
            child: CircleAvatar(radius: 40, backgroundColor: Colors.grey[300], child: const Icon(Icons.add, size: 40, color: Colors.grey)),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _showSelectionFlow(slot),
            style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact, backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
            child: const Text('Selecionar'),
          ),
        ],
      );
    }

    final data = player.data() as Map<String, dynamic>;
    final int? number = data['jersey_number'];
    final String name = data['name'] ?? '';

    return Column(
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            GestureDetector(
               onTap: () => _showSelectionFlow(slot),
               child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.grey[200],
                backgroundImage: (data['photo_url'] != null && data['photo_url'] != '') ? CachedNetworkImageProvider(data['photo_url']) : null,
                child: (data['photo_url'] == null || data['photo_url'] == '') ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
              ),
            ),
            Positioned(
              right: 0, top: 0,
              child: GestureDetector(
                onTap: () {
                  setState(() { if (slot == 1) _player1 = null; else _player2 = null; });
                },
                child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)),
              ),
            )
          ],
        ),
        const SizedBox(height: 8),
        Text(number != null ? '#$number - $name' : name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 1),
        Text(data['team_name'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 1),
      ],
    );
  }

  Widget _buildComparisonRow(String label, String fieldKey, {String? secondaryField, String? labelOverride, required bool higherIsBetter}) {
    final data1 = _player1!.data() as Map<String, dynamic>;
    final data2 = _player2!.data() as Map<String, dynamic>;

    num val1 = (data1[fieldKey] ?? 0) + (secondaryField != null ? (data1[secondaryField] ?? 0) : 0);
    num val2 = (data2[fieldKey] ?? 0) + (secondaryField != null ? (data2[secondaryField] ?? 0) : 0);

    Color color1 = Colors.black;
    Color color2 = Colors.black;
    FontWeight weight1 = FontWeight.normal;
    FontWeight weight2 = FontWeight.normal;

    if (val1 != val2) {
      if (higherIsBetter) {
        if (val1 > val2) { color1 = Colors.green[700]!; weight1 = FontWeight.bold; }
        else { color2 = Colors.green[700]!; weight2 = FontWeight.bold; }
      } else {
        if (val1 < val2) { color1 = Colors.green[700]!; weight1 = FontWeight.bold; }
        else { color2 = Colors.green[700]!; weight2 = FontWeight.bold; }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Expanded(child: Text(val1.toString(), style: TextStyle(fontSize: 18, color: color1, fontWeight: weight1), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(labelOverride ?? label, style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
          Expanded(child: Text(val2.toString(), style: TextStyle(fontSize: 18, color: color2, fontWeight: weight2), textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}