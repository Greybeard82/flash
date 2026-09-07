import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The bundled ad/tracker domain list, and the matching rule applied to it.
///
/// Every sub-resource an embedded page requests round-trips through a
/// platform channel to ask this class whether to allow it — a page with
/// forty ad requests asks forty times, before it finishes loading. The
/// channel hop is unavoidable; the lookup on this side is not, so matching
/// is a handful of `Set` probes (one per dot in the host) rather than a scan
/// down the list.
class AdBlocklist {
  static final AdBlocklist instance = AdBlocklist._empty();

  /// Entries that name a whole host: `doubleclick.net`, `criteo.com`.
  final Set<String> hosts;

  /// Entries that narrow to a path under an otherwise-legitimate host —
  /// `facebook.com/tr`, `yandex.ru/metrika`. Blocking the bare host would
  /// take the whole site with it, so these match on host+path instead.
  /// A short list, deliberately: scanned linearly, and only ever reached for
  /// requests whose host was not already a plain hit.
  final List<String> hostPaths;

  AdBlocklist._(this.hosts, this.hostPaths);

  AdBlocklist._empty()
      : hosts = <String>{},
        hostPaths = <String>[];

  /// Splits raw entries into the two forms above. Used directly by tests, so
  /// the matching rule can be exercised without the asset bundle.
  factory AdBlocklist.fromEntries(Iterable<String> entries) {
    final hosts = <String>{};
    final hostPaths = <String>[];
    for (final raw in entries) {
      final entry = raw.trim().toLowerCase();
      if (entry.isEmpty) continue;
      if (entry.contains('/')) {
        hostPaths.add(entry);
      } else {
        hosts.add(entry);
      }
    }
    return AdBlocklist._(hosts, hostPaths);
  }

  bool get isEmpty => hosts.isEmpty && hostPaths.isEmpty;

  /// True when [url] should not be allowed to load.
  ///
  /// A host matches an entry exactly (`doubleclick.net`), or when the entry
  /// is a parent domain of it — but only on a label boundary, so
  /// `ads.doubleclick.net` matches and `notdoubleclick.net` does not.
  bool blocks(Uri url) {
    final host = url.host.toLowerCase();
    if (host.isEmpty) return false;

    if (hosts.contains(host)) return true;

    // Walk the parent domains: for a.b.example.com this probes b.example.com,
    // example.com, com. Each probe starts one character past a dot, which is
    // what keeps "notdoubleclick.net" from matching "doubleclick.net" — the
    // only substring ever tested there is "net".
    var dot = host.indexOf('.');
    while (dot != -1) {
      if (hosts.contains(host.substring(dot + 1))) return true;
      dot = host.indexOf('.', dot + 1);
    }

    if (hostPaths.isNotEmpty) {
      final hostAndPath = '$host${url.path}'.toLowerCase();
      for (final entry in hostPaths) {
        if (hostAndPath.startsWith(entry)) return true;
      }
    }

    return false;
  }

  /// Reads the bundled list into [instance]. Safe to call more than once;
  /// the second call is a no-op rather than a re-parse.
  static Future<void> load() async {
    if (!instance.isEmpty) return;
    final raw = await rootBundle
        .loadString('assets/blocklists/ad_tracker_domains.json');
    final decoded = (jsonDecode(raw) as List).cast<String>();
    final parsed = AdBlocklist.fromEntries(decoded);
    instance.hosts.addAll(parsed.hosts);
    instance.hostPaths.addAll(parsed.hostPaths);
  }
}
