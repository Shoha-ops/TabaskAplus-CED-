import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/courses/course.dart';
import 'package:e_class/screens/messages/compose_message_screen.dart';
import 'package:e_class/services/courses_service.dart';
import 'package:e_class/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class CourseDetailScreen extends StatefulWidget {
  final Course course;
  final int currentWeek;

  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.currentWeek,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late int _selectedWeek;
  final CoursesService _coursesService = CoursesService();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _selectedWeek = widget.currentWeek;
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final screenWidth = MediaQuery.of(context).size.width;
      const itemWidth = 110.0;
      final target =
          ((_selectedWeek - 1) * itemWidth) -
          (screenWidth / 2) +
          (itemWidth / 2);
      _scrollController.jumpTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _staffDocIdFromName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  bool _matchesCourseScheduleRow(Map<String, dynamic> row) {
    final subject = (row['subject'] ?? row['subjectTitle'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final subjectCode = (row['subjectCode'] ?? row['code'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final courseId = widget.course.id.trim().toLowerCase();
    final courseTitle = widget.course.title.trim().toLowerCase();

    return subject == courseTitle ||
        subject.contains(courseTitle) ||
        subjectCode == courseId ||
        subjectCode == courseTitle.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  DateTime? _nextClassTime(Map<String, dynamic> row) {
    final dayRaw = (row['dayIndex'] ?? row['day'] ?? row['weekday'])
        .toString()
        .trim()
        .toLowerCase();
    final days = {
      '1': DateTime.monday,
      '2': DateTime.tuesday,
      '3': DateTime.wednesday,
      '4': DateTime.thursday,
      '5': DateTime.friday,
      '6': DateTime.saturday,
      '7': DateTime.sunday,
      'mon': DateTime.monday,
      'monday': DateTime.monday,
      'tue': DateTime.tuesday,
      'tuesday': DateTime.tuesday,
      'wed': DateTime.wednesday,
      'wednesday': DateTime.wednesday,
      'thu': DateTime.thursday,
      'thursday': DateTime.thursday,
      'fri': DateTime.friday,
      'friday': DateTime.friday,
      'sat': DateTime.saturday,
      'saturday': DateTime.saturday,
      'sun': DateTime.sunday,
      'sunday': DateTime.sunday,
    };
    final weekday = days[dayRaw];
    if (weekday == null) return null;

    final time = (row['time'] ?? '').toString().trim();
    final startPart = time.split(' - ').first.trim();
    final parts = startPart.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    while (candidate.weekday != weekday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  String _nextClassLabel(List<Map<String, dynamic>> rows) {
    final relevant = rows.where(_matchesCourseScheduleRow).toList();
    if (relevant.isEmpty) return 'Class time will appear here';

    relevant.sort((a, b) {
      final aTime = _nextClassTime(a);
      final bTime = _nextClassTime(b);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });

    final next = relevant.first;
    final nextTime = _nextClassTime(next);
    final day = (next['dayLabel'] ?? next['day'] ?? '').toString().trim();
    final time = (next['time'] ?? '').toString().trim();
    final room = (next['room'] ?? next['location'] ?? '').toString().trim();

    final info = [
      if (day.isNotEmpty) day,
      if (time.isNotEmpty) time,
      if (room.isNotEmpty) room,
      if (nextTime != null) DateFormat('d MMM').format(nextTime),
    ];
    return info.isEmpty ? 'Class is on the schedule' : info.join(' • ');
  }

  String _formatDeadline(DateTime? value) {
    if (value == null) return 'Nothing due yet';
    return DateFormat('d MMM, HH:mm').format(value);
  }

  String _weekRangeLabel(int weekNum) {
    final startDate = DateTime(
      2026,
      2,
      7,
    ).add(Duration(days: (weekNum - 1) * 7));
    final endDate = startDate.add(const Duration(days: 6));
    final format = DateFormat('d MMM');
    return '${format.format(startDate)} - ${format.format(endDate)}';
  }

  Future<void> _confirmAndOpenUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This material does not have a valid link yet.'),
        ),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open this link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final db = DatabaseService(user: user);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.course.title)),
      body: StreamBuilder<DocumentSnapshot>(
        stream: db.userData,
        builder: (context, userSnapshot) {
          final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
          final groupName = (userData?['group'] as String?)?.trim() ?? '';

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: db.scheduleEntriesForGroup(groupName),
            initialData: const <Map<String, dynamic>>[],
            builder: (context, scheduleSnapshot) {
              final nextClass = _nextClassLabel(
                scheduleSnapshot.data ?? const [],
              );

              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primaryContainer,
                            scheme.surfaceContainerHigh,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.course.title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildOverviewChip(
                                context,
                                icon: Icons.person_outline_rounded,
                                label: widget.course.professorName.isEmpty
                                    ? 'Professor TBA'
                                    : widget.course.professorName,
                              ),
                              _buildOverviewChip(
                                context,
                                icon: Icons.calendar_month_rounded,
                                label: widget.course.semester,
                              ),
                              _buildOverviewChip(
                                context,
                                icon: Icons.schedule_rounded,
                                label: nextClass,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.course.professorId.isNotEmpty ||
                        widget.course.professorName.trim().isNotEmpty)
                      FutureBuilder<Staff?>(
                        future: _coursesService.getStaff(
                          widget.course.professorId.isNotEmpty
                              ? widget.course.professorId
                              : _staffDocIdFromName(
                                  widget.course.professorName,
                                ),
                        ),
                        builder: (context, snapshot) {
                          final professor = snapshot.data;
                          if (professor == null) {
                            if (widget.course.professorName.trim().isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _buildFallbackProfessorCard(context);
                          }

                          final widgets = <Widget>[
                            _buildStaffCard(professor, context, 'Professor'),
                          ];

                          final assistantId = professor.assistantId.trim();
                          if (assistantId.isNotEmpty &&
                              assistantId != professor.id) {
                            widgets.add(
                              FutureBuilder<Staff?>(
                                future: _coursesService.getStaff(assistantId),
                                builder: (context, assistantSnapshot) {
                                  final assistant = assistantSnapshot.data;
                                  if (assistant == null) {
                                    return const SizedBox.shrink();
                                  }

                                  final professorName = professor.name
                                      .trim()
                                      .toLowerCase();
                                  final assistantName = assistant.name
                                      .trim()
                                      .toLowerCase();
                                  if (professorName.isNotEmpty &&
                                      assistantName == professorName) {
                                    return const SizedBox.shrink();
                                  }

                                  return _buildStaffCard(
                                    assistant,
                                    context,
                                    'Assistant',
                                  );
                                },
                              ),
                            );
                          }

                          return Column(children: widgets);
                        },
                      ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Weeks',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 82,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: 16,
                        itemExtent: 110,
                        itemBuilder: (context, index) {
                          final weekNum = index + 1;
                          final isSelected = weekNum == _selectedWeek;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              showCheckmark: false,
                              selected: isSelected,
                              onSelected: (_) =>
                                  setState(() => _selectedWeek = weekNum),
                              label: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Week $weekNum'),
                                  Text(
                                    _weekRangeLabel(weekNum),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected
                                          ? Colors.white70
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<Announcement>>(
                      stream: _coursesService.getAnnouncements(
                        widget.course.id,
                        _selectedWeek,
                      ),
                      builder: (context, announcementsSnapshot) {
                        return StreamBuilder<List<CourseMaterial>>(
                          stream: _coursesService.getMaterials(
                            widget.course.id,
                            _selectedWeek,
                          ),
                          builder: (context, materialsSnapshot) {
                            final announcements =
                                announcementsSnapshot.data ?? const [];
                            final materials =
                                materialsSnapshot.data ?? const [];
                            final datedMaterials =
                                materials
                                    .where((item) => item.deadline != null)
                                    .toList()
                                  ..sort(
                                    (a, b) =>
                                        a.deadline!.compareTo(b.deadline!),
                                  );
                            final nextDeadline = datedMaterials.isEmpty
                                ? null
                                : datedMaterials.first.deadline;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSummaryCard(
                                          context,
                                          title: 'Announcements',
                                          value: '${announcements.length}',
                                          subtitle: 'Week $_selectedWeek',
                                          icon: Icons.campaign_rounded,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildSummaryCard(
                                          context,
                                          title: 'Next deadline',
                                          value: _formatDeadline(nextDeadline),
                                          subtitle: nextDeadline == null
                                              ? 'Nothing due yet'
                                              : 'From materials',
                                          icon: Icons.assignment_late_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  _buildSectionHeader(context, 'Announcements'),
                                  if (announcementsSnapshot.connectionState ==
                                          ConnectionState.waiting &&
                                      !announcementsSnapshot.hasData)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  else if (announcements.isEmpty)
                                    _buildEmptySection(
                                      context,
                                      icon: Icons.campaign_outlined,
                                      title: 'No announcements this week',
                                      subtitle:
                                          'Important notes from the professor will appear here.',
                                    )
                                  else
                                    ...announcements.map(
                                      (ann) => Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(
                                            14,
                                          ),
                                          leading: const Icon(
                                            Icons.campaign_rounded,
                                            color: Colors.orange,
                                          ),
                                          title: Text(
                                            ann.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              ann.content.isEmpty
                                                  ? 'Open course materials and weekly tasks for details.'
                                                  : ann.content,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 18),
                                  _buildSectionHeader(context, 'Materials'),
                                  if (materialsSnapshot.connectionState ==
                                          ConnectionState.waiting &&
                                      !materialsSnapshot.hasData)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  else if (materials.isEmpty)
                                    _buildEmptySection(
                                      context,
                                      icon: Icons.folder_open_rounded,
                                      title: 'No materials for this week',
                                      subtitle:
                                          'Lecture files, homework and links will appear here.',
                                    )
                                  else
                                    ...materials.map(
                                      (material) => Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(
                                            14,
                                          ),
                                          leading: Icon(
                                            material.type == 'lecture'
                                                ? Icons.slideshow_rounded
                                                : Icons.assignment_rounded,
                                            color: scheme.primary,
                                          ),
                                          title: Text(
                                            material.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Text(
                                            [
                                              material.type.isEmpty
                                                  ? 'Material'
                                                  : material.type.toUpperCase(),
                                              if (material.deadline != null)
                                                'Due ${_formatDeadline(material.deadline)}',
                                            ].join(' • '),
                                          ),
                                          trailing: const Icon(
                                            Icons.open_in_new_rounded,
                                          ),
                                          onTap: () =>
                                              _confirmAndOpenUrl(material.url),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildOverviewChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildEmptySection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: scheme.outline),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackProfessorCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openComposeMail(
          recipientId: widget.course.professorId,
          recipientName: widget.course.professorName,
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.school_rounded,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(widget.course.professorName),
          subtitle: const Text('Professor'),
          trailing: const Icon(Icons.mail_outline_rounded),
        ),
      ),
    );
  }

  void _openComposeMail({
    required String recipientId,
    required String recipientName,
  }) {
    final normalizedName = recipientName.trim();
    if (normalizedName.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeMessageScreen(
          initialRecipientId: recipientId.trim().isEmpty
              ? null
              : recipientId.trim(),
          initialRecipientName: normalizedName,
          isChat: false,
        ),
      ),
    );
  }

  Widget _buildStaffCard(Staff staff, BuildContext context, String roleLabel) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            _openComposeMail(recipientId: staff.id, recipientName: staff.name),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CachedNetworkImage(
                    imageUrl: staff.avatarUrl,
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      backgroundImage: imageProvider,
                      radius: 24,
                    ),
                    placeholder: (context, url) => const CircleAvatar(
                      radius: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => const CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staff.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          roleLabel,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.mail_outline_rounded),
                ],
              ),
              if (staff.officeHours.isNotEmpty) ...[
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.schedule, size: 18),
                          SizedBox(width: 8),
                          Text('Office hours'),
                        ],
                      ),
                    ),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: staff.officeHours
                        .map(
                          (hour) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.access_time, size: 18),
                            title: Text('${hour.day} • ${hour.time}'),
                            subtitle: Text('Cabinet: ${hour.location}'),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
