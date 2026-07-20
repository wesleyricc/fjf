import 'package:cloud_firestore/cloud_firestore.dart';

class PortalUser {
  final String id;
  final String username;
  final String name;
  final String role; // 'athlete', 'staff', 'president'
  final String? teamId;
  final String? playerId;
  final String? cpf;
  final DateTime createdAt;

  PortalUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.teamId,
    this.playerId,
    this.cpf,
    required this.createdAt,
  });

  factory PortalUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PortalUser(
      id: doc.id,
      username: data['username'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'athlete',
      teamId: data['teamId'],
      playerId: data['playerId'],
      cpf: data['cpf'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'name': name,
      'role': role,
      'teamId': teamId,
      'playerId': playerId,
      'cpf': cpf,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}

class PortalEvent {
  final String id;
  final String title;
  final DateTime date;
  final String location;
  final String description;
  final String? teamId; // Pode ser nulo se for um evento global
  final String? targetRole; // 'all' (todos), 'president' (apenas presidentes)

  PortalEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.location,
    required this.description,
    this.teamId,
    this.targetRole,
  });

  factory PortalEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PortalEvent(
      id: doc.id,
      title: data['title'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      location: data['location'] ?? '',
      description: data['description'] ?? '',
      teamId: data['teamId'],
      targetRole: data['targetRole'] ?? 'all',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'date': Timestamp.fromDate(date),
      'location': location,
      'description': description,
      'teamId': teamId,
      'targetRole': targetRole ?? 'all',
    };
  }
}

class PortalAttendance {
  final String id;
  final String eventId;
  final String userId;
  final String status; // 'pending', 'confirmed', 'absent', 'justified'
  final String? justificationText;

  PortalAttendance({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.status,
    this.justificationText,
  });

  factory PortalAttendance.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PortalAttendance(
      id: doc.id,
      eventId: data['event_id'] ?? '',
      userId: data['user_id'] ?? '',
      status: data['status'] ?? 'pending',
      justificationText: data['justification_text'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'event_id': eventId,
      'user_id': userId,
      'status': status,
      'justification_text': justificationText,
    };
  }
}

class PortalFinancialDue {
  final String id;
  final String userId;
  final String? userName;
  final String title;
  final double amount;
  final DateTime dueDate;
  final String status; // 'pending', 'paid', 'overdue'
  final DateTime? paymentDate;
  final String? teamId; // Para organizar relatórios financeiros

  PortalFinancialDue({
    required this.id,
    required this.userId,
    this.userName,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.status,
    this.paymentDate,
    this.teamId,
  });

  factory PortalFinancialDue.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PortalFinancialDue(
      id: doc.id,
      userId: data['user_id'] ?? '',
      userName: data['user_name'],
      title: data['title'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      dueDate: (data['due_date'] as Timestamp).toDate(),
      status: data['status'] ?? 'pending',
      paymentDate: (data['payment_date'] as Timestamp?)?.toDate(),
      teamId: data['teamId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'user_name': userName,
      'title': title,
      'amount': amount,
      'due_date': Timestamp.fromDate(dueDate),
      'status': status,
      'payment_date': paymentDate != null ? Timestamp.fromDate(paymentDate!) : null,
      'teamId': teamId,
    };
  }
}
