/* ============================================================
   Nordic — 原型数据、图标与屏幕
   ------------------------------------------------------------
   index.html 用它铺「设计板」(所有屏并排);
   player.html 用它跑「交互流」(真机尺寸,可点击走完整条链路)。

   每一屏都是完整的手机页面(灵动岛 + 状态栏 + 内容区),
   沉浸式页面(播放 / 歌词 / 专辑 / 艺人)额外带氛围背景与 Home 指示条。
   ============================================================ */

/* ---------------- 图标 ---------------- */

const ICONS = {
  back:    '<path d="M15 18l-6-6 6-6"/>',
  more:    '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
  play:    '<path d="M8 5.5v13l11-6.5z" fill="currentColor" stroke="none"/>',
  pause:   '<rect x="7" y="5.5" width="3.6" height="13" rx="1.3" fill="currentColor" stroke="none"/><rect x="13.4" y="5.5" width="3.6" height="13" rx="1.3" fill="currentColor" stroke="none"/>',
  next:    '<path d="M6 5.8l9 6.2-9 6.2z" fill="currentColor" stroke="none"/><rect x="16" y="5.8" width="2.4" height="12.4" rx="1.2" fill="currentColor" stroke="none"/>',
  prev:    '<path d="M18 5.8l-9 6.2 9 6.2z" fill="currentColor" stroke="none"/><rect x="5.6" y="5.8" width="2.4" height="12.4" rx="1.2" fill="currentColor" stroke="none"/>',
  shuffle: '<path d="M4 7h3.2l9.6 10H20"/><path d="M4 17h3.2l9.6-10H20"/><path d="M17.4 4.4L20 7l-2.6 2.6M17.4 14.4L20 17l-2.6 2.6"/>',
  repeat:  '<path d="M7 7h10a3 3 0 0 1 3 3v1"/><path d="M17 17H7a3 3 0 0 1-3-3v-1"/><path d="M4.6 11.4L7 13.8l2.4-2.4M16.6 9.6L19 12l2.4-2.4"/>',
  heart:   '<path d="M12 19.6s-6.8-4.5-6.8-9.3A4.2 4.2 0 0 1 12 7.4a4.2 4.2 0 0 1 6.8 2.9c0 4.8-6.8 9.3-6.8 9.3z"/>',
  heartF:  '<path d="M12 19.6s-6.8-4.5-6.8-9.3A4.2 4.2 0 0 1 12 7.4a4.2 4.2 0 0 1 6.8 2.9c0 4.8-6.8 9.3-6.8 9.3z" fill="currentColor" stroke="none"/>',
  search:  '<circle cx="11" cy="11" r="6.2"/><path d="M15.6 15.6L20 20"/>',
  queue:   '<path d="M4 7h11M4 12h11M4 17h7"/><path d="M17.5 11.4v6.9a2.1 2.1 0 1 1-2.1-2.1"/>',
  lyrics:  '<path d="M9.6 7.5H5.4v5.2h4.2v-2.1c0-1.1.5-1.8 1.7-2.3M19 7.5h-4.2v5.2H19v-2.1c0-1.1.5-1.8 1.7-2.3"/>',
  server:  '<rect x="4" y="4.4" width="16" height="6.2" rx="2.1"/><rect x="4" y="13.4" width="16" height="6.2" rx="2.1"/><path d="M7.6 7.5h.01M7.6 16.5h.01"/>',
  gear:    '<circle cx="12" cy="12" r="3"/><path d="M12 3.6v2.1M12 18.3v2.1M4.9 7.8l1.8 1M17.3 15.2l1.8 1M4.9 16.2l1.8-1M17.3 8.8l1.8-1"/>',
  plus:    '<path d="M12 5v14M5 12h14"/>',
  check:   '<path d="M5 12.6l4.6 4.4L19 7.4"/>',
  wifi:    '<path d="M4 9.4a12 12 0 0 1 16 0M7.2 12.9a7.6 7.6 0 0 1 9.6 0M10.2 16.3a3.3 3.3 0 0 1 3.6 0"/><circle cx="12" cy="19.4" r="1.05" fill="currentColor" stroke="none"/>',
  cell:    '<rect x="3" y="14" width="3" height="6" rx="1"/><rect x="8" y="10.5" width="3" height="9.5" rx="1"/><rect x="13" y="7" width="3" height="13" rx="1"/><rect x="18" y="4" width="3" height="16" rx="1"/>',
  battery: '<rect x="3" y="8" width="16.5" height="8" rx="2.4"/><rect x="5" y="10" width="11.5" height="4" rx="1.2" fill="currentColor" stroke="none"/><path d="M21.4 11v2"/>',
  gauge:   '<path d="M4 17.5a8 8 0 1 1 16 0"/><path d="M12 17.5l4.4-5.4"/>',
  route:   '<circle cx="6" cy="6.5" r="2.3"/><circle cx="18" cy="17.5" r="2.3"/><path d="M8.3 6.5h5.2a3 3 0 0 1 0 6H9a3 3 0 0 0 0 6h6.7"/>',
  chevron: '<path d="M9.5 6l6 6-6 6"/>',
  x:       '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  refresh: '<path d="M19.6 11.4a7.8 7.8 0 1 0-2.1 5.7"/><path d="M19.8 5.6v5.8h-5.8"/>',
  sort:    '<path d="M4 7h9M4 12h6M4 17h4"/><path d="M17 6.5v11M17 17.5l3-3M17 17.5l-3-3"/>',
  download:'<path d="M12 4v9.6"/><path d="M8.2 10.6L12 14.4l3.8-3.8"/><path d="M5 19.2h14"/>',
  disc:    '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.3"/>',
  wave:    '<path d="M4 12h2.2M9 6.5v11M14 9v6M19.5 12H22"/>',
  book:    '<path d="M4 5.5A2 2 0 0 1 6 3.5h13v15H6a2 2 0 0 0-2 2z"/><path d="M4 18.5V5.5"/>',
  sparkle: '<path d="M12 4l1.9 5.1L19 11l-5.1 1.9L12 18l-1.9-5.1L5 11l5.1-1.9z"/>',
  bell:    '<path d="M18 9a6 6 0 1 0-12 0c0 5-2 6-2 6h16s-2-1-2-6"/><path d="M13.7 19.5a2 2 0 0 1-3.4 0"/>',
  shield:  '<path d="M12 3.6l7 2.6v5.4c0 4.3-3 7.3-7 8.8-4-1.5-7-4.5-7-8.8V6.2z"/>',
  play2:   '<circle cx="12" cy="12" r="8.4"/><path d="M10.2 8.8l5.6 3.2-5.6 3.2z" fill="currentColor" stroke="none"/>',
  theme:   '<circle cx="12" cy="12" r="8.2"/><path d="M12 3.8v16.4" /><path d="M12 3.8a8.2 8.2 0 0 0 0 16.4z" fill="currentColor" stroke="none"/>',
};

