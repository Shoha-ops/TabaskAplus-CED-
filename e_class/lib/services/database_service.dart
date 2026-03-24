import 'dart:convert';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/services/search_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? user;

  DatabaseService({this.user});

  CollectionReference get users => _db.collection('users');

  Stream<DocumentSnapshot> get userData {
    return users.doc(user?.uid).snapshots();
  }

  String _scheduleCacheKey(String groupName) {
    return 'schedule_cache_${groupName.trim().toUpperCase()}';
  }

  dynamic _jsonSafeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is GeoPoint) {
      return {'lat': value.latitude, 'lng': value.longitude};
    }
    if (value is DocumentReference) {
      return value.path;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _jsonSafeValue(item)),
      );
    }
    if (value is List) {
      return value.map(_jsonSafeValue).toList(growable: false);
    }
    return value;
  }

  List<Map<String, dynamic>> _mapScheduleDocs(
    List<QueryDocumentSnapshot> docs,
  ) {
    return docs
        .map(
          (doc) => {
            'id': doc.id,
            ..._jsonSafeValue(doc.data() as Map<String, dynamic>)
                as Map<String, dynamic>,
          },
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _readScheduleCache(
    String groupName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scheduleCacheKey(groupName));
    if (raw == null || raw.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false);
    } catch (error) {
      log('Failed to read schedule cache for $groupName: $error');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _writeScheduleCache(
    String groupName,
    List<Map<String, dynamic>> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduleCacheKey(groupName), jsonEncode(entries));
  }

  Stream<List<Map<String, dynamic>>> _groupScheduleEntries(
    String groupName,
  ) async* {
    final cachedEntries = await _readScheduleCache(groupName);
    log(
      '[SCHEDULE_STREAM] group=$groupName source=cache entries=${cachedEntries.length}',
    );
    yield cachedEntries;

    try {
      await for (final querySnapshot
          in _db
              .collection('groups')
              .doc(groupName)
              .collection('schedule')
              .snapshots()) {
        final entries = _mapScheduleDocs(querySnapshot.docs);
        log(
          '[SCHEDULE_STREAM] group=$groupName source=firestore docs=${querySnapshot.docs.length} entries=${entries.length}',
        );
        await _writeScheduleCache(groupName, entries);
        yield entries;
      }
    } catch (error) {
      log('Failed to load group schedule for $groupName: $error');
      if (cachedEntries.isNotEmpty) {
        yield cachedEntries;
      }
      yield* Stream<List<Map<String, dynamic>>>.error(error);
    }
  }

  Stream<List<Map<String, dynamic>>> scheduleEntriesForGroup(String groupName) {
    final normalizedGroup = groupName.trim().toUpperCase();
    log(
      '[SCHEDULE_STREAM] request group_raw="$groupName" group="$normalizedGroup"',
    );
    if (normalizedGroup.isEmpty) {
      return Stream.value(const <Map<String, dynamic>>[]);
    }
    return _groupScheduleEntries(normalizedGroup);
  }

  Stream<List<Map<String, dynamic>>> get scheduleEntries {
    if (user?.uid == null) {
      return const Stream.empty();
    }

    final userRef = users.doc(user!.uid);
    return userRef.snapshots().asyncExpand((snapshot) async* {
      final data = snapshot.data() as Map<String, dynamic>?;
      final groupName = (data?['group'] as String?)?.trim() ?? '';

      if (groupName.isEmpty) {
        yield const <Map<String, dynamic>>[];
        return;
      }

      yield* scheduleEntriesForGroup(groupName);
    });
  }

  Stream<QuerySnapshot> get grades {
    return users.doc(user?.uid).collection('grades').snapshots();
  }

  Stream<QuerySnapshot> get subjects {
    return _db.collection('subjects').snapshots();
  }

  Future<void> sendMessage(String text, {required bool isBot}) async {
    final senderUtcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    await users.doc(user?.uid).collection('messages').add({
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'sender': isBot ? 'bot' : 'user',
      'senderUtcOffsetMinutes': senderUtcOffsetMinutes,
    });
  }

  Stream<QuerySnapshot> get messages {
    return users
        .doc(user?.uid)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> sendEmail({
    required String recipientUid,
    required String subject,
    required String message,
    String channel = 'mail',
  }) async {
    if (user?.uid == null) {
      throw StateError('Current user is missing');
    }

    final senderSnapshot = await users.doc(user?.uid).get();
    final senderData = senderSnapshot.data() as Map<String, dynamic>?;
    final recipientSnapshot = await users.doc(recipientUid).get();
    final recipientData = recipientSnapshot.data() as Map<String, dynamic>?;
    final senderName =
        (senderData?['fullName'] as String?)?.trim().isNotEmpty == true
        ? (senderData!['fullName'] as String).trim()
        : '${(senderData?['firstName'] as String?)?.trim() ?? ''} ${(senderData?['lastName'] as String?)?.trim() ?? ''}'
              .trim();
    final recipientName =
        (recipientData?['fullName'] as String?)?.trim().isNotEmpty == true
        ? (recipientData!['fullName'] as String).trim()
        : '${(recipientData?['firstName'] as String?)?.trim() ?? ''} ${(recipientData?['lastName'] as String?)?.trim() ?? ''}'
              .trim();
    final threadId = _buildThreadId(user!.uid, recipientUid);
    final createdAtClient = Timestamp.now();
    final createdAt = FieldValue.serverTimestamp();
    final senderUtcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

    await users.doc(recipientUid).collection('emails').add({
      'channel': channel,
      'threadId': threadId,
      'senderId': user?.uid,
      'senderName': senderName.isEmpty ? (user?.email ?? '') : senderName,
      'recipientId': recipientUid,
      'recipientName': recipientName,
      'otherUserId': user?.uid,
      'otherUserName': senderName.isEmpty ? (user?.email ?? '') : senderName,
      'subject': subject,
      'message': message,
      'createdAtClient': createdAtClient,
      'createdAt': createdAt,
      'senderUtcOffsetMinutes': senderUtcOffsetMinutes,
      'isUnread': true,
      'isReadByRecipient': true,
      'type': 'received',
    });

    await users.doc(user?.uid).collection('emails').add({
      'channel': channel,
      'threadId': threadId,
      'senderId': user?.uid,
      'senderName': senderName.isEmpty ? (user?.email ?? '') : senderName,
      'recipientId': recipientUid,
      'recipientName': recipientName,
      'otherUserId': recipientUid,
      'otherUserName': recipientName.isEmpty
          ? ((recipientData?['email'] as String?) ?? recipientUid)
          : recipientName,
      'subject': subject,
      'message': message,
      'createdAtClient': createdAtClient,
      'createdAt': createdAt,
      'senderUtcOffsetMinutes': senderUtcOffsetMinutes,
      'isUnread': false,
      'isReadByRecipient': false,
      'type': 'sent',
    });
  }

  Stream<QuerySnapshot> get inbox {
    return users
        .doc(user?.uid)
        .collection('emails')
        .where('type', isEqualTo: 'received')
        .snapshots();
  }

  Stream<QuerySnapshot> get emailMessages {
    return users
        .doc(user?.uid)
        .collection('emails')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> updateEmailMessage({
    required String messageId,
    required String newText,
    required String recipientId,
    required Timestamp createdAtClient,
  }) async {
    if (user?.uid == null) return;

    // 1. Update sender's copy
    await users.doc(user!.uid).collection('emails').doc(messageId).update({
      'message': newText,
      'isEdited': true,
    });

    // 2. Update recipient's copy
    // We match by 'createdAtClient' which is shared between both copies
    try {
      final query = await users
          .doc(recipientId)
          .collection('emails')
          .where('senderId', isEqualTo: user!.uid)
          .get();

      QueryDocumentSnapshot? recipientCopy;
      for (final doc in query.docs) {
        final data = doc.data();
        final ts = data['createdAtClient'];
        if (ts is Timestamp && ts == createdAtClient) {
          recipientCopy = doc;
          break;
        }
      }

      if (recipientCopy != null) {
        await recipientCopy.reference.update({
          'message': newText,
          'isEdited': true,
        });
      }
    } catch (e) {
      log('Failed to update recipient message copy: $e');
    }
  }

  Future<void> deleteEmailMessage({
    required String messageId,
    required String recipientId,
    required Timestamp? createdAtClient,
  }) async {
    if (user?.uid == null) return;

    // 1. Delete sender's copy
    // Instead of deleting, we could mark as deleted for soft-delete.
    // But for "unsending" we delete.
    await users.doc(user!.uid).collection('emails').doc(messageId).delete();

    // 2. Delete recipient's copy if we are the sender
    // We match by 'createdAtClient' which is shared between both copies
    if (createdAtClient != null) {
      try {
        final query = await users
            .doc(recipientId)
            .collection('emails')
            .where('senderId', isEqualTo: user!.uid)
            .get();

        QueryDocumentSnapshot? recipientCopy;
        for (final doc in query.docs) {
          final data = doc.data();
          final ts = data['createdAtClient'];
          if (ts is Timestamp && ts == createdAtClient) {
            recipientCopy = doc;
            break;
          }
        }

        if (recipientCopy != null) {
          await recipientCopy.reference.delete();
        }
      } catch (e) {
        log('Failed to delete recipient message copy: $e');
      }
    }
  }

  String _buildThreadId(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  Future<List<QueryDocumentSnapshot>> searchRecipients(
    String query, {
    int limit = 30,
  }) async {
    final normalizedToken = SearchHelper.queryToken(query);
    if (normalizedToken.isEmpty) return [];

    final snapshot = await users
        .where('searchKeywords', arrayContains: normalizedToken)
        .limit(limit)
        .get();

    return snapshot.docs
        .where((doc) => doc.id != user?.uid)
        .toList(growable: false);
  }

  Future<void> updateUserData(String name, String studentId, double gpa) async {
    return await users.doc(user?.uid).set({
      'name': name,
      'studentId': studentId,
      'gpa': gpa,
    }, SetOptions(merge: true));
  }

  Future<void> saveFCMToken(String token) async {
    if (user?.uid == null) return;
    return await users.doc(user!.uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  Future<void> createStudentProfile({
    required String firstName,
    required String lastName,
    required String faculty,
    required String email,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final counterRef = firestore
        .collection('system_counters')
        .doc('student_ids');
    final now = DateTime.now();
    final yearSuffix = now.year.toString().substring(2);
    final facultyCode = faculty == 'SOCIE' ? '1' : '0';
    final counterField = '${faculty}_${now.year}';

    try {
      String studentId = await firestore.runTransaction((transaction) async {
        DocumentSnapshot counterSnapshot = await transaction.get(counterRef);

        if (!counterSnapshot.exists) {
          transaction.set(counterRef, {counterField: 0});
        }

        int currentCount =
            (counterSnapshot.data() as Map<String, dynamic>?)?[counterField] ??
            0;
        int newCount = currentCount + 1;

        transaction.set(counterRef, {
          counterField: newCount,
        }, SetOptions(merge: true));

        return 'U$yearSuffix$facultyCode${newCount.toString().padLeft(4, '0')}';
      });

      await users.doc(user?.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'fullName': '$firstName $lastName',
        'faculty': faculty,
        'email': email,
        'studentId': studentId,
        'searchKeywords': SearchHelper.buildSearchKeywords(
          fullName: '$firstName $lastName',
          firstName: firstName,
          lastName: lastName,
          studentId: studentId,
          group: '',
          email: email,
        ),
        'role': 'student',
        'createdAt': FieldValue.serverTimestamp(),
        'gpa': 0.0,
      });
    } catch (e) {
      log('Error generating student ID: $e');
      rethrow;
    }
  }
}
