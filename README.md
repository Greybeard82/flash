# Flash

An Android RSS and Atom reader: account-free and local-first, with keyword
blocking to cut the noise, keyword alerts for the things you don't want to
miss, and AI article summaries that run on-device where the phone supports it.

Flutter and Dart, SQLite on the device, Android only.

| Where to look | For |
|---|---|
| [`PRD-Flash.md`](PRD-Flash.md) | What the app does, what it deliberately doesn't, and what's decided but unbuilt. The single source of truth — if it and the code disagree, one of them is a bug. |
| [`MANUAL_QA.md`](MANUAL_QA.md) | On-device checks that automated tests can't cover. |
| [`CLAUDE.md`](CLAUDE.md) | Rules for coding agents, including the absolute ban on changing settings on a physical device. |

Build with `flutter build appbundle --release`. Release signing reads
`android/key.properties`, which is not committed.
