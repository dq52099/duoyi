import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/web_file_download.dart';
import '../core/achievements.dart';
import '../core/achievement_ui_copy.dart';
import '../core/i18n.dart';
import '../services/settings_action_origin.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_update_service.dart';
import '../providers/auth_provider.dart';
import '../providers/app_lock_provider.dart';
import '../core/growth_levels.dart';
import '../core/productivity_challenges.dart';
import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../providers/achievement_provider.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart';
import '../widgets/controller_dialog.dart';

class AchievementsScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final provider = context.watch<AchievementProvider>();
    final all = Achievements.all;
    final unlocked = provider.unlockedCount;
    final actionOrigin = SettingsActionOrigin(context);
    final actionGeneration = provider.storageGeneration;

    final unlockedAchievements = _unlockedAchievements(provider);
    final challenges = provider.challenges;
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(
          '${AchievementUiCopy.text('成就', 'Achievements')} · $unlocked / ${all.length}',
        ),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        actions: [
          IconButton(
            tooltip: AchievementUiCopy.text('成就分享图', 'Share achievements'),
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () {
              if (!actionOrigin.isCurrent() ||
                  !identical(context.read<AchievementProvider?>(), provider) ||
                  provider.storageGeneration != actionGeneration) {
                return;
              }
              _showAchievementShareCard(
                context,
                provider: provider,
                unlockedAchievements: unlockedAchievements,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          _ProgressHeader(
            unlocked: unlocked,
            total: all.length,
            coinBalance: provider.coinBalance,
            lifetimeCoins: provider.lifetimeCoins,
            growthLevel: provider.growthLevel,
          ),
          if (provider.rewardLedger.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RewardLedgerCard(entries: provider.rewardLedger.take(3).toList()),
          ],
          if (challenges.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppSectionHeader(
              title: AchievementUiCopy.text(
                '每日/每周挑战',
                'Daily and weekly challenges',
              ),
              subtitle: AchievementUiCopy.text(
                '完成短期目标可获得时光币',
                'Complete short-term goals to earn time coins',
              ),
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            ),
            for (final challenge in challenges) ...[
              _ChallengeCard(challenge: challenge),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 12),
          AppSectionHeader(
            title: AchievementUiCopy.text('徽章墙', 'Badge collection'),
            subtitle: AchievementUiCopy.text(
              '按使用进度逐步解锁',
              'Unlock badges as you make progress',
            ),
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columns = (constraints.maxWidth / (220 * scale))
                  .floor()
                  .clamp(1, 3);
              return Column(
                children: [
                  for (var index = 0; index < all.length; index += columns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var column = 0;
                              column < columns;
                              column++
                            ) ...[
                              if (column > 0) const SizedBox(width: 12),
                              Expanded(
                                child: index + column < all.length
                                    ? _buildBadge(provider, all[index + column])
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  Widget _buildBadge(AchievementProvider provider, Achievement badge) {
    final snapshot = provider.snapshotFor(badge.id);
    return _BadgeCard(
      ach: badge,
      unlocked: snapshot.unlocked,
      current: badge.current == null && snapshot.target == null
          ? null
          : snapshot.current,
      target: snapshot.target,
      progress: snapshot.progress,
    );
  }

  List<Achievement> _unlockedAchievements(AchievementProvider provider) {
    final items = Achievements.all
        .where((achievement) => provider.snapshotFor(achievement.id).unlocked)
        .toList();
    items.sort((a, b) {
      final aTime =
          provider.snapshotFor(a.id).unlockedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          provider.snapshotFor(b.id).unlockedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<void> _showAchievementShareCard(
    BuildContext context, {
    required AchievementProvider provider,
    required List<Achievement> unlockedAchievements,
  }) async {
    final origin = SettingsActionOrigin(context);
    if (!origin.isCurrent()) return;
    final generation = provider.storageGeneration;
    final snapshot = _AchievementShareSnapshot(
      unlockedCount: provider.unlockedCount,
      totalCount: provider.totalCount,
      coinBalance: provider.coinBalance,
      lifetimeCoins: provider.lifetimeCoins,
      growthLevel: provider.growthLevel,
      achievements: List.unmodifiable(unlockedAchievements),
    );
    final changes = Listenable.merge([
      provider,
      AccountLocalDataCleaner.accountDataGenerationListenable,
      origin.preferences,
      context.read<AuthProvider?>(),
      context.read<AppLockProvider?>(),
      context.read<AppUpdateService?>(),
    ]);
    await showControllerDialog<void>(
      context: context,
      controllers: const <TextEditingController>[],
      builder: (_) => _AchievementShareDialog(
        snapshot: snapshot,
        changes: changes,
        isOwnerCurrent: () =>
            origin.isCurrent(checkRoute: false) &&
            identical(context.read<AchievementProvider?>(), provider) &&
            provider.storageGeneration == generation,
      ),
    );
  }
}

class _AchievementShareSnapshot {
  final int unlockedCount, totalCount, coinBalance, lifetimeCoins;
  final GrowthLevel growthLevel;
  final List<Achievement> achievements;
  const _AchievementShareSnapshot({
    required this.unlockedCount,
    required this.totalCount,
    required this.coinBalance,
    required this.lifetimeCoins,
    required this.growthLevel,
    required this.achievements,
  });

  String markdown() {
    final sb = StringBuffer()
      ..writeln('# ${AchievementUiCopy.text('多仪成就海报', 'Duoyi achievements')}')
      ..writeln()
      ..writeln(
        '- ${AchievementUiCopy.text('已解锁', 'Unlocked')}: $unlockedCount / $totalCount',
      )
      ..writeln(
        '- ${AchievementUiCopy.text('成长等级', 'Growth level')}: Lv.${growthLevel.level} ${AchievementUiCopy.levelTitle(growthLevel)}',
      )
      ..writeln(
        '- ${AchievementUiCopy.text('当前时光币', 'Time coins')}: $coinBalance',
      )
      ..writeln(
        '- ${AchievementUiCopy.text('累计时光币', 'Lifetime coins')}: $lifetimeCoins',
      );
    if (achievements.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('## ${AchievementUiCopy.text('最近解锁', 'Recently unlocked')}');
      for (final badge in achievements.take(8)) {
        sb.writeln(
          '- ${AchievementUiCopy.badgeTitle(badge)}: ${AchievementUiCopy.badgeDescription(badge)}',
        );
      }
    }
    return sb.toString();
  }

  Widget card() => _AchievementShareCard(
    unlockedCount: unlockedCount,
    totalCount: totalCount,
    coinBalance: coinBalance,
    lifetimeCoins: lifetimeCoins,
    growthLevel: growthLevel,
    achievements: achievements.take(5).toList(),
  );
}

class _ChallengeCard extends StatelessWidget {
  final ProductivityChallenge challenge;

  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completed = challenge.completed;
    final color = challenge.color;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(13),
      border: Border.all(
        color: color.withValues(alpha: completed ? 0.28 : 0.14),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(
                appSurfaceStyleOf(context)?.smallTileRadius ??
                    DesignTokens.radiusControl,
              ),
            ),
            child: Icon(challenge.icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      AchievementUiCopy.challengeTitle(challenge),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        AchievementUiCopy.challengePeriod(challenge),
                        style: TextStyle(color: color, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AchievementUiCopy.challengeDescription(challenge),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.58),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: challenge.progress,
                    minHeight: 5,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${challenge.current.clamp(0, challenge.target)} / ${challenge.target}',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                completed ? Icons.check_circle : Icons.toll_outlined,
                color: completed ? color : cs.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                '+${challenge.rewardCoins}',
                style: TextStyle(
                  color: completed ? color : cs.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _resolveHeroGradientInk(Color startBg, Color endBg, Color preferred) {
  final midBg = Color.lerp(startBg, endBg, 0.5) ?? startBg;
  double minContrast(Color ink) {
    final cStart = appContrastRatio(startBg, ink);
    final cMid = appContrastRatio(midBg, ink);
    final cEnd = appContrastRatio(endBg, ink);
    return math.min(cStart, math.min(cMid, cEnd));
  }

  if (minContrast(preferred) >= 5.0) {
    return preferred;
  }
  const candidates = <Color>[Color(0xFF111827), Colors.white, Colors.black];
  var best = candidates.first;
  var bestRatio = minContrast(best);
  for (final candidate in candidates.skip(1)) {
    final ratio = minContrast(candidate);
    if (ratio > bestRatio) {
      best = candidate;
      bestRatio = ratio;
    }
  }
  return best;
}

class _ProgressHeader extends StatelessWidget {
  final int unlocked;
  final int total;
  final int coinBalance;
  final int lifetimeCoins;
  final GrowthLevel growthLevel;
  const _ProgressHeader({
    required this.unlocked,
    required this.total,
    required this.coinBalance,
    required this.lifetimeCoins,
    required this.growthLevel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseSurface = cs.surface;
    final gradientStart = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.18 : 0.14),
      baseSurface,
    );
    final gradientEnd = Color.alphaBlend(
      cs.tertiary.withValues(alpha: isDark ? 0.12 : 0.10),
      baseSurface,
    );
    final heroCaptionColor = _resolveHeroGradientInk(
      gradientStart,
      gradientEnd,
      cs.onSurface,
    );
    final p = total == 0 ? 0.0 : unlocked / total;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(
        appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusXl,
      ),
      gradient: LinearGradient(
        colors: [gradientStart, gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: cs.primary.withValues(alpha: isDark ? 0.26 : 0.16),
        width: 0.55,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final stacked = constraints.maxWidth < 420 * scale;
          final summary = Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(
                    appSurfaceStyleOf(context)?.cardRadius ??
                        DesignTokens.radiusLg,
                  ),
                ),
                child: Icon(
                  Icons.emoji_events,
                  color: heroCaptionColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AchievementUiCopy.text('你的成就', 'Your achievements'),
                      style: TextStyle(
                        color: heroCaptionColor,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$unlocked / $total',
                      style: TextStyle(
                        color: heroCaptionColor,
                        fontSize: 24,
                        fontWeight: FontWeight.normal,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 7,
                        backgroundColor: heroCaptionColor.withValues(
                          alpha: 0.16,
                        ),
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final level = _LevelCoinPanel(
            coinBalance: coinBalance,
            lifetimeCoins: lifetimeCoins,
            growthLevel: growthLevel,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 12), level],
                )
              : Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    SizedBox(width: 170, child: level),
                  ],
                );
        },
      ),
    );
  }
}

class _LevelCoinPanel extends StatelessWidget {
  final int coinBalance;
  final int lifetimeCoins;
  final GrowthLevel growthLevel;
  final Color? gradientStart;
  final Color? gradientEnd;

  const _LevelCoinPanel({
    required this.coinBalance,
    required this.lifetimeCoins,
    required this.growthLevel,
    this.gradientStart,
    this.gradientEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseSurface = cs.surface;
    final bgStart =
        gradientStart ??
        Color.alphaBlend(
          cs.primary.withValues(alpha: isDark ? 0.18 : 0.14),
          baseSurface,
        );
    final bgEnd =
        gradientEnd ??
        Color.alphaBlend(
          cs.tertiary.withValues(alpha: isDark ? 0.12 : 0.10),
          baseSurface,
        );
    final panelColor = cs.surface.withValues(alpha: isDark ? 0.42 : 0.62);
    final panelStart = Color.alphaBlend(panelColor, bgStart);
    final panelEnd = Color.alphaBlend(panelColor, bgEnd);
    final heroTextColor = _resolveHeroGradientInk(
      panelStart,
      panelEnd,
      cs.onSurface,
    );
    final isMaxLevel = growthLevel.coinsForNextLevel <= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(
          appSurfaceStyleOf(context)?.cardRadius ?? DesignTokens.radiusLg,
        ),
        border: Border.all(
          color: heroTextColor.withValues(alpha: 0.14),
          width: 0.55,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Lv.${growthLevel.level}',
            style: TextStyle(
              color: heroTextColor,
              fontSize: 18,
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            AchievementUiCopy.levelTitle(growthLevel),
            style: TextStyle(color: heroTextColor, fontSize: 10),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: growthLevel.progress,
              minHeight: 5,
              backgroundColor: heroTextColor.withValues(alpha: 0.22),
              color: heroTextColor,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            isMaxLevel
                ? AchievementUiCopy.text('最高等级', 'Maximum level')
                : AchievementUiCopy.text(
                    '还差 ${growthLevel.coinsRemaining}',
                    '${growthLevel.coinsRemaining} coins to next level',
                  ),
            style: TextStyle(
              color: heroTextColor,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            AchievementUiCopy.text(
              '时光币 $coinBalance',
              'Time coins $coinBalance',
            ),
            style: TextStyle(
              color: heroTextColor,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            AchievementUiCopy.text(
              '累计 $lifetimeCoins',
              'Lifetime $lifetimeCoins',
            ),
            style: TextStyle(
              color: heroTextColor,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardLedgerCard extends StatelessWidget {
  final List<RewardLedgerEntry> entries;

  const _RewardLedgerCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.toll_outlined, color: cs.primary, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AchievementUiCopy.text(
                    '最近奖励/兑换',
                    'Recent rewards and redemptions',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.add_circle_outline,
                      color: cs.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AchievementUiCopy.ledgerTitle(entry),

                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        Text(
                          AchievementUiCopy.ledgerReason(entry),

                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.56),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    entry.coins >= 0 ? '+${entry.coins}' : '${entry.coins}',
                    style: TextStyle(
                      color: entry.coins >= 0 ? cs.primary : cs.error,
                      fontWeight: FontWeight.normal,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AchievementShareDialog extends StatefulWidget {
  final _AchievementShareSnapshot snapshot;
  final Listenable changes;
  final bool Function() isOwnerCurrent;
  const _AchievementShareDialog({
    required this.snapshot,
    required this.changes,
    required this.isOwnerCurrent,
  });
  @override
  State<_AchievementShareDialog> createState() =>
      _AchievementShareDialogState();
}

class _AchievementShareDialogState extends State<_AchievementShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _saving = false;
  bool _removalScheduled = false;

  bool get _current =>
      mounted &&
      widget.isOwnerCurrent() &&
      ModalRoute.of(context)?.isCurrent == true;

  void _removeInvalidRoute() {
    if (_removalScheduled) return;
    _removalScheduled = true;
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.isOwnerCurrent() && route?.isActive == true) {
        route!.navigator?.removeRoute(route);
      }
      _removalScheduled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AchievementProvider?>();
    return AnimatedBuilder(
      animation: widget.changes,
      builder: (context, _) {
        if (!widget.isOwnerCurrent()) {
          _removeInvalidRoute();
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) => AppDialog(
            title: Text(AchievementUiCopy.text('成就分享图', 'Share achievements')),
            content: SingleChildScrollView(
              child: RepaintBoundary(
                key: _cardKey,
                child: widget.snapshot.card(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (_current) Navigator.of(context).pop();
                      },
                child: Text(AchievementUiCopy.text('关闭', 'Close')),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _copyMarkdown,
                icon: const Icon(Icons.copy, size: 16),
                label: Text(AchievementUiCopy.text('复制文案', 'Copy text')),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _savePng,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined, size: 16),
                label: Text(AchievementUiCopy.text('分享 PNG', 'Share PNG')),
              ),
            ],
          ),
        );
      },
    );
  }

  void _feedback(String zh, String en) {
    if (!_current) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) => Text(AchievementUiCopy.text(zh, en)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyMarkdown() async {
    if (!_current || _saving) return;
    setState(() => _saving = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.snapshot.markdown()));
      if (!_current) return;
      _feedback('成就文案已复制', 'Achievement text copied');
    } catch (_) {
      _feedback('复制失败，请重试', 'Could not copy. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePng() async {
    if (!_current || _saving) return;
    final locale = I18n.current;
    final markdown = widget.snapshot.markdown();
    bool valid() => _current && I18n.current == locale;
    setState(() => _saving = true);
    ui.Image? image;
    File? file;
    bool shared = false;
    try {
      // Capture only after the repaint boundary reflects the selected locale.
      await WidgetsBinding.instance.endOfFrame;
      if (!valid()) return;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Share card unavailable');
      image = await boundary.toImage(pixelRatio: 3);
      if (!valid()) return;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!valid()) return;
      if (byteData == null) throw StateError('Image encoding failed');
      final pngBytes = byteData.buffer.asUint8List();
      final fileName =
          'duoyi_achievement_${DateTime.now().microsecondsSinceEpoch}.png';
      if (kIsWeb) {
        final result = await WebFileDownload.saveBytes(
          bytes: pngBytes,
          fileName: fileName,
          mimeType: 'image/png',
          shareText: markdown,
          shareSubject: AchievementUiCopy.text('多仪成就海报', 'Duoyi achievements'),
          canProceed: valid,
        );
        if (!valid() || !mounted) return;
        if (result.saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AchievementUiCopy.text(
                  '已下载成就海报：$fileName',
                  'Downloaded achievement poster: $fileName',
                ),
              ),
            ),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      if (!valid()) return;
      file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes, flush: true);
      if (!valid()) return;
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || box.size.isEmpty) {
        throw StateError('Share origin unavailable');
      }
      final shareOrigin = box.localToGlobal(Offset.zero) & box.size;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: shareOrigin,
          text: markdown,
          subject: AchievementUiCopy.text('多仪成就海报', 'Duoyi achievements'),
        ),
      );
      shared = true;
      if (!valid()) return;
      if (result.status == ShareResultStatus.unavailable) {
        _feedback('系统分享暂不可用，请重试', 'Sharing is unavailable. Please try again.');
      }
    } catch (_) {
      _feedback('分享失败，请重试', 'Could not share. Please try again.');
    } finally {
      image?.dispose();
      // Keep a shared file available for the receiving app; discard aborted captures.
      if (!shared && file != null) {
        try {
          await file.delete();
        } catch (_) {
          /* Best effort temporary cleanup. */
        }
      }
      if (mounted) setState(() => _saving = false);
    }
  }
}

const double _shareCardWidth = 360.0;
const double _shareCardPadding = 22.0;
const double _shareCardBorderWidth = 0.45;
const double _shareMetricSpacing = 8.0;
const double _shareCardInnerWidth =
    _shareCardWidth - 2 * _shareCardPadding - 2 * _shareCardBorderWidth;
const double _twoColumnMetricTileWidth =
    (_shareCardInnerWidth - _shareMetricSpacing) / 2.0;

class _AchievementShareCard extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;
  final int coinBalance;
  final int lifetimeCoins;
  final GrowthLevel growthLevel;
  final List<Achievement> achievements;

  const _AchievementShareCard({
    required this.unlockedCount,
    required this.totalCount,
    required this.coinBalance,
    required this.lifetimeCoins,
    required this.growthLevel,
    required this.achievements,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = totalCount == 0 ? 0.0 : unlockedCount / totalCount;
    return Container(
      width: _shareCardWidth,
      padding: const EdgeInsets.all(_shareCardPadding),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: _shareCardBorderWidth,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            ),
            child: Icon(Icons.emoji_events, color: cs.primary, size: 24),
          ),
          const SizedBox(height: 10),
          Text(
            AchievementUiCopy.text('多仪成就海报', 'Duoyi achievements'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal),
          ),
          const SizedBox(height: 4),
          Text(
            AchievementUiCopy.text('持续积累的可见进步', 'See your progress grow'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text(
            '$unlockedCount / $totalCount',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: cs.primary,
              backgroundColor: cs.primary.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 14),
          _buildMetrics(context, cs, progress),
          if (achievements.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              AchievementUiCopy.text('最近解锁', 'Recently unlocked'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.normal),
            ),
            const SizedBox(height: 8),
            for (final achievement in achievements)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: achievement.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        achievement.icon,
                        size: 16,
                        color: achievement.color,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(AchievementUiCopy.badgeTitle(achievement)),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            AchievementUiCopy.text('由多仪生成', 'Created with Duoyi'),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, ColorScheme cs, double progress) {
    final metrics = [
      (
        label: AchievementUiCopy.text('时光币', 'Time coins'),
        value: '$coinBalance',
      ),
      (
        label: AchievementUiCopy.text('累计', 'Lifetime'),
        value: '$lifetimeCoins',
      ),
      (
        label: AchievementUiCopy.levelTitle(growthLevel),
        value: 'Lv.${growthLevel.level}',
      ),
      (
        label: AchievementUiCopy.text('完成度', 'Progress'),
        value: '${(progress * 100).round()}%',
      ),
    ];

    final textScaler = MediaQuery.textScalerOf(context);
    final defaultTextStyle = DefaultTextStyle.of(context).style;
    final valueStyle = defaultTextStyle.merge(
      const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
      ),
    );
    final labelStyle = defaultTextStyle.merge(
      TextStyle(
        fontSize: 11,
        color: cs.onSurface.withValues(alpha: 0.58),
      ),
    );
    final directionality =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final locale = Localizations.maybeLocaleOf(context);

    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: directionality,
        locale: locale,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    double maxRequiredWidth = 0.0;
    for (final m in metrics) {
      final valW = measure(m.value, valueStyle);
      if (valW > maxRequiredWidth) maxRequiredWidth = valW;
      for (final word in m.label.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final wordW = measure(word, labelStyle);
        if (wordW > maxRequiredWidth) maxRequiredWidth = wordW;
      }
    }

    final minTileWidth = maxRequiredWidth + 24.0;
    final tileWidth = minTileWidth > _twoColumnMetricTileWidth
        ? minTileWidth
        : _twoColumnMetricTileWidth;

    return Wrap(
      spacing: _shareMetricSpacing,
      runSpacing: _shareMetricSpacing,
      children: [
        for (final m in metrics)
          SizedBox(
            width: tileWidth,
            child: _AchievementShareMetric(
              label: m.label,
              value: m.value,
            ),
          ),
      ],
    );
  }
}

class _AchievementShareMetric extends StatelessWidget {
  final String label;
  final String value;

  const _AchievementShareMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.normal,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final Achievement ach;
  final bool unlocked;
  final int? current;
  final int? target;
  final double progress;

  const _BadgeCard({
    required this.ach,
    required this.unlocked,
    required this.current,
    required this.target,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = unlocked ? ach.color : cs.outline;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      border: Border.all(
        color: color.withValues(alpha: unlocked ? 0.24 : 0.14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(
                    appSurfaceStyleOf(context)?.smallTileRadius ??
                        DesignTokens.radiusControl,
                  ),
                ),
                child: Icon(ach.icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AchievementUiCopy.badgeTitle(ach),
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: unlocked ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unlocked
                      ? AchievementUiCopy.text('已解锁', 'Unlocked')
                      : AchievementUiCopy.text('进行中', 'In progress'),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AchievementUiCopy.badgeDescription(ach),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          if (current != null && target != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: color.withValues(alpha: 0.12),
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$current / $target',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
