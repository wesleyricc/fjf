// lib/screens/player_comparison_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/app_drawer.dart'; // <--- 1. Importar o Drawer
import '../widgets/sponsor_banner_rotator.dart';

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
    _fetchAllTeams();
  }

  Future<void> _fetchAllTeams() async {
    try {
      final snapshot = await _firestore
          .collection('teams')
          .orderBy('name')
          .get();
      
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
                              child: Text(
                                selectedTeamName, 
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
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
                                      
                                      final bool isAlreadySelected = 
                                          (player.id == _player1?.id) || (player.id == _player2?.id);
                                      
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            color: isAlreadySelected ? Colors.grey : Colors.black,
                                          ),
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

  /*String _calculateAge(Timestamp? dobTimestamp) {
    if (dobTimestamp == null) return '-';
    final DateTime dob = dobTimestamp.toDate();
    final DateTime today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return '$age anos';
  }*/

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comparador de Atletas')),
      drawer: const AppDrawer(), // <--- 2. Adicionar o Drawer aqui
      body: _isLoadingTeams
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.amber[50],
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: const Text(
                    'Estatísticas - Temporada Atual',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Expanded(child: _buildPlayerHeader(1, _player1)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text("VS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.grey)),
                      ),
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
                               /*Builder(
                                 builder: (context) {
                                   final d1 = _player1!.data() as Map<String, dynamic>;
                                   final d2 = _player2!.data() as Map<String, dynamic>;

                                   final age1 = _calculateAge(d1['date_of_birth']);
                                   final age2 = _calculateAge(d2['date_of_birth']);
                                   
                                   final h1 = d1['height_cm'] != null ? '${d1['height_cm']} cm' : '-';
                                   final h2 = d2['height_cm'] != null ? '${d2['height_cm']} cm' : '-';

                                   final w1 = d1['weight_kg'] != null ? '${d1['weight_kg']} kg' : '-';
                                   final w2 = d2['weight_kg'] != null ? '${d2['weight_kg']} kg' : '-';

                                   final f1 = d1['preferred_foot'] ?? '-';
                                   final f2 = d2['preferred_foot'] ?? '-';

                                   return Column(
                                     children: [
                                       _buildPhysicalRow('Idade', age1, age2),
                                       _buildPhysicalRow('Altura', h1, h2),
                                       _buildPhysicalRow('Peso', w1, w2),
                                       _buildPhysicalRow('Pé', f1, f2),
                                       
                                       const Divider(thickness: 8, color: Color(0xFFEEEEEE)),
                                       const SizedBox(height: 8),
                                     ],
                                   );
                                 }
                               ),*/

                               _buildComparisonRow('Gols', 'goals', higherIsBetter: true),
                               
                               _buildComparisonRow('Assistências', 'assists', higherIsBetter: true),
                               
                               _buildComparisonRow(
                                 'Participações', 
                                 'goals', 
                                 secondaryField: 'assists', 
                                 labelOverride: 'Participações em Gols',
                                 higherIsBetter: true
                               ),

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
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[300],
              child: const Icon(Icons.add, size: 40, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _showSelectionFlow(slot),
            style: ElevatedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white
            ),
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
                backgroundImage: (data['photo_url'] != null && data['photo_url'] != '')
                    ? CachedNetworkImageProvider(data['photo_url'])
                    : null,
                child: (data['photo_url'] == null || data['photo_url'] == '')
                    ? const Icon(Icons.person, size: 50, color: Colors.grey)
                    : null,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (slot == 1) _player1 = null; else _player2 = null;
                  });
                },
                child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)),
              ),
            )
          ],
        ),
        const SizedBox(height: 8),
        Text(
          number != null ? '#$number - $name' : name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        Text(
          data['team_name'] ?? '', 
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  /*Widget _buildPhysicalRow(String label, String value1, String value2) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value1, 
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              label, 
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              value2, 
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }*/

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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              val1.toString(), 
              style: TextStyle(fontSize: 18, color: color1, fontWeight: weight1),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              labelOverride ?? label, 
              style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              val2.toString(), 
              style: TextStyle(fontSize: 18, color: color2, fontWeight: weight2),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}