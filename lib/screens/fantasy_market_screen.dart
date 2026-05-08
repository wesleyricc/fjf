import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/championship_service.dart'; 
import '../models/fantasy_models.dart';
import '../widgets/fantasy_player_card.dart';
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  

class FantasyMarketScreen extends StatefulWidget {
  final bool isSelectionMode;
  final String? requiredPosition;
  final double? maxBudget;

  const FantasyMarketScreen({
    super.key,
    this.isSelectionMode = false,
    this.requiredPosition,
    this.maxBudget,
  });

  @override
  State<FantasyMarketScreen> createState() => _FantasyMarketScreenState();
}

class _FantasyMarketScreenState extends State<FantasyMarketScreen> {
  String _selectedPosition = 'Goleiro'; 
  String _selectedTeamId = 'Todos'; // 🚨 Usamos o ID no código, mas mostraremos o nome na tela!
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  
  final List<String> _positions = ['Goleiro', 'Fixo', 'Ala', 'Pivô', 'Técnico'];

  @override
  void initState() {
    super.initState();
    if (widget.requiredPosition != null) {
      _selectedPosition = widget.requiredPosition!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _populateMarket(BuildContext context) async {
    final fantasyService = context.read<FantasyService>();
    final championshipService = context.read<ChampionshipService>();
    final seasonId = championshipService.currentSeasonId;

    if (seasonId.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erro: Nenhuma temporada ativa."), backgroundColor: Colors.red));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sincronizando mercado...")));
    final result = await fantasyService.populateMarketFromSeason(seasonId); 
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
  }

  @override
  Widget build(BuildContext context) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    
    // 🚨 1. Pega os times oficiais que já estão na memória do aplicativo
    final championshipService = Provider.of<ChampionshipService>(context, listen: false);
    
