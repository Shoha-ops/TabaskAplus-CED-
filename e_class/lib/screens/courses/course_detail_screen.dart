import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/courses/course.dart';
import 'package:e_class/screens/messages/compose_message_screen.dart';
import 'package:e_class/services/courses_service.dart';
import 'package:e_class/services/database_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class _ReplayLessonData {
  const _ReplayLessonData({
    required this.title,
    required this.summary,
    required this.takeaways,
    required this.quizQuestion,
    required this.quizOptions,
    required this.correctAnswerIndex,
  });

  final String title;
  final String summary;
  final List<String> takeaways;
  final String quizQuestion;
  final List<String> quizOptions;
  final int correctAnswerIndex;
}

class _UploadedCourseFile {
  const _UploadedCourseFile({
    required this.name,
    required this.label,
    required this.details,
    required this.icon,
  });

  final String name;
  final String label;
  final String details;
  final IconData icon;
}

class _UploadedCourseEntry {
  const _UploadedCourseEntry({required this.week, required this.file});

  final int week;
  final _UploadedCourseFile file;
}

class _HomeworkUploadFile {
  const _HomeworkUploadFile({
    required this.fileName,
    required this.filePath,
    required this.uploadedAt,
  });

  final String fileName;
  final String filePath;
  final DateTime uploadedAt;
}

class _HomeworkUploadBundle {
  const _HomeworkUploadBundle({
    required this.files,
  });

  final List<_HomeworkUploadFile> files;

  bool get hasUploadedFiles => files.any(
        (file) =>
            file.fileName.trim().isNotEmpty || file.filePath.trim().isNotEmpty,
      );
}

