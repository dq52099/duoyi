import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('黄历和万年历右上角只保留有反馈的今天动作', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();

    expect(source, contains('void _goToday()'));
    expect(source, contains('LayoutBuilder('));
    expect(source, contains('ConstrainedBox('));
    expect(source, contains('maxWidth: 1160'));
    expect(source, contains('final wide = constraints.maxWidth >= 940'));
    expect(source, contains('return Scrollbar('));
    expect(source, contains('SingleChildScrollView('));
    expect(source, contains('Widget _summaryHeroCard({'));
    expect(source, contains('Widget _aboutCard()'));
    expect(source, contains('final compact = constraints.maxWidth < 360'));
    expect(
      source,
      contains(
        'Widget _yijiRow({required String suitable, required String avoid})',
      ),
    );
    expect(
      source,
      contains(
        "Widget _yijiRow({required String suitable, required String avoid}) {\n"
        "    return Column(",
      ),
    );
    expect(
      source,
      contains(
        "_yijiCard(title: '宜', body: suitable, color: const Color(0xFF66BB6A)),\n"
        "        const SizedBox(height: 10),\n"
        "        _yijiCard(title: '忌', body: avoid, color: const Color(0xFFEF5350)),",
      ),
    );
    expect(source, isNot(contains('constraints.maxWidth < 520')));
    expect(source, contains("Text(alreadyToday ? '已经是今天' : '已回到今天')"));
    expect(source, contains('messenger.hideCurrentSnackBar()'));
    expect(source, contains('behavior: SnackBarBehavior.floating'));
    expect(source, contains("tooltip: '回到今天'"));
    expect(source, isNot(contains('class _SeasonalWeatherCard')));
    expect(source, isNot(contains('class _SeasonalWeatherInfo')));
    expect(source, isNot(contains('_seasonalWeatherInfo(DateTime date)')));
    expect(source, isNot(contains('夏季天气参考')));
    expect(source, isNot(contains('补水防晒')));
    expect(source, isNot(contains('OpenMeteoAlmanacWeatherClient')));
    expect(source, isNot(contains('AlmanacWeatherClient')));
    expect(source, isNot(contains("import '../models/diary_entry.dart';")));
    expect(
      source,
      isNot(contains("import '../providers/diary_provider.dart';")),
    );
    expect(source, isNot(contains('context.watch<DiaryProvider?>()')));
    expect(source, isNot(contains('entryForDate(date)?.weather')));
    expect(source, isNot(contains('static List<String> _weatherDetails')));
    expect(
      source,
      isNot(contains('static List<(IconData, String)> _weatherSignals')),
    );
    expect(source, isNot(contains("'本地天气摘要'")));
    expect(source, isNot(contains("'已记录天气'")));
    expect(source, isNot(contains('来自当天日记记录')));
    expect(source, isNot(contains('当前未接入外部天气 API')));
    expect(
      source,
      isNot(contains('showDiaryEditor(context, initialDate: date)')),
    );
    expect(source, isNot(contains("label: const Text('记录天气')")));
    expect(source, isNot(contains("'高温防晒'")));
    expect(source, isNot(contains('void _toggleMode()')));
    expect(source, isNot(contains("tooltip: isAlmanac ? '切换到万年历' : '切换到黄历'")));
    expect(source, isNot(contains('Navigator.pushReplacement(')));
  });
}
