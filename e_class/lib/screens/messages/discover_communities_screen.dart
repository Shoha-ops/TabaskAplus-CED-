import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/community_model.dart';
import 'package:e_class/screens/messages/conversation_screen.dart';
import 'package:e_class/services/community_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DiscoverCommunitiesScreen extends StatefulWidget {
  const DiscoverCommunitiesScreen({super.key});

  @override
  State<DiscoverCommunitiesScreen> createState() =>
      _DiscoverCommunitiesScreenState();
}

class _DiscoverCommunitiesScreenState extends State<DiscoverCommunitiesScreen> {
  static const String _allTopics = 'All';
  String _selectedTopic = _allTopics;
  bool _isJoining = false;

  List<String> get _topics => [
    _allTopics,
    ...{for (final community in CommunityService.catalog) community.topic},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<User?>(context, listen: false);
      if (user == null) return;
      CommunityService(user: user).ensureSeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final service = CommunityService(user: user);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1720),
        foregroundColor: Colors.white,
        title: const Text('Discover Communities'),
      ),
      body: user == null
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: service.userDocumentStream(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final joined =
                    ((data?['joinedCommunities'] as List?) ?? const [])
                        .map((item) => item.toString())
                        .toSet();

                final exploreList = CommunityService.catalog
                    .where(
                      (community) =>
                          _selectedTopic == _allTopics ||
                          community.topic == _selectedTopic,
                    )
                    .toList(growable: false);
                final recommended = CommunityService.catalog
                    .where((community) => !joined.contains(community.id))
                    .take(4)
                    .toList(growable: false);

                return SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1D4ED8), Color(0xFF0EA5A4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Explore communities by topic',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Join IT groups, meet students with similar interests and keep the conversation going in chats.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Explore Communities By Topic',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _topics.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final topic = _topics[index];
                            final isSelected = topic == _selectedTopic;
                            return ChoiceChip(
                              label: Text(topic),
                              selected: isSelected,
                              selectedColor: const Color(0xFF1D4ED8),
                              backgroundColor: const Color(0xFF1A2330),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.transparent
                                    : Colors.white10,
                              ),
                              onSelected: (_) {
                                setState(() {
                                  _selectedTopic = topic;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...exploreList.map(
                        (community) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CommunityCard(
                            community: community,
                            joined: joined.contains(community.id),
                            busy: _isJoining,
                            onJoin: () => _joinCommunity(service, community),
                            onOpen: () => _openCommunity(context, community),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Recommended For You',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...recommended.map(
                        (community) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RecommendedTile(
                            community: community,
                            onJoin: () => _joinCommunity(service, community),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _joinCommunity(
    CommunityService service,
    CommunityModel community,
  ) async {
    if (_isJoining) return;

    setState(() {
      _isJoining = true;
    });
    try {
      await service.joinCommunity(community);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You joined ${community.name}. It is now available in chats.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  void _openCommunity(BuildContext context, CommunityModel community) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          threadId: 'community_${community.id}',
          recipientId: community.id,
          recipientName: community.name,
          threadSubject: community.topic,
          channel: 'chat',
          isCommunity: true,
        ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.joined,
    required this.busy,
    required this.onJoin,
    required this.onOpen,
  });

  final CommunityModel community;
  final bool joined;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17212B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: community.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(community.icon, color: community.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${community.topic} • ${community.memberCount}+ students',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            community.description,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: community.tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : joined
                      ? onOpen
                      : onJoin,
                  style: FilledButton.styleFrom(
                    backgroundColor: joined
                        ? community.color
                        : const Color(0xFF1D4ED8),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(joined ? 'Open Chat' : 'Join Community'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendedTile extends StatelessWidget {
  const _RecommendedTile({required this.community, required this.onJoin});

  final CommunityModel community;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: const Color(0xFF17212B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: community.color.withValues(alpha: 0.18),
        child: Icon(community.icon, color: community.color),
      ),
      title: Text(
        community.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${community.topic} • ${community.memberCount}+ students',
        style: const TextStyle(color: Colors.white60),
      ),
      trailing: TextButton(onPressed: onJoin, child: const Text('Join')),
    );
  }
}