class CourseDetailScreen extends StatefulWidget {
  final Course course;
  final int currentWeek;
  final int? initialWeek;
  final String? initialMaterialTitle;
  final String? initialMaterialType;

  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.currentWeek,
    this.initialWeek,
    this.initialMaterialTitle,
    this.initialMaterialType,
  });

  static String homeworkUploadKey({
    required String courseId,
    required int weekNumber,
    required String materialTitle,
  }) {
    return '${courseId.trim().toUpperCase()}::$weekNumber::${materialTitle.trim().toLowerCase()}';
  }

  static bool hasUploadedHomework({
    required String courseId,
    required int weekNumber,
    required String materialTitle,
  }) {
    final bundle = _CourseDetailScreenState._homeworkUploads[
      homeworkUploadKey(
        courseId: courseId,
        weekNumber: weekNumber,
        materialTitle: materialTitle,
      )
    ];
    return bundle?.hasUploadedFiles ?? false;
  }

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  static final Map<String, _HomeworkUploadBundle> _homeworkUploads = {};
  static const List<_ReplayLessonData> _calculusRepeatLectures = [
    _ReplayLessonData(
      title: 'Calculus Replay: Limits and Continuity',
      summary:
          'This AI replay revisits how a function behaves near a point, why continuity matters, and how limit rules help simplify expressions before substitution.',
      takeaways: [
        'A limit describes the value a function approaches, not only the value it currently has.',
        'Continuity means the left-hand limit, right-hand limit, and function value match.',
        'Algebraic simplification often removes removable discontinuities before evaluation.',
      ],
      quizQuestion:
          'Which condition must be true for a function to be continuous at x = a?',
      quizOptions: [
        'The left and right limits exist and equal f(a)',
        'The derivative exists at every point',
        'The graph crosses the x-axis',
      ],
      correctAnswerIndex: 0,
    ),
    _ReplayLessonData(
      title: 'Calculus Replay: Derivative Rules',
      summary:
          'This replay covers power, product, quotient, and chain rules so the student can quickly recognize which derivative pattern fits each expression.',
      takeaways: [
        'The power rule is the fastest tool for polynomial derivatives.',
        'The chain rule is used when one function is nested inside another.',
        'Product and quotient rules help when expressions cannot be expanded cleanly.',
      ],
      quizQuestion:
          'Which rule is the best first choice for differentiating (3x^2 + 1)^5?',
      quizOptions: ['Product rule', 'Chain rule', 'Quotient rule'],
      correctAnswerIndex: 1,
    ),
    _ReplayLessonData(
      title: 'Calculus Replay: Applications of Derivatives',
      summary:
          'The AI summary explains how derivatives help find increasing intervals, local extrema, and optimization decisions in word problems.',
      takeaways: [
        'Critical points happen when the derivative is zero or undefined.',
        'Sign changes in the derivative help classify maxima and minima.',
        'Optimization problems usually need both a model and a domain check.',
      ],
      quizQuestion:
          'If f\'(x) changes from positive to negative at x = c, what happens at c?',
      quizOptions: ['Local maximum', 'Local minimum', 'Inflection point only'],
      correctAnswerIndex: 0,
    ),
    _ReplayLessonData(
      title: 'Calculus Replay: Definite Integrals',
      summary:
          'This replay introduces the definite integral as accumulated change and signed area, tying graphical intuition to formal notation.',
      takeaways: [
        'A definite integral measures accumulation over an interval.',
        'Area below the x-axis contributes negatively to signed area.',
        'The Fundamental Theorem links antiderivatives to exact values.',
      ],
      quizQuestion:
          'What does a definite integral primarily represent over an interval?',
      quizOptions: [
        'The slope at one point',
        'Accumulated change across the interval',
        'Only the highest y-value of the graph',
      ],
      correctAnswerIndex: 1,
    ),
    _ReplayLessonData(
      title: 'Calculus Replay: Techniques of Integration',
      summary:
          'The recap walks through substitution and basic pattern matching so repeated structures in integrals become easier to recognize.',
      takeaways: [
        'Substitution works best when the integrand contains a function and its derivative.',
        'Rewriting the expression first often reveals the right technique.',
        'Checking by differentiation is the fastest verification step.',
      ],
      quizQuestion: 'When is u-substitution most useful?',
      quizOptions: [
        'When the integral contains a nested function and its derivative',
        'When every term has different denominators',
        'When there are no variables left',
      ],
      correctAnswerIndex: 0,
    ),
  ];
  static const Map<String, Map<int, List<_UploadedCourseFile>>> _uploadedFiles =
      {
        'CAL2': {
          8: [
            _UploadedCourseFile(
              name: 'cal2_week8_slides.pdf',
              label: 'Lecture slides',
              details: 'Week 8 • Integrals recap • 24 pages',
              icon: Icons.picture_as_pdf_rounded,
            ),
            _UploadedCourseFile(
              name: 'cal2_week8_homework.docx',
              label: 'Homework',
              details: 'Week 8 • Practice set with 12 tasks',
              icon: Icons.description_rounded,
            ),
          ],
          5: [
            _UploadedCourseFile(
              name: 'cal2_week5_derivatives_notes.pdf',
              label: 'Lecture notes',
              details: 'Week 5 • Derivative rules summary',
              icon: Icons.sticky_note_2_rounded,
            ),
          ],
        },
        'AE2': {
          3: [
            _UploadedCourseFile(
              name: 'ae2_week3_speaking_prompts.pdf',
              label: 'Practice pack',
              details: 'Week 3 • Speaking prompts and vocabulary',
              icon: Icons.record_voice_over_rounded,
            ),
          ],
        },
        'PHY2': {
          6: [
            _UploadedCourseFile(
              name: 'phy2_week6_lab_sheet.pdf',
              label: 'Lab sheet',
              details: 'Week 6 • Motion lab instructions',
              icon: Icons.science_rounded,
            ),
            _UploadedCourseFile(
              name: 'phy2_week6_slides.pptx',
              label: 'Lecture slides',
              details: 'Week 6 • Dynamics review deck',
              icon: Icons.slideshow_rounded,
            ),
          ],
        },
      };

  late int _selectedWeek;
  final CoursesService _coursesService = CoursesService();
  late final ScrollController _scrollController;
  bool _initialMaterialOpened = false;

  @override
  void initState() {
    super.initState();
    _selectedWeek = widget.initialWeek ?? widget.currentWeek;
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

  bool _isLectureMaterial(CourseMaterial material) {
    return material.type.trim().toLowerCase() == 'lecture';
  }

  bool _usesCalculusRepeatStub(CourseMaterial material) {
    return widget.course.id.trim().toUpperCase() == 'CAL2' &&
        material.weekNumber == 8 &&
        _isLectureMaterial(material);
  }

  void _repeatLecture(CourseMaterial material) {
    if (_usesCalculusRepeatStub(material)) {
      final replayLesson =
          _calculusRepeatLectures[Random().nextInt(
            _calculusRepeatLectures.length,
          )];
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _LectureReplayScreen(
            courseTitle: widget.course.title,
            lectureTitle: material.title,
            replayLesson: replayLesson,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Repeat is a stub for now: "${material.title}" will be replayable later.',
        ),
      ),
    );
  }

  bool _isHomeworkMaterial(CourseMaterial material) {
    return material.type.trim().toLowerCase() == 'homework';
  }

  String _homeworkUploadKey(CourseMaterial material) {
    return CourseDetailScreen.homeworkUploadKey(
      courseId: widget.course.id,
      weekNumber: material.weekNumber,
      materialTitle: material.title,
    );
  }

  bool _hasUploadedHomework(CourseMaterial material) {
    final bundle = _homeworkUploads[_homeworkUploadKey(material)];
    return bundle?.hasUploadedFiles ?? false;
  }

  Future<void> _openHomework(CourseMaterial material) async {
    final upload = await Navigator.of(context).push<_HomeworkUploadBundle>(
      MaterialPageRoute(
        builder: (_) => _HomeworkDetailScreen(
          courseTitle: widget.course.title,
          material: material,
          initialUploadBundle: _homeworkUploads[_homeworkUploadKey(material)],
        ),
      ),
    );

    if (upload == null) return;

    setState(() {
      _homeworkUploads[_homeworkUploadKey(material)] = upload;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Files uploaded successfully.'),
        backgroundColor: Colors.green.shade600,
      ),
    );
  }

  Future<void> _openActionableMaterial(CourseMaterial material) async {
    if (_isHomeworkMaterial(material)) {
      await _openHomework(material);
      return;
    }

    await _confirmAndOpenUrl(material.url);
  }

  void _maybeOpenInitialMaterial(List<CourseMaterial> materials) {
    if (_initialMaterialOpened) return;

    final targetTitle = widget.initialMaterialTitle?.trim();
    final targetType = widget.initialMaterialType?.trim().toLowerCase();
    if (targetTitle == null || targetTitle.isEmpty) return;

    for (final material in materials) {
      final titleMatches = material.title.trim() == targetTitle;
      final typeMatches =
          targetType == null ||
          targetType.isEmpty ||
          material.type.trim().toLowerCase() == targetType;
      if (!titleMatches || !typeMatches) continue;

      _initialMaterialOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openActionableMaterial(material);
        }
      });
      return;
    }
  }

  List<_UploadedCourseFile> _uploadedFilesForSelectedWeek() {
    final courseUploads =
        _uploadedFiles[widget.course.id.trim().toUpperCase()] ?? const {};
    return courseUploads[_selectedWeek] ?? const [];
  }

  bool _isUploadedMaterial(
    CourseMaterial material,
    List<_UploadedCourseFile> uploadedFiles,
  ) {
    final materialType = material.type.trim().toLowerCase();
    if (materialType.isEmpty) return false;

    return uploadedFiles.any((file) {
      final label = file.label.trim().toLowerCase();
      final name = file.name.trim().toLowerCase();

      if (materialType == 'lecture') {
        return label.contains('lecture') ||
            label.contains('notes') ||
            name.contains('slides') ||
            name.contains('lecture') ||
            name.contains('notes');
      }

      if (materialType == 'homework') {
        return label.contains('homework') ||
            name.contains('homework') ||
            name.contains('assignment');
      }

      return label.contains(materialType) || name.contains(materialType);
    });
  }

  List<_UploadedCourseEntry> _allUploadedFilesForCourse() {
    final courseUploads =
        _uploadedFiles[widget.course.id.trim().toUpperCase()] ?? const {};
    final items = <_UploadedCourseEntry>[];

    for (final entry in courseUploads.entries) {
      for (final file in entry.value) {
        items.add(_UploadedCourseEntry(week: entry.key, file: file));
      }
    }

    items.sort((a, b) {
      final weekCompare = a.week.compareTo(b.week);
      if (weekCompare != 0) return weekCompare;
      return a.file.name.compareTo(b.file.name);
    });
    return items;
  }

  void _openAllUploads() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CourseUploadsScreen(
          courseTitle: widget.course.title,
          uploads: _allUploadedFilesForCourse(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final db = DatabaseService(user: user);
    final scheme = Theme.of(context).colorScheme;
    final allUploads = _allUploadedFilesForCourse();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.title),
        actions: [
          IconButton(
            tooltip: 'Uploads',
            onPressed: _openAllUploads,
            icon: Badge.count(
              isLabelVisible: allUploads.isNotEmpty,
              count: allUploads.length,
              child: const Icon(Icons.upload_file_rounded),
            ),
          ),
        ],
      ),
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
                              _buildOverviewChip(
                                context,
                                icon: Icons.upload_file_rounded,
                                label: allUploads.isEmpty
                                    ? 'No uploads yet'
                                    : '${allUploads.length} uploaded files',
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
                            _maybeOpenInitialMaterial(materials);
                            final uploadedFiles =
                                _uploadedFilesForSelectedWeek();
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
                            final nextDeadlineMaterial = datedMaterials.isEmpty
                                ? null
                                : datedMaterials.first;

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
                                              : 'Open required task',
                                          icon: Icons.assignment_late_outlined,
                                          onTap: nextDeadlineMaterial == null
                                              ? null
                                              : () => _openActionableMaterial(
                                                  nextDeadlineMaterial,
                                                ),
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
                                    ...materials.map((material) {
                                      final isLecture = _isLectureMaterial(
                                        material,
                                      );
                                      final isHomework = _isHomeworkMaterial(
                                        material,
                                      );
                                      final isUploaded = _isUploadedMaterial(
                                            material,
                                            uploadedFiles,
                                          );
                                      final hasHomeworkUpload =
                                          _hasUploadedHomework(material);
                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(
                                            14,
                                          ),
                                          leading: Icon(
                                            isLecture
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
                                              if (_usesCalculusRepeatStub(
                                                material,
                                              ))
                                                'Random Calculus replay',
                                            ].join(' • '),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isUploaded ||
                                                  hasHomeworkUpload)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                  child: Icon(
                                                    Icons.check_circle_rounded,
                                                    color:
                                                        Colors.green.shade600,
                                                  ),
                                                ),
                                              if (isLecture)
                                                IconButton(
                                                  tooltip: 'Repeat lecture',
                                                  onPressed: () =>
                                                      _repeatLecture(material),
                                                  icon: const Icon(
                                                    Icons.repeat_rounded,
                                                  ),
                                                ),
                                              IconButton(
                                                tooltip: isHomework
                                                    ? 'Open homework'
                                                    : (isUploaded
                                                          ? 'Open uploaded material'
                                                          : 'Open material'),
                                                onPressed: () => isHomework
                                                    ? _openHomework(material)
                                                    : _confirmAndOpenUrl(
                                                        material.url,
                                                      ),
                                                icon: const Icon(
                                                  Icons.open_in_new_rounded,
                                                ),
                                              ),
                                            ],
                                          ),
                                          onTap: () => isHomework
                                              ? _openHomework(material)
                                              : _confirmAndOpenUrl(
                                                  material.url,
                                                ),
                                        ),
                                      );
                                    }),
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
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
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
        ),
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

