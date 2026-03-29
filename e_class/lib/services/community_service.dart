import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/community_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CommunityService {
  CommunityService({required this.user});

  final User? user;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final List<CommunityModel> catalog = [
    CommunityModel(
      id: 'flutter_builders',
      name: 'Flutter Builders',
      topic: 'Mobile Development',
      description:
          'Dart, Flutter UI, animations, state management and app launches.',
      tags: ['Flutter', 'Dart', 'Mobile'],
      icon: const IconData(0xe286, fontFamily: 'MaterialIcons'),
      color: const Color(0xFF1D9BF0),
      memberCount: 248,
      seedMessages: [
        CommunitySeedMessage(
          senderId: 'student_amina',
          senderName: 'Amina Niyazova',
          message:
              'I finally understood how to structure widgets without making one huge screen.',
          minutesAgo: 170,
        ),
        CommunitySeedMessage(
          senderId: 'student_temur',
          senderName: 'Temur Aliyev',
          message:
              'If anyone wants, I can share my clean architecture notes for Flutter.',
          minutesAgo: 152,
        ),
        CommunitySeedMessage(
          senderId: 'student_madina',
          senderName: 'Madina Rakhmatova',
          message:
              'Hot reload still feels like magic when deadlines are close.',
          minutesAgo: 140,
        ),
      ],
    ),
    CommunityModel(
      id: 'ai_study_circle',
      name: 'AI Study Circle',
      topic: 'AI & ML',
      description:
          'LLMs, classical ML, prompts, Python notebooks and model ideas.',
      tags: ['AI', 'Machine Learning', 'Python'],
      icon: const IconData(0xe4f8, fontFamily: 'MaterialIcons'),
      color: const Color(0xFF13B38B),
      memberCount: 312,
      seedMessages: [
        CommunitySeedMessage(
          senderId: 'student_bekzod',
          senderName: 'Bekzod Karimov',
          message:
              'Our team tested a tiny recommendation model and it worked better than expected.',
          minutesAgo: 210,
        ),
        CommunitySeedMessage(
          senderId: 'student_sabina',
          senderName: 'Sabina Tursunova',
          message:
              'Can someone explain the difference between fine-tuning and RAG in simple words?',
          minutesAgo: 204,
        ),
        CommunitySeedMessage(
          senderId: 'student_jasur',
          senderName: 'Jasur Mamatov',
          message:
              'I can post a shortlist of beginner-friendly ML datasets later today.',
          minutesAgo: 176,
        ),
      ],
    ),
    CommunityModel(
      id: 'backend_forge',
      name: 'Backend Forge',
      topic: 'Backend',
      description:
          'APIs, authentication, databases, clean services and performance.',
      tags: ['API', 'Node', 'Databases'],
      icon: const IconData(0xf051, fontFamily: 'MaterialIcons'),
      color: const Color(0xFFEF6C45),
      memberCount: 196,
      seedMessages: [
        CommunitySeedMessage(
          senderId: 'student_aziza',
          senderName: 'Aziza Kamilova',
          message:
              'I switched my project from local JSON to Firestore and learned a lot about data modeling.',
          minutesAgo: 300,
        ),
        CommunitySeedMessage(
          senderId: 'student_umar',
          senderName: 'Umar Ruziev',
          message:
              'JWT auth finally clicked for me after drawing the whole flow on paper.',
          minutesAgo: 265,
        ),
        CommunitySeedMessage(
          senderId: 'student_ruslan',
          senderName: 'Ruslan Ergashev',
          message:
              'Who else is using Postman collections to test every endpoint before demos?',
          minutesAgo: 251,
        ),
      ],
    ),
    CommunityModel(
      id: 'frontend_lab',
      name: 'Frontend Lab',
      topic: 'Frontend',
      description:
          'Modern UI, React ideas, design systems, accessibility and polish.',
      tags: ['Frontend', 'UI', 'CSS'],
      icon: const IconData(0xe40a, fontFamily: 'MaterialIcons'),
      color: const Color(0xFF8B5CF6),
      memberCount: 227,
      seedMessages: [
        CommunitySeedMessage(
          senderId: 'student_lola',
          senderName: 'Lola Abdullaeva',
          message:
              'Spacing and typography changed my whole landing page more than any animation.',
          minutesAgo: 132,
        ),
        CommunitySeedMessage(
          senderId: 'student_daler',
          senderName: 'Daler Yusupov',
          message:
              'I can share a few color palette tools if anyone is redesigning their portfolio.',
          minutesAgo: 120,
        ),
        CommunitySeedMessage(
          senderId: 'student_muhlisa',
          senderName: 'Muhlisa Ismoilova',
          message:
              'Accessibility audit is harder than I thought, but super useful.',
          minutesAgo: 109,
        ),
      ],
    ),
    CommunityModel(
      id: 'devops_cloud_ops',
      name: 'DevOps Cloud Ops',
      topic: 'DevOps & Cloud',
      description:
          'CI/CD, Docker, deployments, observability and infrastructure basics.',
      tags: ['DevOps', 'Docker', 'Cloud'],
      icon: const IconData(0xe1b8, fontFamily: 'MaterialIcons'),
      color: const Color(0xFF0EA5A4),
      memberCount: 184,
      seedMessages: [
        CommunitySeedMessage(
          senderId: 'student_shohruh',
          senderName: 'Shohruh Akbarov',
          message:
              'My app finally deploys automatically after every push and I feel unstoppable.',
          minutesAgo: 355,
        ),
        CommunitySeedMessage(
          senderId: 'student_munisa',
          senderName: 'Munisa Rakhimova',
          message:
              'Docker became much less scary once I started writing tiny compose files.',
          minutesAgo: 333,
        ),
        CommunitySeedMessage(
          senderId: 'student_odil',
          senderName: 'Odilbek Nurmatov',
          message:
              'Anyone monitoring logs from Firebase and local builds side by side?',
          minutesAgo: 317,
        ),
      ],
    ),
  ];

  static CommunityModel? byId(String id) {
    for (final community in catalog) {
      if (community.id == id) return community;
    }
    return null;
  }

  Future<void> ensureSeeded() async {
    final communities = _db.collection('communities');
    for (final community in catalog) {
      final ref = communities.doc(community.id);
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        await ref.set({
          'name': community.name,
          'topic': community.topic,
          'description': community.description,
          'tags': community.tags,
          'colorValue': community.color.toARGB32(),
          'iconCodePoint': community.icon.codePoint,
          'iconFontFamily': community.icon.fontFamily,
          'memberCount': community.memberCount,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final messagesRef = ref.collection('messages');
      final existingMessages = await messagesRef.limit(1).get();
      if (existingMessages.docs.isNotEmpty) {
        continue;
      }

      final now = DateTime.now();
      final batch = _db.batch();
      CommunitySeedMessage? lastSeed;
      DateTime? lastTime;

      for (final seed in community.seedMessages) {
        final createdAt = now.subtract(Duration(minutes: seed.minutesAgo));
        final doc = messagesRef.doc();
        batch.set(doc, {
          'senderId': seed.senderId,
          'senderName': seed.senderName,
          'message': seed.message,
          'messageType': 'text',
          'createdAtClient': Timestamp.fromDate(createdAt),
          'createdAt': FieldValue.serverTimestamp(),
          'reactions': const <String, dynamic>{},
          'isSeedMessage': true,
        });
        if (lastTime == null || createdAt.isAfter(lastTime)) {
          lastTime = createdAt;
          lastSeed = seed;
        }
      }

      if (lastSeed != null && lastTime != null) {
        batch.set(ref, {
          'lastMessage': lastSeed.message,
          'lastMessageAt': Timestamp.fromDate(lastTime),
          'lastSenderId': lastSeed.senderId,
          'lastSenderName': lastSeed.senderName,
        }, SetOptions(merge: true));
      }

      await batch.commit();
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> userDocumentStream() {
    final uid = user?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _db.collection('users').doc(uid).snapshots();
  }

  Future<void> joinCommunity(CommunityModel community) async {
    final uid = user?.uid;
    if (uid == null) {
      throw StateError('Current user is missing');
    }

    await ensureSeeded();

    final userRef = _db.collection('users').doc(uid);
    final userSnapshot = await userRef.get();
    final joined =
        ((userSnapshot.data()?['joinedCommunities'] as List?) ?? const [])
            .map((item) => item.toString())
            .contains(community.id);

    await userRef.set({
      'joinedCommunities': FieldValue.arrayUnion([community.id]),
    }, SetOptions(merge: true));

    await _db.collection('communities').doc(community.id).set({
      'memberIds': FieldValue.arrayUnion([uid]),
      if (!joined) 'memberCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> joinedCommunitiesStream(
    List<String> joinedIds,
  ) {
    if (joinedIds.isEmpty) {
      return const Stream.empty();
    }
    return _db
        .collection('communities')
        .where(FieldPath.documentId, whereIn: joinedIds.take(10).toList())
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> communityMessages(
    String communityId,
  ) {
    return _db
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('createdAtClient', descending: false)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> communityStream(
    String communityId,
  ) {
    return _db.collection('communities').doc(communityId).snapshots();
  }

  Future<void> sendCommunityMessage({
    required String communityId,
    required String message,
    required Timestamp createdAtClient,
    String? clientMessageId,
    Map<String, dynamic>? replyPreview,
  }) async {
    final uid = user?.uid;
    if (uid == null) {
      throw StateError('Current user is missing');
    }

    final senderSnapshot = await _db.collection('users').doc(uid).get();
    final senderData = senderSnapshot.data();
    final senderName =
        (senderData?['fullName'] as String?)?.trim().isNotEmpty == true
        ? (senderData!['fullName'] as String).trim()
        : user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email ?? 'Student');

    await _db
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .add({
          'clientMessageId': clientMessageId,
          'senderId': uid,
          'senderName': senderName,
          'message': message,
          'messageType': 'text',
          'createdAtClient': createdAtClient,
          'createdAt': FieldValue.serverTimestamp(),
          'reactions': const <String, dynamic>{},
          if (replyPreview != null)
            'replyToMessageId': replyPreview['messageId'],
          if (replyPreview != null) 'replyToText': replyPreview['text'],
          if (replyPreview != null) 'replyToSenderId': replyPreview['senderId'],
          if (replyPreview != null)
            'replyToSenderName': replyPreview['senderName'],
          if (replyPreview != null)
            'replyToMessageType': replyPreview['messageType'] ?? 'text',
        });

    await _db.collection('communities').doc(communityId).set({
      'lastMessage': message,
      'lastMessageAt': createdAtClient,
      'lastSenderId': uid,
      'lastSenderName': senderName,
    }, SetOptions(merge: true));
  }

  Future<void> updateCommunityMessage({
    required String communityId,
    required String messageId,
    required String newText,
  }) async {
    await _db
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .doc(messageId)
        .update({
          'message': newText,
          'isEdited': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    await _syncCommunityLastMessage(communityId);
  }

  Future<void> toggleCommunityReaction({
    required String communityId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = user?.uid;
    if (uid == null) return;

    final ref = _db
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .doc(messageId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null) return;

    final rawReactions = data['reactions'];
    final reactions = <String, List<String>>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        final value = entry.value;
        if (value is List) {
          reactions[entry.key.toString()] = value
              .map((item) => item.toString())
              .toList();
        }
      }
    }

    final usersForEmoji = List<String>.from(
      reactions[emoji] ?? const <String>[],
    );
    if (usersForEmoji.contains(uid)) {
      usersForEmoji.removeWhere((id) => id == uid);
    } else {
      usersForEmoji.add(uid);
    }

    if (usersForEmoji.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = usersForEmoji;
    }

    await ref.update({'reactions': reactions});
  }

  Future<void> deleteCommunityMessage({
    required String communityId,
    required String messageId,
  }) async {
    await _db
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .doc(messageId)
        .delete();
    await _syncCommunityLastMessage(communityId);
  }

  Future<void> _syncCommunityLastMessage(String communityId) async {
    final latest = await _db
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('createdAtClient', descending: true)
        .limit(1)
        .get();

    if (latest.docs.isEmpty) {
      await _db.collection('communities').doc(communityId).set({
        'lastMessage': '',
        'lastSenderId': '',
        'lastSenderName': '',
        'lastMessageAt': null,
      }, SetOptions(merge: true));
      return;
    }

    final data = latest.docs.first.data();
    await _db.collection('communities').doc(communityId).set({
      'lastMessage': (data['message'] as String?)?.trim() ?? '',
      'lastSenderId': (data['senderId'] as String?)?.trim() ?? '',
      'lastSenderName': (data['senderName'] as String?)?.trim() ?? '',
      'lastMessageAt': data['createdAtClient'] as Timestamp?,
    }, SetOptions(merge: true));
  }
}
