import 'package:flutter/material.dart';

// --- SELETOR DE FASE (Estilo Segmented Control) ---
class ModernPhaseSelector<T> extends StatelessWidget {
  final T selectedValue;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const ModernPhaseSelector({
    super.key,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      height: 45,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: options.entries.map((entry) {
          final isSelected = entry.key == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected ? primaryColor : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// --- TIMELINE DE RODADAS (Lista Horizontal) ---
class HorizontalRoundSelector extends StatefulWidget {
  final int currentRound;
  final int totalRounds;
  final ValueChanged<int> onRoundChanged;

  const HorizontalRoundSelector({
    super.key,
    required this.currentRound,
    required this.totalRounds,
    required this.onRoundChanged,
  });

  @override
  State<HorizontalRoundSelector> createState() => _HorizontalRoundSelectorState();
}

class _HorizontalRoundSelectorState extends State<HorizontalRoundSelector> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Tenta centralizar a rodada selecionada após o build
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant HorizontalRoundSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRound != widget.currentRound) {
      _scrollToSelected();
    }
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    // Largura aproximada de cada item (50) + margem (8) = 58
    double targetOffset = (widget.currentRound - 1) * 58.0;
    // Centraliza na tela: Offset - (Tela/2) + (Item/2)
    double screenCenter = MediaQuery.of(context).size.width / 2;
    targetOffset = targetOffset - screenCenter + 29; 
    
    // Garante limites
    if (targetOffset < 0) targetOffset = 0;
    if (targetOffset > _scrollController.position.maxScrollExtent) {
      targetOffset = _scrollController.position.maxScrollExtent;
    }

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return SizedBox(
      height: 60,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: widget.totalRounds,
        itemBuilder: (context, index) {
          final int roundNum = index + 1;
          final bool isSelected = roundNum == widget.currentRound;

          return GestureDetector(
            onTap: () => widget.onRoundChanged(roundNum),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 50,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? primaryColor : Colors.grey.shade300,
                  width: 1.5
                ),
                boxShadow: isSelected 
                  ? [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0,2))]
                  : [],
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "ROD",
                    style: TextStyle(
                      fontSize: 9,
                      color: isSelected ? Colors.white70 : Colors.grey,
                      fontWeight: FontWeight.bold
                    ),
                  ),
                  Text(
                    "$roundNum",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- SELETOR DE MATA-MATA (Chips) ---
class PlayoffStageSelector<T> extends StatelessWidget {
  final T selectedStage;
  final Map<T, String> stages;
  final ValueChanged<T> onChanged;

  const PlayoffStageSelector({
    super.key,
    required this.selectedStage,
    required this.stages,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: stages.entries.map((entry) {
          final isSelected = entry.key == selectedStage;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (_) => onChanged(entry.key),
              selectedColor: primaryColor,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isSelected ? primaryColor : Colors.grey.shade300),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}