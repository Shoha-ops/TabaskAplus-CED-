import 'package:e_class/customization_screen.dart';
import 'package:e_class/services/auth_service.dart';
import 'package:e_class/services/ai_service.dart';
import 'package:e_class/services/database_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainScreen extends StatefulWidget {
  final Function(Color) onColorChange;

  const MainScreen({super.key, required this.onColorChange});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final TextEditingController _chatController = TextEditingController();

  // Temporary data for UI development
  final List<Map<String, dynamic>> _emails = [
    {
      'sender': 'Prof. Alan Turing',
      'subject': 'Algorithm Analysis Project',
      'snippet': 'Please review the attached project specifications...',
      'time': '10:30 AM',
      'isUnread': true,
      'content':
          'Dear Students,\n\nPlease review the attached project specifications for the upcoming Algorithm Analysis assignment. The deadline is next Friday.\n\nBest regards,\nProf. Turing',
    },
    {
      'sender': 'Dr. Grace Hopper',
      'subject': 'Compiler Design Lecture Notes',
      'snippet': 'Here are the notes from today\'s lecture on parsing...',
      'time': '09:15 AM',
      'isUnread': true,
      'content':
          'Hello everyone,\n\nHere are the notes from today\'s lecture on parsing techniques. Let me know if you have any questions.\n\nRegards,\nDr. Hopper',
    },
    {
      'sender': 'Admin Office',
      'subject': 'Semester Registration Confirmation',
      'snippet': 'Your registration for Spring 2026 has been processed...',
      'time': 'Yesterday',
      'isUnread': false,
      'content':
          'Dear Student,\n\nYour registration for the Spring 2026 semester has been successfully processed. You can view your timetable in the app.\n\nAdmin Office',
    },
    {
      'sender': 'Library Services',
      'subject': 'Book Due Reminder',
      'snippet': 'This is a reminder that "Introduction to AI" is due...',
      'time': 'Yesterday',
      'isUnread': false,
      'content':
          'Hello,\n\nThis is a reminder that the book "Introduction to AI" is due tomorrow. Please return or renew it to avoid fines.\n\nLibrary Services',
    },
    {
      'sender': 'Prof. John von Neumann',
      'subject': 'Computer Architecture Quiz',
      'snippet': 'Don\'t forget about the quiz on Friday regarding...',
      'time': '2 days ago',
      'isUnread': false,
      'content':
          'Class,\n\nDon\'t forget about the quiz on Friday regarding instruction sets and memory hierarchy.\n\nSee you there,\nProf. von Neumann',
    },
  ];

  // Hardcoded schedule for testing
  final List<Map<String, dynamic>> _weeklySchedule = [
    {
      'day': 'Monday',
      'classes': [
        {
          'time': '09:00 - 10:15',
          'subject': 'System Programming',
          'room': 'Room 304',
          'active': false,
        },
        {
          'time': '10:30 - 11:45',
          'subject': 'Computer Networks',
          'room': 'Lab 201',
          'active': false,
        },
        {
          'time': '13:00 - 14:15',
          'subject': 'Linear Algebra',
          'room': 'Room 102',
          'active': false,
        },
      ],
    },
    {
      'day': 'Tuesday',
      'classes': [
        {
          'time': '09:00 - 10:15',
          'subject': 'Database Systems',
          'room': 'Lecture Hall A',
          'active': false,
        },
        {
          'time': '13:00 - 14:15',
          'subject': 'Operating Systems',
          'room': 'Room 105',
          'active': false,
        },
        {
          'time': '14:30 - 15:45',
          'subject': 'Web Development',
          'room': 'Lab 303',
          'active': false,
        },
      ],
    },
    {
      'day': 'Wednesday',
      'classes': [
        {
          'time': '09:00 - 10:15',
          'subject': 'System Programming',
          'room': 'Room 304',
          'active': false,
        },
        {
          'time': '10:30 - 11:45',
          'subject': 'Computer Networks',
          'room': 'Lab 201',
          'active': false,
        },
        {
          'time': '13:00 - 14:15',
          'subject': 'Artificial Intelligence',
          'room': 'Room 401',
          'active': true,
        }, // Active class
      ],
    },
    {
      'day': 'Thursday',
      'classes': [
        {
          'time': '09:00 - 10:15',
          'subject': 'Database Systems',
          'room': 'Lecture Hall A',
          'active': false,
        },
        {
          'time': '13:00 - 14:15',
          'subject': 'Operating Systems',
          'room': 'Room 105',
          'active': false,
        },
        {
          'time': '14:30 - 15:45',
          'subject': 'Info Security',
          'room': 'Room 202',
          'active': false,
        },
      ],
    },
    {
      'day': 'Friday',
      'classes': [
        {
          'time': '10:30 - 11:45',
          'subject': 'Linear Algebra',
          'room': 'Room 102',
          'active': false,
        },
        {
          'time': '13:00 - 14:15',
          'subject': 'Senior Project Meeting',
          'room': 'Conf Room B',
          'active': false,
        },
      ],
    },
  ];

  List<Map<String, dynamic>> get _todayClasses {
    final weekday = DateTime.now().weekday;
    if (weekday > 5) return []; // Return empty list on weekends
    return _weeklySchedule[weekday - 1]['classes'];
  }

  String get _formattedTodayDate {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Today, ${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]}';
  }

  bool _isActive(String timeRange) {
    try {
      final now = DateTime.now();
      // If today is not the day of the class, passed from outside, this logic is flawed.
      // But _todayClasses gets classes for the CURRENT day. So this check is valid for "Today's Timetable".

      final parts = timeRange.split(' - ');
      final startStr = parts[0].trim().split(':');
      final endStr = parts[1].trim().split(':');

      final startTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(startStr[0]),
        int.parse(startStr[1]),
      );
      final endTime = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(endStr[0]),
        int.parse(endStr[1]),
      );

      return now.isAfter(startTime) && now.isBefore(endTime);
    } catch (_) {
      return false;
    }
  }

  String _selectedSemester = 'Spring 2026';
  bool _notificationsEnabled = true;

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  // User actions

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final user = Provider.of<User?>(context, listen: false);
    if (user != null) {
      final db = DatabaseService(user: user);

      // Send message to firestore
      await db.sendMessage(text, isBot: false);

      // Clear input field
      _chatController.clear();

      // TODO: Move AI processing to cloud function
      await AIService(db).processMessage(text);
    }
  }

  void _showComposeEmailDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'To',
                hintText: 'Professor or Department',
              ),
            ),
            const SizedBox(height: 10),
            TextField(decoration: const InputDecoration(labelText: 'Subject')),
            const SizedBox(height: 10),
            TextField(
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Message sent successfully!')),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showEmailDetails(Map<String, dynamic> email) {
    setState(() {
      email['isUnread'] = false; // Mark as read
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(
            controller: controller,
            children: [
              Text(
                email['subject'],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(child: Text(email['sender'][0])),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email['sender'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        email['time'],
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 40),
              Text(
                email['content'],
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.reply),
                      label: const Text('Reply'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.forward),
                      label: const Text('Forward'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGradeDetails(String subject, String grade, int credits) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(subject),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Final Grade:'),
                Text(
                  grade,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Credits:'),
                Text(
                  '$credits',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            const Text(
              'Feedback: Excellent performance in practical assignments. Keep it up!',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showNotificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            ListTile(
              leading: Icon(Icons.class_, color: Colors.blue),
              title: Text('Schedule Change'),
              subtitle: Text('System Programming lecture rescheduled.'),
            ),
            ListTile(
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text('Deadline Approaching'),
              subtitle: Text(
                'Database Systems project submission due tomorrow.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<DocumentSnapshot>(
          stream: DatabaseService(user: Provider.of<User?>(context)).userData,
          builder: (context, snapshot) {
            String name = 'Loading...';
            String id = '';
            if (snapshot.hasData &&
                snapshot.data != null &&
                snapshot.data!.data() != null) {
              var data = snapshot.data!.data() as Map<String, dynamic>;
              name = data['name'] ?? 'User';
              id = data['studentId'] ?? '';
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(
                    'https://eclass.inha.ac.kr/pluginfile.php/65438/user/icon/coursemosv2/f1?rev=1517677',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(id, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedIndex = 5; // Go to Others screen
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context); // Close the bottom sheet
                    await AuthService().signOut();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showTimetableDetails(String subject, String time, String room) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey),
                const SizedBox(width: 8),
                Text(time, style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.grey),
                const SizedBox(width: 8),
                Text(room, style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnnouncementDetails(String title, String description, String date) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                date,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableItem(
    String time,
    String subject,
    String room,
    bool isActive,
  ) {
    return Card(
      elevation: isActive ? 4 : 0,
      color: isActive
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => _showTimetableDetails(subject, time, room),
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.access_time_filled,
              color: isActive
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        title: Text(
          subject,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isActive
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          '$time • $room',
          style: TextStyle(
            color: isActive
                ? Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: isActive
            ? Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              )
            : null,
      ),
    );
  }

  Widget _buildAnnouncementItem(String date, String title, String description) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAnnouncementDetails(title, description, date),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      date,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> get _widgetOptions => <Widget>[
    Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            floating: true,
            pinned: true,
            title: Row(
              children: [
                GestureDetector(
                  onTap: _showProfileDialog,
                  child: const CircleAvatar(
                    backgroundImage: NetworkImage(
                      'https://eclass.inha.ac.kr/pluginfile.php/65438/user/icon/coursemosv2/f1?rev=1517677',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: DatabaseService(
                      user: Provider.of<User?>(context),
                    ).userData,
                    builder: (context, snapshot) {
                      String name = 'Student';
                      if (snapshot.hasData &&
                          snapshot.data != null &&
                          snapshot.data!.data() != null) {
                        var data =
                            snapshot.data!.data() as Map<String, dynamic>;
                        name = data['name'] ?? 'Student';
                      } else {
                        name = 'Kevin Park';
                      }
                      return Text(
                        'Hi, $name',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton(
                  onPressed: _showNotificationDialog,
                  icon: Badge(
                    label: const Text('3'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Today\'s Classes',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              _formattedTodayDate,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_todayClasses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: Text('No classes today!')),
                          )
                        else
                          ..._todayClasses.map((cls) {
                            final time = cls['time'] as String;
                            return _buildTimetableItem(
                              time,
                              cls['subject'],
                              cls['room'],
                              _isActive(time),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Announcements',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(onPressed: () {}, child: const Text('See all')),
                  ],
                ),
                const SizedBox(height: 8),
                _buildAnnouncementItem(
                  'Mar 07',
                  'Final Exam Schedule',
                  'The final exam schedule for Spring 2026 has been published.',
                ),
                _buildAnnouncementItem(
                  'Mar 05',
                  'Campus Maintenance',
                  'The main library will undergo maintenance on Saturday.',
                ),
                const SizedBox(height: 80), // Add spacing for bottom nav
              ]),
            ),
          ),
        ],
      ),
    ),
    _buildTimetableScreen(),
    _buildGradesScreen(),
    _buildIIScreen(),
    _buildEmailScreen(),
    _buildOthersScreen(),
  ];

  // Tab Views

  Widget _buildTimetableScreen() {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'Timetable',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          bottom: TabBar(
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(text: 'Today'),
              Tab(text: 'Weekly'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Daily schedule view
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_todayClasses.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40.0),
                      child: Text(
                        'No classes today',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                  )
                else
                  ..._todayClasses.map((cls) {
                    final time = cls['time'] as String;
                    return _buildTimetableItem(
                      time,
                      cls['subject'],
                      cls['room'],
                      _isActive(time),
                    );
                  }),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40.0),
                    child: Text(
                      'No more classes today',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
                ),
              ],
            ),
            // Weekly schedule view
            ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _weeklySchedule.length,
              itemBuilder: (context, index) {
                final dayData = _weeklySchedule[index];
                final dayName = dayData['day'];
                final classes =
                    dayData['classes'] as List<Map<String, dynamic>>;

                // Highlight current day
                final isToday = (DateTime.now().weekday - 1) == index;

                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isToday
                              ? Theme.of(context).primaryColor
                              : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...classes.map((cls) {
                        final time = cls['time'] as String;
                        // Check if class is currently in session
                        final isActive = isToday && _isActive(time);
                        return _buildTimetableItem(
                          time,
                          cls['subject'],
                          cls['room'],
                          isActive,
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradesScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Grades'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // GPA Summary
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.tertiary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total GPA',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimary.withValues(alpha: 0.8),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '4.15',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  fontSize: 42,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: ' / 4.5',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary
                                      .withValues(alpha: 0.7),
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    CircularProgressIndicator(
                      value: 0.95,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.2),
                      color: Theme.of(context).colorScheme.onPrimary,
                      strokeWidth: 8,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Term selection
            ListTile(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: const Text('Spring 2026'),
                          trailing: _selectedSemester == 'Spring 2026'
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedSemester = 'Spring 2026';
                            });
                            Navigator.pop(context);
                          },
                        ),
                        ListTile(
                          title: const Text('Fall 2025'),
                          trailing: _selectedSemester == 'Fall 2025'
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedSemester = 'Fall 2025';
                            });
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
              title: Text(
                _selectedSemester,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              trailing: const Icon(Icons.keyboard_arrow_down),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),

            // Course grades
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: 4,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final subjects = [
                  'System Programming',
                  'Computer Networks',
                  'Database Systems',
                  'Operating Systems',
                ];
                final grades = ['A+', 'A', 'B+', 'A'];
                final credits = [3, 3, 3, 3];

                final isHighGrade = grades[index].startsWith('A');

                return Card(
                  elevation: 0,
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: () => _showGradeDetails(
                      subjects[index],
                      grades[index],
                      credits[index],
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isHighGrade
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          grades[index],
                          style: TextStyle(
                            color: isHighGrade ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      subjects[index],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${credits[index]} Credits'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIIScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            const Text(
              'Inha Intelligence',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: DatabaseService(
                user: Provider.of<User?>(context),
              ).messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isBot = data['sender'] == 'bot';
                    final text = data['text'] ?? '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: isBot
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isBot) ...[
                            CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Icon(
                                Icons.smart_toy_outlined,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isBot
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest
                                    : Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20),
                                  topRight: const Radius.circular(20),
                                  bottomLeft: isBot
                                      ? const Radius.circular(4)
                                      : const Radius.circular(20),
                                  bottomRight: isBot
                                      ? const Radius.circular(20)
                                      : const Radius.circular(4),
                                ),
                              ),
                              child: Text(
                                text,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: isBot
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : Theme.of(context).colorScheme.onPrimary,
                                ),
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
          ),

          // Quick action chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                InputChip(
                  label: const Text('My GPA'),
                  onPressed: () => _sendMessage('What is my current GPA?'),
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: const Text('Library Hours'),
                  onPressed: () => _sendMessage('When is the library open?'),
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: const Text('Shuttle Bus'),
                  onPressed: () => _sendMessage('Next shuttle bus to station?'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Message input
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: _sendMessage,
                    decoration: InputDecoration(
                      hintText: 'Ask anything...',
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => _sendMessage(_chatController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Inbox',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showComposeEmailDialog,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: ListView.separated(
        itemCount: _emails.length,
        separatorBuilder: (c, i) => Divider(height: 1, color: Colors.grey[100]),
        itemBuilder: (context, index) {
          final email = _emails[index];
          bool isUnread = email['isUnread'];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: isUnread
                  ? Theme.of(context).primaryColor
                  : Colors.grey[300],
              child: Text(
                email['sender'][0],
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              email['sender'],
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  email['subject'],
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                Text(
                  email['snippet'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  email['time'],
                  style: TextStyle(
                    fontSize: 12,
                    color: isUnread
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isUnread) ...[
                  const SizedBox(height: 5),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            onTap: () => _showEmailDetails(email),
          );
        },
      ),
    );
  }

  Widget _buildOthersScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Menu'),
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User profile summary
          StreamBuilder<DocumentSnapshot>(
            stream: DatabaseService(user: Provider.of<User?>(context)).userData,
            builder: (context, snapshot) {
              String name = 'Loading...';
              String info = 'Loading...';

              if (snapshot.hasData &&
                  snapshot.data != null &&
                  snapshot.data!.data() != null) {
                var data = snapshot.data!.data() as Map<String, dynamic>;
                name = data['name'] ?? 'User';
                info =
                    '${data['major'] ?? 'Student'} • ${data['studentId'] ?? ''}';
              } else if (!snapshot.hasData) {
                // Show loading indicator
              } else {
                name = 'Guest User';
                info = 'Please login';
              }

              return Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundImage: NetworkImage(
                          'https://eclass.inha.ac.kr/pluginfile.php/65438/user/icon/coursemosv2/f1?rev=1517677',
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              info,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // App settings
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.palette_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Appearance'),
                  subtitle: const Text('Theme color'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomizationScreen(
                          onColorChange: widget.onColorChange,
                          currentColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text('Notifications'),
                  value: _notificationsEnabled,
                  onChanged: (val) {
                    setState(() {
                      _notificationsEnabled = val;
                    });
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Support & About
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              'Support',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline, color: Colors.green),
                  title: const Text('Help Center'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Help Center'),
                        content: const Text(
                          'For support, please contact help@inha.ac.kr or visit the IT center in Building 5.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                ListTile(
                  leading: const Icon(
                    Icons.bug_report_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text('Report a Bug'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report feature coming soon!'),
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.blue),
                  title: const Text('About App'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Inha Class',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '© 2026 Inha University',
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Log Out'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await AuthService().signOut();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              );
            },
            icon: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              'Log Out',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bottom navigation
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'TimeTable',
          ),
          const NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Grades',
          ),
          const NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'AI',
          ),
          const NavigationDestination(
            icon: Icon(Icons.mail_outline),
            selectedIcon: Icon(Icons.mail),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.grid_view),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Menu',
          ),
        ],
      ),
    );
  }
}
