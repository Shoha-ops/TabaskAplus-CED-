import 'package:flutter/material.dart';

class OopAssignmentsScreen extends StatelessWidget {
  const OopAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OOP Assignments'),
      ),
      body: const Center(
        child: Text('Assignments for Object Oriented Programming'),
      ),
    );
  }
}
