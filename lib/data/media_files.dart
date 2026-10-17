/// 音频文件落到磁盘上时的命名规则 —— 下载([DownloadStore])与缓存
/// ([MediaCache])**共用一份**。
///
/// 两处做的是同一件事:把服务器给的曲目信息变成文件名。规则分开写迟早会漏
/// 一处 —— 而这里漏一处的代价不是「名字不好看」:曲目名里一个 `/` 就能把文件
/// 写到别的目录去,一个没洗过的后缀就能让文件名带上额外的路径段。
library;

/// 洗掉文件名里不能出现的字符。
///
/// Windows 上非法的那几个(`\ / : * ? " < > |` 与控制字符)一并挡掉 ——
/// 同一份代码要能在桌面上跑。空白折叠成一个空格,首尾不留空;
/// 洗完是空的就给 [fallback](曲目名叫「...」的时候总得有个名字)。
///
/// 超长截断:最长 60 个字符,给路径留出余量(整个路径在 Android 上也有限制)。
String sanitizeFileName(
  String raw, {
  int maxLength = 60,
  String fallback = '未命名',
}) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return fallback;
  return cleaned.length <= maxLength ? cleaned : cleaned.substring(0, maxLength);
}

/// 后缀只留字母数字。
///
/// 取值来自服务器,但它通向文件名 —— 一个斜杠或者一个点就能把文件指到
/// 别的地方去。**不知道格式就返回空串**:安一个错的(比如把 aac 写成 mp3)
/// 会让解码器按错的格式去解,交给它自己嗅探反而稳。
String audioExtensionOf(String? raw) {
  if (raw == null) return '';
  final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  // 真实容器后缀没有超过 8 个字符的;更长的多半是被污染过的东西。
  return cleaned.length <= 8 ? cleaned : '';
}
