import '../models/folder.dart';

/// The one rule for "does the user already have this category?"
///
/// Two features need it and must not disagree: the starter pack, which reuses
/// a folder rather than creating a second one beside it, and OPML import,
/// which merges into the library instead of replacing it. Both are "add things
/// the user may already have", and a reader who keeps a category called
/// `world news` should get feeds put in it whether they arrive from the pack
/// or from a Feedly export.
///
/// Deliberately a shared library-level function rather than a private helper
/// in either service: Dart's privacy is per-library, so a `_`-prefixed
/// function cannot be shared across files at all — copying it into the second
/// service is exactly the duplication this exists to prevent.
///
/// Trimmed and lower-cased only. No punctuation or whitespace normalisation:
/// "Tech" and "Tech News" are different categories, and guessing otherwise
/// would silently merge two the user meant to keep apart.
String folderMatchKey(String name) => name.trim().toLowerCase();

/// The first folder in [folders] whose name matches [name] under
/// [folderMatchKey], or null.
///
/// The caller's own spelling is never imposed on a match — the stored folder
/// keeps the name the user gave it.
Folder? findFolderByName(List<Folder> folders, String name) {
  final key = folderMatchKey(name);
  for (final folder in folders) {
    if (folderMatchKey(folder.name) == key) return folder;
  }
  return null;
}
