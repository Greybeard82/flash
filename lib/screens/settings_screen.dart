import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/spinning_refresh_icon.dart';
import '../widgets/notification_banner.dart';
import '../widgets/refresh_interval_field.dart';
import '../l10n/app_localizations.dart';
import '../models/feed.dart';
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
import '../services/opml_service.dart';
import '../services/settings_notifier.dart';

/// The hosted privacy policy.
///
/// Google Play requires the policy to be reachable from *inside* the app, not
/// only from the store listing, which is what the About tile below is for.
///
/// A const rather than an inline literal so a typo in a legally-required link
/// fails a test rather than shipping — see settings_privacy_link_test.dart.
const String kPrivacyPolicyUrl = 'https://flashrssapp.github.io/privacy.html';

/// The hosted support page.
///
/// **This must stay identical to the contact URL declared in the Play Console
/// News and Magazines section.** That declaration is checked against what the
/// app actually shows, and the two drifting apart is a rejection — the same
/// class of problem that took the app down on 11 Sep 2026. It is also why the
/// page is reachable from inside the app rather than only from the listing.
const String kSupportUrl = 'https://flashrssapp.github.io/support.html';

/// The support address, shown as the subtitle under Contact & support and
/// launched by the Email us row. A const for the same reason as the two URLs
/// above: pinned by a test rather than retyped.
const String kContactEmail = 'flashrssapp@gmail.com';

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

  /// Separate from [_localBusy] so an OPML operation greys out only the OPML
  /// buttons, not the backup ones.
  bool _opmlBusy = false;

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
    final l10n = AppLocalizations.of(context)!;
    setState(() => _localBusy = true);
    try {
      final saved = await LoadingController.instance.run(() async {
        final folders = await FolderRepository().getAll();
        final feeds = await FeedRepository().getAll();
        final keywords = await KeywordRepository().getAll();
        return LocalBackupService.exportBackup(
          folders: folders,
          feeds: feeds,
          keywords: keywords,
          dialogTitle: l10n.exportDialogTitle,
        );
      }, label: 'Exporting');
      // Nothing on a cancel. Dismissing the picker is a deliberate act, and a
      // banner reporting it would read as a failure the user has to dismiss in
      // turn. Only a written file is worth saying anything about.
      if (saved && mounted) {
        _bannerKey.currentState?.show(l10n.backupSuccess);
      }
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

          // ── OPML ──
          _sectionHeader(l10n.opml),
          _buildOpmlSection(l10n),

          // ── About ──
          _sectionHeader(l10n.about),
          // Above the privacy policy, not below it: Play requires contact
          // details a user can actually reach, and burying them under a legal
          // link is how they stop being reachable in practice.
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: Text(l10n.contactSupport),
            subtitle: const Text(kContactEmail),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: _openSupportPage,
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: Text(l10n.emailUs),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: _sendSupportEmail,
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicy),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: _openPrivacyPolicy,
          ),

          const SizedBox(height: 24),
        ],
      ),
          ),
        ],
      ),
    );
  }

  /// Opens the policy in the browser, not the built-in reader.
  ///
  /// The embedded reader is built around an [Article] and runs Clean-mode
  /// extraction over it, which is the wrong treatment for a legal document —
  /// and a privacy policy is a trust document, so the user should see the real
  /// URL and domain in a real browser. Same call the article opener uses for
  /// an external open.
  Future<void> _openPrivacyPolicy() async {
    try {
      final ok = await launchUrl(Uri.parse(kPrivacyPolicyUrl),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _bannerKey.currentState?.show(kPrivacyPolicyUrl);
      }
    } catch (_) {
      // No browser, or the launch was refused. Showing the URL at least lets
      // the user reach the policy by hand rather than hitting a dead tile.
      if (mounted) _bannerKey.currentState?.show(kPrivacyPolicyUrl);
    }
  }

  /// Opens the support page in the browser, for the same reasons as the
  /// policy above: a real URL in a real browser, not the Clean-mode reader.
  Future<void> _openSupportPage() async {
    try {
      final ok = await launchUrl(Uri.parse(kSupportUrl),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _bannerKey.currentState?.show(kSupportUrl);
      }
    } catch (_) {
      if (mounted) _bannerKey.currentState?.show(kSupportUrl);
    }
  }

  /// Hands the address to whatever mail app is installed.
  ///
  /// On failure the banner shows the address itself rather than an error: a
  /// device with no mail client configured is common, and the useful thing to
  /// do about it is to let the user read the address and write it down.
  Future<void> _sendSupportEmail() async {
    final uri = Uri(scheme: 'mailto', path: kContactEmail);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _bannerKey.currentState?.show(kContactEmail);
      }
    } catch (_) {
      if (mounted) _bannerKey.currentState?.show(kContactEmail);
    }
  }

  /// Imports an OPML file into the library.
  ///
  /// No confirmation dialog, unlike backup restore. Restore is destructive —
  /// it wipes and re-inserts, so it asks first. An OPML import only ever adds,
  /// so the worst outcome of a mistaken tap is some feeds to delete, and a
  /// dialog in front of every import would be a toll on the safe operation to
  /// protect against the dangerous one.
  Future<void> _importOpml() async {
    if (_opmlBusy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _opmlBusy = true);
    try {
      final service = OpmlService();
      final result = await LoadingController.instance.run(
        () => service.importFromPicker(
          fallbackFolderName: l10n.opmlImportedFolderName,
        ),
        label: 'Importing OPML',
      );
      if (!mounted || result == null) return; // null: picker dismissed
      // Not awaited — an import of fifty feeds is fifty favicon round trips,
      // and the banner should not wait behind them.
      unawaited(service.warmFavicons(result.addedFeeds));
      _bannerKey.currentState?.show(l10n.opmlImportedBanner(
        result.feedsImported,
        result.foldersCreated,
        result.skipped,
      ));
    } on OpmlParseException {
      // The file was not usable and nothing was written. One message for every
      // flavour of bad file: the distinction between "not XML", "not OPML" and
      // "unreadable" is not something the user can act on differently.
      if (mounted) {
        _bannerKey.currentState
            ?.show(AppLocalizations.of(context)!.opmlImportFailed);
      }
    } catch (e) {
      if (mounted) _bannerKey.currentState?.show(e.toString());
    } finally {
      if (mounted) setState(() => _opmlBusy = false);
    }
  }

  /// Writes the library out as OPML.
  Future<void> _exportOpml() async {
    if (_opmlBusy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _opmlBusy = true);
    try {
      final saved = await LoadingController.instance.run(() async {
        final folders = await FolderRepository().getAll();
        final feedRepo = FeedRepository();
        final feedsByFolder = <int, List<Feed>>{
          for (final folder in folders)
            folder.id!: await feedRepo.getByFolder(folder.id!),
        };
        if (feedsByFolder.values.every((f) => f.isEmpty)) return null;
        return OpmlService.exportToPicker(
          folders: folders,
          feedsByFolder: feedsByFolder,
          dialogTitle: l10n.exportOpml,
        );
      }, label: 'Exporting OPML');
      if (!mounted) return;
      if (saved == null) {
        // An empty file is a worse outcome than being told there is nothing
        // to write: the user would hand it to another reader and find out
        // there.
        _bannerKey.currentState?.show(l10n.opmlExportEmpty);
        return;
      }
      // Same as the backup export: silence on a cancel, which is a deliberate
      // act rather than a failure.
      if (saved) _bannerKey.currentState?.show(l10n.backupSuccess);
    } catch (e) {
      if (mounted) _bannerKey.currentState?.show(e.toString());
    } finally {
      if (mounted) setState(() => _opmlBusy = false);
    }
  }

  Widget _buildOpmlSection(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.opmlSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _opmlBusy ? null : _exportOpml,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(l10n.exportOpml),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _opmlBusy ? null : _importOpml,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.importOpml),
                ),
              ),
            ],
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
