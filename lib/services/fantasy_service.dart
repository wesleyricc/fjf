import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; 
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import '../models/fantasy_models.dart';
import 'firestore_cache_service.dart';

class FantasyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance; 

  CollectionReference get _fantasyTeamsRef => _firestore.collection('fantasy_teams');
  CollectionReference get _fantasyMarketRef => _firestore.collection('fantasy_market_players');
  
  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<FantasyGameConfig> getGameConfig() async {
    try {
      final doc = await _firestore.collection('fantasy_config').doc('rules').get();
      if (doc.exists && doc.data() != null) {
        return FantasyGameConfig.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Erro ao buscar config do fantasy (usando default): $e");
    }
    return FantasyGameConfig.defaults();
  }

  Future<void> saveGameConfig(FantasyGameConfig config) async {
    await _firestore.collection('fantasy_config').doc('rules').set(config.toMap());
  }

  // ---> OTIMIZAÇÃO DE CUSTO AQUI <---
  // Antes estava a buscar a coleção global inteira de 'players' (milhares de leituras)
  // Agora busca apenas os jogadores instanciados no mercado do Fantasy!
  Future<List<FantasyPlayer>> getAllPlayers({bool forceRefresh = false}) async {
    try {
      final snapshot = await FirestoreCacheService.getWithCache(
        query: _fantasyMarketRef,
        cacheKey: 'fantasy_market_players',
        ttl: const Duration(minutes: 5), // TTL morno (5 minutos)
        forceRefresh: forceRefresh,
      );
      if (snapshot.docs.isEmpty) return [];
      return snapshot.docs.map((doc) => FantasyPlayer.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar todos os jogadores do mercado: $e");
      return [];
    }
  }

  Future<List<FantasyPlayer>> getPlayersByIds(List<String> ids, {bool forceRefresh = false}) async {
    if (ids.isEmpty) return [];
    try {
      // FINOPS: Usa o cache local em memória em vez de fazer queries whereIn diretas
      final allPlayers = await getAllPlayers(forceRefresh: forceRefresh);
      return allPlayers.where((p) => ids.contains(p.playerId)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar jogadores por IDs: $e");
      return [];
    }
  }

  Future<List<FantasyTeam>> getRanking({bool isGlobal = true, int limit = 20, bool forceRefresh = false}) async {
    String orderByField = isGlobal ? 'total_points' : 'last_score';
    final query = _fantasyTeamsRef.orderBy(orderByField, descending: true).limit(limit);
    try {
      final snap = await FirestoreCacheService.getWithCache(
        query: query,
        cacheKey: 'fantasy_ranking_${isGlobal}_$limit',
        ttl: const Duration(minutes: 5),
        forceRefresh: forceRefresh,
      );
      return snap.docs.map((doc) => FantasyTeam.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Erro ao buscar ranking (isGlobal: $isGlobal): $e");
      return [];
    }
  }

  Stream<FantasyTeam?> streamMyTeam(String userId) {
    return _fantasyTeamsRef.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return FantasyTeam.fromFirestore(doc);
    });
  }



  Future<String> updateTeamProfile({
    required String userId, required String teamName, required String ownerName,
    required String shieldType, String? customLogoUrl,
  }) async {
    if (!await _isOnline()) return "Erro: Sem conexão com a internet."; 
    try {
      return await _firestore.runTransaction((transaction) async {
        final docRef = _fantasyTeamsRef.doc(userId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return "Erro: Time não encontrado.";

        transaction.update(docRef, {
          'team_name': teamName, 'owner_name': ownerName, 'shield_type': shieldType, 'custom_logo_url': customLogoUrl,
        });
        return "Sucesso";
      });
    } catch (e) { return "Erro ao atualizar perfil: $e"; }
  }

  Future<void> createUserTeam({required String userId, required String userName, required String teamName}) async {
    if (!await _isOnline()) return; 
    final docSnap = await _fantasyTeamsRef.doc(userId).get();
    
    if (!docSnap.exists) {
      final newTeam = FantasyTeam(
        id: userId, ownerId: userId, userId: userId, shieldType: '1',
        ownerName: userName, teamName: teamName, totalPoints: 0,
        teamValue: 50, currentBalance: 50, lastScore: 0,
        lineupPlayerIds: [], captainId: null, customLogoUrl: null,
      );
      await _fantasyTeamsRef.doc(userId).set(newTeam.toMap());
    }
  }

  Future<String> saveLineup({
    required String userId, required List<String> playerIds, required List<String> benchIds, 
    Map<String, String>? lineupSlots, Map<String, String>? benchSlots,
    required String? captainId, required String? luxuryReserveId,
    required double expectedOldTeamCost, required double newTeamCost,
  }) async {
    if (!await _isOnline()) return "Erro: Sem conexão com a internet. O time não foi salvo."; 
    
    try {
      return await _firestore.runTransaction((transaction) async {
        final statusRef = _firestore.collection('fantasy_config').doc('status');
        final statusSnap = await transaction.get(statusRef);
        
        if (statusSnap.exists) {
          final data = statusSnap.data();
          final bool isOpen = data?['is_open'] ?? true;
          if (!isOpen) return "O Mercado está FECHADO. Não é possível salvar.";

          final dynamic closingRaw = data?['closing_time'];
          if (closingRaw is Timestamp && DateTime.now().isAfter(closingRaw.toDate())) {
            return "O prazo para escalar encerrou 20 min antes do jogo. Mercado FECHADO.";
          }
        }

        final teamRef = _fantasyTeamsRef.doc(userId);
        final teamSnap = await transaction.get(teamRef);
        
        if (!teamSnap.exists) return "Erro: Time inexistente.";
        
        final double serverPatrimony = (teamSnap.data() as Map<String, dynamic>)['team_value'] ?? 0.0;
        final double actualNewBalance = serverPatrimony - newTeamCost;
        
        if (actualNewBalance < -0.01) { 
          return "Saldo insuficiente! Patrimônio: C\$${serverPatrimony.toStringAsFixed(2)} | Time: C\$${newTeamCost.toStringAsFixed(2)}";
        }

        final double safeBalance = double.parse(actualNewBalance.toStringAsFixed(2));

        transaction.update(teamRef, {
          'lineup_player_ids': playerIds, 
          'bench_player_ids': benchIds,
          'lineup_slots': lineupSlots,
          'bench_slots': benchSlots,
          'captain_id': captainId,
          'luxury_reserve_id': luxuryReserveId,
          'current_balance': safeBalance,
          'lineup': FieldValue.delete(), 
        });
        
        return "Sucesso";
      });
    } catch (e) { return "Erro ao salvar transação: $e"; }
  }

  Stream<Map<String, dynamic>> streamMarketStatus() {
    return _firestore.collection('fantasy_config').doc('status').snapshots().map((doc) {
      if (!doc.exists) return {'is_open': true, 'current_round': 1};
      return doc.data() as Map<String, dynamic>;
    });
  }

  Stream<QuerySnapshot> streamHistory(String userId) {
    return _firestore.collection('fantasy_teams').doc(userId).collection('history').orderBy('round', descending: true).snapshots();
  }

  Stream<DocumentSnapshot> streamGlobalScouts() {
    return _firestore.collection('fantasy_stats').doc('global_round_stats').snapshots();
  }

  Future<void> setMarketStatus(bool isOpen, int currentRound, {DateTime? closingTime}) async {
    if (!await _isOnline()) return;
    final Map<String, dynamic> data = {
      'is_open': isOpen,
      'current_round': currentRound,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (closingTime != null) {
      data['closing_time'] = Timestamp.fromDate(closingTime);
    } else if (!isOpen) {
      data['closing_time'] = FieldValue.serverTimestamp();
    } else {
      data['closing_time'] = null;
    }
    await _firestore.collection('fantasy_config').doc('status').set(data, SetOptions(merge: true));
  }

  Future<String> processRoundCloud(String seasonId, int round) async {
    if (!await _isOnline()) return "Erro: Sem internet. Não é possível chamar a Cloud Function."; 
    try {
      final HttpsCallable callable = _functions.httpsCallable('closeRound');
      final result = await callable.call(<String, dynamic>{'seasonId': seasonId, 'round': round});
      final data = result.data as Map<dynamic, dynamic>;
      
      if (data['success'] == true) return "Sucesso: ${data['message']}";
      else return "Erro no retorno da função: ${data['message'] ?? 'Desconhecido'}";
    } catch (e) {
      debugPrint("Erro ao chamar Cloud Function: $e");
      if (e is FirebaseFunctionsException) return "Erro Cloud (${e.code}): ${e.message}";
      return "Erro desconhecido: $e";
    }
  }

  Future<Map<String, dynamic>> computeMarketStatsClientSide(int currentRound) async {
    try {
      final teamsSnap = await _fantasyTeamsRef.get();
      final Map<String, int> playerCounts = {};
      final Map<String, int> captainCounts = {};
      int totalTeams = 0;

      for (var doc in teamsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final List<dynamic> lineup = data['lineup_player_ids'] ?? [];
        final String? captainId = data['captain_id'];

        if (lineup.isNotEmpty) totalTeams++;

        for (var pid in lineup) {
          if (pid != null && pid.toString().isNotEmpty) {
            final strPid = pid.toString();
            playerCounts[strPid] = (playerCounts[strPid] ?? 0) + 1;
          }
        }

        if (captainId != null && captainId.isNotEmpty) {
          captainCounts[captainId] = (captainCounts[captainId] ?? 0) + 1;
        }
      }

      final marketSnap = await _fantasyMarketRef.get();
      final Map<String, Map<String, dynamic>> playersInfo = {};
      for (var doc in marketSnap.docs) {
        playersInfo[doc.id] = doc.data() as Map<String, dynamic>;
      }

      final List<Map<String, dynamic>> mostSelected = [];
      playerCounts.forEach((pid, pCount) {
        final p = playersInfo[pid] ?? {};
        mostSelected.add({
          'player_id': pid,
          'name': p['name'] ?? 'Desconhecido',
          'position': p['position'] ?? 'Desconhecido',
          'team_name': p['team_name'] ?? '',
          'team_shield_url': p['team_shield_url'] ?? '',
          'photo_url': p['photo_url'] ?? '',
          'current_price': p['current_price'] ?? 0,
          'selections': pCount,
          'count': pCount,
          'captain_selections': captainCounts[pid] ?? 0,
        });
      });

      mostSelected.sort((a, b) => (b['selections'] as int).compareTo(a['selections'] as int));

      String? mostSelectedCaptain;
      int maxCaptainCount = 0;
      captainCounts.forEach((pid, cCount) {
        if (cCount > maxCaptainCount) {
          maxCaptainCount = cCount;
          mostSelectedCaptain = pid;
        }
      });

      final top30 = mostSelected.take(30).toList();
      final payload = <String, dynamic>{
        'round': currentRound,
        'most_selected': top30,
        'most_picked': top30,
        'most_selected_player_id': top30.isNotEmpty ? top30[0]['player_id'] : null,
        'most_selected_player_count': top30.isNotEmpty ? top30[0]['selections'] : 0,
        'most_selected_captain_id': mostSelectedCaptain,
        'most_selected_captain_count': maxCaptainCount,
        'total_teams': totalTeams,
        'updated_at': FieldValue.serverTimestamp(),
      };

      try {
        await _firestore.collection('fantasy_stats').doc('global_round_stats').set(payload, SetOptions(merge: true));
        await _firestore.collection('fantasy_stats').doc('round_$currentRound').set(payload, SetOptions(merge: true));
        await _firestore.collection('fantasy_config').doc('market_stats').set({
          'round': currentRound,
          'most_selected_player_id': payload['most_selected_player_id'],
          'most_selected_player_count': payload['most_selected_player_count'],
          'most_selected_captain_id': payload['most_selected_captain_id'],
          'most_selected_captain_count': payload['most_selected_captain_count'],
          'total_teams': totalTeams,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (writeError) {
        debugPrint("Aviso: gravação direta no Firestore bloqueada por regras (esperado para não-admins): $writeError");
      }

      return payload;
    } catch (e) {
      debugPrint("Erro no computeMarketStatsClientSide: $e");
      rethrow;
    }
  }

  Future<String> generateGlobalMarketStats() async {
    if (!await _isOnline()) return "Sem conexão com a internet.";
    
    // 1. Tenta acionar a Cloud Function
    try {
      final HttpsCallable callable = _functions.httpsCallable('generateGlobalMarketStats');
      final result = await callable.call();
      final data = result.data as Map<dynamic, dynamic>;
      if (data['success'] == true) {
        return "Sucesso: ${data['count']} atletas computados para a R${data['round']}.";
      }
      return "Retorno: ${data['message'] ?? 'OK'}";
    } catch (e) {
      debugPrint("Cloud Function indisponível ou bloqueada por CORS ($e). Usando fallback local...");
      
      // 2. Fallback de alta disponibilidade: computação no cliente
      try {
        final statusSnap = await _firestore.collection('fantasy_config').doc('status').get();
        final currentRound = statusSnap.data()?['current_round'] ?? 1;
        final payload = await computeMarketStatsClientSide(currentRound);
        final count = (payload['most_selected'] as List).length;
        return "Sucesso: $count atletas computados localmente com sucesso!";
      } catch (clientErr) {
        return "Erro ao computar estatísticas: $clientErr";
      }
    }
  }


  Future<String> populateMarketFromSeason(String seasonId) async {
    if (!await _isOnline()) return "Erro de Conexão.";
    try {
      final WriteBatch batch = _firestore.batch();
      int count = 0;

      final playersSnap = await _firestore.collection('championships').doc(seasonId)
          .collection('player_stats').where('isActive', isEqualTo: true).get();

      // FINOPS: Busca todos os jogadores do mercado de uma vez para evitar loop de .get()
      final marketSnap = await _fantasyMarketRef.get();
      final Set<String> existingMarketIds = marketSnap.docs.map((doc) => doc.id).toSet();

      for (var doc in playersSnap.docs) {
        final data = doc.data();
        final bool isStaff = data['is_staff'] == true;
        final String staffRole = (data['staff_role'] ?? '').toString().trim();
        
        bool isHeadCoach = false;
        if (isStaff) {
          final roleLower = staffRole.toLowerCase();
          if (roleLower == 'técnico' || roleLower == 'tecnico' || roleLower == 'treinador' || roleLower.isEmpty) {
            isHeadCoach = true;
          }
          
          if (!isHeadCoach) {
            continue; // Ignora membros como Auxiliar, Massagista, etc.
          }
        }
        
        final String position = isHeadCoach ? 'Técnico' : (data['position'] ?? 'Desconhecido');
        final String? secondaryPosition = isHeadCoach ? null : data['secondary_position'];
        final double initialPrice = (data['fantasy_initial_price'] as num?)?.toDouble() ?? 5.0;

        _addToBatchWithCache(batch, doc.id, data, position, secondaryPosition, initialPrice, existingMarketIds.contains(doc.id));
        count++;
      }

      await batch.commit();
      return "Sucesso! $count registros verificados/sincronizados.";
    } catch (e) { return "Erro ao popular mercado: $e"; }
  }

  void _addToBatchWithCache(WriteBatch batch, String id, Map<String, dynamic> data, String position, String? secondaryPosition, double price, bool exists) {
    final marketDocRef = _fantasyMarketRef.doc(id);

    if (!exists) {
      final Map<String, dynamic> playerData = {
        'name': data['name'] ?? 'Sem Nome', 'position': position, 'secondary_position': secondaryPosition, 'team_id': data['team_id'] ?? '',
        'team_shield_url': data['team_shield_url'] ?? '', 'photo_url': data['photo_url'] ?? '',
        'current_price': price, 'last_price_change': 0.0, 'last_score': 0.0, 'average_score': 0.0,
        'matches_played': 0, 'status': 'probable', 'history': [],
      };
      batch.set(marketDocRef, playerData);
    } else {
      batch.update(marketDocRef, {
        'name': data['name'], 'photo_url': data['photo_url'],
        'team_id': data['team_id'], 'team_shield_url': data['team_shield_url'],
        'position': position,
        'secondary_position': secondaryPosition,
      });
    }
  }
}