# Service localization gaps — 2026-10-11

This inventory covers service-generated copy and user-visible service results for update checks, exports, cloud-sync status, backup/WebDAV errors, and the reported Admin API validation work. It does not repeat the screen inventory or the widget action safety audit. Findings are based on source and test inspection; no tests were run and no source was changed for this document.

## Prioritized gaps

### P1 — Update notes and updater errors are not consistently locale-aware

`lib/core/app_update_policy.dart:49-67` always adds the Chinese `本次更新摘要：` heading to generated summaries. `lib/services/app_update_service.dart:63-67,153,205,841,1062-1068` also generates Chinese copy for empty release notes and fallback notes. Those values are surfaced by the force-update gate (`lib/widgets/force_update_gate.dart:32-35,160-165`) and update screen, including in English locale.

The updater also assigns Chinese errors directly in GitHub release handling and download/install paths (`app_update_service.dart:666-676,928-1007`). The force-update gate displays `updater.error` as-is. Localize app-authored fallback and error copy at presentation time or through locale-aware service copy; keep release notes, blocked reasons, versions, asset names, status codes, and API contract diagnostics supplied by the server or protocol unchanged.

Current tests assert the Chinese summary/fallback output (`test/services/app_update_service_test.dart:14-28,353-383`) but do not cover these generated strings across Chinese and English locale changes. Add locale coverage for the generated summary heading, missing-note text, fallback notes, and direct updater errors, including changing locale after the update data has been loaded.

### P1 — ICS and Markdown exports embed Chinese defaults and labels

`lib/services/ics_exporter.dart:13-21,40-48` defaults calendar names to Chinese. `ModuleExporter` embeds Chinese generated copy in the todo, note, diary, anniversary, and goal Markdown output, including headings, attachment/status labels, anniversary type/calendar labels, and the ungrouped-todo fallback (`ics_exporter.dart:110-133,260-327,351-356`). These strings become part of exported files and remain Chinese for English users.

Make generated export labels follow the active locale while preserving user-authored titles, descriptions, tags, group names, and attachment names verbatim. Keep CSV headers/schema stable, as well as ICS `PRODID`, UIDs, enum categories, and other machine-readable identifiers. Existing exporter coverage found in this inspection is CSV-focused; add tests for the default ICS calendar names and generated Markdown copy in both locales, plus assertions that authored values and format identifiers remain unchanged.

### P1 — Cloud-sync retry reasons carry Chinese app-generated text into English widget notices

`lib/providers/cloud_sync_provider.dart:201-210,397-414,818-819,1000-1005,1647-1660,1782-1788` stores Chinese retry fallback text and adds Chinese prefixes such as “远端更新检查失败” before a sanitized API error. `main.dart:4743-4764` passes that reason to `WidgetActionSyncStatus`; `lib/services/widget_action_message.dart:51-86,286-300` localizes the surrounding notice but preserves `syncReason` verbatim. Thus the notice can have English framing with a Chinese app-authored reason.

Represent/localize the app-generated retry reason separately from any dynamic API detail. Preserve server-authored messages and technical values as supplied unless their API contract explicitly defines them as translatable. Existing widget-message tests cover bilingual states and literal reason passthrough (`test/services/widget_action_message_test.dart:117-284`), while provider tests assert Chinese retry text (`test/services/cloud_sync_provider_test.dart:373-423`); add locale assertions for provider-generated reasons and a regression case confirming a dynamic API-authored detail remains intact.

## In progress / scope boundary

Admin API malformed-response validation localization is reported as in progress in the root work. The planned handling is typed, live-locale validation copy while preserving `ApiException` behavior and server/authored messages; this inventory does not inspect or modify that work. Follow-up coverage should exercise malformed response shapes in both locales, changing locale before rendering, and preservation of the existing exception/message contract.

`AdminApi.closeFeedback` has a Chinese default success message, but the current caller explicitly passes that same text when there is no existing reply. A service-only change cannot safely distinguish generated success copy from authored reply text. Keep authored replies unchanged; decide any empty-reply success copy at the caller boundary.

## No service copy gap identified

The widget notice catalog itself provides Chinese and English copy. The gap above comes from provider-generated retry reasons passed as literal data; other widget action text and user-authored parameters should remain as-is.

Backup/WebDAV exceptions include Chinese service details (`lib/services/webdav_backup_service.dart:141-174,216`), but the visible `BackupScreen` error path sends them through locale-aware `DataSettingsUiCopy` formatters (`lib/screens/backup_screen.dart:229,350,443,506,863,1190,1586,1630,1741`; `lib/core/data_settings_ui_copy.dart:522-675`). Those formatters select localized generic/network/auth/status copy and suppress raw technical details and credentials. No user-visible service localization gap was identified in this path. `test/core/data_settings_ui_copy_test.dart` currently covers reward copy, not these error formatter branches; add focused formatter tests for both locales and representative typed errors when expanding this area.

## Localization boundaries

- Translate only app-generated labels, fallbacks, and error framing.
- Preserve authored server/API text, release notes, replies, and user content verbatim.
- Preserve versions, filenames, URLs, status codes, contract identifiers, CSV headers, and ICS identifiers/categories as data or format contracts.

## Accepted service follow-up

The inventory above records the pre-integration baseline. Subsequent accepted commits close the service-owned portions:

- `ec27048`: typed, live-locale cloud-sync reasons and explicit-locale widget/API feedback. **124** distinct regressions passed; nine-file analysis was clean. See `cloud-sync-service-locale-acceptance-20261011.md`.
- `100f9bc`: localized generated Markdown/ICS labels and escaped calendar names, with stable CSV schema and authored content. **5** regressions passed; three-file analysis was clean. See `exporter-service-locale-acceptance-20261011.md`.
- `729f2ea`: typed lazy update errors and factual missing-notes copy, literal release notes/reasons, matching GitHub tag/assets, safe install preflight. **61** distinct regressions passed; three-file analysis was clean. See `updater-service-locale-acceptance-20261011.md`.

The standalone summary utility remains compatibility behavior used only by a testing hook in this checkout; the updater service displays supplied release notes literally. Page-owned ForceUpdateGate labels, caller-supplied Chinese save text, and broader route internationalization remain open. These commits do not establish Android/iOS device behavior or full goal completion.
