import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_league_model.dart';

class FantasyLeagueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🚨 OTIMIZAÇÃO FINOPS: Cache de Rankings de Ligas Privadas
  final Map<String, List<Map<String, dynamic>>> _rankingCache = {};
  final Map<String, DateTime> _lastRankingFetch = {};

  // Gerador de código estilo "X7B9K2"
  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // 1. Criar Liga
  Future<String> createLeague(String name, String userId, {String type = 'classic', int? maxTeams}) async {
    final String inviteCode = _generateInviteCode();
    
    final newLeague = FantasyLeague(
      id: '', 
      name: name.trim(),
      inviteCode: inviteCode,
      ownerId: userId,
      members: [userId], 
      type: type,
      maxTeams: maxTeams,
      status: type == 'knockout' ? 'waiting' : 'active',
    );

    await _firestore.collection('fantasy_leagues').add(newLeague.toMap());
    return inviteCode;
  }

  // 2. Entrar na Liga com Código
  Future<String?> joinLeague(String inviteCode, String userId) async {
    final String cleanCode = inviteCode.trim().toUpperCase();

    final query = await _firestore
        .collection('fantasy_leagues')
        .where('invite_code', isEqualTo: cleanCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return "Código inválido. Nenhuma liga encontrada.";
    }

    final doc = query.docs.first;
    final data = doc.data();
    final List<dynamic> currentMembers = data['members'] ?? [];

    if (currentMembers.contains(userId)) {
      return "Você já participa desta liga!";
    }

    final int? maxTeams = data['max_teams'];
    if (maxTeams != null && currentMembers.length >= maxTeams) {
      return "A liga já atingiu o limite máximo de times ($maxTeams).";
    }

    await doc.reference.update({
      'members': FieldValue.arrayUnion([userId])
    });

    return null; 
  }

  // 2.1. Entrar em Liga Patrocinada (Sem Código)
  Future<String?> joinSponsoredLeague(String leagueId, String userId) async {
    final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();

    if (!doc.exists) {
      return "Liga não encontrada.";
    }

    final data = doc.data()!;
    final bool isSponsored = data['is_sponsored'] ?? false;
    
    if (!isSponsored) {
      return "Esta não é uma liga patrocinada aberta.";
    }

    final List<dynamic> currentMembers = data['members'] ?? [];

    if (currentMembers.contains(userId)) {
      return "Você já participa desta liga!";
    }

    await doc.reference.update({
      'members': FieldValue.arrayUnion([userId])
    });

    return null; 
  }

  // 2.2 Sair de uma Liga
  Future<String?> leaveLeague(String leagueId, String userId) async {
    final doc = await _firestore.collection('fantasy_leagues').doc(leagueId).get();

    if (!doc.exists) {
      return "Liga não encontrada.";
    }

    final data = doc.data()!;
    final String ownerId = data['owner_id'] ?? '';

    if (ownerId == userId) {
      return "O dono da liga não pode sair. Exclua a liga se desejar encerrá-la.";
    }

    await doc.reference.update({
      'members': FieldValue.arrayRemove([userId])
    });

    return null;
  }

  // 3. Escutar as Ligas do Usuário
  Stream<List<FantasyLeague>> streamMyLeagues(String userId) {
    return _firestore
        .collection('fantasy_leagues')
        .where('members', arrayContains: userId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => FantasyLeague.fromFirestore(doc)).toList());
  }

  // 3.1. Escutar Ligas Patrocinadas
  Stream<List<FantasyLeague>> streamSponsoredLeagues() {
    return _firestore
        .collection('fantasy_leagues')
        .where('is_sponsored', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => FantasyLeague.fromFirestore(doc)).toList());
  }

  // =================================================================
  // 🚨 4. BUSCAR RANKING DA LIGA (COM CACHE E BATCHING)
  // =================================================================
  Future<List<Map<String, dynamic>>> getLeagueRanking(FantasyLeague league, {bool forceRefresh = false}) async {
    final now = DateTime.now();
    final lastFetch = _lastRankingFetch[league.id];

    // Verifica se temos os dados em cache e se têm menos de 15 minutos
    if (!forceRefresh && _rankingCache.containsKey(league.id) && lastFetch != null) {
      if (now.difference(lastFetch).inMinutes < 15) {
        return _rankingCache[league.id]!;
      }
    }

    final List<Map<String, dynamic>> teamsData = [];
    final members = league.members;
    
    // OTIMIZAÇÃO: O Firestore aceita no máximo 10 itens no 'whereIn'. 
    // Vamos fatiar a lista de membros em pedaços de 10 e buscar.
    for (var i = 0; i < members.length; i += 10) {
      final chunk = members.sublist(i, i + 10 > members.length ? members.length : i + 10);
      
      final query = await _firestore
          .collection('fantasy_teams')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      
      for (var doc in query.docs) {
        final data = doc.data();
        data['uid'] = doc.id;
        teamsData.add(data);
      }
    }

    // 🚨 ORDENAÇÃO LOCAL
    teamsData.sort((a, b) {
      final double pointsA = (a['total_points'] ?? 0.0).toDouble();
      final double pointsB = (b['total_points'] ?? 0.0).toDouble();
      return pointsB.compareTo(pointsA); 
    });

    // Guardar no Cache Local
    _rankingCache[league.id] = teamsData;
    _lastRankingFetch[league.id] = now;

    return teamsData;
  }

  // =================================================================
  // 5. LIGAS MATA-MATA (GERAR CHAVES)
  // =================================================================
  Future<String> generateBracket(FantasyLeague league) async {
    if (league.type != 'knockout') return "Esta liga não é mata-mata.";
    if (league.members.length != league.maxTeams) return "A liga não atingiu a lotação máxima para sortear.";

    try {
      final statusDoc = await _firestore.collection('fantasy_market').doc('status').get();
      int currentRound = 1;
      if (statusDoc.exists) {
        currentRound = statusDoc.data()?['current_round'] ?? 1;
      }
      final int startRound = currentRound + 1;
      
      // Validação de Rodadas Restantes
      const int TOTAL_FANTASY_ROUNDS = 10; // 7 Fase de Grupos + 3 Mata-Mata
      final int roundsNeeded = (log(league.members.length) / ln2).toInt();
      final int roundsAvailable = TOTAL_FANTASY_ROUNDS - startRound + 1;
      
      if (roundsAvailable < roundsNeeded) {
        return "Não há rodadas suficientes restantes no campeonato para finalizar esta liga. Crie uma liga menor.";
      }

      final batch = _firestore.batch();
      final members = List<String>.from(league.members)..shuffle(); 
      
      final int count = members.length;
      final int matchesCount = count ~/ 2; 
      
      String phase;
      if (count == 4) phase = 'Semi';
      else if (count == 8) phase = 'Quartas';
      else if (count == 16) phase = 'Oitavas';
      else phase = 'Dezesseis-Avos';

      for (int i = 0; i < matchesCount; i++) {
        final matchDoc = _firestore.collection('fantasy_leagues').doc(league.id).collection('matches').doc();
        final teamA = members[i * 2];
        final teamB = members[i * 2 + 1];

        final matchData = KnockoutMatch(
          id: matchDoc.id,
          phase: phase,
          round: startRound,
          teamAId: teamA,
          teamBId: teamB,
          matchIndex: i,
        );
        batch.set(matchDoc, matchData.toMap());
      }

      final leagueRef = _firestore.collection('fantasy_leagues').doc(league.id);
      batch.update(leagueRef, {
        'status': 'active',
        'start_round': startRound,
      });

      await batch.commit();
      return "Sucesso";
    } catch (e) {
      return "Erro ao gerar chaveamento: $e";
    }
  }

  Stream<List<KnockoutMatch>> streamKnockoutMatches(String leagueId) {
    return _firestore
        .collection('fantasy_leagues')
        .doc(leagueId)
        .collection('matches')
        .orderBy('round')
        .orderBy('match_index')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => KnockoutMatch.fromFirestore(doc)).toList());
  }
}