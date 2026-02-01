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
    
    double homePercent = 0.5;
    double awayPercent = 0.5;
    if (totalVotes > 0) {
      homePercent = widget.homeVotes / totalVotes;
      awayPercent = widget.awayVotes / totalVotes;
    }

    int homeFlex = (homePercent * 100).toInt();
    int awayFlex = (awayPercent * 100).toInt();
    
    if (totalVotes == 0) {
      homeFlex = 50;
      awayFlex = 50;
    }

    final homePercentText = "${(homePercent * 100).toStringAsFixed(0)}%";
    final awayPercentText = "${(awayPercent * 100).toStringAsFixed(0)}%";

    // --- MUDANÇA AQUI: TEXTO DO CABEÇALHO ---
    String headerText = "Quem vence? Dê seu palpite!";
    
    if (widget.isClosed) {
      headerText = "Votação Encerrada";
    } else if (_hasVoted) {
      // Removemos a contagem total, mantendo apenas a confirmação
      headerText = "Voto registrado com sucesso!"; 
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Center(
            child: Text(
              headerText, 
              style: TextStyle(
                fontSize: 12, 
                color: _hasVoted ? Colors.green : Colors.grey, 
                fontWeight: FontWeight.bold
              )
            ),
          ),
        ),
        
        Container(
          height: 40,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))]
          ),
          child: Row(
            children: [
              if (homeFlex > 0)
                Expanded(
                  flex: homeFlex,
                  child: InkWell(
                    onTap: (_hasVoted || widget.isClosed) ? null : () => _vote('votes_home'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      color: widget.homeColor.withOpacity((_hasVoted || widget.isClosed) ? 1.0 : 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Expanded(child: Text(widget.homeTeamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis)),
                          if (totalVotes > 0) Text(homePercentText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                ),
              
              if (homeFlex > 0 && awayFlex > 0)
                Container(width: 1, color: Colors.white),

              if (awayFlex > 0)
                Expanded(
                  flex: awayFlex,
                  child: InkWell(
                    onTap: (_hasVoted || widget.isClosed) ? null : () => _vote('votes_away'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      color: widget.awayColor.withOpacity((_hasVoted || widget.isClosed) ? 1.0 : 0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (totalVotes > 0) Text(awayPercentText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(widget.awayTeamName, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}