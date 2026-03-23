import 'package:e_class/models/courses/course.dart';
import 'package:e_class/screens/courses/course_detail_screen.dart';
import 'package:e_class/services/courses_service.dart';
import 'package:flutter/material.dart';

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  final CoursesService _coursesService = CoursesService();
  final List<String> _semesters = const [
    'Fall 2025',
    'Spring 2026',
    'Fall 2026',
  ];
  int _currentWeek = 1;
  late String _selectedSemester;

  @override
  void initState() {
    super.initState();
    _selectedSemester = 'Spring 2026';
    _currentWeek = _weekForSemester(_selectedSemester);
    _initCoursesData();
  }

  int get _currentSemesterIndex => _semesters.indexOf(_selectedSemester);

  String get _semesterHeaderLabel {
    if (_selectedSemester == 'Spring 2026') return 'Spring Semester 2026';
    if (_selectedSemester == 'Fall 2025') return 'Fall Semester 2025';
    return 'Fall Semester 2026';
  }

  Future<void> _initCoursesData() async {
    try {
      await _coursesService.syncData();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _currentWeek = _weekForSemester(_selectedSemester);
    });
  }

  int _weekForSemester(String semester) {
    DateTime start;
    if (semester == 'Fall 2025') {
      start = DateTime(2025, 9, 8);
    } else if (semester == 'Spring 2026') {
      start = DateTime(2026, 2, 7);
    } else {
      // Fall 2026 placeholder start until exact dates are provided.
      start = DateTime(2026, 9, 7);
    }

    final diff = DateTime.now().difference(start).inDays;
    final week = (diff / 7).floor() + 1;
    if (week < 1) return 1;
    if (week > 16) return 16;
    return week;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 38),
              onPressed: _currentSemesterIndex > 0
                  ? () => setState(() {
                      _selectedSemester = _semesters[_currentSemesterIndex - 1];
                      _currentWeek = _weekForSemester(_selectedSemester);
                    })
                  : null,
            ),
            Text(
              _semesterHeaderLabel,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 38),
              onPressed: _currentSemesterIndex < _semesters.length - 1
                  ? () => setState(() {
                      _selectedSemester = _semesters[_currentSemesterIndex + 1];
                      _currentWeek = _weekForSemester(_selectedSemester);
                    })
                  : null,
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<Course>>(
        stream: _coursesService.getCourses(_selectedSemester),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final courses = snapshot.data ?? [];

          if (courses.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.class_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No courses found',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 112),
            itemCount: courses.length,
            itemBuilder: (context, index) {
              final course = courses[index];

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CourseDetailScreen(
                            course: course,
                            currentWeek: _currentWeek,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: colorScheme.primary.withValues(
                              alpha: 0.36,
                            ),
                            child: Icon(
                              _getIconData(course.icon),
                              size: 36,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  course.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 23,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Week $_currentWeek${course.professorName.isNotEmpty ? ' вЂў ${course.professorName}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'code':
        return Icons.code;
      case 'calculate':
        return Icons.calculate;
      case 'science':
        return Icons.science;
      case 'history':
        return Icons.history;
      case 'language':
      case 'translate':
        return Icons.translate;
      case 'design_services':
        return Icons.design_services;
      case 'art_track':
        return Icons.art_track;
      case 'computer':
        return Icons.computer;
      case 'music_note':
        return Icons.music_note;
      case 'business_center':
        return Icons.business_center;
      case 'gavel':
        return Icons.gavel;
      case 'biotech':
        return Icons.biotech;
      default:
        return Icons.book;
    }
  }
}
