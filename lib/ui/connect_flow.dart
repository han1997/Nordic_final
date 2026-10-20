import '../data/server_config.dart';
import '../data/server_route.dart';
import '../state/app_state.dart';

/// 「写配置 → 拉一次库」—— 服务器表单与扫码同步走的是同一趟。
///
/// 收在一处,是因为这一趟上有一个**必须记住的坑**,两处各写一遍迟早有一处漏掉:
/// 整趟要接得住 `Error`。
///
/// `connect` 的第一步是把密码写进系统密钥库,而那是个裸 await —— 存不下时
/// (从局域网的 http 地址打开 Web 时,`flutter_secure_storage_web` 因为没有
/// `window.isSecureContext` 直接抛 `UnsupportedError`,**是 `Error` 不是
/// `Exception`**)异常会一路穿出去,调用点那句「把按钮停掉」于是永远走不到:
/// 按钮一直转圈,而配置一个字都没存。
///
/// 所以这里统一收口:失败翻成 [ConnectFailure],那句 [ConnectFailure.message]
/// 可以直接摆到界面上(服务器表单摆在表单里,扫码那张纸弹一条提示 —— 两处的
/// 说法不同,判断与措辞在这里是一份)。
///
/// 注意这是让它**响亮地失败**,不是让它能用:`http://` 局域网下系统密码存储
/// 本来就是关着的,凭据存不住 —— 放过去也会「连上、一刷新就没」,
/// 那比连不上更让人糊涂。
Future<void> connectAndLoad(
  AppState state, {
  required String name,
  required ServerKind kind,
  required String username,
  required String password,
  required List<ServerRoute> routes,
}) async {
  try {
    await state.connect(
      name: name,
      kind: kind,
      username: username,
      password: password,
      routes: routes,
    );
  } catch (e) {
    throw ConnectFailure(_failureText(e));
  }
  // 连上之后立刻拉一次库 —— 让用户当场看到「成没成」,而不是回去看一屏空白。
  // `loadLibrary` 自己吞掉错误(它把失败记进 `phase` / `error`),不会抛。
  await state.loadLibrary();
}

/// 连接失败。[message] 是**可以原样显示**的那一句。
class ConnectFailure implements Exception {
  const ConnectFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 连不上时给用户看的那句话。
///
/// [UnsupportedError] 单独认一下:从局域网的 http 地址打开 Web 时,
/// `flutter_secure_storage_web` 因为没有 `window.isSecureContext` 直接抛它,
/// 而那时**配置一个字都没存下来**。把它翻译成「该怎么改」,而不是把一行英文
/// 丢给用户。
String _failureText(Object e) => switch (e) {
      UnsupportedError() => '这个页面存不下密码 —— 用 https 或 localhost 打开再连。',
      _ => '连不上：$e',
    };
