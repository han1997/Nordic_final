# 更新历史

Nordic 每一轮改动的原始记录。**从早到晚往下排**(第三轮在最上面,最新的一轮在最下面),
新的一轮**接在本文件末尾** —— 不要新开文件,也不要往 README 里加(README 的
「更新历史」一节只有一句指路)。

- **没有「第一轮」「第二轮」的条目,这不是漏了**:那两轮动的是「写法」(懒加载 /
  独立通道 / 分桶解码),内容已经并进 [docs/performance.md](performance.md)。第三轮的正文开头也留着
  这句说明(`前两轮动的是「写法」……`)。
- 每条记的是**为什么这么写**与**怎么坏的**,不是功能清单;要查「现在为什么是这个写法」,
  看 `docs/performance.md`。
- 改动若同时动了界面 / 交互,**先改 `prototype/`**(唯一的设计真相来源,见 README 的
  「界面改动一律先改原型」一节)。
- 每节末尾那条 `版本 X → Y` 与 `pubspec.yaml` 对应 —— **版本号的真值只在 `pubspec.yaml`**。

---
## 第三轮(2026-10-17):通知粒度与热路径上的盘操作

前两轮动的是「写法」(懒加载、独立通道、分桶解码);这一轮挖出来的是**通知的粒度**
与**热路径上的同步盘操作**。下面同样是「看着绕,别顺手改回去」:

- **只订阅真正读到的那几件,别 `watch` 整个 `AppState`**:`AppState` 把下载进度
  (最多每秒四次)与**音频缓存的淘汰**原样转发给全应用,于是「下载在跑」或
  「切了一首歌」会顺带把每一屏重建一遍。首页 / 音乐库 / 艺人 / 歌单 / 搜索改成
  `context.select` 挑自己读到的那几件(记录按**值**比较,那些事就到不了它们);
  根 `app.dart` 只 select 主题档位,两套 `ThemeData` 也缓存下来(`NordicTheme.light/dark`)
  —— `ColorScheme.fromSeed` 那趟调色计算不必每次通知重算两遍。设置页 / 下载页 /
  缓存面板**继续 watch**:它们真的在画进度与占用。守卫在
  `test/ui/rebuild_scope_test.dart`,一条规则两面都钉住 —— 进度跳动不许重建,
  真正订阅的东西变了必须重建。
- **`MediaCache` 只在数字真的变了的时候播报**:这一趟挂在**每次换歌**的淘汰上
  (`markPlaying` → `_pruneAfterTrackChange`),无条件播报等于让每次切歌都重建界面。
- **切歌那一下的淘汰不再每首都扫目录**:整个缓存目录 stat 一遍、几百份文件,是能
  感觉到的同步 I/O,而绝大多数换歌压根不会越过上限。真扫只在四种情况发生:缓存关着、
  **账面上已经超了上限**、有新文件可能落盘(`fileFor` 拿过空位)、距上次扫描超过
  15s(`MediaCache.rescanInterval`)。三条老约定一条没松:**淘汰仍然发生在换歌这一下**、
  LRU 仍按文件 mtime、正在听的那一份仍然跳过。`prune()` 本身仍是**全量**
  (启动 / 调额度 / 清空 / 测试都走它),而且一趟 `_scan` 同时产出占用与 mtime 序 ——
  原先淘汰要把整个目录 stat 两遍。
- **音乐库快照是合并写**:后台补齐每翻一页都要写一次,而每次都要把**整份**快照
  编码 + fsync,载荷越写越大 —— 合起来是平方级的活。`LibraryCache.write` 同一时刻
  只留一个写者,写着的时候又来的新版本**只留最新那份**;`settle()` 是「等它落定」,
  清缓存 / 删目录之前必须调(`clear()` 自己会等),否则 Windows 上就是
  「另一个程序正在使用此文件」—— 测试的 tearDown 也要等。`loadMoreSongs` 因此不再
  await 写盘,而 `loadLibrary` 继续 await:那条硬约定是「await 过之后读同一份缓存
  一定读得到刚取回的库」。
- **播放地址与缓存槽位都有备忘录**(`SubsonicRepository._rememberUri` /
  `MediaCache._slotFor`):一次 `setQueue` 会把**整条队列**的播放源都拼出来,上千首
  就是上千次「新生成盐 + MD5」外加两次 SHA-1,而其中绝大多数地址到播完也不会被请求
  一次。键里带**线路的 url**(不只是 id):地址被改掉而 id 不变时,只按 id 作键会把
  旧主机一直喂回去。未命中时照旧当场新生成盐 —— 协议口径没动,省的是那几千次哈希。
  下载索引那张封面表(coverArtId → 路径)同理**预先摊平**:它原先在**每个可见封面
  每次重建**时都遍历一遍所有下载记录。
- **冷启动不再数缓存目录**:`MediaCache.open(scan: false)` + 首帧之后
  `mediaCache.prime()`。那是整个缓存目录的 stat 遍历,而它要产出的三件东西
  (设置页的占用数字、清掉没主的半截文件、按上限淘汰)没有一件急着在首帧之前知道。
  **但 `loadCachedLibrary()` 仍然在 `runApp` 之前 await** ——「首屏就有东西」是这一屏
  的契约,改成先出空态是能被看见的。
- **播放页那张封面留旧帧**(`Cover(gaplessPlayback: true)`):换歌就是换图,新图解码
  要几十毫秒,不留旧帧的话每次切歌都先闪一下渐变兜底。原型是浏览器画的,本来就把上
  一张一直画到新图解码完 —— 这是向原型对齐,不是改设计。
- **坞那条玻璃隔了 `RepaintBoundary`**,切 tab 那 220ms 的淡入也隔了一层
  (`shell.dart`):透明度每变一帧就会把整屏重画一遍(包括首页那层 62px 的氛围模糊)。
  透明度、时长、缓动一个字没改,只是让它合成一张现成的层。
- **考虑过、这一轮没做**(写在案,免得下次重新发现一遍,也免得顺手「补」上):
  把快照编解码挪进 Isolate(载荷要跨 isolate 深拷贝一趟,省下的计算与那份拷贝
  成本相当,而重复编码已经被合并写消掉了)、给 `NetworkProbe` 加几秒 TTL(几毫秒的
  收益,换来「网络性质变陈旧」——「流量下不缓存」那道闸比它值钱)、给 `pingAll`
  加 TTL(它本来就并发且稀少,而陈旧排序会削弱「刚失败之后换线」这件事)、
  `songsByArtist` 并发翻页(要拿 500 一页去预取,小库上会**多发**请求,而它只在
  「下载整位艺人」时走)、`mergeSongPage` 跨页复用 id 集合(每页省的是 O(n),主项是
  它上面那次 O(n log n) 重排;动了还要冒「集合不同步 → 列表出重复行」的险)、
  下载队列那条面板改懒加载(那圈边框 + 分隔线是**一整块**面板,拆成每行一张卡片
  就是视觉改动,得先过 `prototype/`;而队列是几十条,不是几千条)。
  **服务器页 / 线路面板 / 添加线路三屏也仍是 `watch`**:它们是冷屏,重建的是一张
  静态表单,不值得为它冒「select 漏字段」的险。

## 第四轮(2026-10-17):进度跳转、歌词点句、放完不切歌

这一轮补的两件事都是**手动调进度**(拖进度条 / 点歌词),外加两处歌词页的老毛病。
第一条尤其值得记住 —— 它不是代码写法问题,是服务器给的东西**根本不能 seek**:

- **冷转码流不可 seek,所以「拖进度条」在远端曲目上要绕一圈**(`audio_handler` 的
  `_seekRemote`)。**实测**(Navidrome 0.64,`curl -D -`):
  - 一首**还没转码过**的曲子,`stream.view?maxBitRate=192&format=mp3` 回的是
    `Accept-Ranges: none` + `Transfer-Encoding: chunked` —— **没有长度、不支持 Range**。
    just_audio 的流式源于是交给平台一个「无长度、不可 seek」的源,`player.seek()`
    **静默不做**:用户看到的就是「拖了,进度纹丝不动」。
  - 同一个 URL 一旦服务器的转码结果落成静态文件,回的就是
    `206 + Content-Range + Accept-Ranges: bytes`(带全长)—— **那才是能 seek 的**。
    本机那一份(下载的 / 边听边缓存下完的)同理。
  - 所以 `seek` 分两步:正在放的是**本机那一份**(装载那一刻记下的,不是此刻磁盘上有没有
    —— 半路下完并不会换掉正在放的那条流)就直接交给平台;是远端流就**等本机那份下完**
    (局域网上一首 3 分钟的歌不到 5 秒,上限 8 秒),再整批重载到目标位置
    (`_reloadAt`,与切档位同一套)。等不到就退回平台的原生 seek —— 那一下在冷流上不作数,
    但**不会把歌从头重放**,也不假报进度。
  - **缓存关掉 + 远端曲目**因此仍然跳不动(没有「本机那一份」可等),这是已知边界:
    「不缓存」就是「每次从服务器拉一条流」,而那条流本来就没有长度。
- **松手之后拇指停在落点上**(`scrubberHold`):远端那一下 seek 要等几秒才落地,
  这期间位置还是旧的 —— 拇指立刻弹回去,看着就像白拖了。两条退出口都必要:
  位置追上了(`settle`)、或者等够久了(`giveUp`,那一下确实没生效)。
- **点某一句歌词 = 跳到那一段**(`seekTargetForLine`);**点行以外的空白仍是回封面**
  —— 与「点封面看歌词」互为来路的那一条不能丢。有时间轴就跳那一句的起点;没有时间轴
  只能按整首摊行反推,取**那一行的中段**而不是起点:高亮走的是
  `floor(比例 × 行数)`,起点在浮点误差下会退到上一行(点第三句、高亮停第二句)。
  两者互为逆运算,有测试钉着(`test/app_test.dart` 的「点一句 → 高亮必须落回同一行」)。
  跳不到的地方(没时间轴又不知道时长)返回 `null`,界面**不接这一下点击** ——
  跳不到的地方不该装成跳了。
- **歌词页的重建面收在「换行那两行」**:当前高亮行是一条 `ValueNotifier`,
  每行自己订它、自己判断要不要重建(`_LyricLine` 的 `_stateFor`)。原先换一行是
  **整屏 + 上百行**重建一次,而且正好落在自动滚动那 260ms 的动画里 ——
  真机反馈的「跳转动画一顿一顿」多半就是这几帧。写「已经排过滚动」的那本账
  (`_scheduledFor`)也一样:同一行只排一次,排重了就是好几个 `ensureVisible`
  同时开跑、互相打断。
- **放完一首后「自己重头再放一遍」是平台干的,护栏在应用这一侧**
  (`audio_handler` 的位置监察 + [didPlatformRewind])。真机抓到的现场(2026-10-17,
  多首队列、熄屏、蓝牙耳机):
  - 一首**还没转码过**的曲子(源是 `lockcache`,即那条 `Accept-Ranges: none` +
    chunked 的**无长度冷流**)放完时,平台**没有切下一首**,而是把**这一首**从 0 秒
    又放了一遍 —— 用户读到的就是「后台播放单曲循环,不会自动切下一首」。
  - 同一首换成**本机文件**(上一轮已经缓存下来的那一份)再放,末尾就老老实实停住了。
    **差别只在源上:有没有长度。** 另外**队列里只有一首**时末尾停住也是对的
    (没有下一首可切),别把那个当成同一个 bug。
  - Dart 侧全程**既没收到 `completed`、也没收到暂停**(逐条日志验证过),也就是说
    just_audio 里「正常那一支」(末尾 `seekToNextMediaItem`)压根没走到 —— 所以
    「在 `completed` 时补一刀」这种修法**不会生效**(那一支不触发)。
  - 于是自己在**位置流**上盯:位置没来由地往回跳一大截 = 平台又倒回开头了 → 自己
    `seekToNext()` 接着放(队列到头就按「这一轮放完」处理)。判据缺一不可
    (我们请求过的 seek、换歌、单曲循环、小抖动都不许误判),有测试钉着
    (`test/playback/playback_test.dart` 的「平台倒回开头」)。那条日志
    「`[Nordic] 平台倒回开头 → 自己切下一首 idx=…`」在真机上**正好在每个曲子末尾
    各出现一次、全程无误触发** —— 它现在是**常驻**的一行(`debugPrint`):
    冷流上这条护栏是**唯一在切歌的那一支**,下一轮真机还要靠它判断有没有响。
  - **平台内部为什么这么干仍是推测**(时长未知时那条末尾恢复分支?媒体期重新预备?),
    证据只到「它把这一首原地重放了」这一步 —— 文档里别把它升级成定论。
- **补强(2026-10-18)**:上面那条护栏补了四处,都是它自己的洞:
  - **门槛跟着曲长收**(`didPlatformRewind` 多了 `trackDuration`):写死「至少 10 秒」
    的话,间奏 / 试听片段这类十秒以内的曲子位置永远够不着门槛 —— 护栏在最需要它
    的那一类曲子上等于不存在,结果是一直单曲循环。
  - **暂停期间那一跳要留住**:位置监察原先先更新基线、再判断「没在播放就返回」,
    于是平台趁暂停倒回开头时那一下被记成了新基线,用户一按播放还是同一首从 0 开始
    —— 原症状换个场景原样复发。现在暂停期间两个基线都不动(下标也不动:否则暂停
    期间换过歌、基线跟着走,恢复播放时会读出「位置跳了但下标没变」的假阳性,
    反而多切一首)。
  - **队列走到头要真的按住播放器**:那一支原先只播报「放完了」,没碰播放器 ——
    平台还在重放,于是界面说放完、扬声器还在响。
  - **真切之前再核一遍**(下标没变 + 位置仍在开头附近):判据到动手之间隔着一次
    异步,平台在**有长度**的源上本来也会自己切,两边各切一刀就是**跳过一整首**。
  - 这条护栏现在有**处理器级**测试:测试里给 `NordicAudioHandler` 递一个可摆布的
    播放器(`_FakePlayer` 继承真 `AudioPlayer`,在测试环境里它是惰性的),
    摆布位置流就能钉住「切一次 / 换歌不算 / 拖动不算 / 单曲循环不算 / 暂停期间
    留住那一跳 / 不在开头附近就不动 / 队列尽头要按住」。只测纯函数是不够的 ——
    冷流上切歌全靠它。
- **考虑过、这一轮没做**:歌词列外面那层 `ShaderMask`(原型 `.lyrics` 的
  `mask-image`,边缘渐隐)在滚动时每帧都要重做一次**整块离屏合成**,是上面那条修完
  之后剩下的头号嫌疑。之所以没动它:渐隐是渐到**氛围背景**上(那层有光晕),换成
  「盖一条背景色渐变」就是改设计(得先过 `prototype/`),而这一轮已经能靠收窄重建面
  把工作量降下来。真机上要是还卡,下一刀在这里。

## 第五轮(2026-10-18):缓冲进度、缓存只留最高档、播放页多两处歌词入口

- **进度条多一段「已缓冲」**(`playback_controls.dart` 的 `_BufferedTrackShape`)。
  缓冲位置走**单独一条通道**(`PlaybackController.buffered`)—— 与 `position` 同一套
  待遇:它来自同一条 `playbackEventStream`,远端流上每秒动好几次,混进 `state` 等于
  让每一屏跟着重建(换歌时先归零,免得上一首的缓冲带在新歌上闪一帧)。画法上只重写
  `paint`:自己画底与缓冲带,再把父类的 inactive 调成透明后调它 —— 父类会把未加载段
  从拇指往右**整个重画一遍**,那一下正好把缓冲带擦掉。**手势仍归 `Slider`**,拖动 /
  松手落点 / 「时长未知不给拖」一个字没动。「画不画」的四条口径(时长未知 / 整首都在
  手边 / 没跑到播放位置前 / 越界夹回)全落在纯函数 `scrubberFrame` 里,于是能直接测;
  不画时连绘制路径都换回原来那条 —— 本机文件那一支与改动前一样。缓冲带用中性的
  `fill3`:强调色是「播到哪儿」的专用信号,让它同时管两件事,这两段就分不出来了。
- **同一首的缓存只留最高那一档**。缓存路径是「曲目 id + 档位」算出来的,于是同一首在
  192 与 原音 各留一份**永远并存**、额度白占。两边一起治:
  - **读**:本机已有**更高**一档的完整缓存时直接拿它播 —— 白拿的音质、不花流量,而且
    这一首压根不会再写第二份(`fileFor` 都轮不上)。候选按「从高到低」给
    (`quality.dart` 的 `betterTiersThan`),**只要完整的**(半截的播到一半会断)。
  - **写**:更高档那份**完整落到本机之后**,同曲更低档那几份让位(连 `.mime` 旁注
    一起删,占用账跟着降)。两条护栏缺一不可:**高码率那份还在下(只有 `.part`)** 时
    一个都不删 —— 网络一断两头落空;候选路径**纯算**、最多三下 stat、**不扫目录**
    (这一步挂在每次换歌上,不能变贵)。
  - 顺带把 `_localLoaded` 从「是不是本机文件」扩成「哪一份 / 哪一档 / 哪个路径」:
    本机拿更高档那份播时,照**所选档**去算缓存路径会指到一个**不存在**的文件 ——
    `_playingPath` 指错,淘汰时就可能删掉正在解码的那一份。
- **播放页的歌词入口从「封面那一块」扩成「整块封面区 + 歌名」**。原先封面四周那一大圈
  留白按下去什么也不发生,而这一屏除了控件就没有别的去处了。艺人 / 专辑那两条链接与
  进度条拖动照旧不受影响(原型那头的委托按 `closest()` 走,**最近的 `data-*` 先赢**)。

## 第六轮(2026-10-18):一次全面审查修下来的一批

这一轮不是新功能,是把整个 `lib/` 审了一遍之后修掉的「说了要做却没做」的事。
按影响从大到小,每一条都留了护栏用例:

- **改服务器设置不再毁掉线路表**。`_connect()` 一直按「首次配置」写:无条件提交一条
  硬编码的 `route-1`、还带 `selected: true`。于是多线路用户改一次密码,内外网那两条
  线路连同它们的 id 一起没了,活下来的那条还被强制锁定(自动择优也跟着停)。
  现在表单里那条地址**只替换第一条**(`mergeEditedRoute`),其余连 id 与锁定状态一起
  留着 —— 那些 id 是测速结果与「当前走哪条」的键。
- **「添加服务器」给的是空表单**(标题也写「添加服务器」),不再预填现有那台:
  预填会让人以为在改现有那台,而按下去确实会把它换掉(这一版一次只连一台,
  表单副标题里说清了)。原型 `screenAddServer` 就是空表单 + 先选接入类型。
- **「这一页不满」不等于「到底了」** —— 见上面翻页那一条(服务器卡 500 时会
  永远停在第一页)。
- **锁定线路之后不再自动切换**。判据不能只看那个全局开关:用户点锁定的时候
  「自动择优」多半还开着。原型与线路面板写的都是「手动锁定后不再自动切换」,
  现在按 `route.selected` 判(`SubsonicClient._candidateOrder`);换到别条的话,
  面板上「当前走 X」与实际发请求的那条会对不上。
- **更高档缓存**接管**与所选档自己有没有缓存无关**(见上一轮那条):早先只在
  `cached == null` 时才去找更高档,于是「先按均衡听过、后来原音也完整了」的曲子
  一直播着均衡那份,原音躺在盘上吃灰。
- **「盘上一份缓存都没有」这条快路不能只看账面数字**:账是上一次数目录的结果,
  `open(scan: false)` 的冷启动窗口里、以及刚删过几份低档之后,它会答「没缓存」——
  同一首于是又拉一遍网络、又写一份。判据加上「数完之后又可能有文件落盘」那一笔
  (`MediaCache._maybeEmpty`)。`markPlaying` 也不再给**下载来的**那一份刷 mtime:
  那是 `Nordic/Music` 里用户看得见的文件,不归缓存的 LRU 记账管。
- **通知栏封面**的判据收进 `_mediaItemFor` 一处:只有「拼播放源」那一处记得传本机
  封面,装载队列与自动切歌那几处不传 —— 同一首歌的封面时有时无(离线时是灰的)。
- **「点歌词没反应,还把歌词页关了」**:歌词行上下各 11px 的行距不在命中区
  (`deferToChild` 只命中文字本身),漏给了外层「点空白回封面」。补
  `HitTestBehavior.opaque`。另外用户翻过歌词之后,宽限一过会被拉回当前句 ——
  「让一次」不该变成「永远不回来」(长句子 / 间奏里几十秒不换行是常态)。
- **封面的「上缘内描边」从来没出现过**:`BoxShadow(offset: (0,1))` 没有 inset 语义,
  画在盒子外面又被不透明的封面盖住(`glass.dart` 早先踩过同一个坑并改成了贴边
  1px 实线,封面与艺人块这两处漏了)。
- **空态的下拉刷新是假的**:`RefreshIndicator` 底下那几条 scroll view 都没给
  `AlwaysScrollableScrollPhysics`,而「或下拉刷新」那句空态正好出现在**内容最短、
  根本不可滚**的时候。
- **收藏失败原先只是「心形自己弹回去」**:错误写进顶层 `_error`,而界面只在
  `phase == failed` 时读它 —— 收藏失败时库是好好的,那句话永远没人看;专辑页 /
  艺人页更糟,它们无条件弹「已收藏这张专辑」。现在 `toggle*Star` 返回成没成,
  四处调用点失败时如实说一句。
- **换服务器(不是移除)也要清上一台的残留**:收藏、歌词、测速数字、音频缓存跟着
  进新那台,曲目 id 撞上就是错的(心形显示成已收藏、歌词是另一首的;而缓存槽位
  只按「曲目 id + 档位」算 —— 撞上会**播错歌**)。判据是「类型 + 账号 + 第一条
  线路」变了,见 `_resetServerScopedState`。
- **`songsByArtist` 也要按空页判到底**:服务器卡 500 时,「下载这位艺人的全部歌曲」
  会默默少下后半截。`createPlaylist` 的服务端空响应兜底不再「同名取第一条」
  (同名歌单早就在时会取回旧的那条),而是认「新出现的那一条」。
- **「JSON 合法但没有 subsonic-response」不算线路不通**:它原先没带 statusCode,
  `isNetworkFailure` 为真 —— 客户端会把剩下的线路挨个试一遍(每条白等一次超时)。
- **磁盘歌词缓存读的过程中不许写**:先立「已读」再 await 的话,同时进来的第二个
  `lyricsFor` 会看到空的磁盘缓存,接着把空的写回去,整份缓存就没了。
- 其余:页脚那句「库里 N 首,M 首没取」在规模估计偏小时会印出「库里 0 首,还有 0 首
  没取」;歌单页曲子行上的 `repo!` 会在服务器被移除后崩掉整张列表;「取消」现在会把
  输入框还原(先前只翻 `_editing`,扔掉的半份改动还留着);详情缓存加了上限;
  「服务器给的数组怎么读」四处重抄的 helper 收成 `json_list.dart`;
  `PlayingBars` 暂停时不再跳回相位 0;首页只让播放卡跟着播放状态重建;
  封面的兜底配色改成惰性算(有真封面时那份白账挂在滚动热路径上)。
- **文案标点**:中文里的 `, ; ! ? : ( )` 一律全角(`tool/fullwidth_punct.py` 批量改,
  `test/ui/copy_punctuation_test.dart` 是守卫;句号 `.` 只报告不改 —— 文件名、URL、
  小数都长那样)。原型那边早就有 `punctcheck.js`,应用这边一直没跟上。
- **`_songsExhausted` / `_maybeEmpty` / `toggleRouteLock` / `mergeEditedRoute` /
  `json_list.dart`** 都是这一轮新立的口径,改它们之前先看各自的注释与用例。

## 第七轮(2026-10-18):循环 / 随机的记忆 + 一处对不齐的两个根

真机反馈两条,都不是新功能。**原型这一轮一行没改**:一条是纯行为,另一条是
**应用没跟上原型**(原型那两处 CSS 早就是目标形态)。

