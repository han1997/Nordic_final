import 'package:nordic/data/server_config.dart';

/// 内存里的密钥库 —— 测试用的替身。
///
/// `CredentialStore` 底下是 `FlutterSecureStorage`,在 `flutter_test` 里没有
/// 通道实现,碰一下就抛 `MissingPluginException`。而这里要钉的是「密码有没有
/// 被存下、存的是不是那一个」,不是「安卓的 keystore 能不能用」—— 换成内存实现
/// 读起来反而更对。
///
/// **生产代码零改动**:`CredentialStore` 的构造函数是公开的,子类化就够
/// (`sync_screen_test.dart` 与 `config_export_sheet_test.dart` 都用它)。
class MemoryCredentials extends CredentialStore {
  MemoryCredentials([this._password]);

  String? _password;

  @override
  Future<void> savePassword(String password) async => _password = password;

  @override
  Future<String?> readPassword() async => _password;

  @override
  Future<void> clear() async => _password = null;
}