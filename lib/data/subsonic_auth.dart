import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Subsonic 的鉴权参数。
///
/// 协议要求每次请求带 `u`(用户名)、`t`(token)、`s`(salt)、`v`(协议版本)、`c`(客户端名)。
/// **token 不是静态密钥,而是 `md5(密码 + salt)` 当场算出来的** ——
/// 这正是密码必须以可逆形式存在本机的原因(参见 [CredentialStore] 的说明)。
class SubsonicAuth {
  SubsonicAuth({required this.username, required this.password});

  final String username;
  final String password;

  /// 协议版本。1.16.1 是 Navidrome 与主流 Subsonic 实现都认的稳定档位;
  /// OpenSubsonic 的扩展端点(如 `getLyricsBySongId`)另外用 `openSubsonic=true` 探测。
  static const apiVersion = '1.16.1';

  /// 客户端标识。服务器会把它记进 play 记录,便于区分来源。
  static const clientName = 'nordic';

  /// 每次请求新生成 salt —— 协议就是这么设计的,重复用会削弱
  /// 「密码不过网」的意义。
  static final _random = Random.secure();

  static String newSalt([int bytes = 8]) {
    final codes = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return codes.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  }

  /// `md5(密码 + salt)` 的小写十六进制。抽成静态是为了让测试能钉住这条算法 ——
  /// bak 项目里同样口径的实现已经和真服务器对过,换写法会直接连不上。
  static String tokenFor(String password, String salt) =>
      md5.convert(utf8.encode('$password$salt')).toString();

  /// 附加到每个请求上的鉴权 query 参数。
  Map<String, String> queryParams({String? salt}) {
    final s = salt ?? newSalt();
    return {
      'u': username,
      't': tokenFor(password, s),
      's': s,
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }
}