    // 🚨 2. Cria o Dicionário de Tradução: ID do Time -> Nome do Time
    final Map<String, String> teamDictionary = {};
    for (var team in championshipService.teams) {
      // Ajuste 'team.id' e 'team.name' se as propriedades do seu modelo Team se chamarem diferente
      teamDictionary[team.id] = team.name; 
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mercado FJF", style: TextStyle(fontSize: 18)),
            if (widget.isSelectionMode && widget.maxBudget != null)
              Text(
                "Orçamento: C\$ ${widget.maxBudget!.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              )
          ],
        ),
      ),
      body: Column(
        children: [
          // Barra de Filtros (Posições)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _positions.length,
              itemBuilder: (ctx, i) {
                final pos = _positions[i];
                final isSelected = _selectedPosition == pos;
                final bool isDisabled = widget.requiredPosition != null && widget.requiredPosition != pos; 

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(pos),
                    selected: isSelected,
                    onSelected: isDisabled ? null : (_) => setState(() => _selectedPosition = pos),
                    backgroundColor: Colors.white,
                    selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? Theme.of(context).primaryColor : (isDisabled ? Colors.grey : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    showCheckmark: false,
                  ),
                );
              },
            ),
          ),
          
          Expanded(
            child: StreamBuilder<List<FantasyPlayer>>(
              stream: fantasyService.streamMarket(
                positionFilter: _selectedPosition,
                searchTerm: _searchTerm,
              ),
              builder: (context, snapshot) {

                if (snapshot.hasError) {
                  return CustomEmptyState.offline(
                    onRetry: () => setState(() {}), 
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: 8,
                    itemBuilder: (ctx, i) => _buildSkeletonPlayerCard(),
                  );
                }
                
                var players = List<FantasyPlayer>.from(snapshot.data ?? []);
                
                // --- 🚨 LÓGICA DE TRADUÇÃO DOS TIMES PARA O DROPDOWN 🚨 ---
                
                // A. Pega apenas os IDs dos times que têm jogadores disponíveis
                final Set<String> uniqueTeamIds = {};
                for (var p in players) {
                  if (p.teamId.isNotEmpty) uniqueTeamIds.add(p.teamId); 
                }

                // B. Constrói a lista amigável com os nomes
                final List<Map<String, String>> teamOptions = [
                  {'id': 'Todos', 'name': 'Todos as Equipes'}
                ];

                for (var tId in uniqueTeamIds) {
                  // Traduz o ID. Se por acaso não achar no dicionário, mostra "Equipe Desconhecida"
                  final String teamName = teamDictionary[tId] ?? 'Equipe Desconhecida';
                  teamOptions.add({'id': tId, 'name': teamName});
                }

                // C. Ordena os times por Ordem Alfabética (pelo Nome, não pelo ID)
                final todosOption = teamOptions.removeAt(0); // Tira o "Todos" temporariamente
                teamOptions.sort((a, b) => a['name']!.compareTo(b['name']!)); // Ordena
                teamOptions.insert(0, todosOption); // Coloca o "Todos" no topo de volta

                // Proteção contra erro se o time sumir do filtro ao mudar a posição
                if (!teamOptions.any((t) => t['id'] == _selectedTeamId)) {
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                     if (mounted) setState(() => _selectedTeamId = 'Todos');
                   });
                }

                // --- APLICAÇÃO DOS FILTROS E ORDENAÇÃO ---

                // 2. Filtro Local de Posição
                if (_selectedPosition.isNotEmpty) {
                  players = players.where((p) => p.position == _selectedPosition).toList();
                }

                // 3. Filtro Local de Equipe (Usando o ID por baixo dos panos)
                if (_selectedTeamId != 'Todos') {
                  players = players.where((p) => p.teamId == _selectedTeamId).toList();
                }

                // 4. Ordenação Decrescente por Preço
                players.sort((a, b) => b.currentPrice.compareTo(a.currentPrice));

                return Column(
                  children: [
                    // --- DROPDOWN DO FILTRO DE EQUIPES (MOSTRANDO NOMES BONITOS) ---
                    if (teamOptions.length > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            const Text("Equipe:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: teamOptions.any((t) => t['id'] == _selectedTeamId) ? _selectedTeamId : 'Todos',
                                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 14),
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                                  items: teamOptions.map((teamData) {
                                    return DropdownMenuItem<String>(
                                      value: teamData['id'], // Valor técnico
                                      child: Text(teamData['name']!, overflow: TextOverflow.ellipsis), // Texto para o Usuário
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedTeamId = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                    const Divider(height: 1, thickness: 1),

                    // --- LISTAGEM FINAL DE ATLETAS ---
                    Expanded(
                      child: players.isEmpty 
                        ? CustomEmptyState(
                            icon: Icons.search_off,
                            title: "Nenhum Atleta",
                            message: "Não encontramos atletas para os filtros selecionados.",
                            buttonText: "Limpar Filtros",
                            onButtonPressed: () => setState(() {
                               _selectedTeamId = 'Todos';
                               _searchTerm = '';
                            }),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: players.length,
                            itemBuilder: (ctx, i) {
                              final player = players[i];
                              final bool canAfford = widget.maxBudget == null || player.currentPrice <= widget.maxBudget!;

                              return Opacity(
                                opacity: canAfford ? 1.0 : 0.5,
                                child: FantasyPlayerCard(
                                  player: player,
                                  onTap: () {
                                    if (widget.isSelectionMode) {
                                      if (canAfford) {
                                        Navigator.pop(context, player);
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Saldo insuficiente.")),
                                        );
                                      }
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonPlayerCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: const [
            ShimmerEffect.circular(size: 56), 
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerEffect.rectangular(height: 16, width: 150), 
                  SizedBox(height: 8),
                  ShimmerEffect.rectangular(height: 12, width: 80), 
                ],
              ),
            ),
            ShimmerEffect.rectangular(height: 20, width: 60), 
          ],
        ),
      ),
    );
  }
}