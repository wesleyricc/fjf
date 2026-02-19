import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/championship_service.dart'; 
import '../models/fantasy_models.dart';
import '../widgets/fantasy_player_card.dart';
import '../widgets/ui/shimmer_effect.dart';     // <-- NOVO
import '../widgets/ui/custom_empty_state.dart';  // <-- NOVO

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
  // Padrão inicia como Goleiro
  String _selectedPosition = 'Goleiro'; 
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mercado Futsal", style: TextStyle(fontSize: 18)),
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
          // Barra de Filtros (Chips)
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
                // 1. Loading
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: 8,
                    itemBuilder: (ctx, i) => _buildSkeletonPlayerCard(),
                  );
                }
                
                var players = snapshot.data ?? [];
                
                if (_selectedPosition.isNotEmpty) {
                  players = players.where((p) => p.position == _selectedPosition).toList();
                }

                // 2. Empty State
                if (players.isEmpty) {
                  return CustomEmptyState(
                    icon: Icons.search_off,
                    title: "Nenhum Atleta",
                    message: "Não encontramos atletas para a posição $_selectedPosition.",
                    buttonText: "Sincronizar (Admin)",
                    onButtonPressed: () => _populateMarket(context),
                  );
                }

                // 3. Data
                return ListView.builder(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- SKELETON DO JOGADOR ---
  Widget _buildSkeletonPlayerCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            const ShimmerEffect.circular(size: 56), // Avatar
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerEffect.rectangular(height: 16, width: 150), // Nome
                  SizedBox(height: 8),
                  ShimmerEffect.rectangular(height: 12, width: 80), // Posição
                ],
              ),
            ),
            const ShimmerEffect.rectangular(height: 20, width: 60), // Preço
          ],
        ),
      ),
    );
  }
}