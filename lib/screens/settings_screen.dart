import 'package:flutter/material.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../services/refresh_service.dart';
import 'keyword_blocklist_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsRepo = SettingsRepository();
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _settingsRepo.getAll();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _save(String key, String value) async {
    await _settingsRepo.set(key, value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          // ── Reading ──
          _sectionHeader('Reading'),
          _themeSelector(s),
          _toggle(
            title: 'Mark as read on scroll',
            subtitle: 'Automatically mark articles as read as you scroll past them',
            value: s.markReadOnScroll,
            onChanged: (v) => _save('mark_read_on_scroll', v.toString()),
          ),

          // ── Refresh ──
          _sectionHeader('Refresh'),
          _dropdown<int>(
            title: 'Background refresh interval',
            value: s.refreshIntervalMinutes,
            items: const [
              DropdownMenuItem(value: 15, child: Text('Every 15 minutes')),
              DropdownMenuItem(value: 30, child: Text('Every 30 minutes')),
              DropdownMenuItem(value: 60, child: Text('Every hour')),
              DropdownMenuItem(value: 180, child: Text('Every 3 hours')),
              DropdownMenuItem(value: 360, child: Text('Every 6 hours')),
              DropdownMenuItem(value: 0, child: Text('Manual only')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await _save('refresh_interval_minutes', v.toString());
              final refreshSvc = RefreshService(_settingsRepo);
              await refreshSvc.schedulePeriodicRefresh();
            },
          ),

          // ── Storage ──
          _sectionHeader('Storage'),
          _dropdown<int>(
            title: 'Max articles per feed',
            value: s.articleLimit,
            items: const [
              DropdownMenuItem(value: 50, child: Text('50 articles')),
              DropdownMenuItem(value: 100, child: Text('100 articles')),
              DropdownMenuItem(value: 200, child: Text('200 articles')),
              DropdownMenuItem(value: 500, child: Text('500 articles')),
              DropdownMenuItem(value: 999999, child: Text('Unlimited')),
            ],
            onChanged: (v) {
              if (v == null) return;
              _save('article_limit', v.toString());
            },
          ),

          // ── Filters ──
          _sectionHeader('Filters'),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text('Keyword Blocklist'),
            subtitle: const Text('Hide articles matching specific words or phrases'),
            trailing: const Icon(Icons.chevron_right_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KeywordBlocklistScreen()),
            ),
          ),

          // ── AI Features (locked) ──
          _sectionHeader('AI Features'),
          _lockedTile(
            title: 'AI Opinion Filter',
            subtitle: 'Available in a future update',
          ),
          _lockedTile(
            title: 'AI Article Summary',
            subtitle: 'Available in a future update',
          ),

          // ── Google Drive (locked) ──
          _sectionHeader('Backup'),
          _lockedTile(
            title: 'Google Drive Backup',
            subtitle: 'Available in a future update',
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
      ),
    );
  }

  Widget _themeSelector(AppSettings s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('System')),
              ButtonSegment(value: 'light', label: Text('Light')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
            ],
            selected: {s.theme},
            onSelectionChanged: (sel) => _save('theme', sel.first),
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _dropdown<T>({
    required String title,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        underline: const SizedBox.shrink(),
        alignment: Alignment.centerRight,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _lockedTile({required String title, required String subtitle}) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
      trailing: Icon(
        Icons.lock_outline_rounded,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
