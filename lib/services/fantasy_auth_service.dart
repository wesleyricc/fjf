import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fantasy_service.dart';

class FantasyAuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FantasyService _fantasyService; // Injeção de dependência

  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  FantasyAuthService(this._fantasyService) {
    // Escuta alterações na sessão (ex: app reiniciado)
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  /// Realiza o login com Google e garante que o time Fantasy exista
  Future<String?> signInWithGoogle() async {
    try {
      _setLoading(true);

      // 1. Inicia fluxo do Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return "Login cancelado pelo usuário."; // Usuário fechou a janela
      }

      // 2. Obtém credenciais de acesso
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 3. Autentica no Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // 4. Verificação Crítica: O usuário já tem time?
        // Acessamos diretamente para não depender de streams aqui
        final docSnap = await FirebaseFirestore.instance
            .collection('fantasy_teams')
            .doc(user.uid)
            .get();

        if (!docSnap.exists) {
          // 5. Se é a primeira vez, cria o time com 50 moedas
          await _fantasyService.createUserTeam(
            userId: user.uid,
            userName: user.displayName ?? 'Treinador',
            teamName: 'Time de ${user.displayName?.split(' ').first ?? 'Treinador'}',
          );
        }
      }

      _setLoading(false);
      return null; // Sucesso
    } on FirebaseAuthException catch (e) {
      _setLoading(false);
      return "Erro no Firebase: ${e.message}";
    } catch (e) {
      _setLoading(false);
      return "Erro desconhecido: $e";
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}