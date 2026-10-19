import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../theme/tokens.dart';

/// 把一串文本画成二维码 —— 「导出配置」那张纸上的那块方形。
///
/// **编码用 `qr`(纯 Dart 的编码器本身),绘制这几十行是自己写的**:静区、纠错
/// 等级、配色于是全在自己手里,不必跟某个现成控件的样式 API 较劲 —— 仓库本来
/// 就自己画玻璃与氛围背景。而 `qr` 只依赖 `meta`,那是本仓库已有的直接依赖,
/// 所以这一项**没有引入任何新的传递依赖**(也不必像 `mobile_scanner` 那样
/// 分平台:它在所有目标上都是同一份 Dart 代码)。
///
/// **二维码不跟主题走。** 扫描器要的是深码浅底,而本应用的主场是深色
/// (`--bg` 近黑):拿 `t.fg` 来画会得到一张白码黑底,大多数扫描器直接读不出来。
/// 这是全应用唯一一处**故意与主题反过来的地方** —— 外面那一圈标题 / 开关 /
/// 按钮照旧全用 token,只有这块方形底是写死的白与黑。
class QrView extends StatefulWidget {
  const QrView({super.key, required this.data, this.size = 280});

  final String data;

  /// 方形码面(不含四周静区)的边长。
  final double size;

  /// 静区 —— 二维码规范里那 4 个模块宽的留白,**扫描器认码靠它,别省**。
  /// 按 280px 的码面算,16px 约等于 4.6 个模块(4 条线路的载荷约 81 个模块)。
  static const quietZone = NordicSpace.s4;

  @override
  State<QrView> createState() => _QrViewState();
}

class _QrViewState extends State<QrView> {
  /// 编好的矩阵与它对应的那串载荷。
  ///
  /// 编码是**真有活**要干的(纠错码 + 建矩阵,几百个模块),而它原先在 `build`
  /// 里现算:父级每一次重建(切「包含密码」开关、软键盘 inset 变化)都会把同一串
  /// 载荷重编一遍。按载荷记一份,变了才重编。
  QrImage? _matrix;

  @override
  void initState() {
    super.initState();
    _matrix = _matrixOf(widget.data);
  }

  @override
  void didUpdateWidget(QrView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _matrix = _matrixOf(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    final matrix = _matrix;

    return Container(
      padding: const EdgeInsets.all(QrView.quietZone),
      decoration: BoxDecoration(
        // 写死的白与黑,理由见类文档。
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(NordicRadius.lg),
      ),
      child: matrix == null
          // 一段长到编不成二维码的载荷 —— 理论上到不了(载荷有 `maxLength`
          // 粗筛),但真到的时候要说清楚,而不是让 paint 里抛出去把这一屏打崩。
          ? const SizedBox(
              width: 240,
              child: Text(
                '这段配置太长，画不成一张二维码 —— 用下面那颗「复制文本」带过去。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF3A3A44), fontSize: 13),
              ),
            )
          : CustomPaint(
              size: Size.square(widget.size),
              painter: _QrMatrixPainter(matrix),
            ),
    );
  }

  /// 编一张码的模块矩阵。编不出来(太长)时返回 null —— **在这里编而不是在
  /// `paint` 里编**:抛在 paint 里发生在下一帧的绘制过程中,界面上只会留下
  /// 一屏红字,而这里能当场换成一句人话。
  static QrImage? _matrixOf(String data) {
    try {
      return QrImage(QrCode(
        payload: QrPayload.fromString(data),
        // **显式给 M,不用别的档**:屏幕→摄像头之间没有损伤要恢复,用不着
        // 25% 的纠错余量;而档位高一档,4 条长主机名那份载荷会从 81 个模块
        // 涨到 90 上下,手机上每个模块就不到 3 个像素了。
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ));
    } catch (_) {
      return null;
    }
  }
}

class _QrMatrixPainter extends CustomPainter {
  _QrMatrixPainter(this.matrix);

  final QrImage matrix;

  @override
  void paint(Canvas canvas, Size size) {
    final module = size.shortestSide / matrix.moduleCount;
    final paint = Paint()..color = const Color(0xFF000000);
    // 每块多画半像素:模块宽度除不尽时相邻两块之间会露出头发丝似的白缝。
    // 深色画在深色上,多出来这半点没有任何副作用。
    final side = module + 0.5;

    for (var row = 0; row < matrix.moduleCount; row++) {
      for (var col = 0; col < matrix.moduleCount; col++) {
        if (!matrix.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * module, row * module, side, side),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrMatrixPainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}