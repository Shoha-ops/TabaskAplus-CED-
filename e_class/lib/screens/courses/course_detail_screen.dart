import 'package:cached_network_image/cached_network_image.dart';
import 'package:e_class/models/courses/course.dart';
import 'package:e_class/services/courses_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  late ScrollController _scrollController;

  String _staffDocIdFromName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> _confirmAndOpenUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid link')));
      return;
    }

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open Link'),
        content: Text('Open this link?\n\n$url'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (shouldOpen != true) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedWeek = widget.currentWeek;
    // Estimate item width ~100px (80 + padding)
    // Screen width / 2 => center
    // We'll adjust in post frame callback for better accuracy if possible,
    // but simple initial offset is often enough for "centered-ish".
    // Better: Scroll to index.

    // Defer to post frame to get context size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double itemWidth = 110.0; // Approximate width of week card
        final double target =
            ((_selectedWeek - 1) * itemWidth) -
            (screenWidth / 2) +
            (itemWidth / 2);
        _scrollController.jumpTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
    });
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.title),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              // Random actions
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Selected: $value')));
            },
            itemBuilder: (BuildContext context) {
              return {'Syllabus', 'Grades', 'Attendance', 'Settings'}.map((
                String choice,
              ) {
                return PopupMenuItem<String>(
                  value: choice,
                  child: Text(choice),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Professor Section
            if (widget.course.professorId.isNotEmpty ||
                widget.course.professorName.trim().isNotEmpty)
              FutureBuilder<Staff?>(
                future: _coursesService.getStaff(
                  widget.course.professorId.isNotEmpty
                      ? widget.course.professorId
                      : _staffDocIdFromName(widget.course.professorName),
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    if (widget.course.professorName.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _buildFallbackProfessorCard(context);
                  }
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
                  if (assistantId.isNotEmpty && assistantId != professor.id) {
                    widgets.add(
                      FutureBuilder<Staff?>(
                        future: _coursesService.getStaff(assistantId),
                        builder: (context, assistantSnapshot) {
                          if (!assistantSnapshot.hasData) {
                            return const SizedBox.shrink();
                          }
                          final assistant = assistantSnapshot.data;
                          if (assistant == null) return const SizedBox.shrink();
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

            // Weeks Scroll
            SizedBox(
              height: 80,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 16,
                itemExtent: 110.0, // Fixed width for easier scrolling math
                itemBuilder: (context, index) {
                  final weekNum = index + 1;
                  final isSelected = weekNum == _selectedWeek;

                  // Calculate dates
                  final startDate = DateTime(
                    2026,
                    2,
                    7,
                  ).add(Duration(days: (weekNum - 1) * 7));
                  final endDate = startDate.add(const Duration(days: 6));
                  final dateFormat = DateFormat('d MMM');
                  final rangeText =
                      '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}';

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Week $weekNum'),
                          Text(
                            rangeText,
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected ? Colors.white70 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedWeek = weekNum;
                          });
                        }
                      },
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(),

            // Content for Selected Week
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Week $_selectedWeek Content',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),

                  // Announcements
                  _buildSectionTitle('Announcements'),
                  StreamBuilder<List<Announcement>>(
                    stream: _coursesService.getAnnouncements(
                      widget.course.id,
                      _selectedWeek,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final announcements = snapshot.data ?? [];
                      if (announcements.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No announcements yet.'),
                        );
                      }

                      return Column(
                        children: announcements
                            .map(
                              (ann) => Card(
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.announcement,
                                    color: Colors.orange,
                                  ),
                                  title: Text(ann.title),
                                  subtitle: Text(ann.content),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Materials
                  _buildSectionTitle('Materials'),
                  StreamBuilder<List<CourseMaterial>>(
                    stream: _coursesService.getMaterials(
                      widget.course.id,
                      _selectedWeek,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final materials = snapshot.data ?? [];
                      if (materials.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No materials uploaded yet.'),
                        );
                      }

                      return Column(
                        children: materials
                            .map(
                              (mat) => Card(
                                child: ListTile(
                                  leading: Icon(
                                    mat.type == 'lecture'
                                        ? Icons.slideshow
                                        : Icons.assignment,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  title: Text(mat.title),
                                  subtitle: Text(
                                    mat.deadline == null
                                        ? mat.type.toUpperCase()
                                        : '${mat.type.toUpperCase()} вЂў Deadline: ${DateFormat('d MMM, HH:mm').format(mat.deadline!)}',
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () => _confirmAndOpenUrl(mat.url),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackProfessorCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      ),
    );
  }

  Widget _buildStaffCard(Staff staff, BuildContext context, String roleLabel) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CachedNetworkImage(
                  imageUrl: staff.avatarUrl,
                  imageBuilder: (context, imageProvider) =>
                      CircleAvatar(backgroundImage: imageProvider, radius: 24),
                  placeholder: (context, url) => const CircleAvatar(
                    radius: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) =>
                      const CircleAvatar(radius: 24, child: Icon(Icons.person)),
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
              ],
            ),
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
                        title: Text('${hour.day} вЂў ${hour.time}'),
                        subtitle: Text('Cabinet: ${hour.location}'),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }
}
