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
