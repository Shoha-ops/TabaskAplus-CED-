import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? user;

  DatabaseService({this.user});

  // Collection reference
  CollectionReference get users => _db.collection('users');

  // Get user profile stream
  Stream<DocumentSnapshot> get userData {
    return users.doc(user?.uid).snapshots();
  }

  // Get schedule stream
  Stream<QuerySnapshot> get schedule {
    return users.doc(user?.uid).collection('schedule').snapshots();
  }

  // Get grades stream
  Stream<QuerySnapshot> get grades {
    return users.doc(user?.uid).collection('grades').snapshots();
  }

  // Add a message (with sender)
  Future<void> sendMessage(String text, {required bool isBot}) async {
    await users.doc(user?.uid).collection('messages').add({
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'sender': isBot ? 'bot' : 'user',
    });
  }

  // Get messages stream
  Stream<QuerySnapshot> get messages {
    return users
        .doc(user?.uid)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  // Save user profile data
  Future<void> updateUserData(String name, String studentId, double gpa) async {
    return await users.doc(user?.uid).set({
      'name': name,
      'studentId': studentId,
      'gpa': gpa,
    }, SetOptions(merge: true));
  }
}
