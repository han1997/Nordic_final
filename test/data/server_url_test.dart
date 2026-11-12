import 'package:flutter_test/flutter_test.dart';
import 'package:nordic/data/server_route.dart';
import 'package:nordic/data/server_url.dart';

/// 地址规范化与线路命名 —— 从两个界面里抽出来的那一份。
///
/// 钉两件事:**原来那两份认的地址现在照样认**(补 http、去尾斜杠、IPv6 与域名),
/// 以及**有一处刻意变了**:`ftp://x` 以前会被拼成 `http://ftp://x`(解析得出来、
/// 因此一路通过校验,但连不上),现在直接判不合法。
void main() {
  group('规范化', () {
    test('只填主机与端口时补上 http://', () {
      expect(normalizeServerUrl('192.168.10.4:4533'), 'http://192.168.10.4:4533');
    });

    test('尾斜杠去掉 —— 基址是要拼端点用的', () {
      expect(normalizeServerUrl('http://nas.local/'), 'http://nas.local');
      expect(normalizeServerUrl('https://music.example.com///'),
          'https://music.example.com');
    });

    test('https 原样保留，不会被降级成 http', () {
      expect(normalizeServerUrl('https://music.example.com'),
          'https://music.example.com');
    });

    test('两头空白不算数', () {
      expect(normalizeServerUrl('  nas.local:4533  '), 'http://nas.local:4533');
    });

    test('域名与 IPv6 都认', () {
      expect(normalizeServerUrl('music.example.com'), 'http://music.example.com');
      expect(normalizeServerUrl('http://[fd00::1]:4533'), 'http://[fd00::1]:4533');
    });

    test('空的不认', () {
      expect(normalizeServerUrl(''), isNull);
      expect(normalizeServerUrl('   '), isNull);
    });

    test('只有协议头、没有主机的不认', () {
      expect(normalizeServerUrl('http://'), isNull);
      expect(normalizeServerUrl('https://'), isNull);
    });

    // 这一条是**行为变了**的地方,如实钉住:老写法补出 http://ftp://x,
    // host 是 `ftp`,于是它能通过校验、能存进配置,等到连的时候才炸。
    test('别的协议不硬拼，直接判不合法', () {
      expect(normalizeServerUrl('ftp://files.example.com'), isNull);
      expect(normalizeServerUrl('smb://nas/share'), isNull);
      expect(normalizeServerUrl('file:///tmp/x'), isNull);
    });
  });

  group('线路命名与标记', () {
    test('私有网段标成「局域网直连」', () {
      expect(routeNameFor('http://192.168.10.4:4533'), '局域网直连');
      expect(routeNameFor('http://10.0.0.8:4533'), '局域网直连');
      expect(routeNameFor('http://172.16.5.2:4533'), '局域网直连');
      expect(routeNameFor('http://127.0.0.1:4533'), '局域网直连');
      expect(routeNameFor('http://localhost:4533'), '局域网直连');
      expect(tagFor('http://192.168.10.4:4533'), RouteTag.lan);
    });

    test('其余用主机名做线路名', () {
      expect(routeNameFor('https://music.example.com'), 'music.example.com');
      expect(tagFor('https://music.example.com'), RouteTag.wan);
    });

    test('私有网段的边界：172.15 与 172.32 都不算', () {
      expect(looksLocal('172.15.0.1'), isFalse);
      expect(looksLocal('172.32.0.1'), isFalse);
      expect(looksLocal('172.31.255.255'), isTrue);
      expect(looksLocal('172.16.0.0'), isTrue);
    });

    test('公网地址与认不出来的串都不算内网', () {
      expect(looksLocal('8.8.8.8'), isFalse);
      expect(looksLocal('music.example.com'), isFalse);
      expect(looksLocal('192.168.10'), isFalse);
      expect(looksLocal('192.168.10.4.5'), isFalse);
    });

    test('IPv6 内网地址也标成「局域网直连」', () {
      // 表单的提示写着认 IPv6;这些地址原先全被判成公网,
      // 于是路由名是一串地址、标记是「公网」—— 择优本身不受影响,
      // 但用户在设置页看到的分类是错的。
      expect(looksLocal('::1'), isTrue);
      expect(looksLocal('[fd00::1]'), isTrue);
      expect(looksLocal('fd00::1'), isTrue);
      expect(looksLocal('fe80::1%en0'), isTrue);
      expect(looksLocal('::ffff:192.168.10.4'), isTrue);
      expect(routeNameFor('http://[fd00::1]:4533'), '局域网直连');
      expect(tagFor('http://[fd00::1]:4533'), RouteTag.lan);
    });

    test('公网 IPv6 不算内网', () {
      expect(looksLocal('2001:db8::1'), isFalse);
      expect(looksLocal('2a00:1450:4001::1'), isFalse);
      expect(routeNameFor('http://[2001:db8::1]:4533'), '2001:db8::1');
    });

    test('Tailscale / 链路本地 IPv4 也归为本地', () {
      // 100.64/10 是 Tailscale 与运营商级 NAT 的段;169.254/16 是链路本地。
      expect(looksLocal('100.64.0.1'), isTrue);
      expect(looksLocal('100.127.255.254'), isTrue);
      expect(looksLocal('169.254.1.1'), isTrue);
      expect(looksLocal('100.128.0.1'), isFalse);
    });
  });
}