- **循环模式与随机播放记进盘里**。这两个开关原先只活在 `just_audio` 播放器上
  (`LoopMode` / `shuffleModeEnabled`),没有任何一处读写盘 —— 于是每次冷启动都悄悄
  回到「顺序播放 + 不随机」。现在与排序 / 转码档 / 缓存档同一套口径:存**枚举名字**
  (`nordic.pref.repeat` / `nordic.pref.shuffle`)而不是序号,免得以后往
  `PlaybackRepeat` 里插一态就把老档错位;认不出来的值当顺序播放(`repeatModeByName`,
  与 `QualityOption.byId` 同一条兜底 —— 一个坏值不该把启动搞崩)。落盘落在
  **用户动作**里(`cycleRepeat` / `toggleShuffle`)而不是流监听上:记的是意图值,
  回读要等一个微任务,连点两下会把上一态记进盘;而且是 `await` 平台那一头成功了才写,
  失败时不留脏值。冷启动由 `_restoreModes()` 摆回**播放器** —— 这两个是播放器级开关,
  装载队列从不碰它们,摆上去就生效;默认值不调,省一次平台往返也省一次没人要的
  通知栏播报。`PlaybackController` 的 `config` 是**可空**的:不传就是「不记忆」,
  测试与假播放层照旧。不进设置页、也不走 `AppState` —— 循环 / 随机不在设置页露脸,
  而 `AppState` 的偏好 setter 都要 `notifyListeners()`,给一个不进界面的值赔上
  整棵树的重建不划算。
- **「测速」按钮里那两个字贴顶**(真机上报的那一处)。根子在 `NordicGlass` 的 `Stack`
  取的是默认的 `topStart` + `loose`:未选中的胶囊是「定高 30 的盒子 + 一层玻璃底 +
  只有 ~15 高的内容」,内容被顶对齐;而选中态走不透明的定高 `Container`(撑满、
  天然居中)——于是点一下「测速」变「测速中」,字会往下跳一截。修法是在未选中分支
  包一层 `Center`,等价于原型那句 `.chip { align-items: center }`。
- **章节头右侧那颗胶囊 / 排序键整体沉到标题下面**。`SectionHeader` 是个 `baseline`
  对齐的 `Row`,标题、计数、`Spacer` 与 `trailing` **全是它的直接子节点** —— 于是塞进
  `trailing` 的**非文字**部件也被按基线摆(基线行的定位是
  `maxBaselineDistance - childBaseline`,而 `RenderFlex` 算嵌套 flex 的基线时不加
  子节点的居中偏移)。原型明确把它摘出来(`.section .chip, .section .pill-btn
  { align-self: center }`),**移植时留下了基线行、丢了这条摘出的规则**。改法:外层
  回到默认居中,标题与计数之间那层基线关系用一个内层 `Row` 保住。一处改动覆盖
  3 个带非文字 `trailing` 的调用点(测速胶囊 ×1、两处排序键),其余 21 处渲染结果不变。
- 顺手扫出来的其余几处(整个 `lib/` 过了一遍):队列行原先是 `SizedBox(height: 64)`,
  大字号下标题加艺人两行要 ~70(改成 `ConstrainedBox(minHeight:)`,与 `NordicRow`
  同一套);设置页那个 `chevron_right` 是 17、其余六处都是 18;`GhostButton` 的图标
  间距 8 对不上原型的 9,`PillButton` 的 6 对不上 7。其余手搓行逐处读过,都是裸 `Row`
  (默认居中),没有别的活的偏移;两处「两边都是文字」的基线行(服务器页的数值加单位、
  弹层标题加副标题)与原型一致,没动。
- **守卫**:`test/app_test.dart` 的「章节头」那一组,原先只是**光秃秃地 pump 一个
  `NordicChip`** —— 既没把它放进 `SectionHeader`,也没查过它内部的居中,这正是这两个
  病先前漏过去的原因。现在三条:胶囊中心 == 标题中心、胶囊不许沉到标题下面、**选中与
  未选中两态里字都落在胶囊中线上、且两态的偏移一致**(最后这条就是「点一下字不跳」,
  只修外层行的话它会继续红)。改前红、改后绿。
- **假播放器补了两个洞**:`test/playback/playback_test.dart` 的 `_FakePlayer` 原先只
  覆盖了 `loopMode` 字段,`setLoopMode` / `setShuffleModeEnabled` 一调就碰平台通道。
  照它已有的写法补齐,并让那两条流真的发事件 —— 否则 `cycleRepeat` 读到的永远是旧态
  (它从流上回读,不是自己记账)。「记忆循环与随机」那一组用**同一份 prefs 再建一个
  控制器**来验「重启之后还在」。
- **考虑过、这一轮没做**:没动 `NordicGlass` 的 `Stack` 的 `fit` / `alignment`。
  那是全应用每一块玻璃面的地基(坞、顶栏、弹层、分段控件都走它),改它爆炸半径大得多
  —— 真要动该是单独一轮,并且逐屏截图对照。
- 版本 `1.0.31+32` → `1.0.32+33`。

## 第八轮(2026-10-18):文档拆分

这一轮没动应用,只动文档。

- **README 从 624 行收到 ~218 行**。分轮记录(第三轮 ~ 第七轮)搬进本文件,
  「性能姿态」那 130 行搬进 `docs/performance.md`,README 只留 5 条**最容易被顺手改
  回去**的摘要 + 链接(挑条标准:改回去看起来像改好、而且坏了不响)。
  顺手修掉一个结构 bug:**第 100 行到第 618 行原先全都名义上嵌在「开发环境」下面**
  —— 性能姿态、五节历史、已知环境问题都成了它的子节,只因为那之后再也没有出现过
  `##` 级标题。
- **新增仓库根 `CLAUDE.md`**:开工先读哪几份 + 那几条硬规矩。此前仓库里没有任何
  agent 指令文件,文档也不会被自动发现 —— 拆出去的内容得有个约定好的入口。
- **4 处源码注释跟着改**(它们按章节名引 README):`lib/playback/quality.dart`、
  `lib/ui/shell/bottom_stack.dart`、`test/ui/shell_test.dart`、`prototype/styles.css`。
  引「构建」的三个 `android/*.gradle*` 与 `tool/build.sh`、`tool/app_icon.py` 所指的
  内容都还留在 README,没动。
- 新规矩:**分轮记录写在 `docs/CHANGELOG.md` 末尾**(从早到晚),不再往 README 里加。
- 版本不变:`1.0.32+33`。从这一轮起,**纯文档 / 纯注释的改动不动版本号** ——
  版本号是为了让侧载的包分得清哪一版,一个行为完全相同的包换号只是噪音。

## 第九轮(2026-10-18):下载按字节续传 + 收藏的真服务器用例 + 三处过时的说法

这一轮把 M2 那四条「尚未完成」对了一遍账:两条是真缺口(做掉了),两条其实
**早就做完了** —— 清单本身在变形。

- **断点续传从「按曲目」升级到「按字节」**(`lib/data/download_manager.dart`)。
  半截的 `.part` 不再在开工时被清掉 —— 清掉就等于这首每次从头下,而这件事**不响**:
  进度条照爬,只是白花流量。续传发 `Range: bytes=<n>-`,并且在写盘**之前**用 dio
  的 `savePath` 回调看 `Content-Range`(dio 是先跑这个回调拿到响应头、之后才
  `openSync`,所以来得及改主意):对得上就往半截后面接,对不上、或服务器干脆回
  `200`(无视了 Range)就**换一个干净文件截断重来**。必须重来的理由是这一轮最要紧
  的那条:把整段接在半截后面会拼出一个**前段重复**的文件 —— 它照样能播,只是从
  中间某一处开始错位。进度也换成**累计口径**:续传时 dio 的 `received` 只是这一次
  收到的字节,不补偏移会让进度条先退再爬。新增 6 条用例钉住这些不响的坏法(206
  拼接、200 回退不重复、总量对不上当不可信、半截为空、没半截时不发 Range、硬失败
  不留半截)。
- **收藏的写路径补了真服务器用例**(`test/data/star_writes_live_test.dart`)。
  M2 那条记的「只有线上形态的用例」是实话:歌单早有 `playlist_writes_live_test`
  这类 live 用例,收藏没有 —— 而参数名或端点写错时服务器只回一句「失败」。收藏
  就地可逆,所以用例是「读当前状态 → 切换 → 回读断言 → 还原」:先记下三个目标
  **各自原本是否已收藏**,收尾按各自的原值写回(不是一律取消收藏,那会把用户原本
  收藏的反而抹掉),最后再比对三个集合的全部 id 与开工前一致。
- **三处过时的记录改掉了**。README 的 M2 第 2 条(整位艺人要翻页 —— 第六轮就改成
  按**空页**翻到底了)与第 4 条(断网只能进下载管理 —— 整库快照本来就落盘,断网
  冷启动照样铺得出库);还有 `lib/data/subsonic_repository.dart` 里「一页 500 是
  服务器的常见上限(实测这台 Navidrome 就卡在 500)」那句,它与同一份文件 172 行
  的注释、以及 `docs/performance.md` 的翻页小节**直接打架** —— 500 只是一个够用的
  页宽,不是服务器的上限。
- `docs/performance.md` 补了一条:半截不许清、回 200 必须截断重来、进度要用累计
  口径。README 那 5 条摘要**没加**:摘要只收「改回去看起来像改好、而且坏了不响」
  的,而这条改回去会让新增的用例当场变红,按既定边界不进摘要。

**只有真机能验的一条**:「下到一半杀进程再续」。单测只能验到「预置一个 `.part`
+ 假 dio 回 206」,验不到进程被杀时操作系统究竟把多少字节刷到了盘上。已知残余
风险:服务器把同一首歌换成**同样大小**的另一个文件时,无校验和的按字节续传无从
察觉(判据只到「起点 + 总量」为止),要更稳得引入 ETag / `Last-Modified`。

版本 `1.0.32+33` → `1.0.33+34`(在代码那一个提交里 +1;补用例与改文档的两个提交
按第八轮的口径不动版本)。

## 第十轮(2026-10-18):Windows 桌面铺开第一步

M2 收口后的下一格是 M3(iOS / 桌面 / Web 铺开,接入飞牛音乐)。先落**桌面**,而且是
Windows —— 这台开发机**唯一能真正构建并运行**的目标:`flutter doctor` 里
`[✓] Visual Studio - develop Windows apps`,`flutter devices` 里已经列出
`Windows (desktop)`。iOS / macOS 在这台机器上根本构建不了;Web 当时记的理由是
「要先把那 8 个文件的 `dart:io` 全部条件化,规模大得多」—— **那句是错的,第十一轮
纠正了**:`dart:io` 在 web 目标上**可以编译**(SDK 的 `libraries.json` 里 `io` 在
vm / dart2js / dartdevc / wasm 四处都有定义,只是运行期抛 `UnsupportedError`),
真正要处理的是别的东西(CanvasKit 那一跳)。

- **补上 `windows/` 脚手架**。整个目录原先不存在,是
  `flutter create --platforms=windows` 生成的 —— 但**没在仓库目录里跑它**:那条命令
  会重写 `.metadata`,它用一份**空的** `MigrateConfig` 重建平台列表(不读现有的),
  于是 `android` 那组 `create_revision` / `base_revision` 会被抹掉。改成一个临时
  目录里生成、只把 `windows/` 搬进来,`.metadata` 手工补 `windows` 三条、保住
  `android` 那条。`--org fun.han1997 --project-name nordic` 都显式给:前者进
  `Runner.rc` 的 `CompanyName`,而 `path_provider_windows` 的应用支持目录是**读 exe
  的 VERSIONINFO** 拼出来的 —— 于是落在 `%APPDATA%\fun.han1997\nordic\`,与 Android
  的 applicationId 同源。
- **修掉一个静默缺陷:桌面上整块下载被判成不可用**。`download_store.dart` 的
  `_resolveRoot()` 只接 `MissingPluginException`,而 `getExternalStorageDirectory()`
  在桌面与 iOS / macOS 上**根本没被实现**(`path_provider_windows` 只覆写了
  temp / support / documents / cache / downloads 五个,没有 `getExternalStoragePath`)
  —— 平台层直接抛 `UnimplementedError`,**它继承 `Error` 不是 `Exception`**,
  `on Exception` 也接不住,于是一路冒到 `open()` 的兜底,把整块下载判成不可用。
  而那份文件 122 行的注释写的正是「桌面 / iOS 退回应用支持目录」,代码与注释相反。
  改法:`catch` 放宽成一律接,第二次 `getApplicationSupportDirectory()` 留在 catch
  里面(两条路都不通才是真的不通);另给 `open()` 那条什么都吞的 catch 加一行
  `debugPrint` —— 它立刻显出价值:跑用例时把「根目录不可用」的真实原因
  (`PathExistsException`)打了出来。**先写用例、先看它红**:新加的「目录归属」一组
  把 `PathProviderPlatform.instance` 换成只实现支持目录的假平台(正是桌面 /
  foundation 的样子),修复前 `store.isAvailable` 实测为 false —— 这就是那个静默
  消失的确定性证据。所有既有用例都走 `open(root: ...)`,没有一条碰得到
  `_resolveRoot`,这正是它活到今天的原因。
- **装 Windows 音频后端 `just_audio_windows: ^0.2.3`**。它是 Windows 上 just_audio
  唯一「零下载」的后端:纯原生包(缓存里没有 `lib/`、依赖只有 `flutter`),直接顶掉
  just_audio 用的那几个平台通道,底层是系统自带的 Media Foundation。所以**没有任何
  Dart 侧初始化**,也不需要 `Platform.isWindows` 判断 —— 注册就是标准那套
  (`generated_plugins.cmake` 的 `FLUTTER_PLUGIN_LIST` 多了它,registrant 调
  `JustAudioWindowsPluginRegisterWithRegistrar`)。
  `just_audio_media_kit` 明确**否决**:它的 CMake 在**构建期**去 github.com 抓 libmpv
  并做 MD5 校验,而本机 GitHub TLS 握手不通 —— 那不是备选,是另一个必然
  `FATAL_ERROR` 的东西。
- **`AudioService.init` 在 Windows 上是 NoOp,所以「跳过 init」那套没做**。原先预想
  要加一处平台判断(怕它挂住、每次启动干等 8 秒),核实下来不必:`audio_service`
  的平台接口在 Windows / Linux 上直接换成 `NoOpAudioService`
  (`audio_service_platform_interface-0.1.3:18-21`),`init` 既不抛错也不挂住。
  **`lib/` 里因此一行平台判断都没加** —— 少一处无人验证的分支。
- **`tool/build.sh` 扩了 `windows` 分支**:产物是**一整个目录**而不是一个文件
  (`nordic.exe` + `flutter_windows.dll` + `data/` + 各插件 dll),单拿 exe 跑不起来,
  所以整目录打包成 `build/dist/Nordic-<版本>-windows-x64.zip`(用 PowerShell 的
  `Compress-Archive`,Git Bash 的 GNU tar 不按扩展名打 zip)。校验 exe 在、引擎 dll
  与 `data/` 都在、以及 exe 里的版本与 pubspec 一致。顺手把版本号提取抽成
  `read_version()`。**版本串两种呈现都认**(`1.0.34+35` 与 `1.0.34.35`)——
  实测过 `FileVersion` 是自由格式字符串。

- **开发者模式开了之后第一次真构建,暴露出两个跟仓库无关的 C++ 问题** —— 都在
  `just_audio_windows` 自己的源码 / 依赖里:
  ① 它的 `uri_utils.hpp` 注释里有个 U+2192(`→`),文件没有 BOM,MSVC 按代码页 936
  去读就报 `C4819` —— 而插件自己开了 `/WX`,警告即错误;
  ② 它链接的 C++/WinRT `2.0.210806` 用的是 `<experimental/coroutine>`,而 MSVC
  14.51 已经把它判成「即将移除」的硬错误(`C2338` / `STL1011`)。
  治法只动我们自己的 `windows/CMakeLists.txt`:给那**一个** target 加 `/utf-8` 与
  微软自己在报错里给的那个静默宏。改完重跑,两条都消失。**这是本仓库唯一一处偏离
  `windows/` 模板的地方**,所以那几行里写清了「升级 Flutter / VS 或这个插件时回来
  看一眼」—— 尤其第二条是「暂时压住」,不是修好。

- **还差一个 VS 组件:ATL**(`flutter_secure_storage_windows` 要 `atlstr.h`)。这是
  **环境前置,不是仓库问题** —— 本机原先没装,构建停在
  `error C1083: 无法打开包括文件: "atlstr.h"`。装上「C++ ATL for latest v143
  Build Tools」之后构建一次通过:产物 `Nordic-1.0.34+35-windows-x64.zip`(13 MB,
  顶层就是 exe + dll + `data/`,不用再解一层),`just_audio_windows_plugin.dll`
  确在产物里 —— 那是「音频后端真编译进来了」最直接的证据。README 的「构建」一节
  记了这条前置。

版本 `1.0.33+34` → `1.0.34+35`(在代码那一个提交里 +1)。

**桌面外壳的两处待办**(这一轮 `windows/` 一个字节没改,好与模板逐字节对照):
窗口标题是模板渲染出来的小写 `nordic`(`windows/runner/main.cpp` 一行)、
图标是模板自带那张 Flutter 默认图。两处都要单独做,图标还得先让 `tool/app_icon.py`
多产出一个 `.ico`(本机没有 PIL,走 ICO 容器直接内嵌 PNG 那种写法,不引新依赖)。

- **README 的「构建」一节补了 Windows 的两条系统前置**(开开发者模式、装 ATL 组件),
  两条都会**直接拦停构建**。另外 `windows/CMakeLists.txt` 里那几行是本仓库唯一一处
  偏离模板的改动(治 `just_audio_windows` 在新工具链下的两个报错,见下),
  所以在那儿写明了「升级 Flutter / VS 或这个插件时回来看看还需不需要」。

**已在本机跑通并验到的**:Windows release 构建一次通过,产物落成
`build/dist/Nordic-1.0.34+35-windows-x64.zip`(exe 里的版本与 pubspec 一致 ——
`standardize_windows` 那条校验也真跑过了);直接运行 exe,进程稳定存活 20 秒
(之后是我手动结束的,不是崩的),而且它在 `%APPDATA%\fun.han1997\nordic\` 下
**建出了完整的目录树**:

```
Nordic/Music/        ← 下载根。**这就是 `download_store` 那个修复的现场判据**
cache/audio/         ← 听过的歌那份缓存
nordic-covers.json   ← 封面磁盘缓存(桌面走 Json 仓储,不用 sqflite)
shared_preferences.json
flutter_secure_storage.dat
```

修复前这一段是走不到这儿的:`getExternalStorageDirectory()` 抛的
`UnimplementedError` 会把整块下载判成不可用,`Nordic/Music` 根本不会被建出来。

**仍然只能人工看的**(我没法验):窗口里那 21 屏长什么样、连上服务器后**能不能真
出声**、布局在 1280×720 下的观感。release 包的启动日志是空的(没有 debug 输出),
所以「启动秒开 / 后台播放服务有没有干等 8 秒」这条也只能看界面出现得快不快。
`tool/build.sh run -d windows` 跑的开发构建会把那两句 `debugPrint` 打出来 ——
控制台里不该出现「后台播放服务启动超时」与「后台播放服务启动失败」。

另外两条仍然没验:

- **iOS / macOS 上这个修复是否奏效** —— 依据是源码(`path_provider_foundation` 同样
  没有 `getExternalStoragePath`),但本机没有 Xcode 工具链,**一次都没跑过**。
- **交付的 zip 在别人的干净机器上能不能跑** —— 模板默认 `/MD`,依赖
  `vcruntime140.dll` / `msvcp140.dll`;换台机器要装 VC++ 2015-2022 运行库。

## 第十一轮(2026-10-18):Web 铺开

M3 的「铺开」里,Web 是本机还能真跑起来的最后一个目标(iOS 没有 Xcode、Linux 本机
构建不了,而且它连「零下载」的音频后端都没现成的)。这一轮把它铺起来。

- **纠正第十轮的一个错误判断**。那轮把 Web 记成「要先把 8 个文件的 `dart:io` 全部
  条件化」,**不成立**:`dart:io` 在 web 目标上是**可编译的** —— SDK 的
  `libraries.json` 里 `io` 在 `vm_common` / `_dart2js_common` / `dartdevc` /
  `wasm_common` 四处都有定义,各带一个 patch(编译期合法,运行期才抛
  `UnsupportedError`)。所以**一行条件导入都不用写**。
- **这一轮真正的坑:web 目标默认让页面在运行时去 `www.gstatic.com` 取 CanvasKit**
  (渲染器本体)。三处证据:`kWebResourcesCdnFlag` 的 `defaultsTo: true`;装载器
  `flutter_web_sdk/flutter_js/src/utils.js` 的 `getCanvaskitBaseUrl()` 在
  `engineRevision && !useLocalCanvasKit` 时返回那个 CDN 地址;`web.dart` 还把同一个
  URL 硬编码进 dart-define。**失败形态是页面停在加载动画上,不报错也不超时**
  (装载器卡在 `main.dart.js` 之前)—— 最难查的一种,所以 `build web` 与
  `run -d chrome` 都带 `--no-web-resources-cdn`,并把这条写进了
  `standardize_web()` 的校验(防有人绕过脚本手打 `flutter build web`)。
  顺带澄清一句容易再踩的:**`FLUTTER_STORAGE_BASE_URL` 管不到这一跳** —— 它只管构建期
  的引擎产物下载,而那个 CDN 地址是运行时用的。
- **`lib/` 这一轮一个字节没改。** 唯一候选是「给几处 `_defaultRoot` 加 `kIsWeb` 早退」,
  逐个核下来**不需要**:三块存储的 `open()` 都有兜底 → `isAvailable == false` → 各处
  早退;`audio_handler` 的本机路径恒 null → 自动落到 `ProgressiveAudioSource`
  (`LockCachingAudioSource` 那个在 web 上会炸的东西根本不会被构造);`cover.dart` 的
  `file://` 判断恒假 → 自动走网络封面。唯一的副作用是 `DownloadStore.open()` 那行
  `debugPrint` 打一次 —— 而它说的正是实话。加 `kIsWeb` 反而更窄:现有 catch 管的是
  「这块存储在这台设备上建不出来」这个一般命题,`kIsWeb` 只覆盖其中一条,而且会成为
  第五个平台的无人验证分支。**全量用例数与改动前一字不差(305/16/0)**,坐实了这一点。
- **CORS 事先验过了**(不是猜):这台 Navidrome 带 `Origin` 的 GET 回
  `Access-Control-Allow-Origin: *`,预检 `OPTIONS` 回 `Access-Control-Allow-Methods: GET`
  + `ACAO: *`。而 `SubsonicClient` 只有一个 `_dio` 调用点、协议本身全是 GET 查询参数,
  **当前没有会被预检拦下的调用**(哪天把写入改成 POST,这里要重新看)。
- **`web/` 脚手架照第十轮补 `windows/` 的办法**:临时目录生成、只搬 `web/`、
  手补 `.metadata` —— 直接在仓库里跑 `flutter create` 会把 `android` / `windows`
  那两组 revision 抹掉。搬进来 7 个文件,`web/` 一个字节没改。
- **`tool/build.sh web` 的产物校验四条**,并说清每条为什么能真查出东西:六个入口文件齐;
  `useLocalCanvasKit` 在产物里;**版本对齐**(读 `build/web/version.json` —— 那是
  **构建系统**在构建那一刻从当次的 pubspec 写进去的,所以「改了版本忘了重建」必被抓);
  以及**没有签名那套,不假装有**(web 产物既没有签名,也没有 Android 那种包名身份可校)。

版本 `1.0.34+35` → `1.0.35+36`。

