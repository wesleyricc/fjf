import 'package:cloud_firestore/cloud_firestore.dart';

class FreeAgent {
  final String id;
  final String userId;
  final String name;
  final String photoUrl;
  final String phone; // Número para o WhatsApp (ex: 5548999999999)
  final DateTime birthDate;
  
  // Informações de Jogo
  final String position; 
  final bool isGoalkeeper;
  final double height;
  final double weight;
  final String preferredFoot; // Destro, Canhoto, Ambidestro
  final String selfEvaluation; // 'Estrela', 'Alto Nível', 'Comum'
  
  // Status Legal (Regras da ACEFJF)
  final String eligibilityType; // Ex: 'Nascido', 'Morador > 1 ano', etc.
  final String status; // 'Aguardando Ética', 'Disponível no Mercado', 'Contratado'
  final DateTime createdAt;

  FreeAgent({
    required this.id,
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.phone,
    required this.birthDate,
    required this.position,
    required this.isGoalkeeper,
    required this.height,
    required this.weight,
    required this.preferredFoot,
    required this.selfEvaluation,
    required this.eligibilityType,
    required this.status,
    required this.createdAt,
  });

  int get age {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  factory FreeAgent.fromMap(Map<String, dynamic> map, String documentId) {
    return FreeAgent(
      id: documentId,
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      phone: map['phone'] ?? '',
      birthDate: (map['birthDate'] as Timestamp).toDate(),
      position: map['position'] ?? '',
      isGoalkeeper: map['isGoalkeeper'] ?? false,
      height: (map['height'] ?? 0.0).toDouble(),
      weight: (map['weight'] ?? 0.0).toDouble(),
      preferredFoot: map['preferredFoot'] ?? '',
      selfEvaluation: map['selfEvaluation'] ?? 'Comum',
      eligibilityType: map['eligibilityType'] ?? '',
      status: map['status'] ?? 'Aguardando Ética',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'photoUrl': photoUrl,
      'phone': phone,
      'birthDate': Timestamp.fromDate(birthDate),
      'position': position,
      'isGoalkeeper': isGoalkeeper,
      'height': height,
      'weight': weight,
      'preferredFoot': preferredFoot,
      'selfEvaluation': selfEvaluation,
      'eligibilityType': eligibilityType,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}