import '../models/alert_entry.dart';

/// A row in the Alerts list: either a keyword section's header or one of the
/// entries under it.
sealed class AlertRow {
  const AlertRow();
}

final class KeywordHeaderRow extends AlertRow {
  final String keyword;
  final int count;
  final bool collapsed;

  const KeywordHeaderRow({
    required this.keyword,
    required this.count,
    required this.collapsed,
  });
}

final class KeywordEntryRow extends AlertRow {
  final AlertEntry entry;
  const KeywordEntryRow(this.entry);
}

/// Groups [entries] by keyword: every entry a keyword matched, in the order
/// [entries] already carries them (`AlertMatchRepository.getEntries()`
/// returns newest-matched-first, and nothing here reorders within a group).
///
/// An entry that hit more than one keyword appears once per keyword it
/// matched — deliberate duplication, not a bug: a section is "everything
/// this keyword caught," not a partition of the list.
///
/// Sections are ordered by their own most recent match, descending — the
/// keyword whose newest entry is most recent comes first. A default, not
/// mandated by any rule this list otherwise follows: alphabetical is the
/// obvious alternative if this doesn't feel right in practice.
///
/// A keyword with no current entries produces no section: this groups
/// whatever [entries] actually contains, not every keyword the user has
/// ever configured.
List<(String keyword, List<AlertEntry> entries)> groupByKeyword(
  List<AlertEntry> entries,
) {
  final byKeyword = <String, List<AlertEntry>>{};
  for (final entry in entries) {
    for (final keyword in entry.keywords) {
      byKeyword.putIfAbsent(keyword, () => []).add(entry);
    }
  }

  final sections = [for (final e in byKeyword.entries) (e.key, e.value)];
  // Each list is already newest-first (straight from the query), so its
  // first entry's matchedAt is that keyword's most recent match.
  sections.sort((a, b) => b.$2.first.matchedAt.compareTo(a.$2.first.matchedAt));
  return sections;
}

/// Flattens [groupByKeyword]'s sections into the rows a list actually
/// renders: a header per keyword, followed by its entries — unless
/// [collapsedKeywords] contains that keyword, in which case only the header
/// appears and its entries are omitted entirely.
///
/// [newestFirst] reorders entries *within* each section only; it never
/// changes which section comes first — that ordering, by most-recent-match,
/// is [groupByKeyword]'s own and does not depend on this flag.
List<AlertRow> alertRows(
  List<AlertEntry> entries, {
  required Set<String> collapsedKeywords,
  required bool newestFirst,
}) {
  final rows = <AlertRow>[];
  for (final (keyword, keywordEntries) in groupByKeyword(entries)) {
    final collapsed = collapsedKeywords.contains(keyword);
    rows.add(KeywordHeaderRow(
      keyword: keyword,
      count: keywordEntries.length,
      collapsed: collapsed,
    ));
    if (!collapsed) {
      final ordered =
          newestFirst ? keywordEntries : keywordEntries.reversed.toList();
      for (final entry in ordered) {
        rows.add(KeywordEntryRow(entry));
      }
    }
  }
  return rows;
}