**已在本机跑通并验到的**:`tool/build.sh web` **50.7 秒一次过**,产物
`build/dist/Nordic-1.0.35+36-web.zip`(14 MB,顶层直接是 `index.html` / `assets/` /
`canvaskit/`,不多套一层);`version.json` 是
`{"version":"1.0.35","build_number":"36",…}`,与 pubspec 逐字对上;
`grep useLocalCanvasKit build/web/flutter_bootstrap.js` 命中(说明走的是本地那份);
`build/web/canvaskit/` 里 `canvaskit.js` 与 `canvaskit.wasm` 都在。

**明确砍掉的**(浏览器里没有对应物,靠现有降级路径自然关掉,不是靠 `kIsWeb` 判断):
下载、断点续传、听过的歌那份音频缓存、库快照的离线冷启动、歌词落盘。
**保留**:浏览、搜索、歌词(内存)、收藏、歌单、播放、循环 / 随机、队列。

**这一轮没验到的(只有人能看)**:

1. **真出声**,尤其**「没转码过的那一首」**。`just_audio_web` 的 `loadUri` 在设完
   `src` 后会 await 一个 duration Completer,而它**只在 `<audio>` 的 `durationchange`
   或 `error` 事件里完成** —— 若某个浏览器对 chunked 响应两个都不触发,
   `setAudioSource` 会一直挂着:界面停在加载态、不出声、不报错。这是这一轮最大的悬念。
2. **Chrome 媒体面板**(`audio_service_web` 走 Media Session API,不建 `<audio>` 元素;
   关掉标签页就没了,那是浏览器语义不是缺陷)。
3. Chrome 里那 21 屏在桌面视口下的观感。

**记下的待办**(都不是这一轮该做的):

1. **Web 外壳**:浏览器标签标题是模板渲染的小写 `nordic`、favicon 与 PWA 图标是模板
   自带那张 —— 与第十轮 Windows 那两条待办对称。
2. **非 secure context 上 `connect()` 会卡死**:`flutter_secure_storage_web` 在没有
   `window.isSecureContext` 时抛 `UnsupportedError`(**是 `Error`,不是 `Exception`**),
   而 `app_state.dart` 里 `savePassword` 是裸 await、`servers_screen` 进来时已经
   `_busy = true` —— 异常冒出去,按钮**永远转圈**,配置一个字都没存。只在「从局域网
   http 地址打开页面」时发生(`localhost` / `127.0.0.1` 是 potentially trustworthy
   origin,不受影响),所以开发期碰不到。修它要动 `lib/state/`,那是另一个决定。
3. Web 上的下载入口该长什么样(这一轮已定「不拦,点了给一句人话错误」)。

## 第十二轮(2026-10-18):音源抽象层

M3 的原话是「iOS / 桌面 / Web 铺开,**接入飞牛音乐**」。前三个平台铺完了,而飞牛
音乐的协议是未知的 —— 所以这一轮做的是它的**前置**:让「音源」在代码里成为一个
真的接缝。顺带把 `README.md` 里程碑表里 M1 那行不实的话改掉(它写着「音源抽象层」,
而抽象层其实今天才做)。

**行为零变化是硬要求**,唯一的例外不是变化:一处不可观测的内部差异见下。

### 两个接口,不是一个

`lib/data/music_source.dart` 是新的中立文件,放三个互相引用的类型:

- **`MusicSourceException`** —— 音源失败的**中立基类**。是**具体类**而不是抽象接口:
  应用层自己也要造失败(`_requireRepository` 的「还没有连接服务器」、`downloadArtist`
  的「音乐库里没有找到…」),那些与协议无关,直接抛它即可;做成抽象的话就得再加第三个
  名字。两个 flag(`isAuthFailure` / `isNetworkFailure`)在基类上默认都不标,**由实现
  各自覆盖** —— 基类不该替实现猜。
- **`ServerConnection`** —— 「怎么连」:`routes` / `setRoutes` / `activeRoute` /
  `autoRoute`(可读可写)/ `pings` / `pingAll` / `pingRoute`。
- **`MusicSource`** —— 「有什么」:21 个音乐方法(`artists` / `albums` / `albumList` /
  `album` / `artist` / `allSongs` / `songsByArtist` / `playlists` / `playlist` /
  `search` / `lyrics` / `setStarred` / `starred` / `coverUri` / `streamUri` /
  `downloadUri` 与 5 个歌单写)加一个 `connection` getter。

**两者分开是有意的**:线路(多地址、择优、故障切换、锁定)是传输层的事,与「这台
服务器上有什么音乐」无关。合成一个接口的话,每个音源都得实现一遍线路表,哪怕它根本
没有多线路这回事。

`SubsonicClient` 那 5 个成员的名字与签名本来就跟 `ServerConnection` 一模一样,所以
`implements` 是**零改名**;`SubsonicRepository` 补了一个 `connection => client`。

### 异常中立化:界面不再认 Subsonic 的名字

`SubsonicException` 从 `lib/data/` 一路漏到界面 —— 16 处 UI `catch` 加 app_state 里
5 处都按这个 Subsonic 专属的名字判。换一个音源之后那些 catch 一条都接不住,错误会直接
穿过界面。这是「真接得进飞牛音乐」的前提。

- `SubsonicException` 改成 `extends MusicSourceException`,构造换成 `super.message`
  转发,自己的 `code` / `statusCode` 与两个 getter 原样。**位置参数与可选命名参数都没
  变**,所以全仓库所有 `SubsonicException(...)` 构造点零改动;`lib/data/` 内部那几十处
  `catch` 因为**子类关系**也零改动 —— 它们判的就是 Subsonic 协议,该留着。
- 16 处 UI `catch` 与 app_state 的三处 `catch` 改判中立类型;app_state 那两处自造异常
  也改成中立 —— 它们本来就不是协议失败,却借了 `SubsonicException` 的名字。
- 11 个界面文件原先只为 `SubsonicException` 而 `import subsonic_payload.dart`,整条换成
  `music_source.dart`。

**一处不可观测的差异,如实记下**:那两处自造异常换成中立类型后,它们的
`isNetworkFailure` 从 `true`(旧判据是 `code == null && statusCode == null`)变成
`false`(基类默认)。全仓库 grep 核实过:`isNetworkFailure` 只有两个读点
(`subsonic_client.dart` 的故障切换、`app_state.dart` 的 `_failLoad`),**都不在这两处
异常的路上**,所以不可观测 —— 但这是真的变了,不假装零差异。

### 分派点:`sourceFor`,**不做抛异常的空壳**

`server_config.dart` 新增 `sourceFor(config, password, autoRoute, dio, localCover)`,
是 `ServerConfig` 到 `MusicSource` 的唯一出口;`clientFor` 降为它的下位构件并保持公开
(5 个 live 测试的 `SubsonicRepository(clientFor(...))` 形态原样可用)。

**三个 `ServerKind` 今天走同一支**,`fnos` 那一档写成显式 case + 注释:

> fnOS:按社区逆向的说法也讲 Subsonic,先走同一条。拿到真实协议时,**分叉就发生在这里**。

本来打算给飞牛音乐做一个「抛 `UnimplementedError` 的空壳」,核完源码发现**那是回归**:

- `ServerKind` 自己的注释(`server_config.dart` 里)逐字写着「三者都讲 Subsonic 协议,
  差异在能力边界:飞牛音乐基于社区逆向,官方无公开 API」—— 仓库的口径就是 fnOS 也讲
  Subsonic;
- `servers_screen.dart` 把 `ServerKind.values` 全部渲染成可选卡片,**飞牛音乐今天就是
  可选项**,而 `clientFor` 从来不读 `kind` —— 选它的用户现在拿到的是一个普通客户端。

一个会抛的桩会把**可能能用**的配置变成**必然失败**。改成显式 case 之后,行为与今天
逐字相同,但那是一支**活的、被执行的**代码,而且把将来的分叉点标了出来。

`sourceFor` 的 `localCover` 形参**必须带**:它是封面「本机优先」的回调,漏掉它,断网时
已下载内容的封面会从「看得见」变成「没有」—— 那是实打实的行为变化(差点漏掉,靠复核
才发现)。

### 顺便搬的两处 + 没进接口的两样

- **`ServerRoute` / `RouteTag` / `RoutePing` 与那两个编辑函数**(`mergeEditedRoute` /
  `toggleRouteLock`)从 `subsonic_client.dart` 搬到新的 `server_route.dart`;
- **`AlbumSort`** 从 `subsonic_repository.dart` 搬到 `sorting.dart` —— 它是**排序口径**,
  不是协议,而且音源接口的签名要用到它,**不搬就成环**
  (`music_source` → `AlbumSort` → `subsonic_repository` → `MusicSource`)。

两个旧文件各 `export` 一次,并且**用 `show` 收窄**(`sorting.dart` 那边只透 `AlbumSort`)
—— 不加 show 的话整个 sorting 库都会跟着透传,原先直连 `SongSort` / `sortSongs` 的文件
会凭空多出一条 `unnecessary_import`。`export` 不把名字带进导出库自己的 scope,所以
`import` 与 `export` **必须成对写**。

- **`invalidateDetail` 不进接口**:全仓库 grep 过,它**只被自己调**(4 处,全是
  `'playlist'`),界面与测试一次都没碰过。参数是 Subsonic 端点名,进接口等于把协议词汇
  焊到中立契约上。
- **通用件不抽**:详情缓存、URI 备忘录、本机封面回退、`_isBy`、`_playCount` 机制上确实
  协议无关,但**只有一个实现**。为一个假想的第二用户造机器是投机;等 fnOS 真接进来、
  真出现第二个消费者时再抽,那时才知道该抽哪一层。

### 翻标注 + 穿墙改道

约 40 处 `SubsonicRepository` 类型标注全改成 `MusicSource`:AppState 的字段 / getter /
`_requireRepository`、`audio_handler`(含那个 `switch` 的类型模式 —— 漏改会在运行时
静默丢封面,编译不报)、`download_manager` 的字段与两个形参、12 个界面文件(含
`context.select<AppState, MusicSource?>` 的泛型参数 —— 那是 Provider 的类型契约,不是
美化,漏改即编译失败)。

5 处穿墙访问 `repo.client.X` 改成 `repo.connection.X`,接缝上不再有洞。
`SubsonicRepository.client` 字段保留公开(live 测试与仓库内部要用)。

### 新增的用例

`test/data/source_for_test.dart` 钉两条**决定**,不是断言 `implements` 生效(那是编译期
的事,写成运行时断言就是空转守卫):

1. 三个 `ServerKind` 今天**都落到 Subsonic 那一条** —— 谁哪天把它换成抛异常的空壳,
   这里当场变红;
2. **`localCover` 真的透传到了音源上** —— 就是上面那条差点漏掉的回归。

### 验证

`flutter analyze` 干净;`flutter test` **309 passed / 16 skipped / 0 failed**
(305 + 新增 4);标点守卫 0 处待改。26 处 `@override` 由
`dart fix --apply --code=annotate_overrides` 补上,不是手写。

**仍然只有人能验的**:这轮是类型级重构,**编译过不等于行为没变** —— 桌面 / 真机上
浏览、搜索、播放、收藏、歌单读写、下载各走一遍才算数。

版本 `1.0.35+36` → `1.0.36+37`。

### 记下的待办

飞牛音乐那份协议拿到之后,分叉点在 `server_config.dart` 的 `sourceFor` 里。另外
`subsonic_payload.dart` 里有一处判据值得那时再看:fnOS 若真应答却不是
`subsonic-response` 外壳,会被判成「协议不对」(不触发换线路)—— 那是符合预期的,但接
fnOS 时会在这一层显现出来。

## 第十三轮(2026-10-18):M3 收尾

四件记下的收尾活:平台外壳统一、货架封面的共享元素过渡、「随机」再点重洗、
非 secure context 上连服务器卡死。

**飞牛音乐这一轮不做** —— 用户说了「有(服务器),但是暂时不做飞牛音乐的接入」。
M3 后半句继续挂着,分叉点仍是 server_config.dart 的 sourceFor。

### 一、平台外壳统一(图标 + 名字)

图形**一个矢量源**:tool/app_icon.py。文本**一个名字口径**:Nordic,真值取
android/app/src/main/AndroidManifest.xml 的 android:label。
**图形有生成器,名字没有** —— Nordic 现在有六处字面量(lib/app.dart、设置页、
AndroidManifest.xml、main.cpp、web/index.html 两处、web/manifest.json 两处),
改名字要照着 android:label 一处一处对。

生成器新增两个目标:

| 产物 | mode | 尺寸 | 通道 |
| --- | --- | --- | --- |
| web/favicon.png | legacy | **32** | RGBA |
| web/icons/Icon-{192,512}.png | legacy | 192 / 512 | RGB |
| web/icons/Icon-maskable-{192,512}.png | maskable | 192 / 512 | RGBA |
| windows/runner/resources/app_icon.ico | legacy | 16/32/48/256 | RGBA |

文件名与 manifest.json 里的 src **一个字符没动**,所以清单的 icons 数组不用改。
favicon 出 32 而不是模板的 16:与 ICON_FAVICON 那个 data URI 对齐,16px 下那七根柱
必然糊,而 link rel=icon 没有 sizes、浏览器自己会缩。

**maskable 的边距与 Android 的不是一回事**(这块最容易抄错):Android 自适应保证的是
中央 72×72 的**方块**,图形角上可以到 50.9;而 web 的 maskable 规范保证的是一个**居中
的、直径 80% 的圆**,半径只有 43.2。定稿 m05 的硬墨迹角点离中心 47.96,所以新增
SCALES['maskable'] = 0.88(0.9008 往下留抗锯齿余量)。代价认下来:会遮罩的启动器里
那份看着比不遮罩平台上那份略小。

**ICO 用 PIL 打包,每一档都作为 provided image 递进去** —— 不让 PIL 自己缩:它只在
没有同尺寸 provided image 时才 thumbnail,而且是在**未 premultiply 的 RGBA** 上缩,
那正是 downscale() 花力气避开的事(透明边缘会出黑边/彩边)。不用
bitmap_format='bmp'(全局开关,会把 256 那帧也写成 DIB,文件涨到几百 KB 且**仍然**
与模板不同)。我们这份**每帧都是 PNG**,模板是「256 用 PNG + 48/32/16 各三种色深的
BMP」—— Win10/11 都正常,**旧系统没验过**,别写成已验证。

**CLI**:加 `--targets android,web,windows`。没点名任何目标时不写任何像素产物、只出
prototype/icon.js(这条等于脚本以前的行为,旧命令含义一个没变)。`--verify` 扩成也
校验 web 与 windows(尺寸 / 通道 / 四角是地面色 / 硬墨迹框与规格的差 / ICO 档位),
**仍然不叫 chromium**,没装 Chrome 的机器上也跑得动。

**唯一一处破坏性变更**:`--out` 的语义从「Android 的 res 根」改成「要落的那棵树的根」
—— 三个目标各落各的子路径,没法给每个目标各配一个开关。

顺手两处收尾:`--freeze` 的 docstring 改准(它写着「重出全部产物」,其实不点 `--targets`
只出原型);`verify()` 里 rglob('*.xml') 钉在 Android 的 res 根上(`--out` 变成树根
之后它会一路摸到 web/)。

**纠正第十轮一句过时的话**:那句「本机没有 PIL,走 ICO 容器直接内嵌 PNG 那种写法」
作废 —— `py -3` 有 PIL 12.2.0 + numpy 2.2.5(脚本的 downscale() 本来就在用),
PIL 直接能写多分辨率 ICO,不必手写容器。(第十轮说的「本机没有 PIL」指的是 PATH 里那个
python,它是 3.8 32 位,确实没有;能跑这个脚本的一直是 `py -3`。)

**文本改了哪些**:

- windows/runner/main.cpp:窗口标题 L"nordic" → L"Nordic",并留一条注释说清
  「应用数据目录在 Runner.rc 的 CompanyName + ProductName,别在这行找」;
- web/index.html:title、apple-mobile-web-app-title、meta description;
- web/manifest.json:name / short_name / description / background_color / theme_color。

**description 那句**逐字取 README 第 3 行,只把逗号换成**全角**(应用可见文案的规矩;
README 的叙述照旧半角)—— 这个刻意的单字差异不是抄漏。manifest.json 是 JSON 写不了
注释,所以口径记在 index.html 的注释与这一节里。

**两个颜色从 Flutter 蓝 #0175C2 改成 #07070C** —— 它与 app_icon.py 的 GROUND、
Android 的 nordic_bg(它的 launch_background.xml 已经在用它铺启动底,注释写着
「和应用第一帧同一个色,冷启动看不出接缝」)、NordicTokens.dark.bg 是同一条口径。
原来启动会先蓝一下再进深色应用,而图标自己的地面就是近黑。

**两条「改了但看不出」,写在这儿免得以后白找**:

1. index.html 的 title **只管加载期** —— 应用起来后引擎会用 MaterialApp.title
   (lib/app.dart 已经是 Nordic)盖掉 document.title。真正看得见的是
   apple-mobile-web-app-title,那条不会被盖(iOS 装到主屏上就叫这个)。
2. manifest.json 的 theme_color **只管开机前** —— 运行期引擎会注入自己的
   meta[name=theme-color]。而开机前正是蓝闪那一下,所以更该改。

**Runner.rc 一个字节没动**:它的 ProductName + CompanyName 决定
%APPDATA%\fun.han1997\nordic\(path_provider_windows 读 exe 的 VERSIONINFO),
动它会把用户数据目录搬走。代价是任务管理器进程名与 exe 属性里的「文件说明 / 产品名称」
仍是小写 nordic —— 如实留着。

**踩到并修掉的一个坑(值得记住)**:windows/runner/main.cpp 是**没有 BOM** 的,而
windows/runner 走的是 Flutter 模板那套 /W4 /WX —— 往里写中文注释会直接
C4819 -> C2220,**构建失败**。第一次加固时就撞上了。现在那个文件里的注释**全是 ASCII**,
并把这条教训写进了注释本身。

这与 just_audio_windows 的 uri_utils.hpp 是同一个病(见 windows/CMakeLists.txt 那条):
要往这类文件里写非 ASCII,得先给它 BOM 或者给 target 挂 /utf-8 —— 两条都比「把注释写成
英文」重,所以选了后者。


### 记一笔:第十轮那句「一个字节没改,好与模板逐字节对照」到此作废

第十轮与第十一轮特意让 windows/、web/ **一个字节不改**,好与 flutter create 的模板逐字节
对照。这一轮有意打破它 —— 现在偏离模板的每一处:

- windows/runner/main.cpp:**1 行**(标题)+ 一段注释;
- windows/runner/resources/app_icon.ico:**整份替换**(二进制);
- web/index.html:**3 处值** + 注释;
- web/manifest.json:**5 个字段**;
- web/ 的 **5 张 PNG**:整份替换;
- windows/runner/Runner.rc:**0 字节**(有意保留,理由见上);
- windows/CMakeLists.txt 里那句「**本仓库唯一一处**对 windows/ 模板的改动」变成假话,
  已改成指路 —— **清单不维护在注释里**,它会一升 Flutter 就过期。

**「逐字节对照」是一次性核对手法,不是长期守卫** —— 它只在「树刚搬进来、还没长出自己的
东西」那两轮有意义。取代它的是三样:tool/app_icon.py --verify(内容级判据)、
windows/CMakeLists.txt 里那条指路注释、以及下面这条**已经核过源码的结论**。

**要再对一次怎么办**:flutter create --org fun.han1997 --project-name nordic
--platforms windows,web 开在**临时目录**,与仓库 diff -r —— **别在仓库里跑**
(它会用一份空的 MigrateConfig 重写 .metadata,第十轮踩过)。

**已经核过源码的两条**(以后有人担心就直接引用):

- **flutter build windows 不会从模板重拷 app_icon.ico**:flutter_tools 里零处引用
  app_icon,构建期那几个 migrator 都不碰它。**唯一会覆盖的是人手跑 flutter create .**。
- **MSBuild 不把 .ico 当成 Runner.rc 的依赖**:nordic.vcxproj 的 ResourceCompile 没有
  AdditionalInputs。只换 .ico 而 Runner.rc 字面量不变,**资源可能不重编、exe 里还是旧
  图标,而且构建全绿、没有任何提示** —— 所以**换图标后第一次构建必须清 build/windows**
  (或 flutter clean)。验收靠从 exe 里抽图标看一眼 + 人眼。

**动手前先核过 Android 那 15 张没被动**:两次渲染逐字节一致;仓库里那 17 个产物今天仍
复现得出来(--out 到 .tmp-shots 再 diff -r,只差它不产的那些文件)。所以 --targets 不是为
「怕 diff 噪音」而加,是为了 CLI 卫生与让 --verify 能分目标。

### 二、货架封面也能飞进专辑页

**「原型已定、应用没做」**,不是新增设计:prototype/app.js 的 .rail-item 本身就带
data-morph,而 morph 逻辑是「点哪个卡片就飞它那张 .cover」—— **不认 tag**,网格与货架
一视同仁。所以 prototype/ 一个字节没改。

**现状**:货架的 tag 是 '$heroPrefix-${album.id}'(首页给的前缀是 cover-rail-recent /
cover-rail-frequent),而专辑页写死 'cover-${album.id}' —— 从货架进去永远配不上起点,
从来没飞过。网格那条今天是飞的。

**不能把货架前缀改成 cover-{id}**:同一张专辑常常同时在两条货架上,同一条路由里重名
Hero 会直接断言失败(真机表现是「从首页点进任何一页都崩」,2026-10-18 修的就是这一处)。

**修法:让 tag 跟着路由走**(不是「专辑页挂两个 Hero」—— 框架按 tag 找起点,挂两个等于
把「哪一张在飞」交给运气):AppRoutes.openAlbum(context, id, {heroTag}) 的参数从 String
改成记录,AlbumScreen 加可空的 heroTag,_AlbumHead 透传,挂 heroTag ?? 'cover-${album.id}';
货架把自己那张卡片的 tag 原样交出去。**其余四个调用点一个字没改**(网格、艺人页、播放页、
歌曲菜单 —— 后三处的来路本身没有 Hero)。

**护栏两条**(app_test.dart 的「页面过渡」一组):一条钉路由把 tag 带过去、不传则退回
网格那个;一条**真搭起来测**货架 —— 挂 NordicTheme.dark(不需要 Provider,因为
NordicAccentScope.of 缺祖先时会退回中性色),读出卡片显示的 tag、点一下、断言路由
**带过去的正是同一个**。

### 三、「随机」再点一次重新洗

setAlbumSort 开头那句 `if (sort == albumSort) return;` 挡掉了「同一个口径再点一次」——
对五个口径是对的(重拉是白花一次请求),但**对「随机」是错的**:那一版的顺序是**服务器
每次请求重新给的**(getAlbumList2 的 type=random),不重拉就永远那一版。

改成 `if (sort == albumSort && sort != AlbumSort.random) return;`。界面一个字不用改
(sort_sheet 已经无条件下调)。别混:**播放的随机**是另一条线(toggleShuffle),它本来就
每次翻转、没有早退。

### 四、非 secure context 上连服务器卡死

**现场**:_connect() 整个函数体没有 try/catch/finally。await appState.connect(...) 一抛
出去,后面那句 _busy = false 就永远走不到 —— 而 _canSubmit 要求 !_busy,于是提交键被
禁用并显示加载态:**按钮永远转圈**。

抛出的是 flutter_secure_storage_web 在没有 window.isSecureContext 时丢的
UnsupportedError(**是 Error 不是 Exception**)。而 connect() 的第一步 savePassword 是
**裸 await 且排在 saveServer 之前**,所以失败时**密码没写、配置也没存** —— 失败得还算
干净,只是用户完全看不出来。

**改成**:把 connect 与 loadLibrary 两个 await 包进 try;catch 里复位 _busy 并写
_formError。存储那一步的 UnsupportedError 单独翻译成人话(说清该怎么改),其余走通用的
「连不上」。

**这是让它响亮地失败,不是让它能用**:http:// 局域网地址下系统密码存储本来就是关着的,
凭据存不住 —— 就算放过去也会「连上、一刷新就没」,那比连不上更让人糊涂。所以不吞异常、
不降级保存。**不是原型改动**:_formError 是服务器页已有的状态与渲染。

