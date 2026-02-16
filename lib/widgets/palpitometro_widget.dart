import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PalpitometroWidget extends StatefulWidget {
  final String seasonId;
  final String matchId;
  final String homeTeamName;
  final String awayTeamName;
  final Color homeColor;
  final Color awayColor;
  final int homeVotes;
  final int awayVotes;
  final bool isClosed;
  
  // Design
  final double barHeight;
  final bool compactView;

  const PalpitometroWidget({
    super.key,
    required this.seasonId,
    required this.matchId,
    required this.homeTeamName,
    required this.awayTeamName,
    this.homeColor = Colors.blue,
    this.awayColor = Colors.red,
    required this.homeVotes,
    required this.awayVotes,
    this.isClosed = false,
    this.barHeight = 24.0, 
    this.compactView = false,
  });

  @override
  State<PalpitometroWidget> createState() => _PalpitometroWidgetState();
}

class _PalpitometroWidgetState extends State<PalpitometroWidget> {
  bool _hasVoted = false;
  bool _isVoting = false;

  @override
  void initState() {
    super.initState();
    _checkIfVoted();
  }

  Future<void> _checkIfVoted() async {
    final prefs = await SharedPreferences.getInstance();
    final voted = prefs.getBool('voted_${widget.matchId}') ?? false;
    if (mounted) setState(() => _hasVoted = voted);
  }

  Future<void> _vote(String teamField) async {
    if (_hasVoted || _isVoting || widget.isClosed) return;
    setState(() => _isVoting = true);

    try {
      await FirebaseFirestore.instance
          .collection('championships')
          .doc(widget.seasonId)
          .collection('matches')
          .doc(widget.matchId)
          .update({
        teamField: FieldValue.increment(1),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('voted_${widget.matchId}', true);

      if (mounted) setState(() { _hasVoted = true; _isVoting = false; });
    } catch (e) {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalVotes = widget.homeVotes + widget.awayVotes;
    
    // Mostra resultados se já votou ou se o jogo está fechado
    final bool showResults = _hasVoted || widget.isClosed;

    double homePercent = 0.5;
    double awayPercent = 0.5;
    
    if (totalVotes > 0) {
      homePercent = widget.homeVotes / totalVotes;
      awayPercent = widget.awayVotes / totalVotes;
    }

    // --- LÓGICA CORRIGIDA: LARGURA MÍNIMA PARA VOTAÇÃO ---
    int homeFlex = 50;
    int awayFlex = 50;

    if (totalVotes > 0) {
      int rawHomeFlex = (homePercent * 100).toInt();
      
      // Se não fechou a votação, garante espaço mínimo para clicar no time perdedor
      if (!widget.isClosed) {
        // Garante que nenhum lado fique menor que 15% (para ser clicável)
        if (rawHomeFlex > 85) rawHomeFlex = 85;
        if (rawHomeFlex < 15) rawHomeFlex = 15;
      } else {
        // Se fechado, pode mostrar 100% real (pois não precisa mais clicar)
        // Opcional: manter o clamp se quiser consistência visual
        // Vamos manter o cálculo real para exibição final
        rawHomeFlex = (homePercent * 100).toInt();
        // Pequeno ajuste para não sumir bordas arredondadas se for 100%
        if (rawHomeFlex == 100) rawHomeFlex = 98; 
        if (rawHomeFlex == 0) rawHomeFlex = 2;
      }

      homeFlex = rawHomeFlex;
      awayFlex = 100 - rawHomeFlex;
    }
    // -----------------------------------------------------

    final homePercentText = "${(homePercent * 100).toStringAsFixed(0)}%";
    final awayPercentText = "${(awayPercent * 100).toStringAsFixed(0)}%";

    String headerText = "Quem vence?";
    Color headerColor = Colors.grey;
    if (widget.isClosed) {
      headerText = "Votação Encerrada";
    } else if (_hasVoted) {
      headerText = "Seu palpite foi registrado";
      headerColor = Colors.green;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.compactView)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_hasVoted && !widget.isClosed) const Icon(Icons.check_circle, size: 12, color: Colors.green),
                if (_hasVoted && !widget.isClosed) const SizedBox(width: 4),
                Text(
                  headerText, 
                  style: TextStyle(
                    fontSize: 11, 
                    color: headerColor, 
                    fontWeight: FontWeight.bold
                  )
                ),
              ],
            ),
          ),
        
        // BARRA
        SizedBox(
          height: widget.barHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.barHeight / 2),
            child: Row(
              children: [
                // TIME CASA
                Expanded(
                  flex: homeFlex,
                  child: InkWell(
                    onTap: (!showResults) ? () => _vote('votes_home') : null,
                    child: Container(
                      color: widget.homeColor.withOpacity(showResults ? 1.0 : 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.homeTeamName, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10), 
                              overflow: TextOverflow.ellipsis
                            ),
                          ),
                          if (showResults && totalVotes > 0) 
                            Text(homePercentText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // DIVISOR (Apenas visual se ambos existirem, mas aqui sempre existem por causa do flex mínimo)
                Container(width: 1, color: Colors.white),

                // TIME FORA
                Expanded(
                  flex: awayFlex,
                  child: InkWell(
                    onTap: (!showResults) ? () => _vote('votes_away') : null,
                    child: Container(
                      color: widget.awayColor.withOpacity(showResults ? 1.0 : 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (showResults && totalVotes > 0) 
                            Text(awayPercentText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.awayTeamName, 
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10), 
                              overflow: TextOverflow.ellipsis
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        //if (totalVotes > 0 && !widget.compactView)
          //Padding(
            //padding: const EdgeInsets.only(top: 4.0),
            //child: Text(
              //"$totalVotes votos computados",
              //textAlign: TextAlign.center,
              //style: TextStyle(fontSize: 9, color: Colors.grey[400]),
            //),
          //),
      ],
    );
  }
}