function ic(name, size = 22, cls = '') {
  return `<svg class="${cls}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
}

/* ---------------- 数据 ---------------- */

const SERVER = {
  name: '客厅 Navidrome',
  kind: 'Navidrome',
  user: 'hhy',
  songs: 529,
  routes: [
    { id: 'lan',  name: '局域网直连', url: 'http://192.168.10.4:4533',   ping: 12,   state: 'ok',   tag: '内网', bars: 4 },
    { id: 'ddns', name: '外网域名',   url: 'https://music.example.com',  ping: 86,   state: 'ok',   tag: '公网', bars: 3 },
    { id: 'v6',   name: 'IPv6 直连',  url: 'http://[240e:390:...]:4533', ping: null, state: 'bad',  tag: '公网', bars: 0 },
  ],
};

const ALBUMS = [
  { id: 'a1', name: '可能',                   artist: '程响',         year: 2022, count: 8,  c1: '#43305A', c2: '#140F22', accent: '#B891FF', mark: '可能' },
  { id: 'a2', name: 'Ultraviolet',            artist: '3LAU',         year: 2018, count: 1,  c1: '#233573', c2: '#0A1029', accent: '#7C96FF', mark: 'UV' },
  { id: 'a3', name: '秋色',                   artist: '拾光乐队',      year: 2021, count: 11, c1: '#6B4526', c2: '#1F1207', accent: '#EFA85F', mark: '秋色' },
  { id: 'a4', name: 'Islands',                artist: 'King Crimson', year: 1971, count: 6,  c1: '#12544A', c2: '#061A1B', accent: '#4DE0C8', mark: 'Is' },
  { id: 'a5', name: '山丘',                   artist: '李宗盛',        year: 2013, count: 5,  c1: '#5C3630', c2: '#1A0E0C', accent: '#F08A76', mark: '山丘' },
  { id: 'a6', name: 'Random Access Memories', artist: 'Daft Punk',    year: 2013, count: 13, c1: '#4A4A4A', c2: '#101010', accent: '#F2E3A8', mark: 'RAM' },
];

/* 曲目摊到全部六张专辑上,而不是五首都挂在《可能》名下 ——
   否则点进任何一张专辑看到的都是同一批歌,专辑页的曲目表就失去了意义。
   album / artist 两个字段是冗余的(albumOf() 查得出来),但列表行到处在用,
   留在数据里比每次查表省事;顺便按各张专辑的实际首数配了曲序。 */
const SONGS = [
  { id: 's1',  no: 1, title: '可能',        artist: '程响',         album: '可能',       albumId: 'a1', dur: 218, fmt: 'FLAC', kbps: 780, fav: true  },
  { id: 's2',  no: 2, title: '人间烟火',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 245, fmt: 'FLAC', kbps: 812, fav: false },
  { id: 's3',  no: 3, title: '四季予你',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 232, fmt: 'FLAC', kbps: 764, fav: false },
  { id: 's4',  no: 4, title: '等你归来',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 258, fmt: 'FLAC', kbps: 798, fav: true  },
  { id: 's5',  no: 5, title: '时光洪流',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 224, fmt: 'FLAC', kbps: 770, fav: false },
  { id: 's6',  no: 1, title: 'Ultraviolet', artist: '3LAU',         album: 'Ultraviolet', albumId: 'a2', dur: 232, fmt: 'FLAC', kbps: 921, fav: true },
  { id: 's7',  no: 1, title: '山色入秋',    artist: '拾光乐队',     album: '秋色',       albumId: 'a3', dur: 246, fmt: 'FLAC', kbps: 806, fav: false },
  { id: 's8',  no: 2, title: '晚风信',      artist: '拾光乐队',     album: '秋色',       albumId: 'a3', dur: 219, fmt: 'FLAC', kbps: 788, fav: false },
  { id: 's9',  no: 3, title: '落叶有信',    artist: '拾光乐队',     album: '秋色',       albumId: 'a3', dur: 268, fmt: 'FLAC', kbps: 794, fav: true  },
  { id: 's10', no: 1, title: 'The Letters', artist: 'King Crimson', album: 'Islands',    albumId: 'a4', dur: 267, fmt: 'FLAC', kbps: 861, fav: false },
  { id: 's11', no: 1, title: '山丘',        artist: '李宗盛',       album: '山丘',       albumId: 'a5', dur: 352, fmt: 'FLAC', kbps: 812, fav: true  },
  { id: 's12', no: 2, title: '给自己的歌',  artist: '李宗盛',       album: '山丘',       albumId: 'a5', dur: 379, fmt: 'FLAC', kbps: 826, fav: false },
  { id: 's13', no: 1, title: 'Get Lucky',     artist: 'Daft Punk',  album: 'Random Access Memories', albumId: 'a6', dur: 369, fmt: 'FLAC', kbps: 934, fav: false },
  { id: 's14', no: 2, title: 'Instant Crush', artist: 'Daft Punk',  album: 'Random Access Memories', albumId: 'a6', dur: 337, fmt: 'FLAC', kbps: 902, fav: false },
];

const ARTISTS = [
  { id: 'ar1', name: '程响',         albums: 6,  songs: 42,  c1: '#43305A', c2: '#140F22', accent: '#B891FF' },
  { id: 'ar2', name: '陈奕迅',       albums: 24, songs: 310, c1: '#26365C', c2: '#0A0F1F', accent: '#7C96FF' },
  { id: 'ar3', name: '李宗盛',       albums: 12, songs: 128, c1: '#5C3630', c2: '#1A0E0C', accent: '#F08A76' },
  { id: 'ar4', name: 'King Crimson', albums: 9,  songs: 86,  c1: '#12544A', c2: '#061A1B', accent: '#4DE0C8' },
  { id: 'ar5', name: '3LAU',         albums: 3,  songs: 24,  c1: '#233573', c2: '#0A1029', accent: '#7C96FF' },
  { id: 'ar6', name: '柳爽',         albums: 4,  songs: 37,  c1: '#38294A', c2: '#130E1C', accent: '#A88BFF' },
];

const PLAYLISTS = [
  { id: 'p1', name: '深夜通勤',     count: 32, desc: '低速、情绪化、适合夜色', c1: '#1B2440', c2: '#0A0F1C', accent: '#6E8BFF' },
  { id: 'p2', name: '工作专注',     count: 58, desc: '器乐为主，无人声干扰',   c1: '#14342E', c2: '#08170F', accent: '#4FD8C4' },
  { id: 'p3', name: '华语民谣精选', count: 41, desc: '长期收藏，持续更新',     c1: '#4A2E2A', c2: '#180F0E', accent: '#E0796A' },
  { id: 'p4', name: '电子脉冲',     count: 27, desc: '高能量，适合运动',       c1: '#1E2A5E', c2: '#0C1024', accent: '#7B8CFF' },
];

/* 歌词为中性占位文字,不使用任何真实歌词 */
const LYRICS = [
  '夜色铺开得像一条河', '我数着路灯慢慢走过',
  '风把声音吹得很轻',   '有些话就不必再说',
  '远处的窗口亮着灯火', '每扇门后都有自己的歌',
  '我把耳机调得再大一点', '让世界安静地退后',
  '这条路我走过很多次',  '每次都想停下又不肯',
];

const QUALITIES = [
  { id: 'original', name: '原音直出', desc: '不转码，按原始文件播放。仅建议在局域网使用。', tag: '无损' },
  { id: 'high',     name: '高质量',   desc: '转码为 320 kbps。音质接近原始，流量约减半。' },
  { id: 'medium',   name: '均衡',     desc: '转码为 192 kbps。移动网络下推荐，拖动进度更快。' },
  { id: 'low',      name: '省流',     desc: '转码为 96 kbps。弱网或流量紧张时使用。' },
];

const STATE = {
  theme: 'dark',
  quality: 'medium',
  routeId: 'lan',
  view: 'servers',
  albumId: 'a1',
  artistId: 'ar1',
  songId: 's1',
  params: {},
  overlay: '',
  history: [],
  /* 收藏只记在本地。原型不连服务器,所以这份名单就是「这台设备上点过心的地方」——
     播放页的心、专辑页/艺人页的心都写这里,重绘后各处的实心/空心才对得上。 */
  fav: { songs: new Set(SONGS.filter((s) => s.fav).map((s) => s.id)), albums: new Set(), artists: new Set() },
  /* 播放进度按秒存,不按百分比 —— 换歌时百分比会留在同一处,
     看起来像是「每首歌都恰好停在 38%」;按秒存则换算出来是新歌自己的位置。 */
  playing: true,
  elapsed: 83,
  /* 搜索页与添加服务器页的实时状态 —— 输入框、分段选中都要有反馈 */
  query: '程响',
  scope: 'all',
  kind: 'navidrome',
  /* 设置里可翻转的几个开关 */
  autoRoute: true,
  bgPlay: true,
  wifiOnly: false,
  pinging: false,
  /* 播放页两个模式按钮 */
  shuffle: false,
  repeat: false,
};

/* 进度换算:秒 → 百分比(夹在 0..100) */
function progressOf(song, sec) {
  return Math.max(0, Math.min(100, (sec / song.dur) * 100));
}

const THEMES = [
  { id: 'dark',  name: '深色', desc: '近黑底，靠光晕撑层次' },
  { id: 'light', name: '浅色', desc: '浅灰底，靠留白与描边' },
];

/* ---- 强调色 ----
   --accent      画描边 / 光晕 / 选中底色,保留封面原色
   --accent-safe 只用来画文字。浅色底上,黄 / 绿 / 青这类高亮色对比度不够,
                 逐档压深到阈值以下再用;深色底原样使用。 */
const ACCENT_CEIL = 168;

function safeAccent(hex) {
  if (STATE.theme !== 'light') return hex;
  const m = /^#([0-9A-Fa-f]{6})$/.exec(String(hex || '').trim());
  if (!m) return hex;
  const n = parseInt(m[1], 16);
  let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  for (let i = 0; i < 8 && Math.max(r, g, b) > ACCENT_CEIL; i++) {
    r = Math.round(r * 0.86); g = Math.round(g * 0.86); b = Math.round(b * 0.86);
  }
  return '#' + [r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('');
}

function accentVars(accent) {
  const a = accent || '#7C8CFF';
  return `--accent:${a};--accent-safe:${safeAccent(a)};`;
}

function applyTheme(id) {
  STATE.theme = id === 'light' ? 'light' : 'dark';
  document.body.dataset.theme = STATE.theme;
}

/* ---------------- 小工具 ---------------- */

const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

const albumOf   = (s) => ALBUMS.find((x) => x.id === s.albumId) || ALBUMS[0];
const ALBUM_BY_ID  = (id) => ALBUMS.find((x) => x.id === id) || ALBUMS[0];
const ARTIST_BY_ID = (id) => ARTISTS.find((x) => x.id === id) || ARTISTS[0];
const currentSong = () => SONGS.find((x) => x.id === STATE.songId) || SONGS[0];
const currentAlbum = () => albumOf(currentSong());

/* 真实关系一律从 SONGS 现推,不再另开一份手写的曲目表 ——
   两份数据迟早会各说各话。
   注意这里的库是「抽样」的:服务器页写着 529 首,ALBUMS 里的 count 也是整张专辑的真实首数,
   而 SONGS 只放了其中若干首。所以专辑页的曲目会比头部数字少,这是有意的,
   页脚会用一行小字把这件事说清楚,免得看起来像漏数据。 */
const tracksOf = (albumId)    => SONGS.filter((s) => s.albumId === albumId);
const songsOf  = (artistName) => SONGS.filter((s) => s.artist === artistName);

/* 择优结果:延迟最低的那条可用线路。两处要用,所以提到外面来一份。 */
const bestRoute = () =>
  SERVER.routes.filter((r) => r.state === 'ok').sort((a, b) => a.ping - b.ping)[0];

/* 专辑头部点艺人名要能跳过去,而专辑数据里只有艺人名字。
   查得到就给 id;原型库里没有这位艺人(比如拾光乐队)就返回 undefined,
   data-artist 不落值,那处文字就只是文字 —— 比点了跳到别处强。 */
const artistIdOf = (name) => (ARTISTS.find((a) => a.name === name) || {}).id;

/* 版式散列:同一批封面要有各自的长相,不能六张一个模子。 */
function coverSeed(item) {
  const k = String(item.id || item.name || item.title || '');
  let n = 0;
  for (let i = 0; i < k.length; i++) n = (n * 31 + k.charCodeAt(i)) % 997;
  return n;
}

function cover(item, cls = '', mark = null, extra = '') {
  const accent = item.accent || '#7C8CFF';
  const style = `--c1:${item.c1};--c2:${item.c2};${accentVars(accent)}${extra}`;
  const m = String(mark ?? item.mark ?? (item.name || item.title || '').slice(0, 2));
  const len = m.length > 4 ? 4 : m.length;

  /* 大封面上把专辑名当成封面的排版元素排出来,而不是只丢两个首字 ——
     首字只在小尺寸下成立(列表行 52px、播放坞 46px),一放大到网格与播放页
     就成了占位图。这里给三种版式,按 id 散列挑一种,再按名字长短定字号档。
     显不显示交给容器查询:同一个 .cover,尺寸够大才长出这层排版。 */
  const title = String(item.name || item.title || '');
  const by = String(item.artist || (item.count ? item.count + ' 首' : ''));
  const seed = coverSeed(item);
  const size = title.length <= 4 ? 0 : title.length <= 8 ? 1 : title.length <= 14 ? 2 : 3;

  return `<div class="cover ${cls}" style="${style}" data-art="${item.id || ''}">
    <span class="cover-mark" data-len="${len}">${m}</span>
    <div class="cover-art" data-layout="${seed % 3}" data-size="${size}">
      <div class="art-word">${title}</div>
      ${by ? `<div class="art-by">${by}</div>` : ''}
    </div>
    <span class="cover-ring" aria-hidden="true"></span>
  </div>`;
}

/* 艺人头像块:大初始字 + 渐变 */
function plate(ar, size = '152px', radius = '26px') {
  return `<div class="artist-tile" style="flex:0 0 ${size}">
    <div class="plate" style="--c1:${ar.c1};--c2:${ar.c2};${accentVars(ar.accent)}height:${size}">
      <span>${ar.name.slice(0, 2)}</span>
    </div>
  </div>`;
}

function avatar(ar, size = 52) {
  const accent = ar.accent || '#7C8CFF';
  return `<div class="avatar" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.34)}px;
    background-image:radial-gradient(90% 76% at 22% 10%,color-mix(in srgb,${accent} 60%,transparent),transparent 64%),
    linear-gradient(150deg,${ar.c1},${ar.c2})">${ar.name.slice(0, 2)}</div>`;
}

