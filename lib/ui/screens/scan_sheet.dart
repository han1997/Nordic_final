import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/music_source.dart';
import '../../state/app_state.dart';
import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../widgets/components.dart';
import '../widgets/states.dart';

/// 揭开「曲库扫描」那张纸 —— 设置页服务器那一栏里那一行。
void showScanSheet(BuildContext context) {
  showNordicSheet<void>(
    context: context,
    builder: (sheetContext) => const _ScanSheet(),
  );
}

/// 曲库扫描:状态 + 一颗「开始扫描」。
///
/// **扫描是服务器在扫它自己的盘**,这边只是问一句、催一下:
///
///   - 打开这张纸先问一次状态(`getScanStatus`),扫着的话**每秒再问一次**
///     —— 只在纸开着的时候轮,关掉即停,不让它在后台一直打服务器;
///   - 「开始扫描」走 `startScan`(要管理员权限)。失败**不假装成功**:
///     把服务器那句话摆在纸上(非管理员最常见的就是这一条);
///   - 轮询到扫完了 → 自动把音乐库重取一遍(「扫完就能看见新歌」是这件事的
///     全部意义),并顺手报一句这次扫到多少首。
class _ScanSheet extends StatefulWidget {
  const _ScanSheet();

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  Timer? _poll;
  bool _starting = false;
  String? _error;

  /// 这一趟的「扫完刷新」做过没有 —— 轮询每秒来一次,别每来一次就重取一遍库。
  bool _refreshed = false;

  @override
  void initState() {
    super.initState();
    // 首帧之后再问:这一趟要走网络,而它在 build 之前发也不会更快。
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 问一次状态,并按它决定要不要继续轮。
  Future<void> _tick() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    await state.refreshScanStatus();
    if (!mounted) return;

    final status = state.scanStatus;
    if (status == null) return;

    if (status.scanning) {
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      return;
    }

    // 没在扫了:停轮询,并把库重取一遍(一次)。
    _poll?.cancel();
    _poll = null;
    if (_refreshed) return;
    _refreshed = true;
    await state.loadLibrary(silent: true);
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await state.startLibraryScan();
      _refreshed = false;
      await _tick();
      if (!mounted) return;
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } on MusicSourceException catch (e) {
      // 非管理员最常见 —— 把服务器那句话原样摆出来,别改写成含糊的「扫描失败」:
      // 用户要拿它判断是自己点错了、还是这个账号真没有权限。
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    // 只订「扫描状态」这一件:别的通知(下载进度、缓存淘汰)与这张纸无关。
    final status = context.select<AppState, ScanStatus?>((s) => s.scanStatus);
    final scanning = status?.scanning ?? false;

    // **按钮夹在滚动区外面**:内容(三行状态 + 说明 + 可能出现的错误)在窄屏 /
    // 大字号下会比纸高,那时该滚的是上面那几行 —— 而这颗按钮是这张纸唯一的
    // 动作,不能跟着一起被切掉。
    return NordicScrim(
      onTap: () => Navigator.of(context).pop(),
      child: NordicSheet(
        title: '曲库扫描',
        subtitle: '服务器端的活',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3),
                      child: Column(
                        children: [
                          _ScanRow(
                            label: '状态',
                            value: status == null
                                ? '问不到'
                                : (status.scanning
                                    ? '正在扫描 · 已扫 ${status.count ?? 0} 首'
                                    : '未在扫描'),
                          ),
                          _ScanRow(
                            label: '上次扫描',
                            value: status?.lastScan == null
                                ? '服务器没说过'
                                : formatClock(status!.lastScan!),
                          ),
                          if (status?.count != null && !scanning)
                            _ScanRow(label: '曲库', value: '${status!.count} 首'),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s4),
                      child: Text(
                        '扫描是**服务器在扫它自己的磁盘**：扫的时候这边照旧听、'
                        '照旧翻库，扫完之后音乐库会自己刷新一次。'
                        '只有管理员账号能发起扫描。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: t.fg3, height: 1.6),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s3),
                        child: Text(
                          _error!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: t.warn, height: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NordicSpace.s5, 0, NordicSpace.s5, NordicSpace.s2),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: scanning
                      ? '正在扫描…'
                      : (_starting ? '正在发起…' : '开始扫描'),
                  icon: Icons.refresh,
                  onPressed: (scanning || _starting) ? null : _start,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 纸里的一行「名目 / 值」—— 与歌曲信息那张纸同一副读法。
class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.nordic;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: t.fg3),
          ),
          const SizedBox(width: NordicSpace.s4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}