import 'package:flutter/material.dart';

class TrophyRoomWidget extends StatefulWidget {
  final List<dynamic>? historyList;

  const TrophyRoomWidget({super.key, required this.historyList});

  @override
  State<TrophyRoomWidget> createState() => _TrophyRoomWidgetState();
}

class _TrophyRoomWidgetState extends State<TrophyRoomWidget> {
  late ScrollController _scrollController;
  bool _showScrollIndicator = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_checkScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScroll() {
    if (!mounted) return;
    bool shouldShow = false;
    if (_scrollController.hasClients) {
      shouldShow = _scrollController.position.maxScrollExtent > 5.0;
    }
    if (shouldShow != _showScrollIndicator) {
      setState(() => _showScrollIndicator = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.historyList == null || widget.historyList!.isEmpty) {
      return const SizedBox.shrink();
    }

    final trophyWidgets = widget.historyList!.map((item) {
      if (item is! Map) return const SizedBox.shrink();
      final data = item as Map<String, dynamic>;
      final int rank = data['rank'] ?? 0;
      final String year = (data['year'] ?? '????').toString();
      
      Color trophyColor;
      if (rank == 1) trophyColor = Colors.amber;
      else if (rank == 2) trophyColor = Colors.grey[600]!;
      else trophyColor = Colors.brown;

      if (rank > 2) return const SizedBox.shrink(); // Mostra apenas Ouro e Prata

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: Column(
          children: [
            Icon(Icons.emoji_events, color: trophyColor, size: 30),
            const SizedBox(height: 4),
            Text(year, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 12)),
          ],
        ),
      );
    }).toList();

    if (trophyWidgets.every((w) => w is SizedBox)) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('Sala de Troféus', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            const Divider(),
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Center(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 2.0, left: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [...trophyWidgets, const SizedBox(width: 20)],
                    ),
                  ),
                ),
                if (_showScrollIndicator)
                  IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.only(left: 8.0),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.centerRight,
                          radius: 1.5,
                          colors: [Theme.of(context).cardColor.withOpacity(0.8), Theme.of(context).cardColor.withOpacity(0.0)],
                        ),
                      ),
                      child: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}