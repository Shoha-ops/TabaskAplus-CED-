import 'package:flutter/material.dart';

class CustomizationScreen extends StatefulWidget {
  final Function(Color) onColorChange;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final Color currentColor;
  final ThemeMode currentThemeMode;

  const CustomizationScreen({
    super.key,
    required this.onColorChange,
    required this.onThemeModeChange,
    this.currentColor = Colors.blue,
    this.currentThemeMode = ThemeMode.system,
  });

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  late ThemeMode _selectedThemeMode;

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.currentThemeMode;
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  Widget _buildColorOption(BuildContext context, Color color, String label) {
    // Determining selection by checking against the current active primary color
    // This ensures checking persists correctly after restart/nav
    final currentPrimary = Theme.of(context).colorScheme.primary;
    final isSelected = currentPrimary.toARGB32() == color.toARGB32();
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        widget.onColorChange(color);
        ScaffoldMessenger.of(context).clearSnackBars();
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
                  ? Border.all(color: scheme.surface, width: 4)
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
                ? const Icon(Icons.check, color: Colors.black, size: 32)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
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
      appBar: AppBar(title: const Text('Appearance'), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accent color',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick the tone that drives the whole app',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme mode',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_rounded),
                        label: Text('System'),
                      ),
                    ],
                    selected: {_selectedThemeMode},
                    onSelectionChanged: (selection) {
                      final mode = selection.first;
                      setState(() {
                        _selectedThemeMode = mode;
                      });
                      widget.onThemeModeChange(mode);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Theme mode changed to ${_themeModeLabel(mode)}',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 24,
                crossAxisSpacing: 24,
                childAspectRatio: 0.72,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildColorOption(context, const Color(0xFF8BB8FF), 'INHA'),
                  _buildColorOption(context, const Color(0xFF5EE6C6), 'Mint'),
                  _buildColorOption(context, const Color(0xFFF7B267), 'Amber'),
                  _buildColorOption(context, const Color(0xFFFF6B8A), 'Rose'),
                  _buildColorOption(
                    context,
                    const Color(0xFFB794F6),
                    'Lavender',
                  ),
                  _buildColorOption(context, const Color(0xFF7EE787), 'Lime'),
                  _buildColorOption(context, const Color(0xFF56CCF2), 'Aqua'),
                  _buildColorOption(context, const Color(0xFFFF8C42), 'Sunset'),
                  _buildColorOption(context, const Color(0xFF7CFFCB), 'Neon'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Text(
                      'Preview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    FloatingActionButton.extended(
                      onPressed: () {},
                      label: const Text('Apply accent'),
                      icon: const Icon(Icons.add),
                      elevation: 0,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
