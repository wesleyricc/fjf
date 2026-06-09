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
  Future<String> createLeague(String name, String userId) async {
    final String inviteCode = _generateInviteCode();
    
    final newLeague = FantasyLeague(
      id: '', 
      name: name.trim(),
      inviteCode: inviteCode,
      ownerId: userId,
      members: [userId], 
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
    final List<dynamic> currentMembers = doc.data()['members'] ?? [];

    if (currentMembers.contains(userId)) {
      return "Você já participa desta liga!";
    }

    await doc.reference.update({
      'members': FieldValue.arrayUnion([userId])
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
}