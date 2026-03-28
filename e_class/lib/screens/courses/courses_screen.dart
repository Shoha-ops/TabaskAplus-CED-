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
  String? _selectedSemester;

  int _weekForSemester(String semester) {
    final lower = semester.toLowerCase();
    DateTime start;
    if (lower.contains('fall') && lower.contains('2025')) {
      start = DateTime(2025, 9, 8);
    } else if (lower.contains('spring') && lower.contains('2026')) {
      start = DateTime(2026, 2, 7);
    } else if (lower.contains('fall') && lower.contains('2026')) {
      start = DateTime(2026, 9, 7);
    } else {
      return 1;
    }

    final diff = DateTime.now().difference(start).inDays;
    final week = (diff / 7).floor() + 1;
    if (week < 1) return 1;
    if (week > 16) return 16;
    return week;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: const Text(
          'Courses',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<List<Course>>(
        stream: _coursesService.getCourses(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load courses right now.',
                style: TextStyle(color: scheme.error),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allCourses = snapshot.data ?? const <Course>[];
          final semesters = allCourses
              .map((course) => course.semester.trim())
              .where((semester) => semester.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final selectedSemester = _selectedSemester == null ||
                  !semesters.contains(_selectedSemester)
              ? (semesters.isNotEmpty ? semesters.last : null)
              : _selectedSemester;

          final courses = selectedSemester == null
              ? allCourses
              : allCourses
                    .where((course) => course.semester == selectedSemester)
                    .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (semesters.isNotEmpty)
                SizedBox(
                  height: 62,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: semesters.map((semester) {
                      final isSelected = semester == selectedSemester;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(semester),
                          selected: isSelected,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _selectedSemester = semester),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              if (selectedSemester != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Week ${_weekForSemester(selectedSemester)} • ${courses.length} course${courses.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: courses.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.class_outlined,
                                size: 60,
                                color: scheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No courses available yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                semesters.isEmpty
                                    ? 'Your subjects will appear here once they are published for your semester.'
                                    : 'Try another semester or check back when your subjects are published.',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                        itemCount: courses.length,
                        itemBuilder: (context, index) {
                          final course = courses[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CourseDetailScreen(
                                        course: course,
                                        currentWeek: _weekForSemester(
                                          course.semester,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 30,
                                        backgroundColor:
                                            scheme.primary.withValues(alpha: 0.14),
                                        child: Icon(
                                          _getIconData(course.icon),
                                          color: scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              course.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              [
                                                course.semester,
                                                if (course.professorName.isNotEmpty)
                                                  course.professorName,
                                              ].join(' • '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.chevron_right_rounded),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'code':
        return Icons.code_rounded;
      case 'calculate':
        return Icons.calculate_rounded;
      case 'science':
        return Icons.science_rounded;
      case 'history':
        return Icons.history_edu_rounded;
      case 'language':
      case 'translate':
        return Icons.translate_rounded;
      case 'design_services':
        return Icons.design_services_rounded;
      case 'art_track':
        return Icons.art_track_rounded;
      case 'computer':
        return Icons.computer_rounded;
      case 'music_note':
        return Icons.music_note_rounded;
      case 'business_center':
        return Icons.business_center_rounded;
      case 'gavel':
        return Icons.gavel_rounded;
      case 'biotech':
        return Icons.biotech_rounded;
      default:
        return Icons.book_rounded;
    }
  }
}
