import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/award_model.dart';
import 'firestore_cache_service.dart';

class AwardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference _getAwardsRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('awards');
  }

  Future<List<Award>> getAwards(String seasonId, {bool forceRefresh = false}) async {
    final query = _getAwardsRef(seasonId).orderBy('order');
    final snap = await FirestoreCacheService.getWithCache(
      query: query,
      cacheKey: 'awards_',
      ttl: const Duration(hours: 1), // Premiações quase nunca mudam
      forceRefresh: forceRefresh,
    );
    return snap.docs.map((d) => Award.fromFirestore(d)).toList();
  }

  Stream<List<Award>> streamAwards(String seasonId) {
    return _getAwardsRef(seasonId)
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Award.fromFirestore(d)).toList());
  }

  Future<void> addAward(String seasonId, Award award) async {
    await _getAwardsRef(seasonId).add(award.toMap());
    await FirestoreCacheService.invalidateCache('awards_');
  }

  Future<void> updateAward(String seasonId, Award award) async {
    await _getAwardsRef(seasonId).doc(award.id).update(award.toMap());
    await FirestoreCacheService.invalidateCache('awards_');
  }

  Future<void> deleteAward(String seasonId, String awardId) async {
    await _getAwardsRef(seasonId).doc(awardId).delete();
    await FirestoreCacheService.invalidateCache('awards_');
  }
}
