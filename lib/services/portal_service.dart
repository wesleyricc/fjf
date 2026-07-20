import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/portal_models.dart';

class PortalService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Usuários ---
  
  Future<PortalUser?> getUser(String userId) async {
    final doc = await _firestore.collection('portal_users').doc(userId).get();
    if (!doc.exists) return null;
    return PortalUser.fromFirestore(doc);
  }

  Future<void> createUser(PortalUser user) async {
    await _firestore.collection('portal_users').doc(user.id).set(user.toMap());
  }
  
  Stream<List<PortalUser>> streamAllUsers() {
    return _firestore.collection('portal_users').orderBy('name').snapshots().map((snap) {
      return snap.docs.map((doc) => PortalUser.fromFirestore(doc)).toList();
    });
  }

  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await _firestore.collection('portal_users').doc(userId).update(data);
  }

  Future<void> deleteUser(String userId) async {
    await _firestore.collection('portal_users').doc(userId).delete();
  }

  // --- Eventos (Agenda) ---
  
  Stream<List<PortalEvent>> streamUpcomingEvents({String? teamId, String? userRole}) {
    Query query = _firestore.collection('portal_events')
        .where('date', isGreaterThanOrEqualTo: Timestamp.now())
        .orderBy('date');
    
    return query.snapshots().map((snap) {
      var events = snap.docs.map((doc) => PortalEvent.fromFirestore(doc)).toList();
      if (teamId != null) {
        events = events.where((e) => e.teamId == teamId || e.teamId == null).toList();
      }
      if (userRole != 'admin' && userRole != 'president') {
        events = events.where((e) => e.targetRole == 'all' || e.targetRole == null).toList();
      }
      return events;
    });
  }

  Future<void> createEvent(PortalEvent event) async {
    await _firestore.collection('portal_events').add(event.toMap());
  }

  Future<void> updateEvent(String eventId, Map<String, dynamic> data) async {
    await _firestore.collection('portal_events').doc(eventId).update(data);
  }

  Future<void> deleteEvent(String eventId) async {
    await _firestore.collection('portal_events').doc(eventId).delete();
  }

  // --- Chamada \(Presença\) ---
  
  Stream<List<PortalAttendance>> streamAttendanceForEvent(String eventId) {
    return _firestore.collection('portal_attendance')
        .where('event_id', isEqualTo: eventId)
        .snapshots().map((snap) {
      return snap.docs.map((doc) => PortalAttendance.fromFirestore(doc)).toList();
    });
  }

  Future<void> updateAttendance(String eventId, String userId, String status, {String? justification}) async {
    final query = await _firestore.collection('portal_attendance')
        .where('event_id', isEqualTo: eventId)
        .where('user_id', isEqualTo: userId)
        .limit(1).get();
        
    if (query.docs.isEmpty) {
      await _firestore.collection('portal_attendance').add({
        'event_id': eventId,
        'user_id': userId,
        'status': status,
        'justification_text': justification,
      });
    } else {
      await query.docs.first.reference.update({
        'status': status,
        'justification_text': justification,
      });
    }
  }

  // --- Financeiro ---
  
  Stream<List<PortalFinancialDue>> streamMyDues(String userId) {
    return _firestore.collection('portal_financial_dues')
        .where('user_id', isEqualTo: userId)
        .orderBy('due_date', descending: true)
        .snapshots().map((snap) {
      return snap.docs.map((doc) => PortalFinancialDue.fromFirestore(doc)).toList();
    });
  }

  Stream<List<PortalFinancialDue>> streamAllDues() {
    return _firestore.collection('portal_financial_dues')
        .orderBy('due_date', descending: true)
        .snapshots().map((snap) {
      return snap.docs.map((doc) => PortalFinancialDue.fromFirestore(doc)).toList();
    });
  }

  Future<Map<String, dynamic>> generatePixForDue(String dueId, String username) async {
    final callable = FirebaseFunctions.instance.httpsCallable('createPixPayment');
    final response = await callable.call({
      'type': 'portal',
      'dueId': dueId,
      'customerContact': '$username@fjf.com.br',
    });
    
    if (response.data == null || response.data is! Map) {
      throw "Erro ao gerar o Pix. Formato inválido.";
    }
    
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['success'] != true) {
      throw data['message'] ?? "Falha ao gerar o Pix.";
    }
    
    return data;
  }

  Future<void> createBatchDues(String title, double amount, DateTime dueDate, String? teamId) async {
    Query query = _firestore.collection('portal_users');
    if (teamId != null) {
      query = query.where('teamId', isEqualTo: teamId);
    }
    
    final snap = await query.get();
    if (snap.docs.isEmpty) throw "Nenhum atleta encontrado para esta seleção.";
    
    final batch = _firestore.batch();
    for (var doc in snap.docs) {
      final docData = doc.data() as Map<String, dynamic>;
      final dueRef = _firestore.collection('portal_financial_dues').doc();
      batch.set(dueRef, {
        'user_id': doc.id,
        'user_name': docData['name'],
        'title': title,
        'amount': amount,
        'due_date': Timestamp.fromDate(dueDate),
        'status': 'pending',
        'teamId': docData['teamId'],
      });
    }
    
    await batch.commit();
  }

  Future<void> createFinancialDue(PortalFinancialDue due) async {
    await _firestore.collection('portal_financial_dues').add(due.toMap());
  }

  Future<void> markDueAsPaid(String dueId) async {
    await _firestore.collection('portal_financial_dues').doc(dueId).update({
      'status': 'paid',
      'payment_date': FieldValue.serverTimestamp(),
    });
  }
  Future<void> updateDue(String dueId, Map<String, dynamic> data) async {
    await _firestore.collection('portal_financial_dues').doc(dueId).update(data);
  }

  Future<void> deleteDue(String dueId) async {
    await _firestore.collection('portal_financial_dues').doc(dueId).delete();
  }
}