function statusbar() {
  return `<div class="statusbar">
    <span>22:41</span>
    <span class="sb-right">${ic('cell', 15)}${ic('wifi', 15)}${ic('battery', 22)}</span>
  </div>`;
}

/* 组装一整台手机:外框 + 灵动岛 + 状态栏 + 内容。
   accent 要写在 .screen 上而不是只写在氛围层里 —— 沉浸式页面的进度条、播放键、
   选中胶囊都在氛围层的兄弟节点上,变量挂在氛围层上的话它们一个也继承不到,
   会退回 :root 的默认紫。这正是「随封面取色」看上去只对了一半的原因。 */
function shell(inner, opts = {}) {
  const accent = opts.accent ? accentVars(opts.accent) : '';
  const c1 = opts.c1 ? `--c1:${opts.c1};` : '';
  const home = opts.home ? '<div class="home-ind"></div>' : '';
  return `<div class="phone">
    <div class="island"></div>
    <div class="screen" style="${accent}${c1}">${statusbar()}${inner}</div>
    ${home}
  </div>`;
}

/* 沉浸式页面的氛围背景(跟随当前封面取色) */
function ambient(album) {
  return `<div class="ambient" style="${accentVars(album.accent)}--c1:${album.c1}"></div>`;
}

function tabbar(active) {
  const tabs = [
    ['library',  'book',   '音乐库'],
    ['search',   'search', '搜索'],
    ['settings', 'gear',   '设置'],
  ];
  return `<nav class="tabbar">${tabs.map(([id, icon, label]) =>
    `<button data-tab="${id}" aria-selected="${active === id}">${ic(icon, 21)}<span>${label}</span></button>`
  ).join('')}</nav>`;
}

function dock(song = currentSong(), pct = progressOf(song, STATE.elapsed)) {
  const a = albumOf(song);
  return `<div class="dock" data-go="player">
    ${cover(a, '', song.title.slice(0, 2), 'width:46px;height:46px;border-radius:13px')}
    <div class="grow">
      <div class="line1">${song.title}</div>
      <div class="line2">${song.artist} · ${a.name}</div>
    </div>
    <button class="icon-btn" data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 25)}</button>
    <button class="icon-btn" data-act="next">${ic('next', 23)}</button>
    <div class="dock-progress"><i style="width:${pct}%"></i></div>
  </div>`;
}

const bottom = (song, pct, active) =>
  `<div class="bottomstack">${dock(song, pct)}${tabbar(active)}</div>`;

/* ---------------- 服务器与线路 ---------------- */

function signalBars(n) {
  return `<span class="sig">${[1, 2, 3, 4].map((i) => `<i class="${i <= n ? 'on' : ''}"></i>`).join('')}</span>`;
}

function routeRows(routes, withCheck, pageAccent) {
  return routes.map((r) => {
    const sel = r.id === STATE.routeId;
    const right = r.state === 'bad'
      ? `<div class="ms"><b style="color:var(--bad);font-size:13px">不可用</b><small>连接超时</small></div>`
      : `<div class="ms"><b>${r.ping}</b><small>ms</small></div>`;
    return `<div class="route ${sel ? 'selected' : ''}" data-route="${r.id}"
        ${withCheck ? `role="radio" aria-selected="${sel}"` : ''}>
      ${withCheck ? `<span class="tick">${ic('check', 14)}</span>` : `<span class="dot ${r.state}"></span>`}
      <div class="grow">
        <div class="rname">${r.name}<span class="tag">${r.tag}</span></div>
        <div class="rurl">${r.url}</div>
      </div>
      ${r.state === 'ok' ? signalBars(r.bars) : ''}
      ${right}
    </div>`;
  }).join('');
}

function screenServers() {
  const best = bestRoute();
  return `<div class="appbar">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <div>
        <div class="h1">服务器</div>
        <div class="sub">1 个已连接 · ${SERVER.routes.length} 条线路</div>
      </div>
    </div>
    <div class="scroll">
      <div class="server-hero">
        <div class="top">
          <div class="badge">ND</div>
          <div class="grow" style="min-width:0">
            <div class="nm">${SERVER.name}</div>
            <div class="sub"><span class="dot ok"></span>${SERVER.kind} · ${SERVER.user}</div>
          </div>
          <button class="icon-btn quiet" data-go="server-config">${ic('more', 20)}</button>
        </div>
        <div class="stat">
          <div>
            <div class="k">正在使用</div>
            <div class="v" style="font-size:17px">${best.name}</div>
          </div>
          <div style="text-align:right">
            <div class="k">延迟</div>
            <div class="v">${best.ping}<small>ms</small></div>
          </div>
          <div style="text-align:right">
            <div class="k">曲库</div>
            <div class="v">${SERVER.songs}<small>首</small></div>
          </div>
        </div>
      </div>

      <div class="section">
        <h2>线路</h2>
        <span class="count">${SERVER.routes.length} 条</span>
        <span class="spacer" style="flex:1"></span>
        <button class="chip" data-act="ping-all" style="height:30px" aria-selected="${STATE.pinging}">${ic('refresh', 14)} ${STATE.pinging ? '测速中' : '重新测速'}</button>
      </div>
      <div class="card" style="margin:0 var(--s5)">${routeRows(SERVER.routes, true)}</div>
      <div style="padding:var(--s4) var(--s5) 0">
        <button class="btn ghost" data-go="server-config" style="height:48px">${ic('plus', 18)} 添加线路</button>
      </div>

      <div class="section"><h2>其他服务器</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" data-go="library">
          <div class="badge" style="width:52px;height:52px;border-radius:18px;display:grid;place-items:center;
            background:var(--fill-2);color:var(--fg-2);font-weight:700;font-size:15px;flex:0 0 auto">飞牛</div>
          <div class="grow">
            <div class="line1">飞牛音乐</div>
            <div class="line2">192.168.10.9 · 未连接</div>
          </div>
          ${ic('chevron', 18)}
        </div>
      </div>

      <div style="padding:var(--s6) var(--s5) var(--s4)">
        <button class="btn primary" data-go="add-server">${ic('plus', 20)} 添加服务器</button>
      </div>
    </div>
    ${bottom()}`;
}

