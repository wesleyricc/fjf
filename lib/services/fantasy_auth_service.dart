import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'fantasy_service.dart';

class FantasyAuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // ---> COLE O SEU WEB CLIENT ID NOVO AQUI <---
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '893803829585-jp8uuugt42m2qknabm4lene03mimllai.apps.googleusercontent.com' : null,
  );

  final FantasyService _fantasyService; 

  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  FantasyAuthService(this._fantasyService) {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<String?> signInWithGoogle() async {
    try {
      _setLoading(true);

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return "Login cancelado pelo usuário."; 
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 1. Faz o login no Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // 🚨 TRUQUE SÊNIOR PARA EVITAR RACE CONDITION (ERRO DE PERMISSÃO) 🚨
        // Força a renovação e propagação imediata do Token de Acesso para o Firestore
        await user.getIdToken(true);
        await Future.delayed(const Duration(milliseconds: 600)); // Fôlego para a rede

        // 2. Garante que o time existe no banco
        final docSnap = await FirebaseFirestore.instance
            .collection('fantasy_teams')
            .doc(user.uid)
            .get();

        if (!docSnap.exists) {
          await _fantasyService.createUserTeam(
            userId: user.uid,
            userName: user.displayName ?? 'Treinador',
            teamName: 'Time de ${user.displayName?.split(' ').first ?? 'Treinador'}',
          );
        }
      }

      _setLoading(false);
      return null; // Retorna nulo indicando Sucesso Absoluto
      
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