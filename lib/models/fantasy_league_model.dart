import 'package:cloud_firestore/cloud_firestore.dart';

class FantasyLeague {
  final String id;
  final String name;
  final String inviteCode;
  final String ownerId;
  final List<String> members;

  FantasyLeague({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.members,
  });

  factory FantasyLeague.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FantasyLeague(
      id: doc.id,
      name: data['name'] ?? 'Liga Sem Nome',
      inviteCode: data['invite_code'] ?? '',
      ownerId: data['owner_id'] ?? '',
      members: List<String>.from(data['members'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'invite_code': inviteCode,
      'owner_id': ownerId,
      'members': members,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}