import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页支持复制 Markdown 报告', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final reportModel = File('lib/core/period_report.dart').readAsStringSync();
    final cjkFont = File('assets/fonts/DroidSansFallbackFull.ttf');

    expect(source, contains('tooltip: copy.copyReportTooltip'));
    expect(source, contains('tooltip: copy.reportShareImageTooltip'));
    expect(source, contains('Clipboard.setData'));
    expect(source, contains("package:share_plus/share_plus.dart"));
    expect(source, contains("package:pdf/pdf.dart"));
    expect(source, contains("package:pdf/widgets.dart"));
    expect(pubspec, contains('pdf:'));
    expect(source, contains('SharePlus.instance.share'));
    expect(source, contains('ShareParams('));
    expect(source, contains('XFile(filePath)'));
    expect(source, contains('_buildReportMarkdown'));
    expect(source, contains('_ReportShareDialog'));
    expect(source, contains('PeriodReportDigest'));
    expect(source, contains('_PeriodReportDigestCard'));
    expect(source, contains('PeriodReportKind.weekly'));
    expect(source, contains('PeriodReportKind.monthly'));
    expect(source, contains('PeriodReportKind.yearly'));
    expect(source, contains('_copyDigest'));
    expect(source, contains('PeriodReportPresentation('));
    expect(reportModel, contains('PeriodReportKind.yearly => \'年度报告\''));
    expect(source, contains('RenderRepaintBoundary'));
    expect(source, contains('ui.ImageByteFormat.png'));
    expect(source, contains('pw.Document'));
    expect(source, contains('PdfPageFormat.a4'));
    expect(source, contains('pw.MemoryImage'));
    expect(source, contains('.savePdfAction'));
    expect(source, contains('_ReportPdfTemplate'));
    expect(source, contains('_ReportPdfTemplate.visual'));
    expect(source, contains('_ReportPdfTemplate.archive'));
    expect(source, contains('_ReportPdfTemplate.briefing'));
    expect(source, contains('_ReportPdfTemplate.dashboard'));
    expect(source, contains('_ReportPdfTemplate.timeline'));
    expect(source, contains('SegmentedButton<_ReportPdfTemplate>'));
    expect(source, contains('SingleChildScrollView'));
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('.pdfTemplate'));
    expect(source, contains('.pdfTemplateVisual'));
    expect(source, contains('.pdfTemplateArchive'));
    expect(source, contains('.pdfTemplateBriefing'));
    expect(source, contains('.pdfTemplateDashboard'));
    expect(source, contains('.pdfTemplateTimeline'));
    expect(source, contains('_buildPdfDocument'));
    expect(source, contains('_buildBriefingPdfContent'));
    expect(source, contains('_buildBriefingSection'));
    expect(source, contains('_buildDashboardPdfContent'));
    expect(source, contains('_buildDashboardMetricCard'));
    expect(source, contains('_buildDashboardRankItem'));
    expect(source, contains('_buildTimelinePdfContent'));
    expect(source, contains('_buildTimelineItem'));
    expect(source, contains('_buildTimelineSideSection'));
    expect(source, contains('_buildPdfBullet'));
    expect(source, contains('_buildPdfMutedText'));
    expect(source, contains('_buildSearchablePdfContent'));
    expect(source, contains('_reportPdfTemplateLabel'));
    expect(source, contains('_markdownTitle'));
    expect(source, contains('_markdownSectionItems'));
    expect(source, contains('pw.MultiPage'));
    expect(source, contains('pw.Text('));
    expect(source, contains('.pdfSearchableLayerTitle'));
    expect(source, contains('.pdfBriefingNotice'));
    expect(source, contains('.pdfDashboardNotice'));
    expect(source, contains('.pdfTimelineNotice'));
    expect(source, contains("rootBundle.load("));
    expect(source, contains('assets/fonts/DroidSansFallbackFull.ttf'));
    expect(source, contains('pw.Font.ttf'));
    expect(source, contains('pw.ThemeData.withFont'));
    expect(source, contains('fontFallback'));
    expect(source, contains('template == _ReportPdfTemplate.visual'));
    expect(pubspec, contains('assets/fonts/'));
    expect(cjkFont.existsSync(), isTrue);
    expect(source, contains('.sharePdfSaved'));
    expect(source, contains('getTemporaryDirectory'));
    expect(source, contains('.markdownReportTitle'));
    expect(source, contains('.markdownOverview'));
    expect(source, contains('.markdownTimeDistribution'));
    expect(source, contains('.markdownRecentRecords'));
    expect(source, contains('.markdownCompletedTodos'));
    expect(source, contains('.reportCopiedNotice'));
    expect(source, contains('.shareImageSaved'));
  });

  test('统计页支持云端 AI 个性化报告解读', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final aiService = File('lib/services/ai_service.dart').readAsStringSync();

    expect(source, contains("import '../services/ai_service.dart';"));
    expect(source, contains("import 'ai_history_screen.dart';"));
    expect(source, contains('context.watch<AiService>()'));
    expect(source, contains('_runDigestAiReview'));
    expect(source, contains('personalizedReportReview('));
    expect(source, contains('reportMarkdown: reportMarkdown'));
    expect(source, contains('.aiReview'));
    expect(source, contains('.aiHistory'));
    expect(source, contains('.aiReviewHeading'));
    expect(source, contains('.aiDisabledMessage'));
    expect(
      source,
      contains('MaterialPageRoute(builder: (_) => const AiHistoryScreen())'),
    );
    expect(source, contains('_aiReportReview = null'));
    expect(source, contains('_aiReportError = null'));

    expect(aiService, contains('Future<String> personalizedReportReview('));
    expect(aiService, contains("'/api/ai/chat'"));
    expect(aiService, contains('云端效率报告分析师'));
    expect(aiService, contains('未来 7 天 3 条可执行动作'));
    expect(aiService, contains(r"'统计报告 AI 解读：$periodLabel'"));
    expect(aiService, contains('_reviewHistory.insert(0, entry)'));
    expect(aiService, contains('await _appendReview(operation, entry)'));
    expect(aiService, contains('await _saveHistory(operation)'));
    expect(aiService, contains('_requireHistoryOperation(operation)'));
    expect(aiService, contains('maxTokens: 900'));
  });
}
