import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/config_transfer.dart';
import 'package:nordic/data/server_config.dart';
import 'package:nordic/data/server_route.dart';

/// 「扫码同步」的载荷编解码 —— 纯 Dart,裸 test() 就够。
///
/// 钉住的是**那几个决定**,不是「代码跑得动」:
///   - 载荷里**没有**哪几样(`ServerConfig.id` / `lastScannedAt` / 线路 id)——
///     它们是原来那台设备的本地东西,带过去是对目标机撒谎;
///   - 密码**默认整个键都不在**,开关开了才写;
///   - 每一种读不出来的情况都落到一个**枚举**上(不是一句文案 —— 文案会改);
///   - 大小还压得住二维码(那张体积表是设计的一部分,别让它悄悄涨上去)。
void main() {
  ServerRoute route(
    String id,
    String url, {
    String name = '线路',
    RouteTag tag = RouteTag.lan,
    bool selected = false,
  }) =>
      ServerRoute(id: id, name: name, url: url, tag: tag, selected: selected);

  /// 直接编一段**任意 JSON** 的载荷 —— 有些坏情况 `encode` 造不出来
  /// (它不会写下认不出的 kind,也不会省掉 v)。
  String payloadOf(Object? json) {
    final code = base64Url.encode(utf8.encode(jsonEncode(json)));
    return ConfigTransfer.prefix + code.replaceAll('=', '');
  }

  TransferredServer okOf(String raw) {
    final result = ConfigTransfer.decode(raw);
    expect(result, isA<TransferOk>(), reason: '这段本该能读出来');
    return (result as TransferOk).server;
  }

  TransferError errOf(String raw) {
    final result = ConfigTransfer.decode(raw);
    expect(result, isA<TransferFailed>(), reason: '这段本该读不出来');
    return (result as TransferFailed).reason;
  }

  String encodeThree() => ConfigTransfer.encode(
        kind: ServerKind.navidrome,
        name: '客厅 Navidrome',
        username: 'demo',
        routes: [
          route('lan', 'http://192.168.10.4:4533', name: '局域网直连',
              tag: RouteTag.lan, selected: true),
          route('wan', 'https://music.example.com', name: '公网', tag: RouteTag.wan),
          route('relay', 'http://relay.example.net:4533',
              name: '中继', tag: RouteTag.relay),
        ],
      );

  group('往返', () {
    test('类型 / 名字 / 账号 / 线路原样回来', () {
      final server = okOf(encodeThree());

      expect(server.kind, ServerKind.navidrome);
      expect(server.name, '客厅 Navidrome');
      expect(server.username, 'demo');
      expect(server.routes.map((r) => r.url), [
        'http://192.168.10.4:4533',
        'https://music.example.com',
        'http://relay.example.net:4533',
      ]);
      expect(server.routes.map((r) => r.name), ['局域网直连', '公网', '中继']);
      expect(server.routes.map((r) => r.tag),
          [RouteTag.lan, RouteTag.wan, RouteTag.relay]);
      expect(server.droppedRoutes, 0);
    });

    test('线路顺序照原样 —— 第一条就是表单里那条', () {
      final server = okOf(encodeThree());
      expect(server.routes.first.url, 'http://192.168.10.4:4533');
    });

    test('锁定状态跟着走，且仍然只有一条锁着', () {
      final server = okOf(encodeThree());
      expect(server.routes.map((r) => r.selected), [true, false, false]);
    });

    test('载荷里同时锁了两条时只认第一条', () {
      final server = okOf(payloadOf({
        'v': 1,
        'kind': 'navidrome',
        'name': 'n',
        'user': 'u',
        'routes': [
          {'n': 'a', 'u': 'http://a.local:1', 't': 'lan', 's': true},
          {'n': 'b', 'u': 'http://b.local:1', 't': 'wan', 's': true},
        ],
      }));
      // 单选语义:两条都锁着会让 activeRoute 取哪一条不确定。
      expect(server.routes.map((r) => r.selected), [true, false]);
    });

    test('中文名字与中文线路名过得去 UTF-8', () {
      final server = okOf(ConfigTransfer.encode(
        kind: ServerKind.fnos,
        name: '书房 飞牛',
        username: '阿涵',
        routes: [route('a', 'http://192.168.1.9:4533', name: '客厅那台')],
      ));
      expect(server.name, '书房 飞牛');
      expect(server.username, '阿涵');
      expect(server.routes.single.name, '客厅那台');
    });

    test('线路名空着时从地址推一个', () {
      final server = okOf(payloadOf({
        'v': 1,
        'kind': 'navidrome',
        'name': 'n',
        'user': 'u',
        'routes': [{'n': '', 'u': 'http://192.168.10.4:4533'}],
      }));
      expect(server.routes.single.name, '局域网直连');
    });

    test('显示名空着时退回类型名', () {
      final server = okOf(payloadOf({
        'v': 1,
        'kind': 'fnos',
        'name': '   ',
        'user': 'u',
        'routes': [{'u': 'http://nas.local:4533'}],
      }));
      expect(server.name, ServerKind.fnos.label);
    });
  });

  group('排除掉的那几样', () {
    test('线路 id 是**本机重发**的，不带原来那台的键', () {
      final server = okOf(encodeThree());
      expect(server.routes.map((r) => r.id), ['route-1', 'route-2', 'route-3']);
      // 原配置里那三个 id 一个都不该出现。
      expect(server.routes.map((r) => r.id), isNot(contains('lan')));
    });

    test('落成 ServerConfig 时 id 由调用方给，lastScannedAt 是空的', () {
      final config = okOf(encodeThree()).toServerConfig(id: 'server-7');
      expect(config.id, 'server-7');
      expect(config.lastScannedAt, isNull);
      expect(config.routes.length, 3);
    });

    test('载荷文本里读不出 id / lastScannedAt 这些字样', () {
      final body = encodeThree().substring(ConfigTransfer.prefix.length);
      final json = utf8.decode(base64Url.decode(
          body.padRight((body.length + 3) ~/ 4 * 4, '=')));
      expect(json, isNot(contains('lastScannedAt')));
      expect(json, isNot(contains('"id"')));
    });
  });

  group('密码', () {
    test('默认**整个键都不在** —— 不是写成 null', () {
      final code = encodeThree();
      final body = code.substring(ConfigTransfer.prefix.length);
      final json = utf8.decode(base64Url.decode(
          body.padRight((body.length + 3) ~/ 4 * 4, '=')));
      expect(json, isNot(contains('pw')));

      final server = okOf(code);
      expect(server.carriedPassword, isFalse);
      expect(server.password, isNull);
    });

    test('开关打开之后才带上', () {
      final server = okOf(ConfigTransfer.encode(
        kind: ServerKind.navidrome,
        name: 'n',
        username: 'u',
        routes: [route('a', 'http://nas.local:4533')],
        password: 's3cret',
      ));
      expect(server.carriedPassword, isTrue);
      expect(server.password, 's3cret');
    });

    test('空字符串不算带了密码', () {
      final server = okOf(ConfigTransfer.encode(
        kind: ServerKind.navidrome,
        name: 'n',
        username: 'u',
        routes: [route('a', 'http://nas.local:4533')],
        password: '',
      ));
      expect(server.carriedPassword, isFalse);
    });
  });

  group('读不出来时各有一句话', () {
    test('空的', () => expect(errOf('   '), TransferError.empty));

    test('长到不像配置的', () {
      expect(errOf('nordic://config/1/${'A' * 9000}'), TransferError.tooLong);
    });

    test('根本不是我们的协议', () {
      expect(errOf('https://example.com/qr'), TransferError.wrongScheme);
      expect(errOf('随便一段字'), TransferError.wrongScheme);
    });

    test('认得协议、版本不对', () {
      expect(errOf('nordic://config/2/AAAA'), TransferError.unsupportedVersion);
      expect(errOf('nordic://other/1/AAAA'), TransferError.unsupportedVersion);
    });

    test('版本写在 JSON 里对不上时也认出来', () {
      expect(
        errOf(payloadOf({'v': 9, 'user': 'u', 'kind': 'navidrome'})),
        TransferError.unsupportedVersion,
      );
    });

    test('编码坏了', () {
      expect(errOf('${ConfigTransfer.prefix}!!!!'), TransferError.badEncoding);
    });

    test('编码没问题、里面不是 JSON', () {
      expect(
        errOf('${ConfigTransfer.prefix}${base64Url.encode(utf8.encode('hello'))}'),
        TransferError.badJson,
      );
    });

    test('JSON 不是个对象', () {
      expect(errOf(payloadOf(['a', 'b'])), TransferError.badJson);
    });

    test('缺账号', () {
      expect(
        errOf(payloadOf({
          'v': 1,
          'kind': 'navidrome',
          'name': 'n',
          'user': '  ',
          'routes': [{'u': 'http://nas.local:4533'}],
        })),
        TransferError.missingFields,
      );
    });

    // 关键的一条:**不退回 navidrome**。这份载荷是从另一台设备来的,
    // 静默按某一档连上去,错误要到连不上库的时候才显形。
    test('接入类型认不出就拒掉，不退回默认那档', () {
      expect(
        errOf(payloadOf({
          'v': 1,
          'kind': 'plex',
          'name': 'n',
          'user': 'u',
          'routes': [{'u': 'http://nas.local:4533'}],
        })),
        TransferError.unknownKind,
      );
    });

    test('一条可用地址都没有', () {
      expect(
        errOf(payloadOf({
          'v': 1,
          'kind': 'navidrome',
          'name': 'n',
          'user': 'u',
          'routes': const [],
        })),
        TransferError.noRoute,
      );
      expect(
        errOf(payloadOf({
          'v': 1,
          'kind': 'navidrome',
          'name': 'n',
          'user': 'u',
          'routes': [
            {'u': 'ftp://files.local'},
            {'u': ''},
            {'u': null},
          ],
        })),
        TransferError.noRoute,
      );
    });

    test('每条错误都有一句给用户看的话', () {
      for (final reason in TransferError.values) {
        expect(reason.message.trim(), isNotEmpty, reason: reason.name);
      }
    });
  });

  group('坏掉的那几条线路', () {
    test('坏条目丢掉、其余照读，并记下丢了几个', () {
      final server = okOf(payloadOf({
        'v': 1,
        'kind': 'navidrome',
        'name': 'n',
        'user': 'u',
        'routes': [
          {'n': '好的', 'u': 'http://192.168.10.4:4533'},
          {'n': 'ftp 的', 'u': 'ftp://files.local'},
          '连对象都不是',
          {'n': '也好', 'u': 'nas.local'},
        ],
      }));
      expect(server.routes.length, 2);
      expect(server.droppedRoutes, 2);
      expect(server.routes.last.url, 'http://nas.local');
    });
  });

  group('那串文本本身', () {
    test('以协议头开头、不含 =', () {
      final code = encodeThree();
      expect(code, startsWith(ConfigTransfer.prefix));
      expect(code, isNot(contains('=')));
      expect(code, isNot(contains(' ')));
    });

    test('带 = 的版本（手工粘来的）照样读得出来', () {
      final code = encodeThree();
      final body = code.substring(ConfigTransfer.prefix.length);
      final padded = body.padRight((body.length + 3) ~/ 4 * 4, '=');
      expect(okOf(ConfigTransfer.prefix + padded).routes.length, 3);
    });

    test('两头空白不算数', () {
      expect(okOf('  ${encodeThree()}\n').username, 'demo');
    });

    // 这串东西的密度直接决定二维码要多少模块(4 条长主机名大约是 81×81)。
    // 谁哪天把键写长了,这条先响。
    test('最坏的一份还压在二维码扛得住的范围内', () {
      final code = ConfigTransfer.encode(
        kind: ServerKind.subsonic,
        name: '书房里的那台音乐服务器',
        username: 'han1997',
        routes: [
          route('a', 'https://music-library.example.com:4533', name: '公网直连'),
          route('b', 'http://192.168.10.4:4533', name: '局域网直连'),
          route('c', 'http://relay-node-3.example.net:4533', name: '中继三号'),
          route('d', 'https://cdn.example.org/navidrome', name: '备份线路'),
        ],
        password: 'a-really-long-password',
      );
      expect(code.length, lessThan(800));
    });
  });
}