### 版本与提交

版本 1.0.36+37 → 1.0.37+38(这一轮只 +1 一次)。六个提交,每个都单独编译过、单独 push:

1. 外壳:图标生成器补 web 与 windows 两个目标(脚本 + 6 个图形产物,**必须一起** ——
   产物是脚本的输出,拆开中间那个 --verify 会红);
2. 外壳:窗口标题与浏览器标题 / 清单统一到 Nordic;
3. 界面:货架封面也能飞进专辑页(tag 随路由走);
4. 状态:「随机」再点一次重新洗;
5. 界面:连服务器失败时不再永远转圈;
6. 文档:第十三轮记录 + 版本号 + 改掉 CMakeLists 那句假话。

### 这一轮没验到的(只有人或别的设备能看)

1. **图标真的进了 exe** —— --verify 只校那个 .ico 文件本身,校不到 exe。要人看:
   任务栏、Alt-Tab、资源管理器开到「超大图标」看 256 那一档。
2. **apple-mobile-web-app-title** —— 要 iOS 设备(装到主屏上才看得见)。
3. **http:// 局域网打开 Web 时那个失败提示** —— 本机没有那样的环境,只做代码走查。
4. **货架的飞行** —— 测试钉的是「tag 两边一致」,真飞起来好不好看要人看。
5. **ICO 在旧版 Windows 上的表现** —— 我们那份每帧都是 PNG,模板是混合编码。Win10/11 正常。

**上一轮还挂着的**:Web 上音频到底出不出声;Windows 那 21 屏在 1280×720 下的观感。

## 第十四轮(2026-10-18):播放页进出改用切 tab 那套淡入

用户原话:「进出音乐播放页的动画卡顿,尝试使用 tab 切换的动画我看看效果」。
一次**试**出来的改动 —— 结论要真机上给。原型先行,应用跟上,两边都验过。

### 一、原型:播放页进出从滑动改成淡入(顺带对齐一处不一致)

`prototype/app.js` 的 `renderStage` 里加了一层 `navKind(nav, entering, leaving)`:
进 / 出 `player`(以及 `lyrics`)走 `fade-in` / `fade-out`,其余二级页仍是 `push` / `back`
那套整屏滑动。方向与用途照旧靠 `<html data-nav>` 分辨。

`prototype/styles.css` 里新增 `vt-fade-in` / `vt-fade-out`,各 0.22s / `--ease`
——**与切 tab 的 `screen-in` 是同一个数**。实现上是交叉淡出:旧那一格原地不动,
新那一格从透明淡上来(View Transition 的新快照本来就压在旧快照之上,不用像返回那样翻 z-index)。

顺带修掉一处**原型与应用不一致**:播放页 ↔ 歌词页在应用里一直是「直接换」
(`AppRoutes.flip`,时长 0),原型却在滑动 —— 这一段的注释早就写着该是「翻面」,
代码没跟上。现在 `navKind` 把这一对判成 `flip`,CSS 里整条 `animation: none !important`
停掉,两边对上了。

**验证**:新脚本 `.tmp-shots/vtfade.cjs`(照 `vtcheck.cjs` 那套写)。判据三样:
`data-nav` 的值、过渡期间挂在伪元素上的动画名与时长、`#phone-slot` 的位置动没动。
结果:坞 → 播放页、歌曲行 → 播放页都是 `vt-fade-in @ ::view-transition-new(phone) 220ms`
且 `dx = 0`(原地不动);返回是 `vt-fade-out @ old(phone)`;播放页 ↔ 歌词页那两次
**一条整格动画都没有**;回归项「专辑格 → 专辑页」仍是 `vt-slide-in-right 320ms`;
控制台无报错。

> 踩到两个坑,记这儿免下次重踩:① 播放计时每秒 `render()` 一次,而 `render()` 会给
> `.screen` 重挂 `screen-in`(220ms),所以**不能**拿「有没有 screen-in」当判据,只认挂在
> 伪元素上的那几条;② 播放页 ↔ 歌词页来回翻过之后,历史里是 `[library, player, lyrics]`,
> 这时按返回是回**歌词页**而不是列表 —— 脚本的预期一开始按「回列表」写,红了一次。

### 二、应用:播放页路由换成 `AppRoutes.fade`

新增 `AppRoutes.fade`(`routes.dart`),`player` 那一路从 `slide` 换过去:

- 时长与缓动是 `NordicMotion.screenFade`(新增,220ms)加 `NordicMotion.ease`
  —— **与 `shell.dart` 切 tab 那个 `AnimationController` 读的是同一个常量**。
  shell 里原先是个字面量 220ms,现在两边一处真值。
- `transitionsBuilder` 只给 `FadeTransition`:**不叠位移、不叠缩放**。淡入那层里垫一层
  `RepaintBoundary` —— 整屏不透明度会把子树关进离屏合成层,少了这道边界,那 62px 氛围模糊
  与玻璃 `BackdropFilter` 每帧都要在新缓冲里重做(与 `shell.dart` 切 tab 那处同一个理由)。
- 其余二级页(专辑 / 艺人 / 歌单 / 服务器…)**仍是滑入**,歌词页仍是 `flip`。

### 三、护栏两条(两边合起来才说明「同一套」)

- `app_test.dart`「页面过渡」:播放页路由两头时长 == `NordicMotion.screenFade`、
  过渡件是 `FadeTransition` 而不是 `SlideTransition`、缓动值 == `ease.transform(0.5)`。
- `shell_test.dart`:主壳那层 `FadeTransition` 背后的 controller,时长与曲线**就是**
  那两个常量 —— 哪一边漂开,至少有一条会红。

### 版本与提交

版本 1.0.37+38 → 1.0.38+39(这一轮只 +1 一次)。三个提交:

1. 原型:播放页进出改用与切 tab 同一套的淡入;
2. 界面:播放页进出改用切 tab 那套淡入;
3. 文档:第十四轮记录 + 版本号。

release 包已出:`build/dist/Nordic-1.0.38+39-release.apk`(签名有效、包名 fun.han1997.nordic)。

### 这一轮没验到的(只有人或真机能看)

1. **顿挫到底有没有了** —— 这是用户提的现场,只有真机能判。原型那边验的是「动的是哪一格、
   动的是什么」,验不出手机的帧率。
2. **淡入的手感要不要调** —— 220ms 是否偏快(整屏换一次比切 tab 的位移量大)、
   返回要不要单独一个时长,都得看着真机定。
3. 顺带一句:真机上如果还是顿,瓶颈大概率不在过渡方式上,而在**推入那几帧里建整棵
   播放页**的活儿(氛围模糊 + 大封面)。下一步该拿 DevTools 的 timeline 量一下,
   别再换第四种过渡猜。

## 第十五轮(2026-10-18):扫码同步(服务器与线路在两台设备之间搬家)

用户原话:「多平台增加扫码同步服务器、线路配置信息」。四个范围是问过一次定下来的:
**双向**(导出 + 导入)、密码**默认不带**、没有摄像头的平台**降级成复制 / 粘贴**、
实现用**成熟包**。这是一次新设计(仓库里原先没有任何二维码 / 相机 / 剪贴板依赖,
原型里也没有),所以照硬规矩**先改 `prototype/`**。

### 一、原型:一屏 + 一弹层 + 一个复活的空态

- `screenSync()`(`VIEWS.sync = '/sync'`):`.segmented`(扫码 / 粘贴)→ 取景框
  (四角括号 + 来回走的扫描线)或粘贴框 → 读出之后一张 `.card` 摆出服务器与逐条线路
  → 一行说明 → 主按钮。按钮文案三种:「连接」「连接并替换」「填上密码」。
- `sheetExportConfig()`:二维码 + 「包含密码」开关(**默认关**)+ 开着时的警告
  + 「复制文本」(真调 `navigator.clipboard`,失败才提示手动选中)+ 一串可手动选中的文本。
- **首页 / 音乐库的未连接空态**共用一块 `notConnectedState()`:两颗入口(连接服务器 /
  扫码同步)。`STATE.removed` 之前是写进去从没被读过的死代码,这一轮正式接进
  `screenHome` / `screenLibrary`。
- 占位二维码**按种子算**,不是每帧重抽 —— 播放时 `render()` 每秒一次,每帧
  `Math.random()` 那块会闪(与「随机排序用 `randomSeed`」同一条理由)。
- 打字那一支**不重渲染**(重渲染会打掉焦点与中文输入法组合),所以「这段不是 Nordic 的
  配置」那句、以及改文本时把上一次读出的预览作废,走的是原地翻显隐。
- 设计板 22 格 → **26 格**(扫码同步 / 扫码同步·没有摄像头 / 导出配置 / 首页·未连接),
  表头写死的格数一并改掉。没有摄像头那一格是必须铺的:它铺的正是 Windows 桌面与浏览器
  真正看到的那个样子 —— 这一条踩过坑,见下面「守卫误报」那一段。

验证:`.tmp-shots/syncsync.cjs`(36 条)全绿、控制台零报错;`board-all.cjs` 深浅各 26 格。

### 二、载荷格式

```
nordic://config/1/<base64url(utf8(JSON)),去掉 '='>
```

版本放在**路径**里而不是 query —— 解码器能在碰 base64 之前就用一句准确的话拒掉别的版本。

- 载荷里**故意没有**三样:`ServerConfig.id`(落盘时由 `connect` 发)、`lastScannedAt`
  (「本机上次扫描」对目标机没意义)、各条线路的 id(导入时重发 `route-1..route-N`)。
  **正因如此解码不能复用 `ServerRoute.fromJson`** —— 那个读 `json['id']`。
- 密码默认**整个键都不在**(不是写 `null`):「开关关着时这串里不该有密码的痕迹」
  这件事要在字节层面成立。
- `pw` 之外:`kind` 认不出就**拒掉**,不像 `ServerConfig.fromJson` 那样退回 navidrome
  —— 这份配置是从另一台设备来的,静默按某一档连上去,错误要到连不上库时才显形。
- 读不出来的每一种都落在一个枚举上(`TransferError`),各带一句能照着做的话。
- 顺手收掉一处重复:`_normalizeUrl` / `_routeNameFor` / `_tagFor` / `_looksLocal`
  在 `servers_screen.dart` 与 `add_route_screen.dart` 里各有一份,解码还要用第三份,
  收进 `lib/data/server_url.dart`。**一处行为变了**,如实记下:`ftp://x` 以前被拼成
  `http://ftp://x`(解析得出来、于是通过校验,但连不上),现在直接判不合法。

**体积(实测,纠错等级 M)**:

| 载荷 | 字符数 | 模块 |
| --- | --- | --- |
| 1 条线路 | 218 | 61×61 |
| 3 条普通线路 | 413 | 81×81 |
| 4 条长主机名 + 中文线路名 | 766 | 105×105 |
| 同上再加 20 字符密码 | 804 | 109×109 |

比动手前的估算大(那份估的是「4 条长主机名约 600 字符 → 81 模块」)—— 差在中文线路名:
一个汉字 3 字节,base64 之后 4 个字符。于是导出那张纸的码面**按宽度铺满**
(`min(可用宽度 - 静区, 300)`,下限 200 只防极窄约束撑破纸面),而不是钉一个 216。
再不够的下一根杠杆是**丢掉线路名**(照 `routeNameFor` 从主机名推),约能省一个版本,
但那要改载荷格式,不在这轮里。

### 三、应用:落点是 `AppState.connect`,不新开写路径

`connect()` 已经把「发 id、写密钥库 + 写 prefs、换台时清 server-scoped 状态、建 source、
测速」做齐了 —— 旁边再开一条写路径,就是把 `_resetServerScopedState` 要防的那类 bug
重写一遍。三种情况三种说法:

| 情况 | 行为 |
| --- | --- |
| 还没连 + 载荷**带**密码 | 直接 `connect` → `loadLibrary` → 回上一页 |
| 已经连着 + 载荷**带**密码 | 弹一句「替换当前的服务器?」(它会清掉本机曲库快照与缓存)后**替换** |
| 载荷**不带**密码 | 落到录入表单,除密码以外全部预填,主按钮写「填上密码」 |

- **不带密码那条路一个字节都不写盘**:含密码的 `saveServer` 才让 `main.dart` 眼里的
  `configured` 成立,所以那条路重启前一直是「未配置」,**不存在半配置状态**。
  这一点写明白,免得以后有人「顺手」补一个不带密码的 `saveServer`。
- 「填上密码」那颗键此刻是**暗的**(`_canSubmit` 要求密码非空),所以那颗键与那句
  「已从扫码内容填入,只差密码」必须一起说清 —— 只给暗键,用户会以为这一屏卡住了。
- **预填走路由参数,不塞 `AppState`**:`ServersArgs` 是个 record,`generate` 里
  `args is ServersArgs` 认不出就退回 `args == true` —— 老的五个调用点一行都不必改。
  放状态层的话它会跨任意导航活下来,「谁来清掉它」就成了没人说得清的问题。
- **`ServersScreen` 那侧最容易写错的一处**:表单只有一个地址框,而 `_connect` 原先按
  「新建就一条 / 否则合回现有」造线路 —— 一份 3 条线路的载荷会被**静默丢掉 2 条**。
  加了 `_importedRoutes`:表单那条地址替换**第一条**,其余连 id 与锁定原样提交
  (复用现成的 `mergeEditedRoute`,不另发明一套);按「取消」时连同 `_creatingNew`
  一起清掉。这条有专门用例钉住(三条线路提交后一条不少,第一条被表单里那条地址替换)。
- 出口只有设置页那一处(「扫码同步」+「导出配置」),两行放在一起才读得懂 ——
  放两处必然与设计板漂移。「导出配置」那一行**只在已连接时渲染**:`_SettingRow` 没有
  禁用态,一颗 `onTap: null` 的行既不置灰也不回弹,读起来就是个坏按钮。

### 四、能力降级:没有摄像头,一样能同步

- `lib/data/scan_capability.dart` 是一个**能力判断**,不是安全判断:
  `!kIsWeb && (android || iOS)`。两个条件必须一起看 —— 只看 `defaultTargetPlatform`
  的话,**安卓上的 Chrome** 会被当成安卓(它报的就是 `TargetPlatform.android`),
  于是网页上会把摄像头那一支建起来。
- **两层,缺一不可**:静态门决定 `MobileScanner` **是否被构造**;运行时再兜一层
  (权限被拒 / 没有摄像头 / `MissingPluginException` / `UnimplementedError`)
  → 切回粘贴并说明,给一句「摄像头起不来(可能是没给权限)」。捕获用**裸 `catch`**
  (`UnimplementedError` 是 `Error` 不是 `Exception`)。
- Android 清单里补 `CAMERA` 权限与 `hardware.camera required="false"` —— 没有摄像头的
  设备不该被拦在安装之外,它退到粘贴。**没加 `permission_handler`**:插件自己申请。
- 桌面必然降级:`mobile_scanner` 声明的平台只有 android / ios / macos / web。
  `tool/build.sh windows` 已验它**不干扰 Windows 构建**(与 `just_audio_windows` 同一条道理)。
- **web 产物不许有运行时 CDN 依赖**:`kIsWeb ⇒ isSupported == false`,摄像头那一支在
  web 上从不被构造,那个包要的动态取脚本的路也就从不被走到;`build.sh` 的
  `standardize_web` 再加第 5 条守卫(产物里出现那两家的域名 / `@zxing` 就 return 1),
  `web/index.html` 里记一句为什么。

> **守卫自己误报了一次,记这儿**:守卫是 `grep` 字面量的,而我在 `index.html` 的注释里
> 把那几个域名**写了出来**(「别往这里加 unpkg 的 @zxing」)—— 于是 `tool/build.sh web`
> 当场失败,而失败的是守卫自己认出了那段说明。现在那段注释改成不提域名、只指路
> (「那几个字面量写在 `build.sh` 的 standardize_web 第 5 条里」)。**写注释时留意:
> 这条守卫扫的是产物,而产物里包含 `index.html` 的注释。**
>
> 同一趟还把注释里一条**假设**改成了实测:原先写着「`main.dart.js` 里必然有那几个地址
> (库源码里就写着,所以刻意排除它)」。真去 grep 了产物:**一处都没有**(树摇摇掉了)。
> 也就是说那条排除今天什么都没遮住;留着是给将来某版不再摇掉它时防误报,不是遮了什么。

### 五、护栏与测试

新增 `scan_capability_test` / `sync_screen_test` / `config_export_sheet_test`;改
`app_test`(`/sync` 走滑入 + record 穿得过 `generate`、老 `bool` 兜底还在)、
`home_screen_test`(未连接空态两颗入口)、`servers_screen_test`(预填 + 多线路)、
`settings_screen_test`(两行新入口,导出那行只在已连接时在)。

两个测试基建收成共享文件,都值得单独说一句:

- `test/ui/memory_credentials.dart`:`connect` 第一句就是往系统密钥库写密码,而
  `flutter_test` 里没有那个通道(`MissingPluginException`)。换成内存实现,生产代码
  零改动 —— 而且这里要钉的本来就是「密码被存下了、存的是那一个」,不是「安卓的 keystore 能用」。
- `test/ui/pump_real_io.dart`:**点击触发的那一串真 I/O 塞不进 `runAsync`**
  (回调建在假时钟里,它的每段后续也在假时钟里排队),只能「让出一次 + 清一次微任务」
  一个回合推进一步。末尾用**有界的 pump**而不是 `pumpAndSettle` —— 那一串跑着时界面上
  可能挂着转圈的加载态,`pumpAndSettle` 会一路推到假的十分钟再报
  「pumpAndSettle timed out」,读起来像是这里出了问题。

**两条测试的临时目录可能删不干净**:`connect` 收尾那次库快照的写还悬在真实事件循环上,
Windows 上那个 `library.json.tmp` 于是占着句柄 —— `tearDown` 改成尽力而为,文件里写了
为什么。这是假时钟的产物,不是产品行为。

### 版本与提交

版本 1.0.38+39 → 1.0.39+40(这一轮只 +1 一次)。四个提交:

1. 原型:扫码同步(导入一屏 + 导出弹层 + 未连接空态 + 26 格设计板 + `syncsync.cjs`);
2. 数据:配置传输载荷(编解码 + 地址规范化 + 单测);
3. 界面:扫码同步(导入 / 导出 + 能力降级 + 相机权限 + web 守卫 + 测试);
4. 界面:导出那张纸的码面按宽度铺满(实测模块数说话)。

验证:`flutter analyze` 干净;`flutter test` 376 passed / 16 skipped / 0 failed;
标点守卫 0 处;原型 36 条全绿;三个产物都出得来(定版之后都按 1.0.39+40 重出过一遍):
`build/dist/Nordic-1.0.39+40-release.apk`(签名有效、包名 fun.han1997.nordic)、
`Nordic-1.0.39+40-windows-x64.zip`、`Nordic-1.0.39+40-web.zip`(第 5 条守卫通过)。

### 这一轮没验到的(只有人或真机能看)

1. **摄像头到底扫不扫得动** —— 这是整个功能的核心假设,CI 里测不了。要拿真机走三档:
   1 条线路(61 模块)→ 3 条普通线路(81)→ 4 条长主机名(105)→ 再带密码(109),
   看从**多远**、以及**多大载荷开始扫不动**。真到扫不动的下一根杠杆是丢掉线路名。
2. **拒绝相机权限之后**是不是**落到粘贴**而不是死屏 —— 代码里那条兜底路(widget 的
   `errorBuilder` → 下一帧切模式)只有真机能触发。
3. **安卓上的 Chrome 打开 web 产物直接是粘贴模式** —— 这是 `kIsWeb` 与平台两个条件
   一起看的现场验证,测试里验的是 `ScanCapability` 的取值,不是浏览器里的实际表现。
4. **web 产物的 Network 面板**:从**根**起静态服务器打开,确认没有对那两家 CDN 的请求
   (守卫只保证产物里没有那些字面量,不保证运行时不去别处取)。
5. **Windows 上导出那张纸的二维码画得出来、扫得动** —— 构建过得去,画面没人看过。

## 第十六轮(2026-10-19):全面性能打磨

用户原话:「全面性能打磨」,随后补了一句**「只是希望你做性能的优化,看看还有没有地方能有
更快,更省资源,不一定是现在还有卡顿的地方」** —— 于是这一轮的判据不是「哪里卡」,
而是「哪里在白干活」。做法是先做一次只读勘察(界面渲染 / 状态与播放 / IO 与启动三路),
把每一处指到 `文件:行号`,再逐条改并配护栏。

**这一轮不改外观**,所以 `prototype/` 一个字节没动。三条会改外观的线索(专辑网格封面的
38px 投影、搜索页三颗玻璃胶囊、歌词换行的逐帧动画)用户明确说**这一轮不动** ——
代码上看它们都不太像元凶(网格卡片自带重绘边界、胶囊在不滚动的头部、歌词只动两行),
没数据就改设计是拿外观换没影的收益。

### 一、先量了一把(真机 profile,provisional)

在真机上(OnePlus PKJ110,120Hz)`flutter run --profile` 跑了一遍,用一个只受
`--dart-define=NORDIC_FRAME_LOG=1` 控制、每 60 帧打一行 `FrameTiming` 的临时探针
(测完已删,`main.dart` 与 HEAD 逐字节一致)。手滑首页约 40 秒:

- **build** p50 0.2–0.7ms,p90 ≤1.0ms,max ≤6.3ms;
- **raster** p50 1.2–1.7ms,p90 最高 9.3ms,max 出现过 20ms —— 快甩那几帧偶尔越过
  16.7ms(这台是 120Hz,预算其实只有 8.3ms)。

结论有两层:这台机器上首页滚动**并没有到「卡」的地步**(这也是为什么这一轮的重心放在
「白干活」而不是「抠帧」);而 raster 比 build 高一个量级,说明**重绘范围**那条线
(下一节)确实有东西可收 —— 换台慢一档的机器,这一头就是先崩的那一头。

另外量了一次冷启动的库快照解析(`LibraryCache.read`:文件读 + `jsonDecode` + 逐条映射),
在同一台机器的 `dart test`(JIT,不是 AOT)下:**1000 首 65ms · 5000 首 174ms ·
20000 首 616ms**。见下面「没做的」那节。

### 二、重建范围:切歌、下载进度跳动不再重建整屏

`AppState` 把下载进度(最多每秒四次)与缓存淘汰**原样转发**给全应用,而
`PlaybackController` 的通知又覆盖切歌 / 缓冲翻转 / 时长上报。首页与音乐库之前已经收窄过
(有一组用例钉着),但**漏了一批**:

- **音乐库**(`library_screen.dart`)是 `IndexedStack` **保活**的常驻 tab,原先整份
  `watch<PlaybackController>()`:play/pause、切歌、缓冲、时长上报都在重建整屏 ——
  含离屏的四百多格专辑网格 delegate。现在只订阅它真正读到的两件:「当前是哪一首」
  (给歌曲行高亮)与「在不在播」;动作那一侧走 `read`。
- **搜索页 / 专辑页 / 艺人页 / 歌单页**同一类:高亮只要那两件。
- **设置页**整屏 `watch<AppState>` —— 它只显示 `autoRoute / backgroundPlay / server /
  wifiOnlyDownload / downloads(条数)/ activeDownloadCount` 这几件。收窄时有个坑
  值得记:**收的是「算好的标量」而不是 `downloads` 那整条列表** —— 下载进度每跳一次
  都会换掉列表里的 job 对象,收整条等于白收。主题与缓存两块各自 `select` 自己那几件。
- **队列面板**对 `AppState` 的全部用处只有「仓库」(拼封面地址);**播放坞**只跟
  `song` / `playing` 走;**首页氛围层**只跟当前曲目的 `albumId` 走(它只用来取色)。
- 顺手把队列面板里那份与 `coverAlbumUri` 同义的 `_coverUri` 收掉(仓库里已有
  `albumCoverUri`)。

