import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/app.dart';
import 'package:nordic/playback/audio_handler.dart';
import 'package:nordic/playback/playback_controller.dart';
import 'package:nordic/playback/quality.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('播着播着断了 —— 屏幕上当场多一句话', (tester) async {
    final playable = _EchoPlayback();
    addTearDown(playable.dispose);
    final key = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      ChangeNotifierProvider<PlaybackController>.value(
        value: playable,
        child: MaterialApp(
          scaffoldMessengerKey: key,
          home: PlaybackInterruptionEcho(
            messengerKey: key,
            child: const Scaffold(body: Center(child: Text('随便哪一屏'))),
          ),
        ),
      ),
    );
    await tester.pump();

    // 断流之前:一句话都没有。
    expect(find.byType(SnackBar), findsNothing);

    playable.interruption.value = '线路断了';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SnackBar), findsOneWidget,
        reason: '播着播着断了，当下就得说一句 —— 原先要等下次进播放页才看得见');
    expect(find.textContaining('播放中断了'), findsOneWidget);
    expect(find.textContaining('线路断了'), findsOneWidget,
        reason: '为什么断的也要说，只说「播放中断了」等于让用户自己猜');
  });

  testWidgets('复位那一下不弹 —— null 是「上一句说完了」不是「又断了一次」', (tester) async {
    final playable = _EchoPlayback();
    addTearDown(playable.dispose);
    final key = GlobalKey<ScaffoldMessengerState>();

    await tester.pumpWidget(
      ChangeNotifierProvider<PlaybackController>.value(
        value: playable,
        child: MaterialApp(
          scaffoldMessengerKey: key,
          home: PlaybackInterruptionEcho(
            messengerKey: key,
            child: const Scaffold(body: Center(child: Text('随便哪一屏'))),
          ),
        ),
      ),
    );
    await tester.pump();

    playable.interruption.value = '线路断了';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);

    playable.interruption.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SnackBar), findsOneWidget,
        reason: '复位不该再弹一条，也不该把刚说的那句撤掉');
  });
}

class _EchoPlayback extends PlaybackController {
  _EchoPlayback() : super(NordicAudioHandler(() => null, QualityController()));

  @override
  PlaybackState get state => const PlaybackState();
}
