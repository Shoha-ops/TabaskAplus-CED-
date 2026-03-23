import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _lastActiveUidKey = 'last_active_uid';
  static const String _lastActiveNameKey = 'last_active_name';

  String _studentIdToEmail(String studentId) {
    final normalized = studentId.trim().toLowerCase();
    return '$normalized@student.local';
  }

  String _toTitleCase(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';

    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _displayFirstName(Map<String, dynamic>? data) {
    final firstName = _toTitleCase((data?['firstName'] as String?) ?? '');
    if (firstName.isNotEmpty) return firstName;

    final fullName = _toTitleCase(
      (data?['fullName'] as String?) ?? (data?['displayName'] as String?) ?? '',
    );
    if (fullName.isEmpty) return '';

    final parts = fullName.split(' ');
    return parts.isNotEmpty ? parts.last : fullName;
  }

  Future<void> _cacheActiveUserName(User? user) async {
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    var firstName = _displayFirstName({'displayName': user.displayName ?? ''});

    if (firstName.isEmpty) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        firstName = _displayFirstName(snapshot.data());
      } catch (e) {
        log('Failed to load user profile for cache: $e');
      }
    }

    if (firstName.isEmpty) return;

    await prefs.setString('last_active_name_${user.uid}', firstName);
    await prefs.setString(_lastActiveUidKey, user.uid);
    await prefs.setString(_lastActiveNameKey, firstName);
  }

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _cacheActiveUserName(result.user);
      return result.user;
    } catch (e) {
      log(e.toString());
      rethrow;
    }
  }

  Future<User?> signInWithStudentId(String studentId, String password) async {
    return signInWithEmail(_studentIdToEmail(studentId), password);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      log(e.toString());
    }
  }
}
