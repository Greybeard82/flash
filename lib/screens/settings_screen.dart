import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/spinning_refresh_icon.dart';
import '../widgets/notification_banner.dart';
import '../widgets/refresh_interval_field.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/article_opener.dart' show kEmbeddedWebViewSettingKey;
import '../services/clean_reader.dart' show kCleanModeEnabledSettingKey;
import '../services/loading_controller.dart';
import '../services/refresh_service.dart';
import '../services/local_backup_service.dart';
import '../services/settings_notifier.dart';

/// The full settings screen.
///
/// No longer a bottom-nav destination: it is pushed from "More settings" at
/// the bottom of the Quick Settings panel, which every top-level screen can
/// open. It took a theme and a Newspaper-mode notifier for as long as it was
/// built by the app shell, and read neither — both are gone, so this is
/// pushable from anywhere with nothing to thread through.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _bannerKey = GlobalKey<NotificationBannerState>();
  final _settingsRepo = SettingsRepository();
  AppSettings? _settings;
  bool _localBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _settingsRepo.getAll();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _setUseEmbeddedWebView(bool value) async {
    setState(() => _settings = _settings?.copyWith(useEmbeddedWebView: value));
    await _settingsRepo.set(kEmbeddedWebViewSettingKey, value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  /// Rescheduling is the whole point, not a side effect: WorkManager only
  /// reads the interval and the network constraint when the periodic task is
  /// registered, so persisting either without `forceReschedule` leaves the
  /// live registration on the old settings until something else happens to
  /// re-register it.
  Future<void> _setRefreshInterval(int value) async {
    setState(
        () => _settings = _settings?.copyWith(refreshIntervalMinutes: value));
    await _settingsRepo.set('refresh_interval_minutes', value.toString());
    await RefreshService(_settingsRepo)
        .schedulePeriodicRefresh(forceReschedule: true);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setRefreshOnWifiOnly(bool value) async {
    setState(() => _settings = _settings?.copyWith(refreshOnWifiOnly: value));
    await _settingsRepo.set('refresh_wifi_only', value.toString());
    await RefreshService(_settingsRepo)
        .schedulePeriodicRefresh(forceReschedule: true);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setCleanModeEnabled(bool value) async {
    setState(() => _settings = _settings?.copyWith(cleanModeEnabled: value));
    await _settingsRepo.set(kCleanModeEnabledSettingKey, value.toString());
    SettingsNotifier.instance.settingsChanged();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = _settings;
    if (s == null) {
      return Scaffold(
          body: Center(
              child: SpinningRefreshIcon(
                  size: 40, color: Theme.of(context).colorScheme.primary)));
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
          // ── Reading ──
          _sectionHeader(l10n.reading),
          // Label-only, matching the Icon badge precedent: the off state is
          // "opens in Chrome instead", which is what anyone flicking this
          // already expects from a viewer toggle.
          SwitchListTile(
            title: Text(l10n.builtInViewer),
            value: s.useEmbeddedWebView,
            onChanged: _setUseEmbeddedWebView,
          ),
          // Subtitled, unlike the toggle above: "clean reading view" does not
          // on its own say that the offer only appears when a page can
          // actually be extracted, and a switch that looks inert on some
          // articles needs to say why up front.
          SwitchListTile(
            title: Text(l10n.cleanModeSettingTitle),
            subtitle: Text(l10n.cleanModeSettingSubtitle),
            value: s.cleanModeEnabled,
            onChanged: _setCleanModeEnabled,
          ),

          // ── Refresh ──
          // Reuses the existing `refresh` string, which already reads
          // "Refresh" and is translated in all five locales for the FAB
          // tooltip; a second key for the same word would be an orphan.
          _sectionHeader(l10n.refresh),
          RefreshIntervalField(
            value: s.refreshIntervalMinutes,
            onChanged: _setRefreshInterval,
          ),
          SwitchListTile(
            title: Text(l10n.refreshOnWifiOnly),
            subtitle: Text(l10n.refreshOnWifiOnlySubtitle),
            value: s.refreshOnWifiOnly,
            onChanged: _setRefreshOnWifiOnly,
          ),

          // ── Local backup file ──
          _sectionHeader(l10n.localBackup),
          _buildLocalBackupSection(l10n),

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
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: SpinningRefreshIcon(
                              size: 16,
                              color: Theme.of(context).colorScheme.primary))
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
}
