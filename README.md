# Expense Tracker

A minimal, black-and-white Android app that turns bank SMS into an expense log.
There is no server and no account. Everything is stored in a local SQLite file on the phone.

## How it works

- **SMS is only read on refresh.** The app never listens for incoming messages. Refresh from
  Home (button or pull-down), Settings, or the daily notification's **Refresh** button. Each refresh
  re-scans from the last scan time minus 2 days. The very first refresh covers the last 3 months.
  Older SMS can be imported from *Settings › Import older SMS*.
- **Only completed debits and credits are kept.** OTPs, offers, bill-due reminders, failed
  transactions, UPI collect requests, future auto-debits and personal (phone-number) senders are
  ignored. See `lib/services/sms_parser.dart`.
- **Each SMS is imported at most once.** Every SMS gets a fingerprint (`sha1(sender|time|body)`)
  stored with a UNIQUE constraint.
- **Two sources:** `SMS` (bank, account/card digits, counterparty and available balance parsed from
  the text) and `Manual` (added with the + button).
- **Tags:** one tag per transaction, user-defined names and colours. Reports show per-tag totals plus
  "No tag", and these always add up to the period total.
- **Notes** on any transaction.
- **Totals:** debited, credited and net for any period (week, month, custom), plus the latest
  bank-reported balance per account.
- **Export** to Excel (.xlsx with Transactions, Summary and Tags sheets) or CSV, saved to the device or shared.
- **Import** (*Settings › Import from Excel / CSV*) restores an export, e.g. after reinstalling. Only the
  Transactions sheet is read; tag colours come from the Tags sheet when present. Rows get the source
  **Imported**. Duplicates are skipped: importing the same file twice adds nothing, and a later SMS refresh
  won't re-add an SMS that was restored from the file (both use `sha1(sender | time to the minute | text)`).
- **Home screen widget** shows debited / credited / net. In Settings you choose the period (this
  month, last month, this week, a specific month), which tag to count, and which figures to show.

### What happens when you…

| Action | Effect |
|---|---|
| **Archive** (single, multi-select, or by date range) | Hidden from lists, totals, reports, balances, widget and exports. The row is kept, so the SMS is never re-imported. Restore from *Settings › Archived*. |
| **Delete** | Only manual entries can be deleted (permanently). SMS and imported entries can only be archived, so their duplicate-check key is never lost. |
| **Delete a tag** | Its transactions, archived ones included, become "No tag". Nothing else is removed. If the widget was filtered to that tag, it falls back to "All". |
| **Any data change** | `AppState._changed()` bumps a revision (all open screens reload) and recomputes the widget. |

## Run

```bash
flutter pub get
flutter run            # Android device or emulator
flutter test           # parser + repository tests
```

Android only: iOS does not allow apps to read SMS.

Note: Google Play restricts `READ_SMS` to approved app categories. This app is meant for
sideloading (personal use).