function screenServerConfig() {
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">服务器设置</span>
      <span class="spacer"></span>
      <button class="pill-btn solid">保存</button>
    </div>
    <div class="scroll">
      <div style="padding:var(--s2) var(--s5) 0;display:flex;flex-direction:column;gap:var(--s4)">
        <div class="field">
          <label>接入类型</label>
          <div class="segmented">
            <button aria-selected="true">Navidrome</button><button>Subsonic</button><button>飞牛音乐</button>
          </div>
        </div>
        <div class="field"><label>显示名称</label>
          <div class="input"><input value="客厅 Navidrome"></div>
        </div>
        <div class="field">
          <label>用户名 / 密码</label>
          <div class="input">${ic('server', 18, 'quiet')}<input value="hhy"></div>
          <div class="input" style="margin-top:var(--s2)"><input type="password" value="password"></div>
          <div class="hint">凭据只存在本机，登录时用密码派生令牌，不保存明文。</div>
        </div>
      </div>

      <div class="section">
        <h2>线路</h2>
        <span class="count">一个账号，多个地址</span>
      </div>
      <div class="card" style="margin:0 var(--s5)">${routeRows(SERVER.routes, false)}</div>
      <div style="padding:var(--s4) var(--s5) 0">
        <button class="btn ghost" style="height:48px">${ic('plus', 17)} 添加线路地址</button>
      </div>

      <div class="section"><h2>线路择优</h2></div>
      <div class="card" style="margin:0 var(--s5);padding:var(--s5)">
        <div style="display:flex;align-items:center;gap:10px">
          ${ic('gauge', 19, 'quiet')}
          <span style="font-weight:660;font-size:15px">自动择优已开启</span>
          <span class="spacer" style="flex:1"></span>
          <span style="font-size:11px;color:var(--fg-3)">2 分钟前测速</span>
        </div>
        <div style="font-size:13px;color:var(--fg-2);line-height:1.65;margin-top:12px">
          ${SERVER.kind} · ${SERVER.routes.length} 条线路 · 自动择优。当前走 ${bestRoute().name}。
        </div>
        <div style="display:flex;align-items:center;gap:var(--s2);margin-top:var(--s4)">
          <button class="chip" data-act="ping-all" style="height:32px" aria-selected="${STATE.pinging}">${ic('refresh', 14)} ${STATE.pinging ? '测速中' : '立即测速'}</button>
          <span class="spacer" style="flex:1"></span>
          <span style="font-size:11px;color:var(--ok)">${SERVER.routes.length} 条线路中 ${SERVER.routes.filter((r) => r.state === 'ok').length} 条可用</span>
        </div>
      </div>

      <div style="padding:var(--s6) var(--s5) var(--s6)">
        <button class="chip" style="height:40px;color:var(--bad);border-color:color-mix(in srgb,var(--bad) 30%,transparent);
          background:color-mix(in srgb,var(--bad) 9%,transparent)">移除该服务器</button>
      </div>
    </div>`;
}

function screenAddServer() {
  const kinds = [
    ['ND', 'Navidrome', '开源音乐服务器，Subsonic 兼容', '#7C8CFF', 'navidrome'],
    ['SU', 'Subsonic / OpenSubsonic', 'Airsonic、Gonic、Ampache 等', '#4FD8C4', 'subsonic'],
    ['FN', '飞牛音乐', 'fnOS 自带的音乐服务', '#FFA45C', 'fnos'],
  ];
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">添加服务器</span>
    </div>
    <div class="scroll" style="padding:0 var(--s5)">
      <div style="font-size:13px;color:var(--fg-2);line-height:1.7;padding:var(--s2) 0 var(--s5)">
        选择接入类型。不确定的话选 Subsonic，大多数兼容服务器都能用它接进来。
      </div>
      ${kinds.map(([m, name, desc, col, kind]) => {
        const on = STATE.kind === kind;
        return `
        <div class="card" data-pick-kind="${kind}" role="radio" aria-selected="${on}" style="margin-bottom:var(--s3);padding:var(--s4);cursor:pointer;
          border-radius:var(--r-lg);border-color:${on ? `color-mix(in srgb,${col} 46%,transparent)` : 'var(--line)'};
          background:${on ? `color-mix(in srgb,${col} 8%,transparent)` : 'var(--fill-1)'}">
          <div style="display:flex;align-items:center;gap:var(--s3)">
            <div style="width:52px;height:52px;flex:0 0 auto;border-radius:var(--r-md);display:grid;place-items:center;
              font-weight:760;font-size:17px;letter-spacing:-0.03em;
              background:linear-gradient(155deg,color-mix(in srgb,${col} 88%,#fff),${col});
              color:#08080E">${m}</div>
            <div class="grow" style="min-width:0">
              <div style="font-size:16px;font-weight:660;letter-spacing:-0.015em">${name}</div>
              <div style="font-size:13px;color:var(--fg-3);margin-top:4px">${desc}</div>
            </div>
            ${on ? `<span class="tick on">${ic('check', 14)}</span>` : ic('chevron', 18)}
          </div>
        </div>`;
      }).join('')}
      <div style="padding:var(--s5) 0 var(--s6)">
        <button class="btn primary" data-go="server-config">下一步</button>
      </div>
      <div class="note">飞牛音乐的接入基于社区逆向的接口，官方没有公开 API，可用性随系统版本变化。</div>
    </div>`;
}

/* ---------------- 音乐库 ---------------- */

function songRow(s, playing = false, trail = null) {
  const a = albumOf(s);
  return `<div class="row ${playing ? 'playing' : ''}" data-song="${s.id}">
    ${cover(a, '', s.title.slice(0, 2), 'width:52px;height:52px;border-radius:14px')}
    <div class="grow">
      <div class="line1">${s.title}</div>
      <div class="line2">${s.artist} · ${a.name}</div>
    </div>
    ${playing ? `<span class="bars"><i></i><i></i><i></i></span>` : ''}
    <span class="trail">${trail ?? mmss(s.dur)}</span>
  </div>`;
}

function screenLibrary(tab = 'albums') {
  const segs = [['albums', '专辑'], ['artists', '艺人'], ['songs', '歌曲'], ['playlists', '歌单']];
  const cur = currentSong();
  const curA = albumOf(cur);
  const pct = progressOf(cur, STATE.elapsed);
  let body = '';

  if (tab === 'albums') {
    body = `<div class="hero-card" style="${accentVars(curA.accent)}">
        ${cover(curA, '', curA.mark, 'width:92px;height:92px;border-radius:20px')}
        <div class="grow" style="min-width:0">
          <div class="label">${STATE.playing ? '继续收听' : '已暂停'}</div>
          <div class="t">${curA.name}</div>
          <div class="a">${curA.artist} · 播到 ${mmss(STATE.elapsed)} / ${mmss(cur.dur)}</div>
        </div>
        <button class="go" data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 20)}</button>
      </div>
      <div class="prog-line" style="margin:0 var(--s5) var(--s5)"><i style="width:${pct}%"></i></div>
      <div class="section"><h2>全部专辑</h2><span class="count">${ALBUMS.length} 张</span></div>
      <div class="grid-covers">${ALBUMS.map((a) => `
        <div class="album-tile" data-album="${a.id}" data-morph>
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.artist} · ${a.year}</div></div>
        </div>`).join('')}</div>
      <div class="section"><h2>最近添加</h2><span class="trail">10 月 12 日扫描</span></div>
      <div class="rail"><div class="rail-track">${ALBUMS.slice(2).map((a) => `
        <div class="rail-item" data-album="${a.id}">
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.artist}</div></div>
        </div>`).join('')}</div></div>`;
  } else if (tab === 'artists') {
    body = `<div class="section"><h2>常听艺人</h2><span class="count">${ARTISTS.length} 位</span></div>
      <div class="rail"><div class="rail-track">${ARTISTS.slice(0, 4).map((ar) => `
        <div class="artist-tile" data-artist="${ar.id}">
          <div class="plate" style="--c1:${ar.c1};--c2:${ar.c2};${accentVars(ar.accent)}"><span>${ar.name.slice(0, 2)}</span></div>
          <div><div class="name">${ar.name}</div><div class="meta">${ar.albums} 张专辑</div></div>
        </div>`).join('')}</div></div>
      <div class="section"><h2>全部艺人</h2></div>
      ${ARTISTS.map((ar) => `
        <div class="row" data-artist="${ar.id}">
          ${avatar(ar)}
          <div class="grow"><div class="line1">${ar.name}</div><div class="line2">${ar.albums} 张专辑 · ${ar.songs} 首</div></div>
          ${ic('chevron', 18)}
        </div>`).join('')}`;
  } else if (tab === 'songs') {
    body = `<div class="section"><h2>全部歌曲</h2><span class="count">${SONGS.length} 首</span></div>
      ${SONGS.map((s) => songRow(s, s.id === cur.id)).join('')}`;
  } else {
    body = `<div class="section"><h2>我的歌单</h2><span class="count">${PLAYLISTS.length} 个</span></div>
      ${PLAYLISTS.map((p) => `
        <div class="row" style="height:72px">
          ${cover(p, '', p.name.slice(0, 2), 'width:56px;height:56px;border-radius:16px')}
          <div class="grow"><div class="line1">${p.name}</div><div class="line2">${p.count} 首 · ${p.desc}</div></div>
          ${ic('chevron', 18)}
        </div>`).join('')}
      <div style="padding:var(--s5) var(--s5) var(--s4)">
        <button class="btn ghost" style="height:48px">${ic('plus', 17)} 新建歌单</button>
      </div>`;
  }

  return `<div class="appbar">
      <div>
        <div class="h1">音乐库</div>
        <div class="sub">${SERVER.name} · ${SERVER.songs} 首</div>
      </div>
      <span class="spacer"></span>
      <button class="icon-btn quiet" data-go="search">${ic('search', 21)}</button>
    </div>
    <div style="padding:0 var(--s5) var(--s4)">
      <div class="segmented">${segs.map(([id, label]) =>
        `<button data-lib="${id}" aria-selected="${tab === id}">${label}</button>`).join('')}</div>
    </div>
    <div class="scroll">${body}<div style="height:var(--s5)"></div></div>
    ${bottom(cur, pct, 'library')}`;
}

/* 曲目行:专辑页与艺人页共用一份标记。
   number 传 null 表示不排曲序(艺人页的「热门」是按播放量排的,序数没有意义);
   播放中的那一行用跳动的竖条顶掉曲序,而不是两个都留在行里。 */
function trackRow(s, { number = null, playing = false, line2 = null } = {}) {
  const detail = line2 ?? `${s.fmt} · ${s.kbps} kbps`;
  return `<div class="row ${playing ? 'playing' : ''}" data-song="${s.id}">
    ${playing
      ? `<span class="track-no bars" style="width:24px"><i></i><i></i><i></i></span>`
      : `<span class="track-no">${number ?? ''}</span>`}
    <div class="grow">
      <div class="line1">${s.title}</div>
      <div class="line2">${detail}</div>
    </div>
    <span class="trail">${mmss(s.dur)}</span>
  </div>`;
}