class _LectureReplayScreen extends StatefulWidget {
  const _LectureReplayScreen({
    required this.courseTitle,
    required this.lectureTitle,
    required this.replayLesson,
  });

  final String courseTitle;
  final String lectureTitle;
  final _ReplayLessonData replayLesson;

  @override
  State<_LectureReplayScreen> createState() => _LectureReplayScreenState();
}

class _LectureReplayScreenState extends State<_LectureReplayScreen> {
  int? _selectedAnswerIndex;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final replay = widget.replayLesson;
    final isCorrect = _selectedAnswerIndex == replay.correctAnswerIndex;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Lecture Replay')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primaryContainer, scheme.surfaceContainerHigh],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'AI replay request sent',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.courseTitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.lectureTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Stub mode: the assistant prepared a repeated lecture summary and a quick quiz for review.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    replay.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    replay.summary,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Key points',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...replay.takeaways.map(
                    (point) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(point)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.quiz_rounded, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Quick quiz',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    replay.quizQuestion,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RadioGroup<int>(
                    groupValue: _selectedAnswerIndex,
                    onChanged: (value) {
                      setState(() {
                        _selectedAnswerIndex = value;
                        _submitted = false;
                      });
                    },
                    child: Column(
                      children: List.generate(replay.quizOptions.length, (index) {
                        return RadioListTile<int>(
                          value: index,
                          contentPadding: EdgeInsets.zero,
                          title: Text(replay.quizOptions[index]),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selectedAnswerIndex == null
                          ? null
                          : () {
                              setState(() {
                                _submitted = true;
                              });
                            },
                      child: const Text('Submit answer'),
                    ),
                  ),
                  if (_submitted) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        isCorrect
                            ? 'Correct. The replay quiz stub marks this answer as right.'
                            : 'Not quite. Stub feedback: try reviewing the lecture summary above and answer again.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseUploadsScreen extends StatelessWidget {
  const _CourseUploadsScreen({
    required this.courseTitle,
    required this.uploads,
  });

  final String courseTitle;
  final List<_UploadedCourseEntry> uploads;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$courseTitle uploads')),
      body: uploads.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.upload_file_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'No uploaded files yet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Prototype storage is empty for this subject right now.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: uploads.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = uploads[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: Icon(item.file.icon),
                    title: Text(
                      item.file.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Week ${item.week} - ${item.file.label} - ${item.file.details}',
                    ),
                    trailing: const Icon(Icons.folder_open_rounded),
                  ),
                );
              },
            ),
    );
  }
}