护栏:扩充 `test/ui/rebuild_scope_test.dart`,补上原先**没有护栏的两条轴** ——
「播放状态」这条轴(时长上报 / 暂停**不该**重建音乐库那屏、换歌**必须**跟着变)与
「设置页 / 队列面板」(下载进度跳动不重建,而订阅的那件变了照样要重建)。
两条反方向的断言都验过「去掉改动就变红」。

### 三、重绘范围:首页那张播放卡

`_NowPlayingCard` 挂在 `SliverToBoxAdapter` 上,而**那个位置不带重绘边界** ——
sliver 默认发的边界只给 `SliverList` / `SliverGrid` 的子项。于是卡上那笔 44px 模糊投影、
两层渐变、以及里面那张 38px 投影的封面,**跟着每一次上下滚动重画一遍**(货架里的卡片
反而自带边界,一直是干净的)。现在整张卡垫一层 `RepaintBoundary`;卡里那条**每秒变
好几次**的位置文字再单独垫一层,不然位置每跳一次数字就把整张卡重绘一遍。

护栏放在 `test/ui/home_screen_test.dart`,判据用**渲染树**:从锚点往上找最近那层
`RenderRepaintBoundary`,它必须存在、且长在 `RenderViewport` **里面**(跑到滚动视图外面
就等于没隔)。验过:去掉里面那层,断言当场变红。

### 四、播放装载路径:整队拼源不再反复问盘

「播放全部 / 随机播整库」按下去那一帧,原本有几件白做的事:

- `_sourceFor`(每首歌)要问一遍盘:`cachedPathFor` 一次 `existsSync`,`completeCopyAmong`
  最多三档各两次;`playbackOriginFor` 又对**同一个** cachedPath 重复 stat 一次。
  一千首的队列就是几千次**同步** stat,全压在那一帧的 UI 线程上。现在 `MediaCache`
  加了一层「这个路径上有没有文件」的备忘录,`playbackOriginFor` 收一个**可选的存在性
  判据**接过去(缺省仍是真身 `File.existsSync`,判据本身一字不改 —— 「坏文件 / 被删掉的
  文件回退网络」那两条护栏一个字没动)。
- 每首歌造了**两个** `MediaItem`(`setQueue` 一份给队列与通知栏,`_sourceFor` 里又算
  一份当 tag)。现在一份两用。
- `reorder` 原本把整队播放源重拼一遍、再从 0 装载 seek 回去 —— 正在听的那一份(位置、
  缓冲、边听边写的那半截缓存)全作废。改成 `moveAudioSource` 就地挪一位(它与
  `insert(removeAt())` 的下标语义逐字相同),当前这一份不动。

备忘录有三条不能碰的线,都写进了 `docs/performance.md` 与代码注释:**只记缓存目录里的
路径**(下载那份在 `Nordic/Music`,可能被用户在系统里删掉,必须每次真查);
**只记「在不在」,不记「完不完整」**(半截 `.part` 是 just_audio 自己造自己改名的,
那条路我们插不上手 —— 第一版就是记了「完整」这一位,被一条既有用例当场抓住);
**`isComplete` 连「在不在」也不记**(它是「半截写完了没有」的轮询路)。失效点收在
`fileFor` / 删除 / `clear` / 调额度 / 扫目录(清完立即回填)与**换歌**(把窗口压到
一首歌以内)。

护栏:缓存侧新增一组(正负命中 / 写入位作废 / 目录外真查 / `isComplete` 真查),
**都用计数探针** —— 行为面那几条用例分不出 1 次和 5 次;播放侧新增一组(每首一个
`MediaItem` / 重排不走整队重装 / 换档仍须整队重装 / 同一批歌同一档再装一遍一次盘都不查)。

### 五、歌词落盘:从「每存一首整份重写」改成合并写

原先每存一首歌词就把**累积的全部歌词**重新编码一遍、整份重写一遍(还带 `flush`):
第一首是一首的活,第 N 首就是 N 首的活 —— 听过的歌越多,每存一首越贵,合起来是平方级的。
同一件事第三轮已经给音乐库快照治过,歌词这份没跟上。现在:

- 落盘改**合并写**(写者每跑一轮重读当前的 `_lyricsDisk`,只保证「最新那一版最终落盘」);
  落盘走临时文件 + 改名(写到一半被杀掉不会留下半截 JSON)。
- 每次读 / 写都要解析一遍的缓存目录**记住**(原先每存一首都走一遍
  `getApplicationSupportDirectory()` 平台通道加一次 `existsSync`)。
- 内存与磁盘两份各加**上限 512**(按插入顺序淘汰,命中时挪到队尾 —— 常听的那几首留得住;
  盘上历史遗留的超额条目在读回时一起收掉)。
- `_resetServerScopedState` 里**先等写盘落地再删文件**:不管飘着的那一趟,它会把你刚删掉
  的文件又写回来。

「磁盘那份还没读进来就不写」这条老护栏**一字未动**(`_lyricsDiskLoaded` 仍是先决条件,
合并写只从 `_saveLyricsDisk` 触发,所以「拿空表写回盘」那条路从入口就堵着)。

护栏:新增「歌词的磁盘缓存」一组,判据是**落盘跑了几趟**(只给用例看的计数器;
行为面那几条用例分不出 1 趟和 12 趟),外加并发两首谁也不丢、换实例读得回来、
移除服务器之后文件不再被写回来(这一条也验过:去掉 settle 就变红)。

### 六、重复的请求与重算

- **搜索**:走 `search3`(打服务器)。「删一个字再打回来」是最常见的改字方式,而那样会为
  同一个词再问一遍 —— 服务器白跑一趟、用户白等一次往返。现在留一张小表(最近 8 个词)。
  只记「上一次」是不够的:`ab → a → ab` 中间那次会把它顶掉(第一版就是单条,被新写的
  用例当场抓住)。护栏:`test/ui/search_screen_test.dart`,判据是**发了几次请求**。
- **导出那张二维码**:原先在 `build` 里现编(纠错码 + 建矩阵),而父级每一次重建
  (切「包含密码」、软键盘 inset 变化)都会把同一串载荷重编一遍 —— `QrView` 改成有状态的,
  按载荷记一份;载荷本身也按它那三样输入记一份。
- 顺手删掉 `PlaybackController.queueDuration`(全仓无调用)。

### 七、量过 / 看过,**没做**的(以及为什么)

1. **冷启动的库快照解析不挪 isolate。** 量下来(见第一节)常见库是几十毫秒级,而代价不小:
   契约要求它在 `runApp` **之前**完成,挪走并不缩短总时长;返回值要跨 isolate 深拷贝回
   主 isolate(几千个域对象),收益被吃掉一半;web 上 `Isolate.run` 不可用、`compute`
   退化为同步(多出一条只有 web 不同的路);而且将来任何 `testWidgets`(假时钟)走到它都会
   挂死。**门槛定在 100ms**:真出现上万首的库、且真机 profile 量出来超过它,再回来做。
2. **`recentlyAddedSongsOf` 的「排全量只取 20」没改。** 看着可以换有界选取,但 Dart 的
   `List.sort` **不稳定**,有界选取在「同一次入库的几十首」上会排出与现在不同的顺序 ——
   那是**看得见的行为变化**,换来的只是「后台每补一页省一次排序」(几毫秒)。不值。
3. **`activeRoute` 每个地址重排一次线路表没加备忘录。** 线路通常 1–4 条,一次排序是
   微秒级;而备忘录的失效面是「线路 / 测速 / 锁定 / 自动择优」四件,收益与风险不成比例。
4. **设置页那几个偏好读没加内存缓存。** `configStore.loadX()` 落在 `SharedPreferences`
   的内存 map 上,是一次哈希查找;给它们加缓存要背上「每条写路径都得同步」的负担
   (`themeModeName` 那份缓存有它的理由 —— 它被根部的 `select` 盯着 —— 但其余几件不是)。
5. **`Song`/`Album` 的 `fromJson` 没抠分配。** 省下来是个位数百分比,而那是冷启动路径上
   最容易被改错的一段。
6. **下载管理那一屏的「整块 Column」没拆成懒加载。** 那是**外观**问题(整块套在一个圆角
   边框里),要动得先改原型 —— 这一轮不改外观。
7. **`PlaybackController` 一次切歌连发多次通知没合并。** 合并到一帧会改变通知时序,
   而收益只是几次重建 —— 风险大于收益。
8. **长列表没加 `itemExtent` / `prototypeItem`。** 行高用的是 `minHeight`(要跟系统字号
   一起长),`itemExtent` 写死会把字裁掉。
9. **首页 `select` 里那句 `downloads.any(isDone)` 没换成派生状态。** 它是 O(下载条数)
   的线性扫描,通知频率下也就几十次比较 —— 为它加一份「派生 bool」是纯记账负担。

### 版本与提交

版本 1.0.39+40 → 1.0.40+41(这一轮只 +1 一次)。四个提交:

1. 界面:收窄重建与重绘范围,并把范围钉进用例;
2. 播放:整队拼源不再反复问盘,重排也不再重建整队;
3. 状态:歌词落盘改合并写,内存那份也有了上限;
4. 界面:搜索同一个词不再重复打服务器,二维码与导出载荷各记一份。

验证:`flutter analyze` 干净;`flutter test` **393 passed / 16 skipped / 0 failed**;
标点守卫 0 处;真机 profile 前后各跑过一遍(第一节)。

### 这一轮没验到的(只有人或真机能看)

1. **手感**。这一轮量的是「白干活少了没有」,不是「顺不顺」—— 首页滑动的跟手程度、
   点「播放全部」那一帧的反应,只有真机上人才判得了。这一版**试**的成分在这儿:
   光栅那一头的改动(第三节)在这台机器上本来就没到卡的阈值。
2. **换台慢一档的机器是否看得出差别**。收掉的那些活(几千次同步 stat、每次滚动的
   重绘、O(n²) 的歌词重写)在旗舰机上都不显眼,它们的价值要到中低端机或大库上才露出来。
3. **`reorder` 改成 `moveAudioSource` 之后的行为**:拖队列面板的位置对不对、正在放的
   那一首断没断、缓冲是否真的保住 —— 单测用假播放器钉住了「没有整队重装」,但平台的
   真实行为(尤其「边听边写缓存」那一半)只有真机能看。
4. **缓存存在性备忘录的失效时机**,最要紧的是**「半截写完之后切到本机文件」**那一下
   (`_waitForLocalCopy`):真机上听一首没听过的歌、听完之后往回拖进度条,看它是否真的
   从流切到了本机文件。
5. **歌词缓存的合并写**在真机上的表现:连着翻十几首歌词、再重启看是不是都还在;
   以及「移除服务器」之后那份文件确实没了。

## 第十七轮(2026-10-19):歌词跳转加一层确认

### 一、要治的是「手一滑就跳走了」

歌词页点任何一句都会**立刻 seek**(`_seekToLine` → `PlaybackController.seek`)。跳转不可逆:
手指划过一行、点错相邻那句、或者只是想看清某句,歌就跳到别处了,而且**原来听到哪儿也回不去**。
这一轮给它加一层确认:**第一下只选中那一句,同一句再点一下才跳**。

形态与频率是用户当场定的(问过,不是我们替他挑的):

- **行内两次点击**,不弹层。理由是弹层会盖住歌词,而「跳到这一句」恰恰要看着那一句确认;
  何况这本来就是个一次点击的动作,为它开一层弹窗是重武器。
- **每次都问**:不做「短时间内免问」,也不做「跳得远才问」—— 行为可预期比省几下更要紧。

顺带定死的边界:点**别的行** = 改选(不跳);点**行以外的空白** = 照旧回封面,选中的那一句
随页面一起没(不新增「先取消选中再退」那一层模式);跳不到的行**连选中都不给**。

### 二、原型(`prototype/`):行尾那枚胶囊

- `STATE.pendingLine`(-1 = 没选中),`go` / `back` / 换歌三处清掉 —— 这层确认只在一趟里算数。
- `screenLyrics()`:行内多了 `.sel` 与一颗 `跳到这句 · 2:30` 的胶囊,时间用**已有**的
  `mmss()`,落点仍是原来那套「取那一行中段」的算式(没有另写一套)。
- `click` 里那个 `data-seek-line` 分支改成两段式:第一下 `pendingLine = i`,同一行再来一下
  才写 `elapsed` 并清掉;点别的行只是改 `pendingLine`。
- `styles.css`:`.lyric-line` 从一块文字改成横排(文字包一层 `.txt`,长句照旧换行),
  新增 `.jump-chip` —— **高 26px,必须 ≤ 文字盒高(22 × 1.4 ≈ 30.8)**,不然选中一下就把
  整行顶高、整列往下推;选中行让那一撮辉光给胶囊腾地方(一行右缘只放一个东西)。
- 设计板那一格副标题改成「逐句高亮 · 两下才跳」。

自检脚本 `.tmp-shots/lyricconfirm.cjs`:第一下不跳且行高不变、改选只留一颗胶囊、第二下才跳
且高亮落过去、点空白回封面不跳,控制台零报错。(原型里还给胶囊写过一版 0.18s 滑入,
应用这边要做同样的过渡得让那枚胶囊一直留在树里,不划算 —— 两边以「直接出现」为准,
原型那条 `@keyframes` 去掉了。)

### 三、应用(`lyrics_screen.dart`):选中态也走 `ValueNotifier`

- `_pendingLine` 与 `_activeLine` 同一个理由**不进 `setState`**:选中一行真正变的只有两行,
  走整屏重建就是顶栏 + 上百行歌词 + 满屏氛围,而这次动作**本来就要点两下**。
- `_seekToLine` 改名 `_onLineTap`:算得出落点才接这一下;没选中就选中,已选中同一句才 `seek`。
- 胶囊**自绘,不复用 `PillButton`**:那个固定 36px 高,塞进 30.8px 的文字盒就是把整行顶高。
- 落点在 `_LyricsList` 里逐行算一份(胶囊要报「跳到哪儿」),只在整屏重建时算,不是每次点。
- 换歌 / 歌词重载时与高亮一起清掉选中。

### 四、护栏与测试

`test/ui/lyrics_screen_test.dart` 八条:两条改写(两下才跳、行距上那两下也算)、两条新增
(改选、**没有时间轴且时长未知时点哪一句都不接**)、其余四条照旧。

**记一笔,免得下次又白写一条用例**:`seekTargetForLine` 里那条「整份有时间轴、偏偏这一句
缺 `start`」的分支,从服务器来的歌词**永远走不到** —— mapper 一遇到缺 `start` 的行就把整份
标成 `synced: false`(`subsonic_mapper.dart:120` 的 `lines.every((l) => l.isSynced)`),
于是落到「按时长摊行」那条路上去。真正能走到的 `null` 只剩「无时间轴 + 时长还不知道」,
用例是照它写的。

### 版本与提交

版本 1.0.40+41 → 1.0.41+42。一个提交,信息里原型与应用各改了什么分开写。

验证:`flutter analyze` 干净;`flutter test` **396 passed / 16 skipped / 0 failed**(跳过的
是打真服务器那几组);标点守卫 0 处(`tool/fullwidth_punct.py` 顺手改掉 17 处)。

### 这一轮没验到的(只有人或真机能看)

1. **两次点击会不会嫌烦**。这一条是**手感**,只有真机上人才判得了 —— 尤其「想跳一句」
   本来就是随手一下的动作,多出来的那一下是保护还是负担,得用了才知道。
2. **长句上胶囊挤出的换行**。胶囊占掉行尾那一段,极长的句子在选中时可能多折一行
   (行高**不变**那一条只对不折行的句子量过)。
3. **点空白即退出**在有选中时够不够顺手:现在空白那一下既清选中又回封面,没做「先取消、
   再退」的两段式。觉得别扭的话,把它改成两段是一行的事。

---

## 第十八轮(2026-10-19):歌曲信息 / 播放页信息行 / 定位正在播放 / 设置整理

四件事一起做,它们其实是同一件事的四面:**听的时候看不到「在听的是什么、按什么在放」,
找的时候回不到「正在放的那一首」,设置里也没有一个说清楚「这是什么软件」的地方。**
形态(入口开在哪儿、徽标报什么、整理到哪一步)是用户选定的,不是我们替他挑的。

### 一、歌曲信息:一张只写真的纸

`Song` 上早就有格式 / 码率 / 体积 / 年份 / 流派 / 入库时间(`subsonic_mapper` 一直在进),
但界面上只有专辑页 / 艺人页曲目行里那句 `FLAC · 780 kbps` 露过脸。这一轮把它收进
**歌曲「⋯」菜单里的一条「歌曲信息」** —— 播放页 / 艺人页 / 歌单页 / 歌词页四处共用一份
菜单,加一条四处同时生效,不单开顶栏图标。

- **缺哪一项就整行不印**(`song_info_sheet.dart`):服务器确实可能不给年份 / 流派 /
  入库时间,写一行「未知」是拿假东西凑数,比没有更糟。用例两头都钉着(字段齐的全在、
  没给的一行不出现)。
- **「实际播放」那一行只对正在放的那一首才有**:别的曲子不在现场,播放层答不出
  「它现在按什么在放」,那就不印 —— 不猜。
- 底部两条去路(查看专辑 / 查看艺人);库里没有这位艺人时不给「查看艺人」那一行,
  不假装能点。

### 二、播放页那一行:源文件的格式 + 这一趟**实际**用的档位

转码档位原先在底部有一颗常驻胶囊,上一轮收进「⋯」菜单之后,**「现在到底按哪一档在放、
是不是在放本机那一份」在界面上彻底看不见了** —— 只看得到设置里那个「默认档位」。现在
歌名 / 艺人 · 专辑下面多一行:左边 `FLAC · 780 kbps`(歌曲自己),右边一枚胶囊报
**这一趟实际用的那一份**,点它直接开转码面板。

- 文案三选一(`quality.dart` 的 `playbackOriginLabel`):**本机**(放的是本机那份,不花流量)/
  **直出**(原音、没过编码器)/ **转码**(过了一道)。三个词说的是三件不同的事。
- 报的是**装载那一刻**那一份,不是「磁盘上此刻有没有」(`audio_handler.loadedOriginOf`)——
  边上边缓存的那份会在播到一半时下完,而播放源没换过。本机要是有更高一档的完整缓存,
  播放层本来就会直接拿它播,那时报的也该是更高的那一档。
- **查不到就只报档位**(null),不猜来源:这句话是用户拿来判断「花不花流量」的。
- 刷新挂在 `PlaybackController._emit` 上(每次状态播报顺手重读一遍),所以换档 /
  换线路 / 切歌三处装载都跟得上;**别改成只在切歌时读** —— 换档恰好是用户盯着它看的时刻,
  而它会停在旧档上。

### 三、音乐库「回到正在播放」

「全部歌曲」可能上千行,而在别处(专辑 / 歌单 / 随机)播起来的那首没有任何办法滚到它那一行。
现在歌曲栏顶栏多一颗定位图标(**没有在播的歌时整颗不出现**,禁用态在这里读起来像坏按钮),
点一下:切到歌曲栏 → 滚到那一行 → 那一行亮一下(1.2 秒后自己灭掉,不留「选中」的错觉)。

钉住的三条:

- **列表必须保持懒加载**。不能像歌词页那样给每行挂 `GlobalKey` 等它们都建出来 ——
  几千行全建出来正是 `docs/performance.md` 第一条要治的。走法是**估一步 + 框架对齐**:
  先按「列表自己报出来的总高度除项数」(= 已建行的平均高度)`jumpTo`,再对那一行的
  `currentContext` 用 `Scrollable.ensureVisible` 按真实布局对齐。**别写死 64** ——
  行高是 `minHeight`,系统字号一放大每行都长高,上千行的库里落点会差出一整屏;
  **也别给 `ListView` 加 `itemExtent`** —— 那等于把行高钉死,大字体会被裁。
- **那一首可能还没取回来**。库里是一页页取的,播的那首完全可能落在还没取到的那些页里 ——
  那就先接着取(封顶四页),取到了再滚;取完还是没有,**如实说一句**,不假装跳过去了。
- **只让那一行亮**:走 `ValueNotifier` + 只包住那一行的 `AnimatedContainer`,不进 `setState`
  —— 这一屏背后挂着四百多张专辑的网格,而这次动作真正变的只有一行。

### 四、设置整理 + 关于软件

- **缓存 + 下载合成一栏「存储」。** 它们回答的是同一个问题——「盘上有什么」,摆在一起
  才看得出「清缓存」清掉的是哪一半(下载不受影响)。「仅 Wi-Fi 下载」原先挂在**播放**那一栏,
  它管的是下载,跟着一起搬。「隐私」那一栏删掉:那两条是**陈述不是开关**,移到关于页。
- **「关于」新屏**(`about_screen.dart`,像别的二级页一样推入):图标 + 名字 + 版本 +
  「默认转码质量」+ 服务器那行(点进服务器页)+ 开源许可(Flutter 自带那一页,不是自己画的)
  + 那两条隐私陈述。这一屏只写真的:读不到的东西印 `—`,不写死一个版本号。
- **版本号从装上那个包里读**(`package_info_plus`):它读出的就是 `pubspec.yaml` 那一行落进
  包里的结果,不是第二份真值。顺带一条环境记录:8.x 与 `flutter_secure_storage_windows`
  要的 `win32 ^6` 冲突,解析不过;`^10.2.2` 才解得开。
- 「关于」页上那颗图标引的是 `web/icons/Icon-512.png` —— 它是 `tool/app_icon.py` 的产物之一,
  与 Android 那五档 mipmap 同一次生成,所以不另存一份图形(`pubspec.yaml` 的 assets 里写着)。
- 设置页那次改动收窄了 `_SettingsView`(下载进度那几件搬进 `_StorageSection` 自己 `select`):
  那一屏的订阅面按**值**比较,而下载进度最多每秒播报四次 —— 收成整条列表等于白收。

### 五、原型(`prototype/`)

- `sheetSongInfo()` 新弹层 + 「⋯」菜单里那条;`SONGS` 补 `sizeMB / year / genre / added`
  (都是服务器真会给的字段)。
- 播放页 `.p-meta`(`.p-fmt` + `.q-badge`);原型里「本机」那一态由**下载队列**派生 ——
  下载过的那一首就演这一态,设计板上两种都看得到。
- 音乐库顶栏那颗定位 + `.row.located` 的亮。**亮走 `STATE.locateAt` 而不是往 DOM 加 class**:
  下载计时器每 1.2 秒整屏重绘一次,直接加的 class 会被抹掉,高亮没亮完就没了。
- 设置:缓存 / 下载 → 存储,隐私 → 关于;`screenAbout()` 新屏进 `VIEWS` 与 `BOARD`。
- 自检 `.tmp-shots/infolocate.cjs`:定位(点一下滚到那一行、1.2 秒后自己灭掉、别的栏没有
  这颗)、播放页信息行(格式 + 档位,点徽标开转码面板)、歌曲信息八个字段、设置五栏、
  关于页三件 —— 全过,控制台零报错。顺带记一条坑:关弹层**不能点 `.sheet-scrim` 的中心**
  (那里正好是那张纸本身,事件目标不是遮罩),要点遮罩最上边那一条。

### 六、护栏与测试

- 新增 `test/ui/song_info_sheet_test.dart`(7 条)、`about_screen_test.dart`(4 条)、
  `library_screen_test.dart`(4 条);`player_screen_test.dart` 加 3 条(信息行 / 不知道
  来源时只报档位 / 点徽标开面板),`settings_screen_test.dart` 加 2 条(存储栏、「关于」那行)。
  合计 **416 passed / 16 skipped / 0 failed**。
- 替身播放层(`fake_playback.dart`)多两件:`loadedQuality` / `loadedLocal`(两种情形都要验)、
  以及一份 `song` 为 null 的 `idleController()`。
- 全角标点:`tool/fullwidth_punct.py` 改掉 32 处(新写的文案 + 新用例的描述)。
- 一条用例的调整:设置页「点开歌曲缓存」补了 `ensureVisible` —— 合并成「存储」之后那一行
  离屏幕下沿更近,**半截在屏幕上时点击会落空**(点了没反应、不报错),下一条用例的注释里
  本来就记着这个坑。