function screenAlbum(id) {
  const a = ALBUMS.find((x) => x.id === id) || ALBUMS[0];
  /* 曲目从 SONGS 里按专辑过滤 —— 之前这里写死了全局 SONGS,
     于是六张专辑点进去看到的都是程响那五首。 */
  const tracks = tracksOf(a.id);
  const cur = currentSong();
  const firstId = (tracks[0] || cur).id;
  const faved = STATE.fav.albums.has(a.id);
  const rows = tracks.map((s) => trackRow(s, {
    number: s.no,
    playing: STATE.playing && s.id === cur.id,
  })).join('');
  /* 抽样说明:tracks 只有几首,而头部写着这张专辑的真实首数(比如 count 13)。
     两处对不上会让人以为是漏数据,所以在末尾把这件事讲明。 */
  const rest = a.count - tracks.length;
  const more = rest > 0
    ? `<div class="list-note">原型只带了这张专辑的 ${tracks.length} 首，库里还有 ${rest} 首未列出。</div>`
    : '';

  return `${ambient(a)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('download', 21)}</button>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>
    <div class="scroll">
      <div class="album-head">
        ${cover(a, '', a.mark, 'width:140px;height:140px;border-radius:24px')}
        <div style="min-width:0">
          <div class="title">${a.name}</div>
          <div class="artist" data-artist="${artistIdOf(a.artist)}">${a.artist}</div>
          <div class="meta"><span>${a.year}</span>·<span>${a.count} 首</span>·<span>FLAC 无损</span></div>
        </div>
      </div>
      <div class="action-row">
        <button class="btn primary" data-song="${firstId}">${ic('play', 20)} 播放</button>
        <button class="icon-btn halo" style="width:48px;height:48px" data-act="shuffle">${ic('shuffle', 20)}</button>
        <button class="icon-btn halo" style="width:48px;height:48px;color:${faved ? 'var(--accent-safe)' : ''}" data-act="fav-album">${ic(faved ? 'heartF' : 'heart', 20)}</button>
        <button class="icon-btn halo" style="width:48px;height:48px" data-sheet="queue">${ic('queue', 20)}</button>
      </div>
      <div class="divider"></div>
      ${rows}
      ${more}
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(cur, progressOf(cur, STATE.elapsed))}`;
}

function screenArtist(id) {
  const ar = ARTISTS.find((x) => x.id === id) || ARTISTS[0];
  const alb = { c1: ar.c1, c2: ar.c2, accent: ar.accent };
  /* 这位艺人在原型库里实际有的歌与专辑 —— 之前两者都写死了全局列表,
     于是每位艺人都挂着同样三首热歌和同样四张专辑。 */
  const mine = songsOf(ar.name);
  const albums = ALBUMS.filter((x) => x.artist === ar.name);
  const hot = mine.slice(0, 3);
  const cur = currentSong();
  const albumRail = albums.length
    ? `<div class="rail"><div class="rail-track">${albums.map((a) => `
        <div class="rail-item" data-album="${a.id}">
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.year}</div></div>
        </div>`).join('')}</div></div>
        ${albums.length < ar.albums ? `<div class="list-note">原型只收录了这位艺人的 ${albums.length} 张唱片,服务器上共有 ${ar.albums} 张。</div>` : ''}`
    : '';
  /* 播放键是整屏唯一的实心主按钮,库里没歌的艺人(比如陈奕迅)点它就会去播
     上一首别人的歌 —— 这一下等于对用户说了假话。这类艺人整行收掉,
     在旁边说明一句。剩下的圆按钮各自成行,不跟着一起消失。 */
  const playable = mine.length > 0;
  const faved = STATE.fav.artists.has(ar.id);
  return `${ambient(alb)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>
    <div class="scroll">
      <div style="padding:var(--s2) var(--s5) var(--s5);display:flex;align-items:center;gap:var(--s4);position:relative;z-index:1">
        <div class="plate" style="--c1:${ar.c1};--c2:${ar.c2};${accentVars(ar.accent)}
          width:104px;height:104px;flex:0 0 auto;border-radius:30px;display:grid;place-items:center;position:relative;overflow:hidden;
          background-image:radial-gradient(90% 76% at 22% 10%,color-mix(in srgb,${ar.accent} 58%,transparent),transparent 64%),
          linear-gradient(150deg,${ar.c1},${ar.c2});box-shadow:inset 0 1px 0 rgba(255,255,255,.15)">
          <span style="font-size:36px;font-weight:780;letter-spacing:-0.05em;color:rgba(255,255,255,.95)">${ar.name.slice(0, 2)}</span>
        </div>
        <div style="min-width:0">
          <div style="font-size:29px;font-weight:740;letter-spacing:-0.038em;line-height:1.1">${ar.name}</div>
          <div style="font-size:13px;color:var(--fg-3);margin-top:8px">${ar.albums} 张专辑 · ${ar.songs} 首歌曲</div>
        </div>
      </div>
      <div class="action-row">
        ${playable ? `<button class="btn primary" data-song="${hot[0].id}">${ic('play', 20)} 播放热门</button>` : ''}
        <button class="icon-btn halo" style="width:48px;height:48px" data-act="shuffle">${ic('shuffle', 20)}</button>
        <button class="icon-btn halo" style="width:48px;height:48px;color:${faved ? 'var(--accent-safe)' : ''}" data-act="fav-artist">${ic(faved ? 'heartF' : 'heart', 20)}</button>
        ${playable ? '' : `<span style="font-size:13px;color:var(--fg-3);line-height:1.6">原型里没有这位艺人的曲目,暂时没得可播。</span>`}
      </div>
      <div class="section"><h2>热门歌曲</h2><span class="count">${mine.length} 首</span></div>
      ${hot.length
        ? hot.map((s) => trackRow(s, { playing: STATE.playing && s.id === cur.id, line2: `${s.album} · ${s.fmt}` })).join('')
        : `<div class="list-note">${ar.name}的曲目在原型库里没有收录,真实客户端会在这里按播放量排满。</div>`}
      <div class="section"><h2>专辑</h2><span class="count">${albums.length ? `${albums.length} / ${ar.albums} 张` : `${ar.albums} 张`}</span></div>
      ${albumRail || `<div class="list-note">${ar.name}的专辑在原型库里没有收录,真实客户端会在这里铺满 ${ar.albums} 张。</div>`}
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(cur, progressOf(cur, STATE.elapsed))}`;
}

/* ---------------- 播放 ---------------- */

function screenPlayer() {
  const s = currentSong();
  const a = albumOf(s);
  const pct = progressOf(s, STATE.elapsed);
  const elapsed = Math.min(STATE.elapsed, s.dur);
  const q = QUALITIES.find((x) => x.id === STATE.quality) || QUALITIES[2];
  const route = SERVER.routes.find((r) => r.id === STATE.routeId) || SERVER.routes[0];
  const codec = STATE.quality === 'original' ? 'FLAC' : 'MP3';

  return `${ambient(a)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:11px;color:var(--fg-3);letter-spacing:0.1em;font-weight:660">正在播放</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>

    <div class="player-hero">
      <div class="hero-stack">
        <div class="vinyl${STATE.playing ? '' : ' paused'}" aria-hidden="true"><i></i></div>
        ${cover(a, 'sq', a.mark)}
      </div>
    </div>

    <div class="player-info">
      <div class="top-row">
        <div style="min-width:0">
          <div class="t">${s.title}</div>
          <div class="a"><span data-album="${a.id}">${s.artist} · ${a.name}</span></div>
        </div>
        <button class="icon-btn" style="color:${STATE.fav.songs.has(s.id) ? a.accent : 'var(--fg-2)'}" data-act="fav">
          ${ic(STATE.fav.songs.has(s.id) ? 'heartF' : 'heart', 25)}</button>
      </div>
    </div>

    <div class="scrub">
      <div class="track" data-seek><i style="width:${pct}%"></i><span class="knob" style="left:${pct}%"></span></div>
      <div class="times"><span>${mmss(elapsed)}</span><span>-${mmss(s.dur - elapsed)}</span></div>
    </div>

    <div class="controls">
      <button class="icon-btn${STATE.shuffle ? ' on' : ''}" style="color:${STATE.shuffle ? 'var(--accent-safe)' : ''}" data-act="shuffle">${ic('shuffle', 23)}</button>
      <button class="icon-btn" data-act="prev">${ic('prev', 27)}</button>
      <button class="play-btn" data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 30)}</button>
      <button class="icon-btn" data-act="next">${ic('next', 27)}</button>
      <button class="icon-btn${STATE.repeat ? ' on' : ''}" style="color:${STATE.repeat ? 'var(--accent-safe)' : ''}" data-act="repeat">${ic('repeat', 23)}</button>
    </div>

    <div class="chip-row-b">
      <button class="quality-chip on" data-sheet="quality">${ic('wave', 15)} ${q.name} · ${codec}</button>
      <span class="spacer" style="flex:1"></span>
      <button class="quality-chip" data-go="lyrics">${ic('lyrics', 15)} 歌词</button>
      <button class="quality-chip" data-sheet="queue">${ic('queue', 15)} 队列</button>
    </div>

    <div class="route-line" data-sheet="routes" style="cursor:pointer">
      <span class="dot ${route.state}"></span>
      线路 <b>${route.name}</b> · ${route.state === 'ok' ? `${route.ping} ms · ` : '不可用 · '}自动择优</div>`;
}

