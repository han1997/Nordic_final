/// 「服务器给的那个数组」→ `List<Map<String, dynamic>>`。
///
/// 协议里的数组元素偶尔不是对象(有的实现会往 `song[]` 里塞 null / 字符串),
/// 而下游的映射函数一律假设是对象 —— 这一处把不是对象的筛掉:坏元素只少了
/// 那一行,不至于让整次响应报错。
///
/// **为什么单开一个文件**:载荷 / 映射 / 仓库 / 库快照四处原先各写了一份同样的
/// 实现(名字还各不相同),口径要改就得记得改四遍 —— 而这是「怎么读服务器给的
/// 数组」这一件事,只该有一处说法。
List<Map<String, dynamic>> mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}