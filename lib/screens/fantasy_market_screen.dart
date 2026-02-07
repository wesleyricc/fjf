import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../services/championship_service.dart'; 
import '../models/fantasy_models.dart';
import '../widgets/fantasy_player_card.dart';

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
  // Padrão inicia como Goleiro, já que "Todos" foi removido
  String _selectedPosition = 'Goleiro'; 
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  
  // Lista de posições sem a opção "Todos"
  final List<String> _positions = ['Goleiro', 'Fixo', 'Ala', 'Pivô', 'Técnico'];

  @override
  void initState() {
    super.initState();
    // Se vier uma posição obrigatória (ex: clicou no slot de Ala), seleciona ela.
    // Caso contrário, mantém o padrão (Goleiro).
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erro: Nenhuma temporada ativa identificada."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Sincronizando mercado com a temporada $seasonId..."))
    );
    
    final result = await fantasyService.populateMarketFromSeason(seasonId); 
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.isSelectionMode) {
              Navigator.pop(context);
            } else {
              Navigator.of(context).pushNamedAndRemoveUntil('/fantasy-home', (route) => route.isFirst);
            }
          },
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
                
                // Desabilita troca de filtro se estiver em modo de seleção restrita
                // (Ex: Clicou para trocar um Ala, só pode ver Ala)
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
              // Passamos diretamente a _selectedPosition, pois ela nunca será "Todos" ou null
              stream: fantasyService.streamMarket(
                positionFilter: _selectedPosition,
                searchTerm: _searchTerm,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                var players = snapshot.data ?? [];
                
                // Filtro de segurança no cliente (caso o delay do stream traga dados antigos)
                if (_selectedPosition.isNotEmpty) {
                  players = players.where((p) => p.position == _selectedPosition).toList();
                }

                if (players.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text("Nenhum ${_selectedPosition} encontrado."),
                        const SizedBox(height: 24),
                        
                        // Botão Admin para sincronizar se estiver vazio
                        // (Idealmente mostrar só para admin, mas deixamos acessível por enquanto para facilitar testes)
                        ElevatedButton.icon(
                          onPressed: () => _populateMarket(context),
                          icon: const Icon(Icons.cloud_download),
                          label: const Text("Sincronizar Dados"),
                        )
                      ],
                    ),
                  );
                }

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
}