function sheetQuality() {
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>转码质量 <span>原文件 FLAC ${SONGS[0].kbps} kbps</span></h2>
      <div class="sheet-note">档位由服务器实时转码后推送。切到转码档后拖动进度会重新请求音频，可能有短暂停顿。</div>
      <div class="sheet-body">
        ${QUALITIES.map((q) => `
          <div class="qopt" data-quality="${q.id}" role="radio" aria-selected="${STATE.quality === q.id}">
            <div style="flex:1 1 auto">
              <div class="qname">${q.name}${q.tag ? `<span class="tag">${q.tag}</span>` : ''}</div>
              <div class="qdesc">${q.desc}</div>
            </div>
            <span class="tick">${ic('check', 14)}</span>
          </div>`).join('')}
      </div>
    </div>
  </div>`;
}

function sheetQueue() {
  const cur = currentSong();
  const total = SONGS.reduce((n, s) => n + s.dur, 0);
  const done = SONGS.slice(0, SONGS.findIndex((s) => s.id === cur.id)).reduce((n, s) => n + s.dur, 0);
  const rest = Math.max(0, total - done - STATE.elapsed);
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>播放队列 <span>${SONGS.length} 首 · 还有约 ${mmss(rest)}</span></h2>
      <div class="sheet-body">
        ${SONGS.map((s) => {
          const on = s.id === cur.id;
          const a = albumOf(s);
          return `<div class="row ${on ? 'playing' : ''}" data-song="${s.id}">
            <span style="width:18px;flex:0 0 auto;display:flex;color:var(--accent-safe)">${on && STATE.playing ? ic('wave', 16) : ''}</span>
            ${cover(a, '', s.title.slice(0, 2), 'width:46px;height:46px;border-radius:12px')}
            <div class="grow"><div class="line1">${s.title}</div><div class="line2">${s.artist}</div></div>
            <span class="trail">${mmss(s.dur)}</span>
          </div>`;
        }).join('')}
      </div>
    </div>
  </div>`;
}

