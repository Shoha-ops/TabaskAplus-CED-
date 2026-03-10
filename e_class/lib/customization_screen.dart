import 'package:flutter/material.dart';

class CustomizationScreen extends StatelessWidget {
  final Function(Color) onColorChange;
  final Color currentColor;

  const CustomizationScreen({
    super.key,
    required this.onColorChange,
    this.currentColor = Colors.deepPurple,
  });

  Widget _buildColorOption(BuildContext context, Color color, String label) {
    final isSelected = currentColor == color;

    return GestureDetector(
      onTap: () {
        onColorChange(color);
        // Show feedback snackbar on change
        ScaffoldMessenger.of(context).clearSnackBars(); // Clear previous
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Theme changed to $label'),
            behavior: SnackBarBehavior.floating,
            width: 200,
            duration: const Duration(milliseconds: 1000),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isSelected ? 80 : 60,
            height: isSelected ? 80 : 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 4)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: isSelected ? 12 : 6,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 32)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Appearance'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Accent Color',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a color that matches your style.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(24),
              crossAxisCount: 3,
              mainAxisSpacing: 24,
              crossAxisSpacing: 24,
              children: [
                _buildColorOption(context, Colors.red, 'Red'),
                _buildColorOption(context, Colors.green, 'Green'),
                _buildColorOption(context, Colors.blue, 'Blue'),
                _buildColorOption(context, Colors.orange, 'Orange'),
                _buildColorOption(context, Colors.deepPurple, 'Purple'),
                _buildColorOption(context, Colors.teal, 'Teal'),
                _buildColorOption(context, Colors.pink, 'Pink'),
                _buildColorOption(context, Colors.indigo, 'Indigo'),
                _buildColorOption(context, Colors.cyan, 'Cyan'),
              ],
            ),
          ),
          // Component preview section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              children: [
                Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                FloatingActionButton.extended(
                  onPressed: () {},
                  label: const Text('My Button'),
                  icon: const Icon(Icons.add),
                  elevation: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