### 版本与提交

版本 1.0.41+42 → 1.0.42+43。一个提交,信息里原型与应用各改了什么分开写。

验证:`flutter analyze` 干净;`flutter test` **416 passed / 16 skipped / 0 failed**
(跳过的是打真服务器那几组);原型自检脚本全过、控制台零报错。

### 这一轮没验到的(只有人或真机能看)

1. **信息弹层读起来累不累**。八个字段一次铺开,是否该分两段、或者把「实际播放」提到最前,
   得盯着真机看才知道。
2. **播放页多那一行挤不挤**。窄屏 / 分屏 / 系统字号拉大三种情形下,封面被压掉多少 ——
   用例只保证了不溢出。
3. **定位那一跳的落点准不准**。估的那一步用的是「已建行的平均高度」,行高随字号变时
   仍有小偏差,靠 `ensureVisible` 找回来;真机上要看是否「一跳到位」而不来回蹭一下。
4. **关于页上那个版本号对不对**。它从包里读,只有真的装上去才知道(模拟器上读的是
   debug 包,构建脚本那条校验管的是产物名与包里的 `versionName`,不是这一页)。

---

## 第十九轮(2026-10-19):档位附注化 / 关于页瘦身 / 蒙版那一下位移 / 播放状态上报服务端

真机走查 + 用户自己看出来的四条。前三条是**改回去**,第四条是**补上从来没做过的**。

### 一、播放页那枚档位:附注,不是按钮

上一轮把它做成了一颗 `NordicChip`(薄玻璃底 + 发丝边 + 全圆角)。用户原话:
「加了按钮和边框,看起来有点丑」。它摆在 `FLAC · 780 kbps` 右边,读起来是一块
**贴上去的控件**,而这一行左边明明是「这首歌的格式」——两半的读法被搅乱了。

现在只剩一枚强调色的小图标(13px)+ 三级前景的小字,没有底、没有边、没有圆角。
**唯一提示「可点」的就是那点颜色**;按下去仍开转码面板,行为一点没变。
原型 `.q-badge` 同步改成这样,自检脚本里补一条**计算样式**的断言
(`border-width == 0`、`background` 透明、圆角 0)——「不是按钮」这件事得用样式钉住,
免得下次又长回一颗胶囊。

### 二、「关于」删掉三行重复的

「版本」(顶部 hero 已经有一份)、「默认转码质量」(设置页第一行就是它)、
「服务器」(设置页那一栏已经能进)——三行都不解释「这是什么软件」,只是重复。
删完这一页只剩:图标 / 名字 / 一句话 / 版本、开源许可一条、隐私两条、仓库地址。
`_InfoRow` 的 `trailing` 参数(只有那一行版本用过)一并去掉,免得留一个永远空着的口子。

### 三、弹层升起时那块「压下来的蒙版」——一个曲线对不上的 bug

`NordicScrim` 里有一层「抵消框架位移」的补偿:路由会把**整块内容**从屏幕下方挪上来,
蒙版在里头于是也跟着走(上半屏最后才暗下来),补偿的作用是把它抵成原地淡入。

**但补偿按错了曲线**:框架 `_BottomSheetLayout` 定位用的是**带缓动的**
`_sheetAnimation`(`Easing.legacyDecelerate`,见 `bottom_sheet.dart:694/628`),
而补偿拿的是路由**线性的** `animation`。两条不等价 → 补偿只抵掉一部分,
净剩 `H[v - curve(v)]` 的位移(中段可达屏高的四分之一)——真机上就是
「**一整块蒙版带着边缘从上方压下来**」。原型 `.sheet-scrim` 只淡入、不位移,
所以这是个 bug,不是设计。

修法是把两边**钉成同一条曲线**:新增 `nordicSheetCurve`(`Easing.legacyDecelerate`),
显式传给 `showModalBottomSheet` 的 `sheetAnimationStyle`(顺带:这个参数在这个
Flutter 版本上叫 `sheetAnimationStyle`,不叫 `animationStyle` —— 文档里那个说法
是给 `BottomSheet` 用的),补偿层改用 `CurveTween` 按同一条求值。

`test/ui/sheet_scrim_test.dart` 逐帧量蒙版的全局矩形:它必须**始终等于整屏**。
把曲线换回线性,这条立刻红(验过)。

### 四、播放状态上报服务端(Subsonic `scrobble`)——原先一处都没有

全仓库**没有任何一处**向服务器报过播放状态:`grep scrobble` 是空的。于是
Navidrome 的「正在播放」恒为空、播放次数永远是 0,而「关于」里那句
「只用于服务器端的播放统计」在接上之前是一句**空话**。

- 接口:`MusicSource.reportPlayback(songId, {submission, at})` —— `submission`
  为 false 是「正在播放」(不计数),true 是「听过一次」。实现只有 `SubsonicRepository`
  一个(`scrobble.view`;`submission` 传字符串,`time` 只在「听过一次」时给,
  且是**那一刻**的墙上时间而不是服务器收到的时间)。
- 判据(`playback/scrobble.dart` 的 `ScrobbleTracker`,纯逻辑、可单测):
  **同一首各只报一次**(队列重排 / 换档重装都会再走一遍装载,不该重复报);
  「听过」的门槛是 **`min(时长的一半, 4 分钟)`**;时长未知(0)时**一条都不报**
  —— 判不出「一半」就别猜。
- 接线在 `audio_handler.dart`:换歌那条播放事件上报「正在播放」(与缓存记账同一刻,
  而不是拼播放源时 —— 一次 `setQueue` 会把整条队列都拼一遍),位置流上报「听过」。
- **失败一律静默**:离线、服务器不可达、对面不认这个端点都不弹错误。代价是
  离线听的那些不计入服务器统计 —— 这与「本机不另存一份播放记录」是同一件事的两面。
- 「关于」里那条隐私陈述改成说**实际行为**:「开播报一次『正在播放』,听够一半报
  一次『听过』—— 只发给服务器,本机不另存」。原型同步。

### 五、原型(`prototype/`)

- `.q-badge` 附注化(见上);`.p-fmt` 加 `min-width: 0`(左边那半可以省,右边不行)。
- `screenAbout()` 删「版本」与「服务器」两行,卡里只剩「开源许可」;「播放记录」
  那句按实际行为改写;设计板那一格的副标题跟着改。
- 自检 `.tmp-shots/infolocate.cjs` 补两条断言(档位那枚的计算样式、关于页少三行),全过。

### 六、测试

- 新增 `test/playback/scrobble_test.dart`(9 条:判据 6 条 + 上报器 3 条)、
  `test/ui/sheet_scrim_test.dart`(3 条)。
- `test/data/write_operations_test.dart` 加 3 条:scrobble 的线上形态
  (`submission=false` 不带 `time`、`true` 带毫秒、`false`/`true` 各走各的)。
- `test/playback/playback_test.dart` 加 3 条**接线**用例:换歌报正在播放 / 听一半报听过 /
  仓库被移除时一条都不发(判据再对,接线漏一处也没人用)。
- `test/ui/player_screen_test.dart`:那条「点档位」改名并加一条「**附注不是按钮**」
  (那颗 Pressable 底下不许有 `DecoratedBox` / `Container`)。
- `test/ui/about_screen_test.dart`:版本那一条改成「只在顶部说一次」,删掉服务器那一条,
  新增「与别处重复的那三行都不在了」。
- 全角标点:`tool/fullwidth_punct.py` 改掉 34 处。

### 版本与提交

版本 1.0.42+43 → 1.0.43+44。一个提交,信息里原型与应用各改了什么分开写。

验证:`flutter analyze` 干净;`flutter test` **435 passed / 16 skipped / 0 failed**;
原型自检全过、控制台零报错。

### 这一轮没验到的(只有人或真机能看)

1. **Navidrome 里真的看得到吗** —— 「正在播放」那一栏与播放次数只有打到真服务器
   才算数;`scrobble` 的形状有用例钉着,但那台机器收不收、多久清一次「正在播放」,
   只有真机上进去看一眼才知道。
2. **档位那行在深色底上的对比度**。fg3 已经退到能读的底线,而那点强调色图标在
   浅色主题下会不会显得脏,得看着真机调。
3. **蒙版那一下的手感**。用例保证的是「矩形逐帧不变」,而人看到的是「淡入得快不快、
   有没有一顿」——这仍然只有真机判得了。

---

## 第二十轮(2026-10-19/20):播放队列同步 / 曲库扫描 / 离线补报

上一轮把播放状态上报接上之后,用户的下一步是**继续把两侧的通讯补齐**。这一轮三件:
队列同步(换设备接着听)、曲库扫描(补上文案里那句承诺)、离线听到的补报。

三件事都**先在用户那台 Navidrome 0.64.2 上探过**再写(见下面各节的「实测」)——
协议口径这种东西,照着文档写容易写得像对的。

### 一、播放队列同步:换设备接着听

`savePlayQueue` / `getPlayQueue`。写与读分开说:

**写**(`playback/play_queue_sync.dart`,由 `PlaybackController` 持有):

- **只写当前曲目前后的一段**(前 49、后 150,总 ≤200)。这是一条 **GET 查询串**,
  几千个 id 拼出来的 URL 会被反向代理挡下(nginx 默认 8KB);而「接着听」本来
  要的也只是这一段。**current 一定落在名单里** —— 服务器按 id 找它。
- 写的三个时刻:**队列变 / 切歌 → 防抖 1.5 秒**(拖动重排会连发好几条通知);
  **播放中每 30 秒**补一次进度;**暂停立刻写**(那一瞬间的位置就是用户松手的地方)。
- 失败静默(与 scrobble 同一条口径)。队列是**状态**,过期的状态补上去反而是错的,
  所以它没有「补报」那一说。

**读**与「问一句」:主壳首帧之后读一次(与拉库同一处),**只在指纹不一样时问** ——
指纹是「条数 + 头一首 + 末一首 + 当前那一首」(`data/play_queue.dart` 的 `queueMark`)。
一样就说明那是**我们自己刚写上去的**那一份,每次都问会很烦。所以每次保存成功都把
指纹记回 `ConfigStore`,而「忽略」也记(他刚说了不要)。「继续」= 装载那份队列 +
摆好落点,**但不出声**(`playAll(..., autoPlay: false)` —— 打开应用自己放起来
很吓人)。

**实测**(这台 Navidrome):`getPlayQueue` 在空队列时**没有 `entry` 键**,
`changed` 是**零时间** `0001-01-01T00:00:00Z`;`savePlayQueue` 的 `id` 重复出现
是**对的**(写完再读,两条 entry、current、position 逐字回来);**不带 `id` 的
`savePlayQueue` 就是把队列清空** —— 所以仓库那一层把空队列拦掉了(本地队列空掉
不该顺手抹掉另一台设备正在听的那一份)。探测写进去的那一份已清回原样。

### 二、曲库扫描:补上文案里那句承诺

应用里**三处空态**早就写着「到设置里重新扫描一次曲库」(首页 / 音乐库 / 搜索),
而设置里根本没有这一条 —— 那三句话一直是一句**空话**。现在有了:

- 设置 →「服务器」那一栏多一行「曲库扫描」,点开是那张纸(`scan_sheet.dart`):
  状态 / 上次扫描 / 曲库首数 + 一颗「开始扫描」。
- **只在纸开着的时候每秒轮询**一次状态,关掉即停 —— 不让它在后台一直打服务器。
  轮询到扫完了把音乐库重取一遍(「扫完就能看见新歌」是这件事的全部意义)。
- **那一行自己不发起请求**:进设置页不该悄悄打一次服务器(它是保活的常驻 tab),
  而没问过时如实说「看看服务器上有没有新加的歌」—— 编一个「未在扫描」是假的。
- `startScan` **要管理员权限**:非管理员会拿到服务器的拒绝,这时**如实转述**那句话
  (Navidrome 回「not authorized」),不假装扫上了。

**实测**:这台服务器回 `scanning` / `count: 522` / `lastScan` 三件;当前账号
`adminRole: true`(所以扫得动 —— 换非管理员账号那条路只能在用例里模拟)。

### 三、离线补报播放记录

上一轮的 scrobble 是「失败一律静默」,于是**断开网络听的这一趟在服务器统计里
完全不存在**。现在发不出去的「听过一次」先落盘(`data/scrobble_store.dart`,
单文件 JSON、上限 200 条丢最老、坏了当空),下次有机会(下一条 scrobble)按时间
顺序补报,**带上听的那一刻**(`time` 参数就是为这件事准备的;不带的话上周离线听
的那几十首会全挤在同一时刻)。

两条边界:**「正在播放」永不入队**(它说的是此刻,补报没有意义);
请求**超时但服务器其实收到了**的话补报会双计(Subsonic 没有幂等键)——
宁可偶尔多一次,也别整趟丢掉。

### 四、原型(`prototype/`)

- 设置 →「服务器」那一栏加「曲库扫描」一行(副标题报状态)+ `sheetScan()` 那张纸。
- `sheetResume()`:「接着上次听?」—— 一句「服务器上还留着一份别的设备留下的队列」
  + 「继续 / 忽略」。设计板另起两格。
- 自检 `.tmp-shots/infolocate.cjs` 补两条(扫描那行与那张纸的字段)。顺带记一个坑:
  设置页靠下的那一行,**光 force 点击不够** —— 它的中心落在视口外,得先在页面里
  `scrollIntoView({block:'center'})` 再点(否则点了没反应、也不报错)。

### 五、测试

- 新增 `test/data/play_queue_test.dart`(13 条:解析的三条形状 / 窗口 / 指纹)、
  `test/playback/play_queue_sync_test.dart`(7 条:防抖、封顶、心跳、暂停立刻写)、
  `test/playback/scrobble_queue_test.dart`(6 条:入队、补报、不入队、上限、坏文件)、
  `test/ui/scan_sheet_test.dart`(3 条)、`test/ui/queue_restore_test.dart`(6 条:
  该不该问四条 + 那张纸两条)。
- `write_operations_test.dart` 加 3 条(savePlayQueue 的重复 id / 空队列拦住 / 扫描两个端点),
  `subsonic_live_test.dart` 加 2 条**打真服务器**的(扫描状态、队列读回来)——
  在现场跑过,两条都过。
- `settings_screen_test.dart` 加 1 条(那一行在,且没问过时说的是「不知道」)。
- 全角标点:`tool/fullwidth_punct.py` 改掉 61 处(含一处把标题里的 `?` 变成 `?` ——
  测试里那半角的一版因此对不上,顺手也被工具改齐了)。

### 版本与提交

版本 1.0.43+44 → 1.0.44+45。一个提交,信息里原型与应用各改了什么分开写。

验证:`flutter analyze` 干净;`flutter test` **474 passed / 18 skipped / 0 failed**
(跳过的含那两条新的 live 用例 —— 配 `NORDIC_LIVE_*` 跑过,都过;协议形状还有
本机 curl 的实测记录)。

### 这一轮没验到的(只有人或真机能看)

1. **换设备接着听那一问的手感**:什么时候该问、什么时候不该问,只有真机上换着用
   才判得了(现在的判据是「指纹变没变」,它只保证「不烦人」,不保证「不错过」)。
2. **队列很长时那一次保存的开销**:封顶之后 URL 还是有好几 KB,真机上要看它会不会
   在弱网下拖慢那一秒。
3. **非管理员那条错误读起来清不清楚**:这台账号是管理员,那条路只能在用例里模拟。
4. **补报什么时候真的发出去**:要等下一次有机会(下一条 scrobble),真机上看
   「离线听几首、再联网听一首」之后服务器上有没有补上。

## 第二十一轮(2026-10-20):包体积按 ABI 拆分

用户原话:「细节优化;现在软件体积很大有没有办法优化」。**先量账再动手** —— 把
`build/dist/Nordic-1.0.44+45-release.apk`(74.6 MB)拆开,按目录汇总体积:

| 部分 | 体积 | 备注 |
| --- | --- | --- |
| `lib/x86_64/*` | 26.6 MB | 模拟器专用,真机永远用不到 |
| `lib/arm64-v8a/*` | 24.2 MB | 现代手机要的就是这一份 |
| `lib/armeabi-v7a/*` | 20.0 MB | 32 位 ARM 老设备 |
| `classes.dex` | 3.96 MB | 未开 R8 |
| `assets/` | 1.3 MB | ML Kit 模型 0.88 MB + `CupertinoIcons.ttf` 0.26 MB |
| `res/` + `resources.arsc` | 0.5 MB | |

结论是:**体积几乎全在 `lib/`,根因是三个 ABI 打进了同一个包**。一台设备只用得到其中
一份,另外两份引擎(`libflutter.so`,每份 8.4~12.9 MB)加两份 Dart 快照
(`libapp.so`,每份 7.5~8.2 MB)是白背的 —— 三份 `.so` 合计约 71 MB。

顺带把 1.0.38 那次「56 MB 跳到 73 MB」也对上了:`git log -S mobile_scanner` 指到
`535c1a4`(扫码同步),它带进来的 `libbarhopper_v3.so` 三份合计 14.1 MB,加 ML Kit 的
三个 `.tflite` 共 0.88 MB —— 那一跳几乎全是扫码模型的体积。

### 一、三个决策(问过用户,不是自己拍的)

1. **按 ABI 分三份**,而不是只出 arm64 单包 —— 模拟器仍装得上 `x86_64` 那份;
2. **扫码的 ML Kit 模型继续内置** —— mobile_scanner 支持换成走 Play 服务的 unbundled
   版(能再省 5.9 MB),但那三个字是「静默失效」:中国区设备多数没有 Play 服务,
   扫不出结果也不报错;
3. **这轮不开 R8** —— 只省约 1.5 MB,却要重验 audio_service / just_audio /
   flutter_secure_storage 的反射路径,值得单独一轮。

### 二、改了什么

- **`tool/build.sh`**:`release` 分支加 `--split-per-abi`;`standardize_apk()` →
  `standardize_apks()`,收目录、按 `arm64-v8a` / `armeabi-v7a` / `x86_64` 循环落名
  (`Nordic-<版本>-<abi>-release.apk`)。**校验一条没放松**:三个包逐个跑
  `apksigner verify` 与 `aapt dump badging` 核包名与 `versionName`,任一个不过就整批
  失败 —— 免得 `build/dist` 里出现「一半新版、一半旧版」。
- **逃生通道没有新写**:脚本的 `*)` 分支本来就是 `exec flutter "$@"`,所以
  `tool/build.sh build apk --release` 照样出那个 74.6 MB 的万能包(只是不落
  `build/dist`)。这条在脚本注释与 README 里都点明了。
- **`pubspec.yaml`**:删掉模板自带的 `cupertino_icons`(全仓库 grep 零引用,
  `CupertinoIcons` 一处都没有),顺带省掉 `CupertinoIcons.ttf` 那 257 KB。
- **`README.md` 构建节**:产物名改示例、写明手机该装哪一份、以及分 ABI 的理由。

### 三、实测

| 产物 | 体积 |
| --- | --- |
| 改前 `Nordic-1.0.44+45-release.apk`(万能包) | 74.6 MB |
| 改后 `Nordic-1.0.45+46-arm64-v8a-release.apk` | **26.4 MB(-65%)** |
| 改后 `Nordic-1.0.45+46-armeabi-v7a-release.apk` | 22.4 MB |
| 改后 `Nordic-1.0.45+46-x86_64-release.apk` | 28.7 MB |

`arm64-v8a` 那份里 `lib/` 只剩 7 个文件、全是 `lib/arm64-v8a/`(对照:旧万能包里
21 个);`mlkit_barcode_models` 三个模型仍在;Cupertino 字体已不在。

### 这一轮没做(及理由)

- **`--obfuscate --split-debug-info`**:会打乱 Dart 符号名,而本仓库排障靠真机
  logcat,混淆之后栈就不可读了 —— 不值那 1 MB 上下;
- **`.so` 改回压缩(`useLegacyPackaging`)**:包会小一截,但每次启动要解压,是性能
  倒退;现代 AGP 默认 Stored 就是为了免解压,这一条不动。

### 版本与提交

版本 1.0.44+45 → 1.0.45+46。一个提交(构建脚本 + 依赖 + 文档)。

验证:`flutter analyze` 干净;`flutter test` **474 passed / 18 skipped / 0 failed**;
三个包都出得来,`build/dist/` 下三个名字都在,脚本那三条校验(签名 / 包名 / 版本)
逐个过。

### 这一轮没验到的(只有人或真机能看)

1. **手机上装 `arm64-v8a` 那份能不能正常装、正常跑** —— 打包方式换了,虽然校验都过,
   真机装一次才算数;
2. **模拟器装 `x86_64` 那份** —— 同理,而这台机器上的音频隧道验证本来就走模拟器;
3. **扫码有没有受影响** —— 模型是内置的、没动,但换了分包也值得扫一次确认;
4. **后台播放 / 下载 / 缓存各走一遍** —— 这几条是「换打包方式会不会顺手打坏别的」的
   哨兵。

## 第二十二轮(2026-10-20):通审 lib/ —— 去重 / 清死代码 / 补两处「说了没做」

起点是「把 `lib/` 通读一遍,能优化的优化」。74 个文件、24.5k 行全读过,`flutter analyze`
干净、474 条用例全过。这一轮**净减 326 行**,没有新功能 —— 下面按类分组,每一条都是
能指到具体文件与行的。

### 一、先修两处「文档说了、代码没做」

1. **`PlaybackState.error` 是个死字段。** `playback_controller.dart` 上写着「非空时
   界面要显示错误而不是空态」,而全仓**没有任何一处读它** —— 写它的倒有四处(播放流的
   `onError`、`playAll` 的 `catch`、`playbackEventStream` 的 `onError`、那几处 clear)。
   后果是「点一首播不出来的歌」在界面上**一点反馈都没有**:坞不出现、播放页仍是
   「还没有在播的歌」。
   **这一轮没做** —— 补一个播放错误态是界面交互的增删改,按规矩要先改 `prototype/`
   (原型里现在也没有这个态),单独一轮。

2. **`setQueue` 的注释说它拦了「没有仓库」,实际没拦。** `retargetCurrentRoute` 照着
   这条假设写了提前返回,而 `setQueue` 从头到尾没有那个判断 —— 没有仓库且这首不是本机
   文件时,`_sourceFor` 的 `remote()` 闭包会抛。这一轮把**抛出来的那句话**改成中文的
   `MusicSourceException`(原先是英文的 `StateError('还没有配置服务器,无法构建播放源')`),
   并让 `PlaybackController` 对音源自造的失败取 `message` 而不是 `'$e'` —— 这样等第一条
   做完,那句话就是能直接摆上屏幕的。注释也改对了:这一支**不自己收手**,因为
   「什么都不做」同样是静默。

   另修一处同类:`search_screen` 与 `library_screen` 的歌曲行原先用 `repo!.coverUri(...)`,
   而 `playlist_screen` 明确写着「仓库可为空......不拿 `repo!` 崩掉整张列表」——
   同一件事一处防一处不防。三处现在走同一份包装。

### 二、删掉没人用的(6 处)

| 位置 | 情况 |
| --- | --- |
| `NordicGlass.saturationOverride` | 收了、存了、**从头到尾没读过** —— 传进来会被静默丢弃,这是 API 在撒谎 |
| `NordicGlass.blurOverride` / `shadow` | 被读,但没有任何调用点传过 |
| `NordicToast`(`states.dart`) | 零引用。它的文档还在解释「用 overlay 而不是 SnackBar,因为 SnackBar 会顶起底部内容」,而全应用用的都是 `showSnackBar` —— 类和理由一起过期了 |
| `NordicAudioHandler` 的五个流 getter | `positionStream` / `bufferedPositionStream` / `durationStream` / `playerStateStream` / `processingStateStream` —— `lib/` 与 `test/` 都没有调用点(`PlaybackController` 直接订 `_handler.player.*`) |
| `CredentialStore.hasPassword` | 零引用 |
| `tokensFor()`(`theme_mode.dart`) | 零引用,连 `tokens.dart` 的 import 一起删 |