function sheetRoutes() {
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>线路 <span>播放中可随时切换</span></h2>
      <div class="sheet-body">
        <div class="card" style="margin:0 var(--s5)">${routeRows(SERVER.routes, true)}</div>
        <div class="sheet-note" style="padding-top:var(--s4)">
          播放时优先走延迟最低的可用线路，当前线路中断会自动换到下一条并接着放。手动锁定后不再自动切换。
        </div>
      </div>
    </div>
  </div>`;
}

/* ---------------- 歌词 ---------------- */

function screenLyrics() {
  const s = currentSong();
  const a = albumOf(s);
  const pct = progressOf(s, STATE.elapsed);
  const elapsed = Math.min(STATE.elapsed, s.dur);
  /* 歌词随整首歌的进度同步推进:播到哪儿,高亮就挪到哪儿。
     activeIx 用秒的占比取整 —— 等价于切歌时高亮回到第一行,而不需要单独的状态。 */
  const activeIx = Math.min(LYRICS.length - 1, Math.floor((elapsed / s.dur) * LYRICS.length));
  return `${ambient(a)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:12px;color:var(--fg-2);font-weight:620">${s.title} · ${s.artist}</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>
    <div class="lyrics">
      ${LYRICS.map((l, i) => `<div class="lyric-line ${i === activeIx ? 'on' : i < activeIx ? 'past' : ''}">${l}</div>`).join('')}
    </div>
    <div class="scrub" style="padding-bottom:var(--s5)">
      <div class="track" style="height:5px" data-seek><i style="width:${pct}%"></i></div>
      <div class="times"><span>${mmss(elapsed)}</span><span>-${mmss(s.dur - elapsed)}</span></div>
    </div>
    <div style="display:flex;align-items:center;justify-content:center;gap:var(--s7);
      padding:0 var(--s6) var(--s5);position:relative;z-index:1">
      <button class="icon-btn" data-act="prev" style="width:52px;height:52px">${ic('prev', 26)}</button>
      <button class="play-btn" style="width:64px;height:64px;border-radius:var(--r-full);display:grid;place-items:center;
        color:var(--accent-ink);background:linear-gradient(155deg,color-mix(in srgb,var(--accent) 88%,#fff),var(--accent));
        box-shadow:0 18px 36px -12px color-mix(in srgb,var(--accent) 78%,transparent),inset 0 1px 0 rgba(255,255,255,.45)"
        data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 27)}</button>
      <button class="icon-btn" data-act="next" style="width:52px;height:52px">${ic('next', 26)}</button>
    </div>`;
}

/* ---------------- 搜索 ---------------- */

/* 关键词命中:标题、专辑名、艺人名任一包含即可。
   原型里不做分词也不做拼音,一律按子串匹配 —— 撑起「输入即出结果」这件事就够了。 */
function searchHits(q) {
  const k = String(q || '').trim().toLowerCase();
  if (!k) return { songs: [], albums: [], artists: [] };
  const hit = (...fields) => fields.some((f) => String(f || '').toLowerCase().includes(k));
  return {
    songs:   SONGS.filter((s) => hit(s.title, s.album, s.artist)),
    albums:  ALBUMS.filter((a) => hit(a.name, a.artist)),
    artists: ARTISTS.filter((a) => hit(a.name)),
  };
}

function screenSearch() {
  const q = STATE.query;
  const scope = STATE.scope;
  const hits = searchHits(q);
  const total = hits.songs.length + hits.albums.length + hits.artists.length;
  const show = (what) => scope === 'all' || scope === what;
  /* 分类胶囊是过滤器,所以标题上的数字也要跟着过滤走 —— 否则点「专辑」进来看见
     标题写着「1 条结果」、下面却一片空,像是结果没渲染出来。
     scope 的取值(songs / albums / artists)与 hits 的键同名,可以直接取。 */
  const inScope = scope === 'all' ? total : hits[scope].length;
  const cat = { songs: '歌曲', albums: '专辑', artists: '艺人' }[scope];
  const unit = { songs: '首', albums: '张', artists: '位' }[scope];
  /* 副标题跟着分类走:选了「专辑」就说这一档有几张,而不是全库总数。 */
  const subtitle = !q.trim() ? '全库检索'
    : scope === 'all' ? `${total} 条结果`
    : `${cat} · ${inScope} ${unit}`;

  const chips = [['all', '全部'], ['songs', '歌曲'], ['albums', '专辑'], ['artists', '艺人']]
    .map(([id, label]) => `<button class="chip" data-scope="${id}" aria-selected="${scope === id}">${label}</button>`).join('');
  const esc = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');

  let body;
  if (!q.trim()) {
    body = `<div class="search-empty">输入歌名、专辑或艺人，结果会按分类铺开。</div>`;
  } else if (!total) {
    body = `<div class="search-empty">没有匹配「${esc(q.trim())}」的内容。<br>换个关键词，或到服务器设置里重新扫描曲库。</div>`;
  } else {
    body = `
      ${show('songs') && hits.songs.length ? `
        <div class="section" style="padding-top:0"><h2>歌曲</h2><span class="count">${hits.songs.length} 首</span></div>
        ${hits.songs.map((s) => songRow(s, s.id === STATE.songId && STATE.playing)).join('')}` : ''}
      ${show('albums') && hits.albums.length ? `
        <div class="section"><h2>专辑</h2><span class="count">${hits.albums.length} 张</span></div>
        <div class="grid-covers">${hits.albums.map((a) => `
          <div class="album-tile" data-album="${a.id}" data-morph>
            ${cover(a, 'sq', a.mark)}
            <div><div class="name">${a.name}</div><div class="meta">${a.artist} · ${a.year}</div></div>
          </div>`).join('')}</div>` : ''}
      ${show('artists') && hits.artists.length ? `
        <div class="section"><h2>艺人</h2><span class="count">${hits.artists.length} 位</span></div>
        ${hits.artists.map((ar) => `
          <div class="row" data-artist="${ar.id}">
            ${avatar(ar)}
            <div class="grow"><div class="line1">${ar.name}</div><div class="line2">${ar.albums} 张专辑 · ${ar.songs} 首</div></div>
            ${ic('chevron', 18)}
          </div>`).join('')}` : ''}
      ${!inScope
        ? `<div class="search-empty">「${esc(q.trim())}」在${cat}里没有结果，换成「全部」看看。</div>` : ''}`;
  }

  return `<div class="appbar">
      <div><div class="h1">搜索</div><div class="sub">${subtitle}</div></div>
    </div>
    <div class="searchfield">
      ${ic('search', 19)}
      <input id="search-input" placeholder="歌曲、专辑、艺人" value="${esc(q)}"
        autocomplete="off" spellcheck="false">
      <button class="clr${q ? ' on' : ''}" data-act="clear-query" aria-label="清空">${ic('x', 16)}</button>
    </div>
    <div class="chip-row">${chips}</div>
    <div class="scroll">
      ${body}
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom()}`;
}

/* ---------------- 设置 ---------------- */

function screenSettings() {
  /* 四个开关都是活的：点一下翻转，行里立刻换勾选态。
     第一行的值不是开关而是当前档位，所以走 data-sheet 打开转码面板。 */
  const rows = [
    { key: 'quality', icon: 'wave',  t: '默认转码质量', d: '移动网络下生效', value: () =>
        (QUALITIES.find((x) => x.id === STATE.quality) || QUALITIES[2]).name, sheet: 'quality' },
    { key: 'autoRoute', icon: 'route', t: '线路自动择优', d: '按延迟选择最快可用地址', toggle: true },
    { key: 'bgPlay',    icon: 'bell',  t: '播放时后台运行', d: '通知栏与锁屏可控制',   toggle: true },
    { key: 'wifiOnly',  icon: 'download', t: '仅 Wi-Fi 下载', d: '避免消耗移动流量',  toggle: true },
  ];
  const themeRow = `
      <div class="section" style="padding-top:var(--s2)"><h2>外观</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" style="cursor:default">
          <span class="set-icon">${ic('theme', 18)}</span>
          <div class="grow"><div class="line1">主题</div><div class="line2">深色 / 浅色，两种主题共用同一份结构</div></div>
        </div>
        <div class="divider"></div>
        <div class="segmented" style="margin:var(--s3) var(--s4) var(--s3)">
          ${THEMES.map((t) => `<button data-set-theme="${t.id}" aria-selected="${STATE.theme === t.id}">${t.name}</button>`).join('')}
        </div>
      </div>`;
  return `<div class="appbar">
      <div><div class="h1">设置</div><div class="sub">Nordic 原型 v1</div></div>
    </div>
    <div class="scroll">
      ${themeRow}
      <div class="section"><h2>播放</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        ${rows.map((r, i) => {
          const on = STATE[r.key] !== false;
          return `
          ${i ? '<div class="divider"></div>' : ''}
          <div class="row" ${r.sheet ? `data-sheet="${r.sheet}"` : `data-toggle="${r.key}" role="switch" aria-checked="${on}"`}>
            <span class="set-icon">${ic(r.icon, 18)}</span>
            <div class="grow"><div class="line1">${r.t}</div><div class="line2">${r.d}</div></div>
            ${r.toggle
              ? `<span class="tick${on ? ' on' : ''}">${ic('check', 13)}</span>`
              : `<span class="trail" style="color:var(--fg-2)">${r.value()}</span>${ic('chevron', 17)}`}
          </div>`;
        }).join('')}
      </div>

      <div class="section"><h2>服务器</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" data-go="servers">
          <span class="set-icon">${ic('server', 18)}</span>
          <div class="grow"><div class="line1">${SERVER.name}</div>
            <div class="line2"><span class="dot ok"></span>${SERVER.kind} · ${SERVER.routes.length} 条线路 · 自动择优</div></div>
          ${ic('chevron', 18)}
        </div>
        <div class="divider"></div>
        <div class="row" data-go="add-server">
          <span class="set-icon">${ic('plus', 18)}</span>
          <div class="grow"><div class="line1">添加服务器</div></div>${ic('chevron', 18)}
        </div>
      </div>

      <div class="section"><h2>隐私</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row">
          <span class="set-icon">${ic('shield', 18)}</span>
          <div class="grow"><div class="line1">凭据仅存本机</div><div class="line2">不保存明文密码，也不上传任何数据</div></div>
        </div>
      </div>
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom()}`;
}

/* ---------------- 视图表 ---------------- */

const sheets = { quality: sheetQuality, queue: sheetQueue, routes: sheetRoutes };

/* 弹层是叠在当前屏上的，不是某一屏专属 —— 专辑页的「队列」、设置里的
   「默认转码质量」都要能把同一张面板揭起来。之前只有播放页拼了 overlay,
   于是另外两处点了没反应（点了跟没点一样）。统一在这里接。 */
const withOverlay = (inner) => inner + (STATE.overlay && sheets[STATE.overlay] ? sheets[STATE.overlay]() : '');

const VIEWS = {
  servers:        () => shell(screenServers()),
  'server-config':() => shell(screenServerConfig()),
  'add-server':   () => shell(screenAddServer()),
  library:        (p) => shell(screenLibrary((p && p.lib) || 'albums')),
  album:          (p) => { const a = ALBUM_BY_ID((p && p.album) || STATE.albumId); return shell(withOverlay(screenAlbum(a.id)), { home: true, accent: a.accent, c1: a.c1 }); },
  artist:         (p) => { const ar = ARTIST_BY_ID((p && p.artist) || STATE.artistId); return shell(screenArtist(ar.id), { home: true, accent: ar.accent, c1: ar.c1 }); },
  player:         () => shell(withOverlay(screenPlayer()), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 }),
  lyrics:         () => shell(screenLyrics(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 }),
  search:         () => shell(screenSearch()),
  settings:       () => shell(withOverlay(screenSettings())),
};

/* ============================================================
   设计板
   ============================================================ */

const BOARD = [
  ['服务器与线路',    '线路状态 / 自动择优',  () => shell(screenServers())],
  ['服务器设置',      '一个账号，多个地址',    () => shell(screenServerConfig())],
  ['添加服务器',      '选择接入类型',         () => shell(screenAddServer())],
  ['音乐库 · 专辑',   '继续收听 + 封面网格',  () => shell(screenLibrary('albums'))],
  ['音乐库 · 艺人',   '方块头像 + 常听',      () => shell(screenLibrary('artists'))],
  ['音乐库 · 歌曲',   '全部歌曲',             () => shell(screenLibrary('songs'))],
  ['音乐库 · 歌单',   '我的歌单',             () => shell(screenLibrary('playlists'))],
  /* 专辑 / 艺人 / 播放这几屏的强调色要跟着内容走，和交互流里走的是同一份取值 ——
     漏传的话这一格会退回默认紫，和旁边几格的「随封面取色」对不上。 */
  ['专辑详情',        '氛围背景 + 曲目',      () => shell(screenAlbum('a1'), { home: true, accent: ALBUM_BY_ID('a1').accent, c1: ALBUM_BY_ID('a1').c1 })],
  ['艺人详情',        '热门 + 专辑',          () => shell(screenArtist('ar1'), { home: true, accent: ARTIST_BY_ID('ar1').accent, c1: ARTIST_BY_ID('ar1').c1 })],
  ['播放页',          '封面主导 + 封面取色',  () => shell(screenPlayer(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  ['转码质量',        '四档位，含说明',       () => shell(screenPlayer() + sheetQuality(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  ['播放队列',        '队列管理',             () => shell(screenPlayer() + sheetQueue(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  ['线路切换',        '播放中改线路',         () => shell(screenPlayer() + sheetRoutes(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  ['歌词',            '逐句高亮',             () => shell(screenLyrics(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  ['搜索',            '输入即筛选',           () => shell(screenSearch())],
  ['设置',            '播放 / 服务器 / 隐私', () => shell(screenSettings())],
];

function boardFrames() {
  return BOARD.map(([title, sub, fn]) => `
    <div class="board-col">
      <div class="frame-label"><b>${title}</b>${sub ? `<i>${sub}</i>` : ''}</div>
      ${fn()}
    </div>`).join('');
}

function renderBoard(root) {
  /* 设计板也要看得见搜索页的真实样子 —— 直接拿「程响」去搜，
     铺出来的就是交互流里同一组结果，而不是一张手写的假结果。 */
  const prev = STATE.theme;
  STATE.query = STATE.query || '程响';
  const dark = (STATE.theme = 'dark', boardFrames());
  const light = (STATE.theme = 'light', boardFrames());
  STATE.theme = prev;
  root.innerHTML = `
    <div class="board-wrap">
      <div class="board-head">
        <h1>Nordic — 音乐播放器原型</h1>
        <p>手机竖屏，16 屏，<b>深色 / 浅色两套</b>。强调色<b>从当前封面里提取</b> —— 每张专辑驱动界面的光晕、进度条与选中态，
          所以每张专辑有自己的气质。深色靠发光撑层次，浅色把发光几乎关掉、改用留白与描边；两套共用同一份结构，差异全部落在 token 上。
          这是并排铺开的设计板；<b>要点击走完整条链路，请开 <a href="player.html">player.html</a></b>，那边的搜索、开关、进度都能直接上手点。</p>
      </div>

      <section class="board-sec" data-theme="dark">
        <div class="board-sec-head"><h2>深色</h2><span>近黑底 · 封面光晕 · 强调色不压深</span></div>
        <div class="board">${dark}</div>
      </section>

      <section class="board-sec" data-theme="light">
        <div class="board-sec-head"><h2>浅色</h2><span>浅灰底 · 留白与描边 · 高亮强调色自动压深以保证对比度</span></div>
        <div class="board">${light}</div>
      </section>
    </div>`;
}

/* ============================================================
   交互流
   ============================================================ */

function renderStage(root) {
  const slot = () => root.querySelector('#phone-slot');

  /* ---- 封面共享元素过渡 ----
     点专辑封面 → 播放页那一小段「封面飞过去并放大」的动画，用 View Transitions
     实现，比手写 FLIP 稳（框架自己管跨文档的快照与时长）。
     关键点：view-transition-name 在同一个状态里只能有一个元素持有，重名会被整条
     忽略掉，所以不能写死在标记里（网格里有 4 张专辑）。改成点击那一刻给被点的那张
     临时命名，入场完成后再撤掉 —— 这样任何时刻全局只有一个。 */
  const supportsVT = typeof document.startViewTransition === 'function';
  let morphEl = null;

  const clearMorph = () => {
    if (morphEl) { morphEl.style.viewTransitionName = ''; morphEl = null; }
  };

  const render = (morph = false) => {
    const view = VIEWS[STATE.view];
    if (!view) return;
    const paint = () => {
      slot().innerHTML = view(STATE.params);
    };

    if (!morph || !supportsVT) { clearMorph(); return paint(); }

    /* 起名必须在快照之前，撤名必须在快照之后，否则两端拿不到同一对元素。 */
    const named = [];
    if (morphEl) { morphEl.style.viewTransitionName = 'cover-art'; named.push(morphEl); }

    const t = document.startViewTransition(() => {
      paint();
      /* 播放页与专辑页的大封面在这里点名 —— 名字只在过渡期间挂着。
         不能图省事写成标记里的静态样式：t.finished 撤名时会连静态值一起抹掉，
         第一次过渡之后那处封面就再也当不了起点或终点。 */
      const hero = slot().querySelector('.player-hero .cover, .album-head .cover');
      if (hero) { hero.style.viewTransitionName = 'cover-art'; named.push(hero); }
    });
    t.finished.finally(() => { named.forEach((el) => { el.style.viewTransitionName = ''; }); });
    /* 起点是一次性的，用完就丢，免得下一次 back() 把它当成起点再点一次名。 */
    morphEl = null;
  };

  const go = (name, params) => {
    const morph = name === 'player' || name === 'album';
    if (name !== STATE.view) STATE.history.push({ view: STATE.view, params: STATE.params });
    STATE.view = name;
    STATE.params = params || {};
    STATE.overlay = '';
    render(morph);
  };

  const back = () => {
    const prev = STATE.history.pop();
    if (prev) {
      STATE.view = prev.view;
      STATE.params = prev.params || {};
    } else {
      STATE.view = 'library';
      STATE.params = { lib: 'albums' };
    }
    STATE.overlay = '';
    render(true);
  };

  root.innerHTML = `
    <div class="stage">
      <aside class="stage-side">
        <h2>可点击原型</h2>
        <ol>
          <li>服务器页有 3 条线路，已自动选中延迟最低的局域网直连</li>
          <li>点「音乐库」切换 专辑 / 艺人 / 歌曲 / 歌单</li>
          <li>点专辑或艺人进详情页；点歌曲进播放页，封面会飞过去</li>
          <li>搜索页可以直接打字，结果是实时筛出来的</li>
          <li>播放页里拖动进度条；歌词随进度逐句走高亮</li>
          <li>设置里的开关都能点，主题能在深色 / 浅色之间切</li>
        </ol>
        <div style="border-top:1px solid var(--line);padding-top:16px">
          <h2 style="margin-bottom:8px">主题</h2>
          <div class="segmented" style="margin-bottom:16px">
            ${THEMES.map((t) => `<button data-set-theme="${t.id}" aria-selected="${STATE.theme === t.id}">${t.name}</button>`).join('')}
          </div>
        </div>
        <div style="border-top:1px solid var(--line);padding-top:16px">
          <h2 style="margin-bottom:6px">随封面取色</h2>
          每张专辑给界面一套自己的强调色：
          <div class="swatches" id="sw"></div>
          <div style="margin-top:14px;font-size:11px;color:var(--fg-3)">
            返回：左上角按钮，或键盘 <span class="kbd">←</span> / <span class="kbd">Esc</span>（在输入框里打字时不触发）
          </div>
        </div>
      </aside>
      <div id="phone-slot"></div>
    </div>`;

  root.querySelector('#sw').innerHTML = ALBUMS.map((a) =>
    `<span class="sw" title="${a.name}" style="background:linear-gradient(148deg,${a.c1},${a.accent})"></span>`).join('');

  const typingIn = (el) =>
    !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);

  /* ---- 进度条拖动 ----
     指针按下就跳转，按住拖动持续跟。用 pointer 事件一套同时覆盖鼠标与触摸；
     按下时指针捕获到那根轨道上，所以手指滑出去也还算数，松手才摘监听。
     拖动期间只改样式、不重绘 —— 一旦重绘，手里这根 trackEl 就成了孤儿节点。
     时间轴与歌词页共用 .track，所以这里只认 [data-seek] 这个挂点。
     挂成委托而不是渲染后逐个绑定：每次 render() 都会换掉整屏 DOM,
     委托只绑一次，天然跟着新节点走。 */
  const bindSeekDrag = (trackEl, ev) => {
    const s = currentSong();
    const paint = (clientX) => {
      const r = trackEl.getBoundingClientRect();
      const ratio = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
      STATE.elapsed = Math.round(ratio * s.dur);
      const bar = trackEl.querySelector('i');
      if (bar) bar.style.width = `${ratio * 100}%`;
      const knob = trackEl.querySelector('.knob');
      if (knob) knob.style.left = `${ratio * 100}%`;
      const times = trackEl.parentElement.querySelector('.times');
      if (times && times.children.length === 2) {
        const e2 = Math.min(STATE.elapsed, s.dur);
        times.children[0].textContent = mmss(e2);
        times.children[1].textContent = `-${mmss(s.dur - e2)}`;
      }
    };
    trackEl.setPointerCapture(ev.pointerId);
    paint(ev.clientX);
    const move = (m) => paint(m.clientX);
    const up = () => {
      trackEl.removeEventListener('pointermove', move);
      trackEl.removeEventListener('pointerup', up);
      trackEl.removeEventListener('pointercancel', up);
    };
    trackEl.addEventListener('pointermove', move);
    trackEl.addEventListener('pointerup', up);
    trackEl.addEventListener('pointercancel', up);
  };

  /* 监听挂在舞台根上而不是 #phone-slot 上 —— 侧栏是 #phone-slot 的兄弟节点，
     挂在内层会让侧栏里的主题按钮点不动。 */
  root.addEventListener('pointerdown', (e) => {
    const trackEl = e.target.closest('[data-seek]');
    if (!trackEl) return;
    e.preventDefault();
    bindSeekDrag(trackEl, e);
  });

  root.addEventListener('click', (e) => {
    /* 注意：委托选择器里不能出现 [data-theme] —— applyTheme() 把 data-theme 写在
       <body> 上，而 body 是所有点击的祖先。closest() 在没命中更近的 [data-*] 元素时
       会一路匹配到 body，于是「点遮罩关闭弹层」这条分支永远走不到（点遮罩会变成
       重新应用一次主题）。所以主题按钮改用独立属性 data-set-theme。 */
    const t = e.target.closest('[data-back],[data-tab],[data-go],[data-lib],[data-song],[data-album],[data-artist],[data-route],[data-quality],[data-set-theme],[data-sheet],[data-act],[data-scope],[data-pick-kind],[data-toggle]');
    if (t) {
      const d = t.dataset;
      if (d.back !== undefined) return back();
      if (d.tab) { STATE.history = []; return go(d.tab); }
      if (d.lib) { STATE.params = { lib: d.lib }; return render(); }
      if (d.song) {
        /* 从顶部播放坞点进播放页时，坞里也有同一张封面 —— 但那块的尺寸太小，
           飞过去的观感不如不加。只在从列表/网格进来时记录起点。 */
        morphEl = t.closest('[data-morph]') ? t.querySelector('.cover') : null;
        /* 换歌要重算进度：上一首听到哪儿，和这一首没有关系。
           原进度超过新歌长度的话，夹回去，免得一进去就显示成"已放完"。 */
        STATE.songId = d.song;
        STATE.elapsed = Math.min(STATE.elapsed, currentSong().dur - 1);
        STATE.playing = true;
        return go('player');
      }
      if (d.album) {
        morphEl = t.closest('[data-morph]') ? t.querySelector('.cover') : null;
        STATE.albumId = d.album; return go('album', { album: d.album });
      }
      if (d.artist) { STATE.artistId = d.artist; return go('artist', { artist: d.artist }); }
      if (d.route) { STATE.routeId = d.route; return render(); }
      if (d.scope) { STATE.scope = d.scope; return render(); }
      if (d.pickKind) { STATE.kind = d.pickKind; return render(); }
      if (d.toggle) { STATE[d.toggle] = STATE[d.toggle] === false; return render(); }
      if (d.setTheme) { applyTheme(d.setTheme); return render(); }
      if (d.quality) { STATE.quality = d.quality; STATE.overlay = ''; return render(); }
      if (d.sheet) { STATE.overlay = STATE.overlay === d.sheet ? '' : d.sheet; return render(); }
      if (d.go) return go(d.go);
      /* 三处的心共用一份本地名单。传进来的 id 必须来自当前这一屏，
         否则换页后按下会改到上一屏的对象上 —— 卡片上的心变实，播放页却不认。 */
      if (d.act === 'fav') {
        const set = STATE.fav.songs;
        set.has(STATE.songId) ? set.delete(STATE.songId) : set.add(STATE.songId);
        return render();
      }
      if (d.act === 'fav-album') {
        const set = STATE.fav.albums;
        const id = STATE.params.album;
        if (!id) return;
        set.has(id) ? set.delete(id) : set.add(id);
        return render();
      }
      if (d.act === 'fav-artist') {
        const set = STATE.fav.artists;
        const id = STATE.params.artist;
        if (!id) return;
        set.has(id) ? set.delete(id) : set.add(id);
        return render();
      }
      if (d.act === 'clear-query') { STATE.query = ''; return render(); }
      if (d.act === 'toggle-play') { STATE.playing = !STATE.playing; return render(); }
      /* 上下一首按全库顺序走，走到头绕回第一首 —— 原型里不假装有随机播放队列。 */
      if (d.act === 'next' || d.act === 'prev') {
        const i = SONGS.findIndex((x) => x.id === STATE.songId);
        const n = d.act === 'next' ? (i + 1) % SONGS.length : (i - 1 + SONGS.length) % SONGS.length;
        STATE.songId = SONGS[n].id;
        STATE.elapsed = 0;
        STATE.playing = true;
        return render();
      }
      if (d.act === 'shuffle') { STATE.shuffle = !STATE.shuffle; return render(); }
      if (d.act === 'repeat')  { STATE.repeat  = !STATE.repeat;  return render(); }
      if (d.act === 'ping-all') {
        STATE.pinging = true;
        render();
        /* 不真的测速，但「按下去要等一下才有结果」这个节奏得对上：
           800ms 后重绘，按钮从「测速中」跳回「重新测速」。 */
        window.setTimeout(() => { if (STATE.pinging) { STATE.pinging = false; render(); } }, 800);
        return;
      }
      return; // 其余为示意，不改变状态
    }
    if (e.target.classList.contains('sheet-scrim')) {
      STATE.overlay = '';
      render();
    }
  });

  /* 搜索框：input 走委托，因为 #search-input 会随每次重绘被整块换掉。
     重绘后要把焦点和光标位置还回去，否则打一个字就掉焦，得重新点一下才能接着打。 */
  root.addEventListener('input', (e) => {
    if (e.target.id !== 'search-input') return;
    STATE.query = e.target.value;
    render();
    const next = slot().querySelector('#search-input');
    if (next) {
      next.focus();
      try { next.setSelectionRange(next.value.length, next.value.length); } catch { /* 某些输入源没有选区 */ }
    }
  });

  document.addEventListener('keydown', (e) => {
    /* 正在输入框里打字时，Backspace 是删字符、方向键是移光标，都不能当成「返回」。
       这条守卫之前没有，于是在搜索框里按退格会直接退出当前页。 */
    if (typingIn(e.target)) return;
    if (e.key === 'Escape' || e.key === 'ArrowLeft' || e.key === 'Backspace') {
      if (STATE.overlay) { STATE.overlay = ''; return render(); }
      back();
    }
  });

  render();
}

/* ---------------- 启动 ---------------- */

window.addEventListener('DOMContentLoaded', () => {
  applyTheme(STATE.theme);
  if (document.body.dataset.mode === 'board') renderBoard(document.body);
  else renderStage(document.body);
});
