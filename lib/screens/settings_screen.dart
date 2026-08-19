import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/drive_backup_service.dart';
import '../services/loading_controller.dart';
import '../services/local_backup_service.dart';
import '../services/opml_service.dart';
import '../services/refresh_service.dart';
import '../services/settings_notifier.dart';
import 'keyword_alerts_screen.dart';
import 'keyword_blocklist_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ValueNotifier<String> themeModeNotifier;
  final ValueNotifier<bool> newspaperModeNotifier;

  const SettingsScreen({
    super.key,
    required this.themeModeNotifier,
    required this.newspaperModeNotifier,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsRepo = SettingsRepository();
  final _backupService = DriveBackupService();
  AppSettings? _settings;
  GoogleSignInAccount? _googleUser;
  bool _backupBusy = false;
  bool _localBusy = false;
  bool _opmlBusy = false;
  DateTime? _lastBackupAt;

  @override
  void initState() {
    super.initState();
    _load();
    _initGoogle();
  }

  Future<void> _initGoogle() async {
    final account = await _backupService.signInSilently();
    final lastMs = int.tryParse(
        await _settingsRepo.get('drive_last_backup_at') ?? '0');
    if (mounted) {
      setState(() {
        _googleUser = account;
        if (lastMs != null && lastMs > 0) {
          _lastBackupAt = DateTime.fromMillisecondsSinceEpoch(lastMs);
        }
      });
    }
  }

  Future<void> _load() async {
    final s = await _settingsRepo.getAll();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _save(String key, String value) async {
    await LoadingController.instance.run(() async {
      await _settingsRepo.set(key, value);
      await _load();
    }, label: 'Saving');
    // FeedScreen is kept alive in an IndexedStack and never rebuilds on a tab
    // switch, so it has to be told rather than left to notice.
    SettingsNotifier.instance.settingsChanged();
  }

  /// Applies [apply] to the in-memory settings immediately (so the UI reacts
  /// on this frame, not after a DB round-trip) and persists in the
  /// background. Use for toggles/selectors whose visible effect (theme,
  /// segmented-button highlight) must never lag behind the tap.
  void _saveInstant(String key, String value, AppSettings Function(AppSettings) apply) {
    final current = _settings;
    if (current == null) return;
    setState(() => _settings = apply(current));
    unawaited(_settingsRepo.set(key, value));
  }

  Future<void> _connectGoogle() async {
    final account = await LoadingController.instance
        .run(() => _backupService.signIn(), label: 'Connecting');
    if (mounted) setState(() => _googleUser = account);
  }

  Future<void> _signOutGoogle() async {
    await LoadingController.instance
        .run(() => _backupService.signOut(), label: 'Signing out');
    if (mounted) setState(() { _googleUser = null; _lastBackupAt = null; });
  }

  Future<void> _backupNow() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await LoadingController.instance.run(() async {
        final folders = await FolderRepository().getAll();
        final feeds = await FeedRepository().getAll();
        final keywords = await KeywordRepository().getAll();
        final when = await _backupService.backup(
          folders: folders,
          feeds: feeds,
          keywords: keywords,
        );
        await _settingsRepo.set(
            'drive_last_backup_at', when.millisecondsSinceEpoch.toString());
        if (mounted) {
          setState(() => _lastBackupAt = when);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.backupSuccess),
          ));
        }
      }, label: 'Backing up');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportLocalBackup() async {
    if (_localBusy) return;
    setState(() => _localBusy = true);
    try {
      await LoadingController.instance.run(() async {
        final folders = await FolderRepository().getAll();
        final feeds = await FeedRepository().getAll();
        final keywords = await KeywordRepository().getAll();
        await LocalBackupService.exportBackup(
          folders: folders,
          feeds: feeds,
          keywords: keywords,
        );
      }, label: 'Exporting');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _importLocalBackup() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(l10n.restoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _localBusy = true);
    try {
      final count = await LoadingController.instance
          .run(() => LocalBackupService.importBackup(), label: 'Restoring');
      if (!mounted) return;
      if (count == -1) return; // user cancelled picker
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.restoreSuccess(count)),
      ));
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.invalidBackupFile),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _exportOpml() async {
    if (_opmlBusy) return;
    setState(() => _opmlBusy = true);
    try {
      await LoadingController.instance.run(() async {
        final folders = await FolderRepository().getAll();
        final feeds = await FeedRepository().getAll();
        await OpmlService.exportToFile(folders: folders, feeds: feeds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.opmlExportSuccess)),
          );
        }
      }, label: 'Exporting OPML');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _opmlBusy = false);
    }
  }

  Future<void> _importOpml() async {
    if (_opmlBusy) return;
    setState(() => _opmlBusy = true);
    try {
      final count = await LoadingController.instance.run(() => OpmlService.importFromFile(
        folderRepo: FolderRepository(),
        feedRepo: FeedRepository(),
        settingsRepo: _settingsRepo,
        articleRepo: ArticleRepository(),
      ), label: 'Importing OPML');
      if (!mounted) return;
      if (count == -1) return; // cancelled
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.opmlImportSuccess(count))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _opmlBusy = false);
    }
  }

  Future<void> _restoreFromDrive() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(l10n.restoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(l10n.restore),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _backupBusy = true);
    try {
      final count = await LoadingController.instance
          .run(() => _backupService.restore(), label: 'Restoring');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.restoreSuccess(count)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = _settings;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          // ── Reading ──
          _sectionHeader(l10n.reading),
          _themeSelector(s, l10n),
          _newspaperToggle(s, l10n),
          _toggle(
            title: l10n.markReadOnScroll,
            subtitle: l10n.markReadOnScrollSubtitle,
            value: s.markReadOnScroll,
            onChanged: (v) => _save('mark_read_on_scroll', v.toString()),
          ),
          _toggle(
            title: l10n.autoMarkReadAtBottom,
            subtitle: l10n.autoMarkReadAtBottomSubtitle,
            value: s.autoMarkReadAtBottom,
            onChanged: (v) => _save('auto_mark_read_at_bottom', v.toString()),
          ),
          // Only meaningful while the behaviour is on; hidden rather than
          // disabled so the Reading section doesn't carry a dead control.
          if (s.autoMarkReadAtBottom)
            _dropdown<int>(
              title: l10n.autoMarkReadDelay,
              value: s.autoMarkReadAtBottomSeconds,
              items: [
                for (final seconds in AppSettings.autoMarkReadDelayOptions)
                  DropdownMenuItem(
                    value: seconds,
                    child: Text(seconds == 0
                        ? l10n.autoMarkReadImmediately
                        : l10n.autoMarkReadAfterSeconds(seconds)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                _save('auto_mark_read_at_bottom_seconds', v.toString());
              },
            ),

          // ── Refresh ──
          _sectionHeader(l10n.refresh),
          _dropdown<int>(
            title: l10n.backgroundRefreshInterval,
            value: s.refreshIntervalMinutes,
            items: [
              DropdownMenuItem(value: 15, child: Text(l10n.every15Minutes)),
              DropdownMenuItem(value: 30, child: Text(l10n.every30Minutes)),
              DropdownMenuItem(value: 60, child: Text(l10n.everyHour)),
              DropdownMenuItem(value: 180, child: Text(l10n.every3Hours)),
              DropdownMenuItem(value: 360, child: Text(l10n.every6Hours)),
              DropdownMenuItem(value: 0, child: Text(l10n.manualOnly)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await _save('refresh_interval_minutes', v.toString());
              final refreshSvc = RefreshService(_settingsRepo);
              await refreshSvc.schedulePeriodicRefresh(forceReschedule: true);
            },
          ),

          // ── Storage ──
          _sectionHeader(l10n.storage),
          _cleanupAgeControl(s),
          _dropdown<int>(
            title: l10n.maxArticlesPerFeed,
            value: s.articleLimit,
            items: [
              DropdownMenuItem(value: 50, child: Text(l10n.articles50)),
              DropdownMenuItem(value: 100, child: Text(l10n.articles100)),
              DropdownMenuItem(value: 200, child: Text(l10n.articles200)),
              DropdownMenuItem(value: 500, child: Text(l10n.articles500)),
              DropdownMenuItem(value: 999999, child: Text(l10n.unlimited)),
            ],
            onChanged: (v) {
              if (v == null) return;
              _save('article_limit', v.toString());
            },
          ),

          // ── Filters ──
          _sectionHeader(l10n.filters),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text(l10n.keywordBlocklist),
            subtitle: Text(l10n.keywordBlocklistSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KeywordBlocklistScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.keywordAlerts),
            subtitle: Text(l10n.keywordAlertsSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KeywordAlertsScreen()),
            ),
          ),

          // ── OPML ──
          _sectionHeader(l10n.opml),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.opmlSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _opmlBusy ? null : _exportOpml,
                        icon: _opmlBusy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_outlined),
                        label: Text(l10n.opmlExport),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _opmlBusy ? null : _importOpml,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(l10n.opmlImport),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Local backup file ──
          _sectionHeader(l10n.localBackup),
          _buildLocalBackupSection(l10n),

          // ── Google Drive Backup ──
          _sectionHeader(l10n.backup),
          _buildBackupSection(l10n),

          // ── Changelog ──
          _sectionHeader(l10n.changelog),
          _buildChangelog(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildLocalBackupSection(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.localBackupSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _localBusy ? null : _exportLocalBackup,
                  icon: _localBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(l10n.exportBackup),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _localBusy ? null : _importLocalBackup,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.importBackup),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final isConnected = _googleUser != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isConnected)
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(l10n.connectGoogle),
            subtitle: Text(_googleUser?.email ?? ''),
            trailing: const Icon(Icons.chevron_right_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: _connectGoogle,
          )
        else ...[
          ListTile(
            leading: const Icon(Icons.account_circle_rounded),
            title: Text(_googleUser!.email),
            subtitle: _lastBackupAt != null
                ? Text(l10n.lastBackup(_formatDate(_lastBackupAt!)))
                : null,
            trailing: TextButton(
              onPressed: _signOutGoogle,
              child: Text(l10n.signOut,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _backupBusy ? null : _backupNow,
                      icon: _backupBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(l10n.backupNow),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _backupBusy ? null : _restoreFromDrive,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: Text(l10n.restoreFromDrive),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _sectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, thickness: 1, indent: 0, endIndent: 0),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
          ),
        ),
      ],
    );
  }

  Widget _themeSelector(AppSettings s, AppLocalizations l10n) {
    final disabled = s.newspaperMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.theme,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: disabled
                  ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'system', label: SizedBox(width: 72, child: Text(l10n.themeSystem, textAlign: TextAlign.center))),
                ButtonSegment(value: 'light',  label: SizedBox(width: 72, child: Text(l10n.themeLight,  textAlign: TextAlign.center))),
                ButtonSegment(value: 'dark',   label: SizedBox(width: 72, child: Text(l10n.themeDark,   textAlign: TextAlign.center))),
              ],
              selected: {s.theme},
              onSelectionChanged: disabled ? null : (sel) {
                final value = sel.first;
                widget.themeModeNotifier.value = value;
                _saveInstant('theme', value, (s) => s.copyWith(theme: value));
              },
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, 44),
              ),
            ),
          ),
          if (disabled) ...[
            const SizedBox(height: 4),
            Text(
              l10n.newspaperModeOverridesTheme,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _newspaperToggle(AppSettings s, AppLocalizations l10n) {
    return SwitchListTile(
      title: Text(l10n.newspaperMode),
      subtitle: Text(l10n.newspaperModeSubtitle),
      value: s.newspaperMode,
      onChanged: (v) {
        widget.newspaperModeNotifier.value = v;
        _saveInstant('newspaper_mode', v.toString(), (s) => s.copyWith(newspaperMode: v));
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

  Widget _buildChangelog() {
    final theme = Theme.of(context);
    final done = theme.colorScheme.primary;
    final wip = theme.colorScheme.tertiary;
    final todo = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    Widget entry(String text, {bool isDone = false, bool isWip = false}) {
      final color = isDone ? done : isWip ? wip : todo;
      final icon = isDone ? Icons.check_circle_rounded : isWip ? Icons.timelapse_rounded : Icons.radio_button_unchecked;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ),
          ],
        ),
      );
    }

    Widget version(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            letterSpacing: 0.8,
          )),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        version('v0.1 — CORE'),
        entry('RSS 2.0 + Atom 1.0 feed parsing', isDone: true),
        entry('Category folders with tab navigation', isDone: true),
        entry('Background auto-refresh (WorkManager)', isDone: true),
        entry('Pull-to-refresh', isDone: true),
        entry('Mark as read on scroll + swipe', isDone: true),
        entry('Mark as unread (swipe left)', isDone: true),
        entry('Long-press radial menu (share, bookmark, AI summary)', isDone: true),
        entry('Article search', isDone: true),
        entry('Bookmarks / saved articles', isDone: true),
        entry('Dead feed indicator (⚠)', isDone: true),
        version('v0.1 — FILTERS & ALERTS'),
        entry('Keyword blocking (case-sensitive)', isDone: true),
        entry('Keyword alert notifications', isDone: true),
        entry('Daily unread digest notification', isDone: true),
        version('v0.1 — UI & PERSONALISATION'),
        entry('Dark / light / system theme', isDone: true),
        entry('Dynamic colour (Android 12+)', isDone: true),
        entry('5 languages: EN, ES, FR, DE, IT', isDone: true),
        version('v0.1 — DATA'),
        entry('OPML import / export', isDone: true),
        entry('Local file backup & restore', isDone: true),
        entry('Google Drive backup', isWip: true),
        version('PLANNED'),
        entry('AI summaries on more devices (requires Gemini Nano)'),
        entry('Per-feed article limits'),
        entry('Search scoped to current category'),
        entry('iPad / wider screen layout'),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _cleanupAgeControl(AppSettings s) {
    final days = s.cleanupAgeDays;
    return ListTile(
      title: const Text('Article cleanup window'),
      subtitle: const Text('Read articles older than this are removed'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: days <= 5
                ? null
                : () => _save('cleanup_age_days', (days - 1).toString()),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '$days days',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: days >= 20
                ? null
                : () => _save('cleanup_age_days', (days + 1).toString()),
          ),
        ],
      ),
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

}
