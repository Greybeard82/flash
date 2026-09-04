import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/fetching_indicator.dart';
import '../widgets/notification_banner.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/drive_backup_service.dart';
import '../services/loading_controller.dart';
import '../services/local_backup_service.dart';
import '../services/refresh_service.dart';
import '../services/settings_notifier.dart';

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
  final _bannerKey = GlobalKey<NotificationBannerState>();
  final _settingsRepo = SettingsRepository();
  final _backupService = DriveBackupService();
  AppSettings? _settings;
  GoogleSignInAccount? _googleUser;
  bool _backupBusy = false;
  bool _localBusy = false;
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
          _bannerKey.currentState?.show(AppLocalizations.of(context)!.backupSuccess);
        }
      }, label: 'Backing up');
    } catch (e) {
      if (mounted) {
        _bannerKey.currentState?.show(e.toString());
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
        _bannerKey.currentState?.show(e.toString());
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
      _bannerKey.currentState?.show(l10n.restoreSuccess(count));
    } on FormatException {
      if (mounted) {
        _bannerKey.currentState?.show(AppLocalizations.of(context)!.invalidBackupFile);
      }
    } catch (e) {
      if (mounted) {
        _bannerKey.currentState?.show(e.toString());
      }
    } finally {
      if (mounted) setState(() => _localBusy = false);
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
        _bannerKey.currentState?.show(AppLocalizations.of(context)!.restoreSuccess(count));
      }
    } catch (e) {
      if (mounted) {
        _bannerKey.currentState?.show(e.toString());
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
      return const Scaffold(body: Center(child: FetchingIndicator(size: 40)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        centerTitle: false,
      ),
      body: Column(
        children: [
          NotificationBanner(key: _bannerKey),
          Expanded(
            child: ListView(
        children: [
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

          // ── Local backup file ──
          _sectionHeader(l10n.localBackup),
          _buildLocalBackupSection(l10n),

          // ── Google Drive Backup ──
          _sectionHeader(l10n.backup),
          _buildBackupSection(l10n),

          const SizedBox(height: 24),
        ],
      ),
          ),
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
                          child: FetchingIndicator(size: 16))
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
            // IntrinsicHeight sizes both cells to the taller button, so when
            // "Restore from Drive" (or its French translation) wraps to two
            // lines, "Back up now" grows to match rather than the pair looking
            // mismatched. The 48dp is a floor for the tap target, not a cap —
            // a fixed height is what clipped the label in the first place.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: OutlinedButton.icon(
                        onPressed: _backupBusy ? null : _backupNow,
                        icon: _backupBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: FetchingIndicator(size: 16))
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(l10n.backupNow, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: OutlinedButton.icon(
                        onPressed: _backupBusy ? null : _restoreFromDrive,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text(l10n.restoreFromDrive,
                            textAlign: TextAlign.center),
                      ),
                    ),
                  ),
                ],
              ),
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