### 三、去重(省下的行数几乎全在这里)

1. **封面地址那份包装,原先只有 2 处在用。** `cover.dart` 的 `albumCoverUri` 写着
   「十几处各写一遍 try/catch 是同一份逻辑......收成一处」,而实际**还有 12 处**各写各的:
   `home_screen.dart` 一个文件里三份(其中两份**逐字相同**)、`library_screen.dart` 两份,
   album / artist / playlist / bottom_stack / player 各一份。全部改走 `albumCoverUri`。
2. **`extension _FirstOrNull` 被复制了五份**(media_cache / download_manager /
   subsonic_client / sorting / quality,逐字相同)→ 新增 `data/iterables.dart` 一份。
   没有为此引 `package:collection` —— 那是给这一句加一条直接依赖。
3. **设置页与关于页原先各有一套卡片与行**(`_Card` / `_SettingRow` 对 `_Card` / `_InfoRow`)
   → 收成 `NordicCard` / `NordicIconRow`。关于页那份的文档自己就写着「两边哪天合并成
   一个共享组件也不亏」。
4. **三张面板的选项行原先各一套**(缓存上限 / 转码档位 / 排序)→ `NordicOptionRow`;
   顺带把写了三遍的「小标记」收成 `NordicTag`(线路标记、档位「无损」、服务器行的
   「已锁定 / 使用中」)。
5. **两条连接流程原先各写一遍**(服务器表单、扫码同步:连上 → 拉一次库 → 兜住
   `UnsupportedError`)→ 新增 `ui/connect_flow.dart`。连那句「为什么整趟必须接得住
   `Error`」的解释也只剩一份。
   **行为上有一处措辞统一**:扫码那条路带密码导入失败时从「没能连上:...」改成
   「连不上:...」(表单那条一直是这么说的)。

### 四、顺手向原型对齐两处(原型本来是对的,是应用漂了)

核对原型时发现的,不是设计变更 —— 原型里早就这么写着,应用没跟上:

- **`.row { gap: var(--s3) }`** —— 关于页那一行**右侧箭头的间距是 4**,而设置页同类行
  是 `s3`(12)。合并之后统一按原型取 `s3`。
- **`.divider { margin: 0 var(--s5) }`** —— 手写的 `Divider(...)` 有的只写了 `indent`
  (右侧没留白)、有的两侧都没写、有的靠外层 `Padding` 凑。这里要说清一件上一轮的事:
  上一轮我把它当「零引用的死代码」删掉了,而**它才是跟原型对的那一份**(两侧都留 s5),
  零引用是因为**从来没人采纳它**。这一轮把它请回来,并铺到全部 7 处。

### 五、小清理

- **四处悬空的文档注释**(底下什么都没有,抽组件时留下的):`states.dart`、
  `player_screen.dart`(它还带着三行连续空行)、`album_screen.dart`、`tokens.dart`。
- `LibrarySnapshot.markSongsComplete` 原先把 `copyWith` 的全部字段重抄一遍 ——
  给 `copyWith` 加一个 `songsComplete` 参数,它就成了两行。
- `cover.dart` 里一段注释的缩进掉了一级;`player_screen.dart` 里 `Column(` 后面多一个空行。
- 两处**已经过期的注释**:`subsonic_repository` 里那句「而不是各页面的 `_coverUri` 里」
  (那些 `_coverUri` 这一轮没了)、`settings_screen` 里 `[_SettingRow]` 的名字。

### 验证

`flutter analyze` 干净;`flutter test` **474 passed / 18 skipped / 0 failed**
(与改动前同数);标点守卫 0 处。

release 包(1.0.46+47,三个 ABI 逐个校验签名 / 包名 / 版本):

| 产物 | 体积 |
| --- | --- |
| `build/dist/Nordic-1.0.46+47-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.46+47-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.46+47-x86_64-release.apk` | 28.7 MB |

### 这一轮没验到的(只有人或真机能看)

1. **第四节那两处间距** —— 关于页的箭头、以及 7 处发丝分隔线的两侧留白。改的是往原型
   上靠,但**肉眼得看一眼**才算数(尤其设置页卡片里那条线的右侧,原先是没有留白的);
2. **两条连接流程** —— 服务器表单改配置、扫码导入带密码 / 不带密码,四条路各走一遍;
3. **三张面板**(缓存 / 转码 / 排序)的选项行 —— 抽成一份之后勾的位置统一了,
   排序那张的勾会比从前贴近一点;
4. **封面** —— 12 处改走同一份包装,重点看断网时已下载内容的封面还在不在
   (那是这份包装「本机优先」的承诺)。

### 这一轮没做

- **A1(播放失败要有反馈)** —— 要动原型,单独一轮;
- 其余改动都是「改名 / 搬位置 / 删没人用的」级别,没有行为变化 —— 除了第四节那两处
  间距与第三节第 5 条那句措辞。

## 第二十三轮(2026-10-21):播放失败要有回声(A1)

上一轮通审时发现的那条,收掉:**点一首播不出来的歌,屏幕上什么都不会发生。**
病灶在 `PlaybackState.error` —— 它被四处写入(播放流的 `onError`、`playAll` 的
`catch`、`playbackEventStream` 的 `onError`,以及那几处 clear),而**全仓没有一处
读它**。于是坞不出现、播放页仍是「还没有在播的歌」,而那句在这个场景里是**假的**:
用户刚刚点了。

按规矩先改原型(见下),再落到应用。

### 一、原型:两处新格子

| 位置 | 是什么 |
| --- | --- |
| 设计板「音乐库 · 播放失败」 | 点的那一下**当下**那一句 —— `.toast`,1.6 秒自己消失 |
| 设计板「播放页 · 播放失败」 | **事后走到播放页**看到的那一块 |

两处缺一不可:只做当下那一句,隔一会儿进播放页又变回「还没有在播的歌」;
只做播放页那一块,点完那几十毫秒里仍然是「点了没反应」。

改了什么:

- `prototype/app.js`:`screenPlayer()` 收一个 `failed` 参数(与 `screenHome(true)` /
  `screenSync(true)` 同一套「一屏的另一个状态」的摆法);正文抽成 `playerBody()`,
  不抽的话失败那支得把整段模板复制一份。顶栏抽成 `playerBar(showMenu)` ——
  失败时没有在播的歌,那颗「⋯」背后没有东西可指,收掉(留等宽空位,标签仍居中)。
- `ICONS` 加一颗 `off`(圆圈斜杠)。原先那 44 颗里没有「失败」这个意思,
  拿 `x` 顶会读成「关掉」。
- `toastMarkup()` 收一个可选 `override` —— 气泡本来从 `STATE.toast` 来,而它是一次性
  交互,不钉住的话设计板上没有这一格可核对。
- `styles.css` 加 `.player-fail`(图标 + 语气色 + 一句说明 + 一条去路)。
  **没有复用 `.empty`**:那一块说的是「这儿现在没有东西」(中性),这一块说的是
  「刚才那一下没成」—— 混成一句会让用户以为是自己没点到。

自检:`flutter analyze` 那套在这儿不适用,跑的是 `.tmp-shots/a1-playerfail.cjs` ——
两格各自铺出来、正常那一支没被带坏、控制台干净。

### 二、应用:两条口径

1. **点的那一下要说话。** `PlaybackController.playAll` 的返回值从 `void` 改成
   `Future<String?>` —— 失败时把**那一句话**交回去。新的 `ui/play_tapped.dart` 拿它
   弹一条 SnackBar(2 秒,与「已加入下载队列」同长),文案带上这一首的名字:
   「「可能」播不了 —— 服务器没有给出这一首的音频」。**唱十八个调用点全部改走它**
   (专辑 / 艺人 / 歌单 / 搜索 / 首页货架 / 音乐库歌曲行 / 下载面板 / 整库随机)。
   空列表也回一句话(`队列里没有可播的曲目`)—— 那些「是不是空」的判断原先散在
   调用点,迟早漏一处,表现就是「点了没反应」。
2. **事后走到播放页要看得见。** `player_screen.dart` 的 `song == null` 那一支按
   `state.error` 分两支:中性空态(还没开始听)/ 失败态(`PlaybackFailureState`,
   新增在 `widgets/states.dart`:图标 + 「这一首没能播起来」+ 失败原因 + 「回音乐库
   挑一首别的」)。同时没有在播的歌时顶栏「⋯」收掉 —— 它背后没有东西可指。

`playSong` 一并改成返回 `Future<String?>`;`playAll` 里对
`MusicSourceException` 取 `message`(上一轮已经把 `_sourceFor` 那句换成了中文),
其余照旧印原文。

### 三、用例(`test/ui/playback_failure_test.dart`,7 条)

这一轮的承诺是「点了要有回声」,它原先一条用例都没有 —— 所以补一组钉住:

- `playAll` 播不起来 → 回一句人话,**并且**记进 `state.error`(界面读的就是它);
- 空列表 → 回「队列里没有可播的曲目」(调用点不必自己判空);
- 播得成 → 回 null(成功不说话);
- 播放页:失败过 → 铺失败态、原因印出来、**中性空态一个都不出现**、去路在场;
- 播放页:没失败过 → 仍是那句中性的空态;
- **点的那一下 → 一句 SnackBar,同时带上「哪一首」与「为什么」**(主判据);
- 失败时顶栏那颗「⋯」收掉。

### 验证

`flutter analyze` 干净;`flutter test` **481 passed / 18 skipped / 0 failed**
(上一轮 474 + 这一轮 7);标点守卫 0 处;原型自检脚本无控制台错误。

release 包(1.0.47+48,三个 ABI 逐个校验签名 / 包名 / 版本):

| 产物 | 体积 |
| --- | --- |
| `build/dist/Nordic-1.0.47+48-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.47+48-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.47+48-x86_64-release.apk` | 28.7 MB |

### 这一轮没验到的(只有人或真机能看)

1. **真的点一首播不出来的歌** —— 造这个现场有一条省事的路:把某个已知曲目的
   文件从服务器上移走(或临时改坏线路),然后点它。要同时看到两样:
   **当下弹一句**,以及**进播放页是那块失败卡**而不是「还没有在播的歌」;
2. **失败之后点别的歌能恢复** —— 那一句错误由 `_emit(clearError: true)` 清掉,
   但两个「点了都会失败」的歌连着点、再点一首好的,这条路径值得实机走一遍;
3. **十八个入口各点一次** —— 改动是机械的,但每一处都走同一个 `playTapped`,
   哪一处漏了就是那一处仍然没有回音。

### 这一轮没做

- **播放中途断流**(播着播着线路断了)没有单独做态:它走的是 `_track` 的
  `onError`,会把 `state.error` 写进去,于是**下次**进播放页会看到失败态 ——
  但当下那一屏不会自己跳。要不要为此加一块浮层,单独一轮再说(原型里也没有)。

## 第二十四轮(2026-10-21/22):数据读不出来时,别把整屏卡死

病灶在映射层:把 `id` 直接 cast 成 `String`。服务器偶尔给出一条没有 `id`
的条目,那时抛的是 `TypeError` —— 它实现的是 `Error`,**不是** `Exception`,
于是各屏的 `on MusicSourceException catch` 一条都接不住:异常穿出去,`_loading`
永远停在 `true`,界面一直转圈,而屏幕上没有一个字说明发生过什么。

同一个形状还有几处:换档位、建歌单、搜索、详情页 —— 都是「接得住的只有
`MusicSourceException`,接不住的就静默卡死」。

### 一、映射层:坏元素只少那一行

- `SubsonicMapper.hasIdentity` 与 `_id` 一起进来:实体(专辑 / 歌曲 / 艺人 /
  歌单)缺 `id`、`id` 为空串、`id` 不是字符串 —— **整条丢掉**,其余照常。
  `id` 是缓存键、路由参数、Stream 的槽位,没有默认值可用。
- **只在实体这一层筛**,不塞进通用的 `mapList`。这条是踩出来的:第一版放进
  `mapList`,歌词的 `line[]`、`genres[]` 被整批筛掉,而那个错不响(歌词页只是
  空着),是 `app_state_test` 的「歌词的磁盘缓存」三条先红的。
- `getRandomSongs` 那条排序前也先筛一遍 —— 它要的是「读得出来」,不是「排得动」。

### 二、界面:兜底那一支必须存在

五处补 `catch (e)`(`AlbumScreen` / `ArtistScreen` / `PlaylistScreen` /
`SearchScreen` / `NewPlaylistScreen`):宁可把一句技术报错摆出来,也不要一屏
转不完的圈。与 `AppState.loadLibrary` 那条兜底同一口径。

`SearchScreen` 那一处还带 `_pendingQuery != query` 的判断 —— 旧的请求晚回来,
不该把新一次搜索的 `_searching` 抹掉。

### 三、换档位也要说话

`PlaybackController.setQuality` 的返回值从 `Future<void>` 改成 `Future<String?>`，与上一轮 `playAll` 同一套。原先 `quality_sheet` 上是裸 `await`:换档要整队重装,
那一步会失败(没有仓库 / 服务器不给这一首),异常从 `onTap` 冒出去,用户看到的是
「点了一档、没有任何反应,档位也还是旧的」。现在弹一句「没能切到「X」 —— 原因」。

### 四、用例(`test/data/mapper_resilience_test.dart`,7 条)

- 专辑 / 歌曲 / 艺人 / 歌单 缺 `id` → 那一条不出现,别的还在;
- 一条都读不出来 → 空表,不是抛、也不是 null;
- 搜索的三个桶各自筛 —— 一个坏元素不该带走另外两桶;
- **非实体数组一条都不许丢**:歌词 `line[]` 全留着;`mapList` 只筛「不是对象」;
- `hasIdentity` 的判据:非空 String 才算,空串、数字、缺字段都不算。

### 验证

`flutter analyze` 干净;`flutter test` **488 passed / 18 skipped / 0 failed**
(上一轮 481 + 这一轮 7)。18 跳过是本机连不到 Navidrome,与这一轮无关。

### 这一轮没验到的(只有人或真机能看)

1. **真的让服务器吐一条没有 id 的数据** —— 用例是喂字典,真机得靠坏数据撞上;
2. **换档位失败那一下** —— 得在没有仓库(刚启动、还没连上)时点档位才能看到。
## 第二十五轮(2026-10-22):播着播着断了,当场就得说一句

上一轮末尾自己记了一条尾巴:播放**中途**断流没有单独的态。这一轮补上。

病灶:播放层那条统一错误处理只做了两件事 —— 把原因写进播放状态、把「正在播」置 false。
而那个错误字段全应用只有播放页读,而且是**下次**走到播放页才读。于是用户正听着、
线路断了:声音没了,界面上一个字都没有 —— 他分不清是自己误触了暂停、还是线路断了。

### 一、播放层:断流是一条**事件**,不是状态

新增 `PlaybackController.interruption`(`ValueNotifier<String?>`)与播放状态里的错误字段分工
不同:那一份回答「这一刻该怎么显示」,这一份回答「刚刚出了事」。

- 音源自己造的失败原样给用户看(它的 `message`),别的照旧印原文 —— 与 `playAll` 同一条口径;
- **先置 null 再置值**:连着断两次就该说两次,而 `ValueNotifier` 见同值不通知。
  订阅方跳过 null 即可(它是「上一句说完了」的复位信号,不是「又断了一次」)。

### 二、界面:挂在根上,不看用户停在哪一屏

`PlaybackInterruptionEcho` 挂在 `MaterialApp.builder` 里(与后台播放那条护栏同一处),
弹一条「播放中断了 —— 原因」。提示走**全局** `scaffoldMessengerKey`:按 context 找
messenger 会漏掉没有 Scaffold 的树,而断流那一下用户可能停在任何一屏。

`PlaybackInterruptionEcho` 公开(不是下划线前缀)是为了能测 —— 判据是「值出现之后
屏幕上多了一句话」,它在整棵树最外层,不公开就只能拿一整个 `NordicApp` 去验。

### 三、踩到的坑:无条件排到下一帧 = 永远不说

第一版把所有播报都塞进 `addPostFrameCallback`。用例红了:值变了,屏幕上却没有提示。
诊断打印出来才看清 —— `addPostFrameCallback` 要有**下一帧**才跑得起来,而这一下本来
就没有别的活要干,那句话就永远排在那里。

改成按阶段分:只有正处在 `SchedulerPhase.persistentCallbacks`(构建期)才排到帧末
并 `scheduleFrame()` 主动请求一帧,其余情况(绝大多数:流事件落在帧与帧之间)直接说。

### 四、原型

设计板补「播放中断流」一格,走既有 `.toast`(与「音乐库 · 播放失败」同一套)。
这一格是必须的:它是一次性交互,只在截图里存在的话设计板上没人核对得到。

### 五、用例(4 条)

- `test/playback/playback_test.dart` 新增一组:流上报错 → 交出那一句,音源的话
  原样给用户;连断两次 → 两次都在(中间那次归零是刻意的);
- `test/ui/playback_interruption_test.dart`:断流之后屏幕上当场多一句话;
  复位那一下不弹,也不把刚说的那句撤掉。

### 验证

静态检查干净;全量测试 **492 passed / 18 skipped / 0 failed**(上一轮 488 + 这一轮 4)。
18 跳过仍是本机连不到 Navidrome。

### 这一轮没验到的(只有真机能看)

**真的让线路断一次**。用例是往流上灌错误,真机得靠网络真断(切飞行模式 / 服务器掉线)
才撞得上 —— 届时该看到:声音停、底部弹一句「播放中断了 —— ...」,3 秒后自己消失;
再进播放页还能看到那一块失败态。


## 第二十六轮(2026-10-22):宽屏 + 平板适配(原型先行)

用户要求「适配宽屏、平板、TV」。这一轮做**宽屏 + 平板**;TV(Android TV 的
leanback 身份、遥控器焦点导航、10 尺字号)留下一轮,复用本轮的宽屏形态
(`NordicNavRail` 已按 `{activeTab, onTabSelected}` 定型,下一轮加 focus 参数即可)。

### 一、原型(先做,唯一设计真相来源)

- `.phone` 加 `container-type: inline-size`,文件尾新增「宽屏 / 平板」一节:
  容器查询挂在**每一台设备**上 —— 设计板每一格、舞台那一台各自独立判级,不看浏览器视口;
- `>= 840`:三颗 tab 进左侧玻璃竖栏、底部托盘只剩播放横条(上一首与行内进度并进坞里)、
  专辑头改横排、播放页两栏(封面居左放大到 512)、歌词 / 设置 / 卡片屏收成一栏;
  600 以下逐像素不变。类名保持 `phone`(几十个自检脚本按它选),平板 / 宽屏只是变体类;
- 竖栏挂点用 `data-rail-tab` 而**不**复用 `data-tab`:复用会让既有脚本的 `[data-tab]`
  选择器同时命中两颗按钮,playwright 撞在隐藏的那颗上超时;
- 网格列数与应用**同一条公式**(`ceil(可用宽 / 296)`),由 app.js 的 `gridColsOf`
  写进 `--grid-cols` —— CSS auto-fill 向下取整、应用向上取整,到位宽边界
  (1024 / 1280 附近)会差一列,列数只留一条公式;
- 设计板 +6 格宽屏(共 76 格),舞台侧栏加 手机 / 平板 / 宽屏 切换。12 格 1280×800
  在整板同绘时会压垮渲染进程(实测 Target crashed),设计板格子加 `content-visibility: auto`;
- 自检:`verify.cjs` 全链路通过、零控制台报错(顺手修它两处陈旧:轨道选择器改
  `i.played`、搜索入口早已挪进顶栏放大镜);新增 `widecheck.cjs`,30 条判据全过。

### 二、应用

- 新 `lib/ui/adaptive/window.dart`:断点(600 / 840)与宽屏几个数(栏宽 84 / 让位 104 /
  横条 72 / 留白 88 / 网格 296)**只此一处**,`adaptive_test` 读原型文件核对同源;
- 常驻区唯一切换点 `NordicChrome`:窄屏**原样**返回 `BottomStack`,宽屏换
  `NordicNavRail` + `WidePlaybackBar`(订阅面与坞逐条相同);主壳 / 沉浸外壳 / 服务器页
  三处共用。tab 视觉抽成 `NavTabButton`(托盘那份保持裸 GestureDetector,行为零变);
- 内容让位走壳上的 `NavGutter`(104):12 处 `listInset` 调用点一个没动,只把函数分两档
  (窄 150 / 宽 88),顺手修掉 `library_screen` 里唯一一处绕过口径的写死值;
- 网格抽成共享 `AlbumGridSliver`(音乐库与搜索页原先各写一份,且宽屏列数要按断点算):
  列数只在 expanded 算,封面从 0.78 的比例改成**恒正方形** —— 旧值在两列手机宽下
  封面就是 167×159.5(扁 4%),网格拉大后这个偏差会变成肉眼可见;
- 播放页两栏(封面限 512,与网格 / 专辑页同一档解码桶);歌词 / 设置 / 关于正文收成
  720 一栏;专辑头横排(封面 200),艺人 / 歌单头图放大一档;
- 平台:Windows 最小窗 480×720(`WM_GETMINMAXINFO`,按 DPI 缩放,注释全 ASCII);
  web manifest 去掉 portrait 锁(PWA 不再锁竖屏)。

### 三、用例(10 条)与验证

- `adaptive_test`:分级四个边界点(599/600/839/840)、断点与原型同源、网格三点、listInset 两档;
- `wide_shell_test`:840 处翻面 + 839 / 390 反向守卫、竖栏换树与 HeroMode 语义、
  横条的空态 / 按下 / 点进播放页;
- `wide_layout_test`:网格 1280 四列、800 与 390 恒两列(钉死「除式在 800 会算出 3 列」的坑)、
  播放页两栏与单列、设置限宽。

静态检查干净;全量测试 **502 passed / 18 skipped / 0 failed**(上一轮 492 + 这一轮 10,
**原有用例零改动** —— 默认测试视口 800×600 落在 medium,形态与分级一起钉死)。
18 跳过仍是本机连不到 Navidrome。

### 这一轮没验到的(只有人或真机能看)

1. **Windows 上拖窗穿过 839 / 840** 那一下的观感(竖栏与横条的出现与消失);
2. 平板竖屏(834)实机 —— 形态与手机一致、网格恒两列,用例覆盖了,真机尺寸没上过手;
3. 原型 6 格宽屏与真机的逐格对照。



## 第二十七轮(2026-10-23):把第二十六轮的复验收完 —— 顺手抓出两处实伤

第二十六轮末尾记了三条「只有人或真机能看」;这一轮先上真机把那三条过完
(839/840 拖窗观感、平板竖屏 834、原型 6 格宽屏与真机逐格对照),复验里又撞出
两处实伤,一并修掉。版本 1.0.51+52。

### 一、复验(Windows release 实拍,1280×800 逻辑 / 150% DPI)

- **839 / 840**:1 逻辑像素的跨界,底部托盘与「左竖栏 + 播放横条」翻面对;
- **平板竖屏 834**:形态与手机一致、恒两列网格 —— 与用例同形;
- **6 格宽屏逐格对照**:首页(货架) / 音乐库(四列网格) / 专辑详情(横排头) /
  播放页(两栏) / 歌词(720 一栏、逐句高亮) / 设置(720 一栏) —— 全部与原型同形。

复验捎回两条**工具事实**(不是产品缺陷,记下来给 TV 那一轮省事):
- 本机屏幕 1440×960 物理 @150%,而最小窗高是 480×720 逻辑(= 1080 物理):
  **窗口模式在这台机器上竖向放不下**,底边永远在屏外,截图只能靠 PrintWindow;
- 窗口放在 (0,0) 时,客户区 x > 1429 物理的部分落在屏外、**鼠标点不到** ——
  要点播放页暂停键、质量胶囊这类右侧控件,得先把窗口左移再点。

### 二、实伤一:专辑页那颗「播放」从来不是胶囊