class _HomeworkDetailScreen extends StatefulWidget {
  const _HomeworkDetailScreen({
    required this.courseTitle,
    required this.material,
    required this.initialUploadBundle,
  });

  final String courseTitle;
  final CourseMaterial material;
  final _HomeworkUploadBundle? initialUploadBundle;

  @override
  State<_HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<_HomeworkDetailScreen> {
  List<_HomeworkUploadFile> _uploads = const [];
  bool _hasPendingUpload = false;

  @override
  void initState() {
    super.initState();
    _uploads = List<_HomeworkUploadFile>.from(
      widget.initialUploadBundle?.files ?? const [],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final upload = _HomeworkUploadFile(
      fileName: file.name,
      filePath: file.path ?? '',
      uploadedAt: DateTime.now(),
    );

    if (!mounted) return;
    setState(() {
      _uploads = [..._uploads, upload];
      _hasPendingUpload = true;
    });
  }

  void _submitUpload() {
    if (_uploads.isEmpty || !_hasPendingUpload) return;
    Navigator.of(context).pop(_HomeworkUploadBundle(files: _uploads));
  }

  void _removeFile(int index) {
    setState(() {
      _uploads = List<_HomeworkUploadFile>.from(_uploads)..removeAt(index);
      _hasPendingUpload = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Homework'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
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
                  widget.courseTitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.material.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Upload your assignment file here. After upload, this homework will be marked with a check in Materials.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assignment details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text('Type: ${widget.material.type.toUpperCase()}'),
                  if (widget.material.deadline != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Deadline: ${DateFormat('d MMM, HH:mm').format(widget.material.deadline!)}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uploaded files',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_uploads.isEmpty)
                    Text(
                      'No files uploaded yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else
                    ...List.generate(_uploads.length, (index) {
                      final file = _uploads[index];
                      return Container(
                        margin: EdgeInsets.only(
                          bottom: index == _uploads.length - 1 ? 0 : 10,
                        ),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.description_rounded,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.fileName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Uploaded ${DateFormat('d MMM, HH:mm').format(file.uploadedAt)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove file',
                              onPressed: () => _removeFile(index),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(
                        _uploads.isEmpty ? 'Upload assignment' : 'Add another file',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          (_uploads.isEmpty || !_hasPendingUpload)
                              ? null
                              : _submitUpload,
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
