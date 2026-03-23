import 'package:cloud_firestore/cloud_firestore.dart';

class StudentModel {
  final String uid;
  final String fullName;
  final String studentId;
  final String group;
  final String email;
  final String avatarId;
  final String profilePicBase64;
  final String? profilePicUrl;

  StudentModel({
    required this.uid,
    required this.fullName,
    required this.studentId,
    required this.group,
    required this.email,
    required this.avatarId,
    required this.profilePicBase64,
    this.profilePicUrl,
  });

  factory StudentModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final fullName = (data['fullName'] as String?)?.trim().isNotEmpty == true
        ? (data['fullName'] as String).trim()
        : '${(data['firstName'] as String?)?.trim() ?? ''} ${(data['lastName'] as String?)?.trim() ?? ''}'
              .trim();
    return StudentModel(
      uid: doc.id,
      fullName: fullName.isEmpty ? (data['email'] ?? '') : fullName,
      studentId: data['studentId'] ?? '',
      group: (data['group'] as String?)?.trim() ?? '',
      email: data['email'] ?? '',
      avatarId: (data['avatarId'] as String?)?.trim() ?? '',
      profilePicBase64: (data['profilePicBase64'] as String?)?.trim() ?? '',
      profilePicUrl: data['profilePicUrl'],
    );
  }
}
