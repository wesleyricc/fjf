import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/portal_models.dart';

class PortalAuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  PortalUser? _currentPortalUser;
  bool _isLoading = false;

  PortalUser? get currentPortalUser => _currentPortalUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentPortalUser != null;

  PortalAuthService() {
    _auth.authStateChanges().listen((User? user) {
      if (user != null) {
        _loadPortalUserProfile(user.uid);
      } else {
        _currentPortalUser = null;
        notifyListeners();
      }
    });
  }

  Future<void> _loadPortalUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('portal_users').doc(uid).get();
      if (doc.exists) {
        _currentPortalUser = PortalUser.fromFirestore(doc);
      } else {
        _currentPortalUser = null;
      }
    } catch (e) {
      print("Erro ao carregar perfil do portal: $e");
      _currentPortalUser = null;
    }
    notifyListeners();
  }

  /// Faz o login utilizando a estratégia de pseudo-email para contornar a limitação do Firebase Auth
  Future<String?> loginWithUsername(String username, String password) async {
    _setLoading(true);
    try {
      // Normaliza o username para minúsculas e sem espaços
      final cleanUsername = username.trim().toLowerCase().replaceAll(' ', '');
      final pseudoEmail = '$cleanUsername@fjf.com.br';

      await _auth.signInWithEmailAndPassword(
        email: pseudoEmail,
        password: password,
      );
      
      _setLoading(false);
      return null; // Sucesso
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return "Usuário ou senha incorretos.";
      }
      return "Erro ao fazer login: ${e.message}";
    } catch (e) {
      _setLoading(false);
      return "Erro desconhecido: $e";
    }
  }

  /// Cria um novo acesso para o portal sem deslogar o Admin (Usa Secondary App)
  Future<String?> createUserAccess(String username, String password, String name, String role, {String? teamId, String? playerId}) async {
    try {
      final cleanUsername = username.trim().toLowerCase().replaceAll(' ', '');
      final pseudoEmail = '$cleanUsername@fjf.com.br';

      // Cria um app secundário temporário para criar o usuário sem afetar a sessão atual
      FirebaseApp secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      UserCredential userCredential = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(email: pseudoEmail, password: password);

      final portalUser = PortalUser(
        id: userCredential.user!.uid,
        username: cleanUsername,
        name: name,
        role: role,
        teamId: teamId,
        playerId: playerId,
        createdAt: DateTime.now(),
      );

      // Salva no banco de dados
      await _firestore.collection('portal_users').doc(portalUser.id).set(portalUser.toMap());
      
      // Limpa a instância secundária
      await secondaryApp.delete();

      return null; // Sucesso
    } catch (e) {
      return "Erro ao criar usuário: $e";
    }
  }

  Future<void> updatePortalUserCpf(String uid, String cpf) async {
    try {
      await _firestore.collection('portal_users').doc(uid).update({'cpf': cpf});
      // Refresh current user
      if (_currentPortalUser?.id == uid) {
        _currentPortalUser = PortalUser(
          id: _currentPortalUser!.id,
          username: _currentPortalUser!.username,
          name: _currentPortalUser!.name,
          role: _currentPortalUser!.role,
          teamId: _currentPortalUser!.teamId,
          playerId: _currentPortalUser!.playerId,
          cpf: cpf,
          createdAt: _currentPortalUser!.createdAt,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Erro ao atualizar CPF: $e");
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
