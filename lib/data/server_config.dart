import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subsonic_auth.dart';
import 'subsonic_client.dart';

/// 一个已配置的服务器。
class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.username,
    required this.routes,
    this.lastScannedAt,
  });

  final String id;
  final String name;
  final ServerKind kind;
  final String username;

  /// 一个账号,多个地址。至少一条。
  final List<ServerRoute> routes;

  final DateTime? lastScannedAt;

  ServerConfig copyWith({
    String? name,
    ServerKind? kind,
    String? username,
    List<ServerRoute>? routes,
    DateTime? lastScannedAt,
  }) =>
      ServerConfig(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        username: username ?? this.username,
        routes: routes ?? this.routes,
        lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      );

  /// 落盘时不带密码 —— 密码单独走 [CredentialStore] 的加密存储。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'username': username,
        'routes': routes.map((r) => r.toJson()).toList(),
        'lastScannedAt': lastScannedAt?.toIso8601String(),
      };

  static ServerConfig fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: ServerKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ServerKind.navidrome,
        ),
        username: json['username'] as String,
        routes: [
          for (final r in (json['routes'] as List? ?? const []))
            if (r is Map) ServerRoute.fromJson(r.cast<String, dynamic>()),
        ],
        lastScannedAt: json['lastScannedAt'] is String
            ? DateTime.tryParse(json['lastScannedAt'] as String)
            : null,
      );
}

/// 接入类型 —— 原型「添加服务器」页的三档。
///
/// 三者都讲 Subsonic 协议,差异在能力边界:飞牛音乐基于社区逆向,
/// 官方无公开 API,可用性随系统版本变化(原型里那句提示照搬过来)。
enum ServerKind {
  navidrome('Navidrome', 'ND', '开源音乐服务器,Subsonic 兼容'),
  subsonic('Subsonic / OpenSubsonic', 'SU', 'Airsonic、Gonic、Ampache 等'),
  fnos('飞牛音乐', 'FN', 'fnOS 自带的音乐服务');

  const ServerKind(this.label, this.badge, this.description);

  final String label;

  /// 卡片上的两字徽标。
  final String badge;

  final String description;
}

/// 凭据存储。
///
/// **为什么密码必须可逆保存**:Subsonic 的 token 是 `md5(密码 + 每次新生成的 salt)`,
/// 每次请求现算,所以本地必须持有明文密码本身,不能只存哈希。
/// 折中是把它交给系统密钥库(Android Keystore / iOS Keychain),
/// 由平台加密落盘 —— 应用沙箱之外拿不到明文,备份里也不是明文。
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _passwordKey = 'nordic.server.password';

  Future<void> savePassword(String password) =>
      _storage.write(key: _passwordKey, value: password);

  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  Future<void> clear() => _storage.delete(key: _passwordKey);

  Future<bool> get hasPassword async => (await readPassword()) != null;
}

/// 服务器配置与界面偏好的持久化。
///
/// 配置(地址 / 用户名 / 线路)放 SharedPreferences —— 不是机密;
/// 密码走 [CredentialStore] 的加密存储。
class ConfigStore {
  ConfigStore(this._prefs);

  final SharedPreferences _prefs;

  static const _serverKey = 'nordic.server.config';

  static Future<ConfigStore> open() async =>
      ConfigStore(await SharedPreferences.getInstance());

  ServerConfig? loadServer() {
    final raw = _prefs.getString(_serverKey);
    if (raw == null) return null;
    try {
      return ServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 存的东西坏了(手改过 / 版本迁移),当作没配过 ——
      // 让用户重填比让应用每次启动都崩要好。
      return null;
    }
  }

  Future<void> saveServer(ServerConfig config) =>
      _prefs.setString(_serverKey, jsonEncode(config.toJson()));

  Future<void> clearServer() => _prefs.remove(_serverKey);

  // ---- 界面偏好 ----

  static const _themeKey = 'nordic.pref.theme';
  static const _qualityKey = 'nordic.pref.quality';
  static const _autoRouteKey = 'nordic.pref.autoRoute';
  static const _backgroundPlayKey = 'nordic.pref.backgroundPlay';
  static const _wifiOnlyKey = 'nordic.pref.wifiOnlyDownload';

  String? loadThemeMode() => _prefs.getString(_themeKey);

  Future<void> saveThemeMode(String mode) => _prefs.setString(_themeKey, mode);

  String? loadQuality() => _prefs.getString(_qualityKey);

  Future<void> saveQuality(String qualityId) =>
      _prefs.setString(_qualityKey, qualityId);

  /// 线路自动择优。关掉后每条线路要手动锁定(原型设置页的语义)。
  bool loadAutoRoute() => _prefs.getBool(_autoRouteKey) ?? true;

  Future<void> saveAutoRoute(bool value) => _prefs.setBool(_autoRouteKey, value);

  bool loadBackgroundPlay() => _prefs.getBool(_backgroundPlayKey) ?? true;

  Future<void> saveBackgroundPlay(bool value) =>
      _prefs.setBool(_backgroundPlayKey, value);

  bool loadWifiOnlyDownload() => _prefs.getBool(_wifiOnlyKey) ?? false;

  Future<void> saveWifiOnlyDownload(bool value) =>
      _prefs.setBool(_wifiOnlyKey, value);
}

/// 用已有配置拼一个可直接开工的客户端。
///
/// 放在这里而不是各调用点,是为了让「配置 → 鉴权 → 线路」这条接线只有一份,
/// 免得某处忘了把密码传进去,表现成一连串 40 错误。
SubsonicClient clientFor({
  required ServerConfig config,
  required String password,
}) {
  final auto = config.routes.where((r) => r.selected).firstOrNull;
  return SubsonicClient(
    auth: SubsonicAuth(username: config.username, password: password),
    routes: config.routes.isEmpty
        // 没线路时给一条占位,让界面能显示「未配置」而不是抛异常。
        ? const [ServerRoute(id: 'unset', name: '未配置', url: '')]
        : [
            ...(auto == null ? [] : [auto]),
            ...config.routes.where((r) => r.id != auto?.id),
          ],
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}