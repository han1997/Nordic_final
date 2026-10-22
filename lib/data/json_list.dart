/// 「服务器给的那个数组」→ `List<Map<String, dynamic>>`。
///
/// 协议里的数组元素偶尔不是对象(有的实现会往 `song[]` 里塞 null / 字符串),
/// 而下游的映射函数一律假设是对象 —— 这一处把不是对象的筛掉:坏元素只少了
/// 那一行,不至于让整次响应报错。
///
/// **只筛「不是对象」这一种。** 这个函数是通用的:它既读实体数组(专辑 /
/// 歌曲 / 艺人 / 歌单,那些都该有 `id`),也读**不是实体**的数组(歌词的
/// `line[]`、`genres[]`、`artists[]` 里那个嵌套数组) —— 后者本来就没有 id。
/// 所以「缺 id 的要不要丢」是**实体那一层**的判断(见
/// `SubsonicMapper.hasIdentity` 与 `entities`),不能塞进这里:一刀切会把
/// 歌词行整批筛掉,而那个错不响(歌词页只是空着)。
///
/// **为什么单开一个文件**:载荷 / 映射 / 仓库 / 库快照四处原先各写了一份同样的
/// 实现(名字还各不相同),口径要改就得记得改四遍 —— 而这是「怎么读服务器给的
/// 数组」这一件事,只该有一处说法。
List<Map<String, dynamic>> mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}
