import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/award_model.dart';

class AwardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference _getAwardsRef(String seasonId) {
    return _firestore.collection('championships').doc(seasonId).collection('awards');
  }

  Stream<List<Award>> streamAwards(String seasonId) {
    return _getAwardsRef(seasonId)
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Award.fromFirestore(d)).toList());
  }

  Future<void> addAward(String seasonId, Award award) async {
    await _getAwardsRef(seasonId).add(award.toMap());
  }

  Future<void> updateAward(String seasonId, Award award) async {
    await _getAwardsRef(seasonId).doc(award.id).update(award.toMap());
  }

  Future<void> deleteAward(String seasonId, String awardId) async {
    await _getAwardsRef(seasonId).doc(awardId).delete();
  }
}