1280 实拍是整条通栏绿条,而原型 `.album-play .btn` 是居中的 190 胶囊。查下去:
**不是宽屏才有的回归** —— 从 M2(a0f4afe)起它一直是通栏,手机上也是,只是这条
没人拿尺子量过。

根因在 `PrimaryButton`:容器里多包了一层 `Center(child: child)`。`Center`(Align)
在松约束下会**撑满可用宽度**:内层 Row 老实收着自己的宽、也居中,但外面那层容器
被撑成整行宽,整颗按钮于是静悄悄变成通栏。`fillMaxWidth: true` 那支本来就该满宽,
所以这个洞一直没露出来。

修:去掉那层 `Center` —— 居中由 Row 自己的 `mainAxisAlignment.center` 给(两种
形态下都在)。用例 +3(`test/ui/components_test.dart`):420 / 1280 下胶囊恒 190
且居中;长标签跟着内容撑宽(对应原型 `width:auto`);默认形态仍是通栏。

### 三、实伤二:Windows 转码流报回「2.9 万年」的时长

播放页剩余时间写成 `-15372286726:04`,进度条滑块瘫在最左(位置本身是对的)。
实拍 A/B 归因:原音直出全正常,切回 192k 转码档就现形 —— 正是
`docs/performance.md` 记过的「转码流没有 Content-Length」在 Windows 上的另一副
面孔:Android / iOS 的平台(ExoPlayer / AVPlayer)报 **null**,有元数据时长兜底;
Windows 后端不报 null,**报哨兵** —— int64 满格按 100ns 折算(≈ 922,337,203,685
秒 ≈ 2.9 万年),而 `durationStream` 那条监听只挡了 null。

修:`playback_controller.dart` 顶层加判据 `plausibleDuration`(0 < d ≤ 24 小时),
监听里坏值一律不盖 —— 切歌时铺好的元数据时长留在原位。用例 +1:哨兵值(实拍那个
数)、零、负值都不收;24 小时边界与正常曲长照收。

### 验证

静态检查干净;全量测试 **506 passed / 18 skipped / 0 failed**(上一轮 502 + 这一轮 4)。
Windows release 重建后实拍核对:胶囊居中 190;转码档下播放页恢复
`1:57 / -1:28`(和 = 元数据时长 3:25),滑块落点真实。

| `build/dist/Nordic-1.0.51+52-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.51+52-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.51+52-x86_64-release.apk` | 28.8 MB |

### 这一轮没验到的(只有人或真机能看)

1. 胶囊修复在 Android / iOS 真机屏上的目视 —— 用例与 Windows 实拍都过了,手机还没上手;
2. 坏时长那道判据只在 Windows 触发过(Android / iOS 本来就报 null,没有对照场景);
3. 播放页「看歌词」的另一处入口(封面区整块)在真机上没点过 —— 只验了歌名那处。

## 第二十八轮:悬浮导航的尺寸重调(2026-10-24)

用户一句「悬浮导航大小调整得更好看一些」,指向两处:手机的那颗底部胶囊托盘,
以及宽屏的那根左竖栏。对下来三个具体症状 —— **偏大偏笨、太挤、选中胶囊太宽、
图标 / 字号偏小**。版本 1.0.52+53。

### 一、先搭比对台,再动像素

「更好看」是主观的,拿数字猜不如把候选铺开看。于是写了两个只读脚本
(`.tmp-shots/navlab2.cjs` / `navlab-rail.cjs`):从 `player.html` 取来**真实的**
托盘与竖栏 markup,克隆几份叠上作用域 CSS,深色 / 浅色两套并排一屏看完。
试了 A–H 八组底部参数、R0–R4 五组竖栏参数,定下来的那组再用
`nav-ab.cjs` 与 `git show HEAD:prototype/...` 出来的旧版左右对照复核。

**比对台是这一轮的产物,不进仓库**(`.tmp-shots` 已被忽略);但它证了一件事:
这几处尺寸以后要再调,不必靠改一行看一眼。

### 二、底部胶囊托盘(原型 `.tabbar` + 应用 `_TabBar`)

| | 改前 | 改后 |
|---|---|---|
| 标签栏高 | 62 | 58 |
| 胶囊高 | 54 | 50 |
| 胶囊宽 | 118.7(占满三分之一屏) | 85(左右各内缩 16) |
| 图标 | 21 | 23 |
| 文字 | 10.5 / 行高默认 | 11.5 / 行高 1 |
| 图标与文字间距 | 3 | 4 |

三条各自的理由:

- **胶囊不再横跨整个三分之一屏**。原先那颗 118.7 × 54 是一块**板子**,不是胶囊 ——
  这是「选中胶囊太宽」的正身。现在按内容收窄,左右各让 16。
- **边距与缝同宽**:标签栏左右各 16 的边距,加每颗上 16 的内缩,正好等于三颗之间
  那 32 的缝。靠托盘的两条留白与胶囊之间的缝一样宽,三段于是看起来是均分的。
- **内容长高、行高收到 1**:图标 21→23、字号 10.5→11.5、间距 3→4,内容整体
  38.5;在 50 的胶囊里上下各剩 5.75。**先前是内容 38 塞在 54 里** —— 上下不算
  少,但文字行高吃掉的那几像素让它读着贴底,「太挤」出在这里。

### 三、宽屏左竖栏:面板贴合内容(原型 `.railnav` + `NordicNavRail`)

这是「偏大偏笨」的最大一处,而且与尺寸参数无关:**原先 `top:10 + bottom:10`
是一根通到屏幕底的柱子,柱子里只有三颗按钮** —— 底下七成是一整片空玻璃。
842 高以上的窗口里,那是整块界面里最大的一块什么都没有的面。

改成只给 `left` / `top`,面板按内容自己收口(84 × 180:8 × 2 内衬 + 52 × 3 按钮
+ 4 × 2 缝)。顺带把按钮与字调成与托盘同一套比例:`72×60` → `68×52`
(68 = 84 − 8 × 2,把内衬用满)、间距 6 → 4、图标 21 → 23、字号 10.5 → 11.5、行高 1。

**栏宽 84 与让位 104 一个字没动** —— 那套数在 `NordicWindow.gutter` 与原型
`gridColsOf` 的网格公式里,牵一发动全身;这次要修的是「里面太空」,不是「太宽」。

### 四、验证

静态检查干净;全量测试 **509 passed / 18 skipped / 0 failed**(上一轮 506,
这一轮 +3)。

那 +3 是**为这一轮补的守卫**(`test/ui/nav_size_test.dart`)。查下去才发现:
改前 / 改后都是 506 全绿 —— 这一组尺寸**原先没有任何用例守着**,谁把它们顺手
改回去,测试一声都不会出。所以钉住三件:标签栏 58 与胶囊 80.7 × 50、
边距(16 + 16)与三颗之间的缝(16 + 16)同宽、竖栏面板 84 × 180 且底下留得下东西。

钉的是**关系**不是绝对像素(绝对数会随字号与设备宽漂移)。这三条做过变异
校验:把 `height` 改回 54、图标改回 21,前两条立刻红 —— 不是不会失败的「守卫」。

原型侧拿改前 / 改后实拍逐行对照(手机托盘深色、手机托盘浅色、托盘选中态、
宽屏竖栏),4 行 8 张。

**应用侧也实拍过**(Windows release,150% DPI):窄档 652 逻辑宽看托盘 ——
三颗、选中胶囊收窄、图标与文字都长了一号;宽档 918.7 逻辑宽看竖栏 ——
面板在三颗之后收口,底下留得下一大片内容。两档都与原型同形。

### 五、产物

| `build/dist/Nordic-1.0.52+53-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.52+53-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.52+53-x86_64-release.apk` | 28.8 MB |
| `build/dist/Nordic-1.0.52+53-windows-x64.zip` | — |

签名与版本校验通过(包名 fun.han1997.nordic)。

### 这一轮没验到的(只有人或真机能看)

1. **真机上那几毫米的手感** —— 胶囊窄了 38、标签栏矮了 4,手指按上去是不是
   还是「一按就到」,只有上手知道(点按区仍有 80 × 50,离 48 的下限有余量);
2. **宽屏竖栏收口之后**,极矮窗口(逻辑高 < 480)里它会不会与播放横条打架 ——
   本机最小窗高放不下,量不到。

## 第二十九轮:悬浮导航再调 —— 手机胶囊收到 64;宽屏竖栏改竖直居中(2026-10-24)

第二十八轮上完之后用户看了实机 / 实屏,指出两处还不对:「手机悬浮胶囊太宽」、
「宽屏、电脑胶囊位置不太好」。版本 1.0.53+54。

### 一、手机:选中胶囊 81 → 64

第二十八轮把胶囊从 118.7 收到 80.7,还不够 —— 那仍然是一块横向的板子。
这一轮收到 **63.3**(应用侧 64.7),比例 63.3 / 50 = **1.27**,这才是真胶囊的
样子。「音乐库」三个字两边各留 14。

做法还是那条**边距与缝同宽**:标签栏左右各 22 的 padding + 每颗胶囊左右各 22
的 margin,正好等于三颗之间那 44 的缝。留白(22 + 22)与缝(22 + 22)是同一个数,
三段于是看起来是均分的。

点按范围跟着窄到 64 x 50 —— 仍高过 48 的下限,余量没吃完。

### 二、宽屏:竖栏从「贴左上角」改「左缘竖直居中」

第二十八轮把竖栏从「通到屏幕底的柱子」改成贴合内容(84 x 180),位置仍是
贴左上角。用户指出贴角也不好,对下来是这么回事:**面板底下那一列全空,而播放
横条又从 104 起,左下角就是一块没用的空档** —— 一根 104 宽的柱子,顶上占了一截、
底下一大截什么都没有。

先按老办法搭了比对台(`.tmp-shots/navwidepos.cjs`,四组整屏构图:贴角 / 居中 /
贴底与横条同线 / 贴在横条上缘),拿给用户挑,定了**竖直居中**:

- 上下留白对称,读作「一颗浮着的胶囊」,而不是「一根被截断的侧栏」;
- **不依赖播放横条在不在场** —— 贴底那一版在没有歌、横条整条不出现时,
  竖栏会孤零零坐在左下角;
- 面板高 180,比最小窗高(480)矮得多,居中不会溢出。

原型 `left: 10px; top: 50%; transform: translateY(-50%)`;应用侧用
`Positioned(top/bottom: 安全区) + Center`,顺带把左列其余地方变成**不拦点击**
(原先那根通到底的玻璃整条都在吃点击)。

**一处应用侧才有的坑**:`SizedBox(width: 84)` 必须写在 `Center` **外面**。
写在里面的话 `Center` 先拿到 Stack 让出来的整条宽度(1270),把玻璃摆到屏幕正中
——用例当场红(`Expected 180, Actual 800`),没有漏到实拍那一步。

### 三、验证

静态检查干净;全量测试 **509 passed / 18 skipped / 0 failed**。
`test/ui/nav_size_test.dart` 三条几何守卫跟着更新,并且把「关系」写得更紧了:

- 胶囊宽 = (托盘宽 − 8 x inset) / 3,**且必须小于自身高度的 1.5 倍**
  (「是胶囊不是板子」这条现在是用比例钉的,不再是某个绝对像素)、
  且不小于 48(点按下限);
- 竖栏面板中心必须落在可用高度的正中 —— 贴角、贴底都会当场红。

原型侧实拍对照(改前 / 改后:手机托盘深色、手机托盘浅色、托盘选中态、
宽屏竖栏)四行八张。

### 四、产物

| `build/dist/Nordic-1.0.53+54-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.53+54-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.53+54-x86_64-release.apk` | 28.8 MB |
| `build/dist/Nordic-1.0.53+54-windows-x64.zip` | — |

### 这一轮没验到的(只有人或真机能看)

1. 真机上 64 宽的点按手感(离 48 的下限还有 16 的余量,但手感得上手);
2. 极矮窗口(逻辑高 < 480)里竖栏居中的观感 —— 本机最小窗高放不下,量不到。

## 第三十轮:悬浮托盘**整体**收窄(手机 370 → 334)(2026-10-24)

用户澄清:「我是想修改手机胶囊**整体**的宽度!」—— 第二十八 / 二十九两轮调的
都是托盘里**选中的那颗药丸**,而用户说的是**整颗玻璃托盘**。改对了对象,
这一轮只有一条数,但拖出两条连带。版本 1.0.54+55。

### 一、托盘左右留白 10 → 28

`.bottomstack` 的左右留白原先只有 10,在 390 的屏上占 **95%** —— 那读起来是
一条**贴着边的横栏**,不是一颗浮着的东西。收到 28(托盘 334,占 86%)才真的浮起来。

比对台(`.tmp-shots/navlab2.cjs`)铺了 370 / 354 / 342 / 330 / 314 五档整机取景,
取 334 这一档:再窄就压到播放坞那行文字了(坞 60 高、里面还有封面 + 歌名 + 两个按钮)。

### 二、连带一:标签栏的边距必须跟着收(22 → 18)

**这是这一轮最容易踩的一脚。** 药丸的宽是
`(托盘宽 − 8 × 边距) / 3` —— 托盘瘦了而边距不动,药丸就跟着被压没:
托盘 334 减掉左右各 22 只剩 290,三等分再各减 44 就只剩 **53**。
边距与药丸的内缩一起收到 18(留白 18+18 = 缝 36,仍是同一个数),
药丸落回 63 —— 与上一轮定的那颗基本同宽。

两条数是一起动的,所以用例里加了一条**跨过它们的判据**:药丸宽必须 ≥ 60。
单改一边(不管是托盘还是边距)都会当场红。

### 三、连带二:宽屏播放横条被顺带推偏(原型侧一并校正)

托盘那层 padding 是手机与宽屏**共用**的,所以一改,宽屏的播放横条也被推着走:
左缘从 114 变成 132。

查下去发现原型这一处**本来就差 10**:内容标题在 104、应用侧的横条也在 104,
而原型的横条落在 114(`.bottomstack` 的 `left: 104` 上又叠了一层 10 的内衬)。
一起校正:宽屏这一档 `padding: 0 10px 10px 0` —— 左 104 / 右 10 / 下 10,
与 `.screen` 的让位、与应用侧的横条三处对齐。手机那颗浮着的 28 **不带到宽屏**:
那一档它不是浮着的胶囊,是一条横栏,该与屏幕边距对齐。

### 四、验证

静态检查干净;全量测试 **509 passed / 18 skipped / 0 failed**。

`test/ui/nav_size_test.dart` 跟着更新:主角换成**托盘本身**(左右各留 28、
宽 < 屏宽的 90%),药丸那几条照旧。做过变异校验 —— 托盘留白改回 10、
或只收托盘不收边距,都会当场红。

原型侧实拍对照(改前 = 第二十九轮 / 改后:手机托盘深色、手机托盘浅色、
托盘选中态、宽屏竖栏)四行八张;宽屏各层的实测:横条左 104 / 右 10,标题左 104。

### 五、产物

| `build/dist/Nordic-1.0.54+55-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.54+55-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.54+55-x86_64-release.apk` | 28.8 MB |
| `build/dist/Nordic-1.0.54+55-windows-x64.zip` | 13.0 MB |

### 这一轮没验到的(只有人或真机能看)

1. 334 这颗托盘真机上的观感 —— 歌名那一行比原先少 36 的宽度,长标题的
   省略号会来得更早一点;
2. 宽屏播放横条左缘从 114 挪到 104 之后,与本机附表那一排的对齐目视。

## 第三十一轮:托盘定在「与内容栏同一条边线」(左右 20)(2026-10-24)

第三十轮把托盘收到 334(左右 28)之后,用户说「现在看着更不舒服」,并把决定权
交了过来。于是不再猜数字,先把**三版铺进整屏里**比(`.tmp-shots/navstruct.cjs`),
一眼就看出问题不在宽窄、在**对不对齐**。版本 1.0.55+56。

### 一、诊断:不是宽度,是这条线

| | 托盘 | 与内容栏(缩进 20)的关系 |
|---|---|---|
| 10(第二十九轮) | 370 | 比内容栏**宽** 10 —— 读作贴边的横栏 |
| 28(第三十轮) | 334 | 比内容栏**窄** 7 —— 跟屏幕上任何东西都不对齐 |
| **20(这一轮)** | **350** | **同一条左缘线** |

28 那一版「更不舒服」的来源就在这里:托盘自己一条线、内容栏另一条线,中间那
7 个像素的错位说不清道不明,只让人觉得「哪儿不对」。20 之下托盘与上面每一条
卡片同一条左缘,一眼看得出是**这一列的最下面那一块**。

### 二、整块托盘上上下下只有一个数:20

定在 20 之后,这处的数**收敛成一个**:内容栏缩进 20、托盘左右留白 20、
标签栏内衬 20、药丸内缩 20 —— 连三颗之间的缝(40 = 20 × 2)也是它。
一条数管到底,以后要调只动这一处(`BottomStack.trayMargin`,已直接写成
`NordicSpace.s5`,不再另立字面量)。

药丸跟着落在 63.3 × 50(上一版 62.7),基本没动。

### 三、一并记下考虑过、没走的那条路

比对台里还做了一版**拆成两颗**:播放坞一颗浮着(350)+ 导航一颗紧收成
260 居中胶囊。它最直接地回答「胶囊太宽」,观感也利落 —— 没走它的理由:
(1) 一体托盘是当初**照着飞牛播放器定的**(见 `bottom_stack.dart` 的类注释),
不是随手合并的;(2) 两颗不同宽摞在一起是「宽横条 + 窄药丸」的台阶,
在这套安静的玻璃里比一条线更吵。留着这张图,真要走那条路随时可切。

### 四、验证

静态检查干净;全量测试 **509 passed / 18 skipped / 0 failed**。

用例把判据换成了**对齐本身**:`trayMargin` 必须等于 `NordicSpace.s5`,
托盘左右留白各 20 —— 位置一旦再被挪开(10 或 28 都会)当场红。

原型侧整屏实拍(深色 / 浅色);宽屏各层复测:横条左 104 / 右 10,未受牵连。

### 五、产物

| `build/dist/Nordic-1.0.55+56-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.55+56-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.55+56-x86_64-release.apk` | 28.8 MB |
| `build/dist/Nordic-1.0.55+56-windows-x64.zip` | 13.0 MB |

### 这一轮没验到的(只有人或真机能看)

1. 真机上这条对齐线是否一眼看得出来 —— 20 的错位在模拟器截图里是清楚的,
   在手上隔着玻璃是不是同样清楚,得上手。

## 第三十二轮:常驻导航区的**原型 ↔ 应用对账**(2026-10-24)

用户一句「注意原型与软件同步」,于是把这一片从头对了一遍。前四轮一直在动这里,
而对下来 **8 处漂了** —— 其中一处不是「差几个像素」,是**画错了**(进度线只有
它自己那么宽)。版本 1.0.56+57。

### 一、怎么对的

不再靠记忆逐条看,而是把它变成一条**常驻的守卫**:新用例
`test/ui/proto_sync_test.dart` 把 `prototype/styles.css` 的原文读进来,
和**渲染出来的几何**比 —— 8 条用例覆盖托盘 / 坞 / 标签栏 / 竖栏 / 宽屏横条 /
玻璃的深度影。原型改一个字、应用没跟上,当场红(做过两处变异校验:应用把
留白改回 88 红、原型把坞高改成 62 也红)。

顺带把这一片的数**逐条核过一遍没问题**的也记下来:托盘左右 20 / 下 10、
标签栏 58 / 药丸 50 / 两层内衬各 20、坞 60 / 内衬 8 / 封面 46 · 13、
竖栏 10 / 84 / 8 / 缝 4 / 按钮 68 × 52、让位 104、字阶 13 / 11、
圆角 34 / 999、底槽与选中胶囊用的 token。

### 二、漂开的那些(应用侧对齐原型)

| | 原型 | 应用(改前) |
|---|---|---|
| 坞里的缝 | `.dock { gap: var(--s3) }` —— 每一格都是 12 | 只有封面后面那一格:歌名贴着播放键,两颗键挤在一起 |
| 托盘那条线 | 是 `.tray-line`:`--fill-2` 底槽 + 亮条末端 8px 的光 | 借了 `.prog-line` 那套:`--fill-3`、没有光 |
| **进度线的宽** | **块级,横向铺满容器** | **只有「亮带本身」那么宽** |
| 宽屏进度两侧 | gap 12 **加上** `.prog-inline` 自己的 margin 12 = 24 | 16(少算了一层) |
| 宽屏「上一首」 | 25 | 23 |
| 宽屏列表底部留白 | 94 | 88 |
| 玻璃的深度影 | 两档都带**负的 spread**(`.tray` -20 / `.glass-panel` -24) | 没有 spread:影在四周散成一大圈灰 |
| 选中胶囊 | 上缘一道白 + 下缘一道黑(`inset 0 ±1px 0`) | 只有一块 17% 的底 |

### 三、那处画错的:进度线只有亮带那么宽

`ProgressLine` 一直写成「按内容收窄」。放在 `Expanded` 里(宽屏横条)看不出问题,
可托盘里那条是 `Column` 的孩子 —— 给的是松约束,`Stack` 于是缩到**亮带本身**
那么宽:底槽整段不见,线永远看着是满的。原型里 `.prog-line` 是块级的,
`i` 的宽度才决定亮带多长。

修法就是补一句 `width: double.infinity`(铺满容器),并加一条判据:
那条线必须正好是托盘宽减去左右各 16 —— 收窄的话当场红。

### 四、验证

- 静态检查干净;全量测试 **517 passed / 18 skipped / 0 failed**(上一轮 509 + 8 条新守卫)
- 新守卫**读原型文件**,比的是**渲染结果**(不是代码里的字面量):
  托盘与坞的每一段间距、药丸与面板的每一处尺寸、玻璃的影、选中胶囊的两道线
- 变异校验两处都当场红(见上);`copy_punctuation` 那条也顺手过了一遍新用例的文案
- 原型侧这一轮**一个字节没改**(要改的就是应用:原型本来写对了)

### 五、对出来了、这一轮没动的(下一轮候选)

1. **分段控件与筛选胶囊**:原型 `.segmented` / `.chip` 的边是 `1px var(--line)`、
   选中那颗另有 `--fill-3` 底 + `inset glass-rim` + `0 4px 12px -6px var(--depth-2)`
   的影;应用这两处(`NordicGlassPanel.thin`)一处画的是 `--line-2` 的边、
   一处干脆 `border: false`,那颗影也还没有;
2. **`.glass-panel` 的 `inset 0 0 0 0.5px var(--glass-sh)`** 那道内环(半像素的环
   要另叠一层,单独一轮做);
3. **字重与字距**:原型写 640 / 650 / 660 这类中间档,应用按 `w600` 一档收
   (要精确得走 `fontVariations` 的 wght 轴,而各平台的字体不一定可变);
   `.tabbar button` 的 0.005em / `.dock .line1` 的 -0.01em 在 11.5 / 13px 上
   不足 0.15px,没有搬;
4. 原型里 **`.glass-thin` 是个死类**(样式定义了、markup 里没人用)—— 应用倒是有
   两处在用它,要么给原型补上用处,要么把那两处改成原型里对应的类。

### 六、产物

| `build/dist/Nordic-1.0.56+57-arm64-v8a-release.apk` | 26.4 MB |
| `build/dist/Nordic-1.0.56+57-armeabi-v7a-release.apk` | 22.4 MB |
| `build/dist/Nordic-1.0.56+57-x86_64-release.apk` | 28.8 MB |
| `build/dist/Nordic-1.0.56+57-windows-x64.zip` | 13.0 MB |

### 这一轮没验到的(只有人或真机能看)

1. 那圈 8px 的光、胶囊上下那两道 1px 的内描边 —— 都是「差一点点」的东西,
   真机上隔着玻璃还看不看得出来,得上手;
2. 深度影加上负 spread 之后**所有**面板玻璃(卡片 / 弹层 / 分段控件)的分量:
   这一处动的面最大,屏幕上的观感只有人能判 —— 要是觉得卡片「贴地」了,
   退回上一版只需把那个 spread 去掉。
