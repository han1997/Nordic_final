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
  home:    '<path d="M3.8 10.6L12 4.2l8.2 6.4"/><path d="M6.2 9.6V20h11.6V9.6"/><path d="M9.8 20v-5.2h4.4V20"/>',
  sparkle: '<path d="M12 4l1.9 5.1L19 11l-5.1 1.9L12 18l-1.9-5.1L5 11l5.1-1.9z"/>',
  bell:    '<path d="M18 9a6 6 0 1 0-12 0c0 5-2 6-2 6h16s-2-1-2-6"/><path d="M13.7 19.5a2 2 0 0 1-3.4 0"/>',
  shield:  '<path d="M12 3.6l7 2.6v5.4c0 4.3-3 7.3-7 8.8-4-1.5-7-4.5-7-8.8V6.2z"/>',
  play2:   '<circle cx="12" cy="12" r="8.4"/><path d="M10.2 8.8l5.6 3.2-5.6 3.2z" fill="currentColor" stroke="none"/>',
  theme:   '<circle cx="12" cy="12" r="8.2"/><path d="M12 3.8v16.4" /><path d="M12 3.8a8.2 8.2 0 0 0 0 16.4z" fill="currentColor" stroke="none"/>',
  /* 缓存:两层叠起来的盘 —— 「本机还留着一份」 */
  stack:   '<ellipse cx="12" cy="6.4" rx="7" ry="2.9"/><path d="M5 6.4v11.2c0 1.6 3.13 2.9 7 2.9s7-1.3 7-2.9V6.4"/><path d="M5 12c0 1.6 3.13 2.9 7 2.9s7-1.3 7-2.9"/>',
  trash:   '<path d="M5.4 7.4h13.2"/><path d="M9.8 7.4V5.7a1.3 1.3 0 0 1 1.3-1.3h1.8a1.3 1.3 0 0 1 1.3 1.3v1.7"/><path d="M7.4 7.4l.75 11.3A1.4 1.4 0 0 0 9.55 20h4.9a1.4 1.4 0 0 0 1.4-1.3l.75-11.3"/>',
  /* 扫码同步:二维码、摄像头、粘贴、复制 —— 这四个原先一个都没有。 */
  qr:      '<rect x="3.6" y="3.6" width="6.8" height="6.8" rx="1.6"/><rect x="13.6" y="3.6" width="6.8" height="6.8" rx="1.6"/><rect x="3.6" y="13.6" width="6.8" height="6.8" rx="1.6"/><path d="M13.6 13.6h3v3h-3zM20.4 13.6v3.2M13.6 20.4h6.8"/>',
  camera:  '<path d="M4 8.6h3l1.5-2.4h7l1.5 2.4h3v9.8H4z"/><circle cx="12" cy="13.2" r="3.1"/>',
  paste:   '<rect x="5.6" y="5.2" width="12.8" height="14.8" rx="2.2"/><path d="M9.6 5.2V4a1.6 1.6 0 0 1 1.6-1.6h1.6A1.6 1.6 0 0 1 14.4 4v1.2"/><path d="M9 11.4h6M9 15h4"/>',
  copy:    '<rect x="8.6" y="8.6" width="10.8" height="10.8" rx="2.2"/><path d="M15.4 5.6H6.6A1.8 1.8 0 0 0 4.8 7.4v8.8"/>',
  /* 歌曲信息与「回到正在播放」各一颗 —— 原先一个都没有。 */
  info:    '<circle cx="12" cy="12" r="8.4"/><path d="M12 11.2v5.2"/><path d="M12 7.7h.01"/>',
  locate:  '<circle cx="12" cy="12" r="6.6"/><circle cx="12" cy="12" r="1.9" fill="currentColor" stroke="none"/><path d="M12 2.6v3.4M12 18v3.4M2.6 12h3.4M18 12h3.4"/>',
};

function ic(name, size = 22, cls = '') {
  return `<svg class="${cls}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
}

/* 「添加时间」:真实服务器上这是每首曲目的 `created`(Navidrome 会给)。
   原型里按一张固定表**算**出日期,而不是往每条 mock 数据里塞一个字段 ——
   它是「什么时候入库」,和歌本身无关。顺序刻意跨专辑错开,
   好让「按添加时间」排出来与别的口径明显不同。 */
const ADDED_ORDER = ['s6', 's3', 's11', 's1', 's13', 's8', 's2', 's10', 's5', 's9', 's4', 's12', 's7', 's14'];

function addedOf(song) {
  const rank = ADDED_ORDER.indexOf(song.id);
  const days = (rank < 0 ? ADDED_ORDER.length : rank) * 3;
  return new Date(Date.UTC(2026, 0, 18) - days * 86400000).toISOString().slice(0, 10);
}

/* ---------------- 排序 ----------------
   只影响「全部专辑 / 全部歌曲」这两个列表 —— 最近添加那条轨道、常听艺人那
   几排货架讲的是另一件事(它们本身就是按某个口径挑出来的),不跟着变。 */

const ALBUM_SORTS = [
  ['artist', '按艺人'], ['name', '按名称'], ['newest', '最近添加'], ['random', '随机'],
];
const SONG_SORTS = [
  ['title', '按标题'], ['artist', '按艺人'], ['album', '按专辑'], ['added', '按添加时间'],
];

/* 按当前口径取排序后的专辑 / 歌曲。 */
const byText = (a, b) => String(a).localeCompare(String(b), 'zh');

/* 随机要**稳**:每帧重抽一次的话,点个心都会让整页换序。种子存在 STATE 里,
   只在用户重新选「随机」时换一个 —— 于是随机也是一份确定的顺序。 */
function seededShuffle(list, seed) {
  const hash = (str) => {
    let h = 2166136261 ^ seed;
    for (let i = 0; i < str.length; i++) {
      h = Math.imul(h ^ str.charCodeAt(i), 16777619);
    }
    return h >>> 0;
  };
  return [...list].sort((a, b) => hash(a.id) - hash(b.id));
}

function sortedAlbums() {
  const list = [...ALBUMS];
  switch (STATE.albumSort) {
    case 'name':   return list.sort((a, b) => byText(a.name, b.name));
    case 'newest': return list.sort((a, b) => (b.year || 0) - (a.year || 0));
    case 'random': return seededShuffle(list, STATE.randomSeed);
    default:       return list.sort((a, b) => byText(a.artist, b.artist) || (b.year || 0) - (a.year || 0));
  }
}

function sortedSongs() {
  const list = [...SONGS];
  switch (STATE.songSort) {
    case 'artist':   return list.sort((a, b) => byText(a.artist, b.artist) || byText(a.title, b.title));
    case 'album':    return list.sort((a, b) => byText(a.album, b.album) || (a.no || 0) - (b.no || 0));
    // 入库时间新的在前 —— 与专辑那一栏的「最近添加」同一个方向。
    case 'added':    return list.sort((a, b) => byText(addedOf(b), addedOf(a)));
    default:         return list.sort((a, b) => byText(a.title, b.title));
  }
}

function sortLabel(options, current) {
  const hit = options.find(([id]) => id === current);
  return hit ? hit[1] : options[0][1];
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
  { id: 'a1', name: '可能',                   artist: '程响',         year: 2022, count: 8,  c1: '#43305A', c2: '#140F22', accent: '#B891FF' },
  { id: 'a2', name: 'Ultraviolet',            artist: '3LAU',         year: 2018, count: 1,  c1: '#233573', c2: '#0A1029', accent: '#7C96FF' },
  { id: 'a3', name: '秋色',                   artist: '拾光乐队',      year: 2021, count: 11, c1: '#6B4526', c2: '#1F1207', accent: '#EFA85F' },
  { id: 'a4', name: 'Islands',                artist: 'King Crimson', year: 1971, count: 6,  c1: '#12544A', c2: '#061A1B', accent: '#4DE0C8' },
  { id: 'a5', name: '山丘',                   artist: '李宗盛',        year: 2013, count: 5,  c1: '#5C3630', c2: '#1A0E0C', accent: '#F08A76' },
  { id: 'a6', name: 'Random Access Memories', artist: 'Daft Punk',    year: 2013, count: 13, c1: '#4A4A4A', c2: '#101010', accent: '#F2E3A8' },
];

/* 曲目摊到全部六张专辑上,而不是五首都挂在《可能》名下 ——
   否则点进任何一张专辑看到的都是同一批歌,专辑页的曲目表就失去了意义。
   album / artist 两个字段是冗余的(albumOf() 查得出来),但列表行到处在用,
   留在数据里比每次查表省事;顺便按各张专辑的实际首数配了曲序。

   sizeMB / year / genre / added 只有「歌曲信息」那张纸在看(见 sheetSongInfo):
   它们本来就是服务器随每首歌给下来的字段(mapper 那边进的是 suffix / bitRate /
   size / year / genre / created),应用的信息弹层铺的就是这一份真东西。 */
const SONGS = [
  { id: 's1',  no: 1, title: '可能',        artist: '程响',         album: '可能',       albumId: 'a1', dur: 218, fmt: 'FLAC', kbps: 780, fav: true,  sizeMB: 21, year: 2022, genre: '流行',     added: '2026-10-12' },
  { id: 's2',  no: 2, title: '人间烟火',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 245, fmt: 'FLAC', kbps: 812, fav: false, sizeMB: 25, year: 2022, genre: '流行',     added: '2026-10-12' },
  { id: 's3',  no: 3, title: '四季予你',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 232, fmt: 'FLAC', kbps: 764, fav: false, sizeMB: 22, year: 2022, genre: '流行',     added: '2026-10-12' },
  { id: 's4',  no: 4, title: '等你归来',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 258, fmt: 'FLAC', kbps: 798, fav: true,  sizeMB: 26, year: 2022, genre: '流行',     added: '2026-10-12' },
  { id: 's5',  no: 5, title: '时光洪流',    artist: '程响',         album: '可能',       albumId: 'a1', dur: 224, fmt: 'FLAC', kbps: 770, fav: false, sizeMB: 22, year: 2022, genre: '流行',     added: '2026-10-12' },
  { id: 's6',  no: 1, title: 'Ultraviolet', artist: '3LAU',         album: 'Ultraviolet', albumId: 'a2', dur: 232, fmt: 'FLAC', kbps: 921, fav: true,  sizeMB: 27, year: 2018, genre: '电子',     added: '2026-09-28' },
  { id: 's7',  no: 1, title: '山色入秋',    artist: '拾光乐队',     album: '秋色',       albumId: 'a3', dur: 246, fmt: 'FLAC', kbps: 806, fav: false, sizeMB: 25, year: 2021, genre: '民谣',     added: '2026-08-30' },
  { id: 's8',  no: 2, title: '晚风信',      artist: '拾光乐队',     album: '秋色',       albumId: 'a3', dur: 219, fmt: 'FLAC', kbps: 788, fav: false, sizeMB: 22, year: 2021, genre: '民谣',     added: '2026-08-30' },
  { id: 's9',  no: 3, title: '落叶有信',    artist: '拾光乐队',     album: '秋色',       albumId: 'a3', dur: 268, fmt: 'FLAC', kbps: 794, fav: true,  sizeMB: 27, year: 2021, genre: '民谣',     added: '2026-08-30' },
  { id: 's10', no: 1, title: 'The Letters', artist: 'King Crimson', album: 'Islands',    albumId: 'a4', dur: 267, fmt: 'FLAC', kbps: 861, fav: false, sizeMB: 29, year: 1971, genre: '前卫摇滚', added: '2025-11-03' },
  { id: 's11', no: 1, title: '山丘',        artist: '李宗盛',       album: '山丘',       albumId: 'a5', dur: 352, fmt: 'FLAC', kbps: 812, fav: true,  sizeMB: 36, year: 2013, genre: '民谣',     added: '2025-11-03' },
  { id: 's12', no: 2, title: '给自己的歌',  artist: '李宗盛',       album: '山丘',       albumId: 'a5', dur: 379, fmt: 'FLAC', kbps: 826, fav: false, sizeMB: 39, year: 2013, genre: '民谣',     added: '2025-11-03' },
  { id: 's13', no: 1, title: 'Get Lucky',     artist: 'Daft Punk',  album: 'Random Access Memories', albumId: 'a6', dur: 369, fmt: 'FLAC', kbps: 934, fav: false, sizeMB: 43, year: 2013, genre: '电子', added: '2026-10-05' },
  { id: 's14', no: 2, title: 'Instant Crush', artist: 'Daft Punk',  album: 'Random Access Memories', albumId: 'a6', dur: 337, fmt: 'FLAC', kbps: 902, fav: false, sizeMB: 38, year: 2013, genre: '电子', added: '2026-10-05' },
];

const ARTISTS = [
  { id: 'ar1', name: '程响',         albums: 6,  songs: 42,  c1: '#43305A', c2: '#140F22', accent: '#B891FF' },
  { id: 'ar2', name: '陈奕迅',       albums: 24, songs: 310, c1: '#26365C', c2: '#0A0F1F', accent: '#7C96FF' },
  { id: 'ar3', name: '李宗盛',       albums: 12, songs: 128, c1: '#5C3630', c2: '#1A0E0C', accent: '#F08A76' },
  { id: 'ar4', name: 'King Crimson', albums: 9,  songs: 86,  c1: '#12544A', c2: '#061A1B', accent: '#4DE0C8' },
  { id: 'ar5', name: '3LAU',         albums: 3,  songs: 24,  c1: '#233573', c2: '#0A1029', accent: '#7C96FF' },
  { id: 'ar6', name: '柳爽',         albums: 4,  songs: 37,  c1: '#38294A', c2: '#130E1C', accent: '#A88BFF' },
];

/* 首页那两条货架 —— **服务器口径**(getAlbumList2 的 recent / frequent)。
   本地算不出「最近播放 / 最常播放」:那要播放次数与时间,只有服务器有。
   原型库小(6 张专辑),这里按序号错开摆出与「最近添加」不同的顺序,
   好让三条货架一眼看出不是同一份;真实客户端上它们各自铺满一屏。 */
const RECENT_PLAYED = ['a4', 'a1', 'a6', 'a3'];
const MOST_PLAYED   = ['a2', 'a5', 'a1', 'a4'];

/* 「最近添加」按**歌曲**排(2026-10-17 用户要求):服务器没有「最近添加歌曲」
   端点,真实客户端从已拉的歌曲列表按入库时间本地排。原型这里挑几首跨专辑的
   曲子示意 —— 一眼能看出它不是「最近添加专辑」那一份。 */
const RECENT_ADDED_SONGS = ['s13', 's7', 's11', 's2', 's10', 's14'];
const SONG_BY_ID = (id) => SONGS.find((s) => s.id === id);

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

/* 歌曲缓存的上限档位。
   「不缓存」是**真的不写盘**,而不是写一个小额度 —— 开关说关就得关。
   首数按 320 kbps(约 9.6 MB/首)估,写成整数是为了读起来是个约数;
   实际还取决于当前转码档与曲目长短,所以文案说「约」。 */
const CACHE_LIMITS = [
  { id: 'off', name: '不缓存', desc: '听过的歌每次都从服务器拉,本机不留音频', mb: 0 },
  { id: '256', name: '256 MB', desc: '约 25 首',  mb: 256 },
  { id: '512', name: '512 MB', desc: '约 50 首',  mb: 512 },
  { id: '1g',  name: '1 GB',   desc: '约 100 首 · 默认', mb: 1024 },
  { id: '2g',  name: '2 GB',   desc: '约 200 首', mb: 2048 },
  { id: '4g',  name: '4 GB',   desc: '约 400 首', mb: 4096 },
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
  /* 歌词页**待跳转的那一句**。点第一下只选中(行尾浮出「跳到这句 · 2:30」),
     同一句再点一下才真跳 —— 跳转不可逆,手一滑就跳走、还回不到原来那句。
     -1 = 没选中。这一层确认只在**这一趟**里算数:离开歌词页(go / back)与换歌都清掉。 */
  pendingLine: -1,
  /* 「回到正在播放」那一下高亮的时间戳(0 = 没亮)。
     **走 STATE 而不是往 DOM 上加 class**:下载计时器每 1.2 秒整屏重绘一次,
     直接加的那份 class 会被重绘抹掉,高亮没亮完就没了。 */
  locateAt: 0,
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
  /* 服务器设置页的表单与系统状态 —— 保存按钮要真把字段写回去，
     否则点多少次都不疼不痒,看起来像装饰。 */
  serverName: SERVER.name,
  serverUser: SERVER.user,
  serverKindCfg: 'navidrome',   /* 服务器设置页里的接入类型分段 */
  serverDirty: false,           /* 表单动过 -> 保存按钮亮起来 */
  removed: false,               /* 点了「移除该服务器」 */
  toast: '',                    /* 屏幕底部的小气泡,几秒后消失 */
  /* 排序:只影响「全部专辑 / 全部歌曲」两栏。随机用种子算,不是每帧重抽。 */
  albumSort: 'artist',
  songSort: 'title',
  randomSeed: 7,
  sortFor: 'albums',
  /* 下载:专辑页下载按钮真的往这里记一笔。原型不真拉文件,
     但队列要有进度的样子 —— 下载中 → 已完成,几个条目各在各的阶段。 */
  downloads: [],
  dlSeq: 0,
  /* 下过的与听过的分开记:
     - downloads 是**用户点名要的**,永远不删;
     - cacheUsed 是「听过的歌留一份」,上限到了就先扔最久没听的。
     原型不真拉文件,这里只摆一个已经用掉的数字。 */
  cacheLimit: '1g',
  cacheUsedMb: 138,
  /* 新建歌单表单:名字与封面色实时反映在预览卡上 */
  plName: '',
  plHue: 0,
  /* 添加线路表单 */
  routeUrl: '',
  routeTag: '内网',
  /* 上下文菜单:点「⋯」弹出的那张纸,内容随来源不同 */
  menuFor: 'song',
  /* 扫码同步:导入那一屏的模式、粘贴框里那段文本、读出来了没有、这段载带不带密码。
     文本**预填**一段 —— 与搜索页预填「程响」同一个理由:可点原型一进门就走得通
     那条路,不必先手打一串 base64 才有东西看。结尾那个 `#pw` 是**原型自己的记号**,
     表示这段载荷带了密码(真解码在 lib/data/config_transfer.dart)。 */
  syncMode: 'scan',
  syncText: syncDemoPayload(false),
  syncRead: false,
  syncHasPw: false,
  /* 导出弹层那颗「包含密码」—— **默认关**,与「落盘不带密码」是同一口径。 */
  syncIncludePw: false,
  /* 这台设备有没有相机。原型默认跑在手机上(有);置真之后那一屏退成纯粘贴 ——
     设计板上单独铺一格的就是这个状态,因为 Windows 桌面与浏览器看到的是它。 */
  syncNoCamera: false,
};

/* 进度换算:秒 → 百分比(夹在 0..100) */
function progressOf(song, sec) {
  return Math.max(0, Math.min(100, (sec / song.dur) * 100));
}

/* 已缓冲到哪儿 —— 原型按「播放位置 + 一段固定提前量」模拟边听边下。
   返回百分比,**null = 不画那条缓冲带**,两条口径:
   - 提前量顶到曲尾 = 整首都在手边(本机文件 / 已下完的缓存),没有待拉的东西,
     再画一层只是把整条轨道点亮,没有信息量;
   - 拉不动的位置(没有余量)也一样。
   与应用的 `scrubberFrame` 是同一套话(那边还有「时长未知不画」一条)。 */
const BUFFER_AHEAD = 15;
function bufferedPctOf(song, sec) {
  const buf = Math.min(song.dur, sec + BUFFER_AHEAD);
  if (buf >= song.dur) return null;
  return progressOf(song, buf);
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

/* 这一首**现在按什么在放**:档位名 + 来源。三个来源的说法各自说的是不同的事 ——
   「本机」= 放的是本机那一份(下载过的、或听过的缓存,不花流量),
   「直出」= 原音、没转码,「转码」= 过了一道编码。
   接的是应用那边的真口径(见 lib/playback/audio_handler.dart 的 loadedOriginOf):
   档位与来源都是「**装载那一刻**」定下的,不是此刻磁盘上有没有 —— 边上边缓存
   那一份会在播到一半时下完,而播放源没换过。
   原型里「本机」由下载队列派生:下载过的那一首就演这一态。 */
function playbackOriginOf(song) {
  const q = QUALITIES.find((x) => x.id === STATE.quality) || QUALITIES[2];
  const local = STATE.downloads.some((d) => d.songId === song.id);
  const source = local ? '本机' : (q.id === 'original' ? '直出' : '转码');
  return { quality: q.name, source, label: `${q.name} · ${source}` };
}

/* 「入库时间」按 `2026 年 10 月 12 日` 印。**不比 mmss 那一套详到分钟** ——
   那一条说的是「哪时候同步的」,这一条说的是「这首什么时候进的库」,年比分钟要紧。 */
function dayLabel(iso) {
  const [y, m, d] = String(iso).split('-');
  return `${y} 年 ${+m} 月 ${+d} 日`;
}

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

function cover(item, cls = '', extra = '') {
  const accent = item.accent || '#7C8CFF';
  const style = `--c1:${item.c1};--c2:${item.c2};${accentVars(accent)}${extra}`;
  /* 封面是纯渐变的占位 —— 不放任何文字。真实的专辑封面接入后,
     在这里加一层 background-image 即可;结构和所有尺寸都不用动。 */
  return `<div class="cover ${cls}" style="${style}" data-art="${item.id || ''}"></div>`;
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
  /* 原型原本是「音乐库 / 搜索 / 设置」。**2026-10-17 改成「首页 / 音乐库 / 设置」**:
     搜索是「知道要找什么」时的动作,用完就退,占一个常驻位置不划算 ——
     它挪进首页与音乐库顶栏那颗放大镜,变成一张推入的页面(见 data-go="search")。
     空出来的位置给首页:「不知道听什么」时才需要一个一直能回的地方。 */
  const tabs = [
    ['home',     'home',   '首页'],
    ['library',  'book',   '音乐库'],
    ['settings', 'gear',   '设置'],
  ];
  return `<nav class="tabbar">${tabs.map(([id, icon, label]) =>
    `<button data-tab="${id}" aria-selected="${active === id}">${ic(icon, 21)}<span>${label}</span></button>`
  ).join('')}</nav>`;
}

/* 播放坞 —— 现在只是托盘里的一行(见下)。
   进度线不在这儿:它挪到托盘中间那条分隔线上,整块东西一起表示「正在放」。 */
function dock(song = currentSong()) {
  const a = albumOf(song);
  return `<div class="dock" data-go="player">
    ${cover(a, '', 'width:46px;height:46px;border-radius:13px')}
    <div class="grow">
      <div class="line1">${song.title}</div>
      <div class="line2">${song.artist} · ${a.name}</div>
    </div>
    <button class="icon-btn" data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 25)}</button>
    <button class="icon-btn" data-act="next">${ic('next', 23)}</button>
  </div>`;
}

/* 底部那一片:播放坞与标签栏**合成一颗托盘**(参考飞牛播放器那种一体式下方)。
   原先两块各自一颗胶囊、中间留 8px 缝 —— 两层玻璃、两条边框、两道光影,
   读起来是两个各自独立的东西,而它们本来就是一件事:你现在在听什么、
   以及去哪儿。合成一颗之后:一层玻璃、一条外框,中间只用一条分隔线分开,
   那条线同时就是**进度**:播放坞与标签栏之间那条细线从左往右长,
   整块托盘于是自己说明「正在放」。 */
const bottom = (song, pct, active) => {
  const bar = pct == null ? progressOf(currentSong(), STATE.elapsed) : pct;
  return `<div class="bottomstack"><div class="tray">
    ${dock(song)}
    <div class="tray-line"><i style="width:${bar}%"></i></div>
    ${tabbar(active)}
  </div></div>`;
};

/* 托盘里没有歌可显示时的那一版:只留标签栏。外框、玻璃与分隔线照旧 ——
   少了播放坞不等于少了一颗托盘,未连接的首页要的正是「还站在这儿,只是没东西可放」。 */
const trayNoDock = (active) =>
  `<div class="bottomstack"><div class="tray">${tabbar(active)}</div></div>`;

/* ---------------- 服务器与线路 ---------------- */

function signalBars(n) {
  return `<span class="sig">${[1, 2, 3, 4].map((i) => `<i class="${i <= n ? 'on' : ''}"></i>`).join('')}</span>`;
}

function routeRows(routes, withCheck, pageAccent) {
  return routes.map((r) => {
    const sel = r.id === STATE.routeId;
    const right = r.state === 'bad'
      ? `<div class="ms"><b style="color:var(--bad);font-size:13px">不可用</b><small>连接超时</small></div>`
      : r.ping == null
        ? `<div class="ms"><b style="font-size:13px;color:var(--fg-3)">测速中</b><small>--</small></div>`
        : `<div class="ms"><b>${r.ping}</b><small>ms</small></div>`;
    return `<div class="route ${sel ? 'selected' : ''}" data-route="${r.id}"
        ${withCheck ? `role="radio" aria-selected="${sel}"` : ''}>
      ${withCheck
        ? `<span class="tick${sel ? ' on' : ''}">${ic('check', 14)}</span>`
        : `<span class="dot ${r.state}"></span>`}
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
        <div class="row" data-go="add-server" role="button">
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
  /* 表单带来的脏状态:任何输入改过,保存按钮才亮 —— 没动过就别装着能保存。 */
  const kinds = [['navidrome','Navidrome'],['subsonic','Subsonic'],['fnos','飞牛音乐']];
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">服务器设置</span>
      <span class="spacer"></span>
      <button class="pill-btn solid" data-act="save-server" ${STATE.serverDirty ? '' : 'disabled style="opacity:.45;cursor:default"'}>保存</button>
    </div>
    <div class="scroll">
      <div style="padding:var(--s2) var(--s5) 0;display:flex;flex-direction:column;gap:var(--s4)">
        <div class="field">
          <label>接入类型</label>
          <div class="segmented">${kinds.map(([id, label]) =>
            `<button data-kind-cfg="${id}" aria-selected="${STATE.serverKindCfg === id}">${label}</button>`).join('')}</div>
        </div>
        <div class="field"><label>显示名称</label>
          <div class="input"><input data-field="serverName" value="${STATE.serverName}"></div>
        </div>
        <div class="field">
          <label>用户名 / 密码</label>
          <div class="input">${ic('server', 18, 'quiet')}<input data-field="serverUser" value="${STATE.serverUser}"></div>
          <div class="input" style="margin-top:var(--s2)"><input type="password" value="password" readonly></div>
          <div class="hint">凭据只存在本机，登录时用密码派生令牌，不保存明文。</div>
        </div>
      </div>

      <div class="section">
        <h2>线路</h2>
        <span class="count">一个账号，多个地址</span>
      </div>
      <div class="card" style="margin:0 var(--s5)">${routeRows(SERVER.routes, false)}</div>
      <div style="padding:var(--s4) var(--s5) 0">
        <button class="btn ghost" data-go="add-route" style="height:48px">${ic('plus', 17)} 添加线路地址</button>
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
        <button class="chip" data-act="remove-server" style="height:40px;color:var(--bad);border-color:color-mix(in srgb,var(--bad) 30%,transparent);
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

function songRow(s, playing = false, trail = null, located = false) {
  const a = albumOf(s);
  return `<div class="row ${playing ? 'playing' : ''}${located ? ' located' : ''}" data-song="${s.id}">
    ${cover(a, '', 'width:52px;height:52px;border-radius:14px')}
    <div class="grow">
      <div class="line1">${s.title}</div>
      <div class="line2">${s.artist} · ${a.name}</div>
    </div>
    ${playing ? `<span class="bars"><i></i><i></i><i></i></span>` : ''}
    <span class="trail">${trail ?? mmss(s.dur)}</span>
  </div>`;
}

/* 这一行现在该不该亮着 —— 「回到正在播放」那一下的落点。
   1.2 秒后自己灭掉(见 STATE.locateAt)。 */
const locatedNow = (s) => s.id === STATE.songId && Date.now() - STATE.locateAt < 1200;

/* ---------------- 首页 ----------------

   一级 tab 的第一屏(2026-10-17 取代了原先的「搜索」那一格)。
   它回答的是「现在听什么 / 最近在听什么」,而音乐库回答「库里有什么」——
   两屏的分工就这么一条线:首页不铺全量,只铺**最近动过的那几摞**。

   三条货架都是服务器口径:**本地算不出「最近播放 / 最常播放」**
   (那要播放次数与时间,只有服务器有),所以真实客户端各拉一份
   (`getAlbumList2` 的 recent / frequent;最近添加是 newest)。 */
/* 「还没有连接服务器」那一块。首页与音乐库共用一份 —— 两屏都在等同一件事,
   各写一份必然走形。两个入口并排:手填是原有的路,扫码是这一轮新开的那条。 */
function notConnectedState() {
  return `<div class="empty">
    <span style="color:var(--fg-4);display:grid;place-items:center">${ic('server', 34)}</span>
    <div class="big">还没有连接服务器</div>
    <div class="small">扫码带走另一台设备的配置,或者手动填上地址与账号。</div>
    <div style="display:flex;flex-direction:column;gap:var(--s3);width:210px;margin-top:var(--s3)">
      <button class="btn primary" data-go="add-server" style="height:46px">连接服务器</button>
      <button class="btn ghost" data-go="sync" style="height:46px">${ic('qr', 17)} 扫码同步</button>
    </div>
  </div>`;
}

function screenHome(notConnected = false) {
  /* 未连接那一支的状态来自设置页的「移除该服务器」(STATE.removed)。
     托盘里此时没有歌可显示,所以只留标签栏 —— 外框与那条分隔线照旧,
     那是这颗托盘的本体(见 trayNoDock)。 */
  if (notConnected) {
    return `<div class="appbar">
        <div>
          <div class="h1">首页</div>
          <div class="sub">还没有连接服务器</div>
        </div>
      </div>
      <div class="scroll">${notConnectedState()}</div>
      ${trayNoDock('home')}`;
  }
  const s = currentSong();
  const a = albumOf(s);
  const pct = progressOf(s, STATE.elapsed);

  /* 正在播放是这一屏的主角:封面 + 「在听什么」+ 三颗键。
     键**竖着排** —— 横着塞在 92 的封面右边会把歌名挤没。
     还没播过东西时给一张说明性的卡(卡里有「随机播放」这颗入口),
     而不是留白:那一条空白会被读成加载失败。
     注意:可点击原型**一进门就有歌在放**(见 STATE.songId / STATE.playing),
     所以这一屏的可点原型里落不到空态那一支 —— 那是真机冷启动才有的样子,
     标记留着是为了让设计意图跟着代码走。 */
  const now = s
    ? `<div class="hero-card" style="${accentVars(a.accent)}">
        ${cover(a, '', 'width:92px;height:92px;border-radius:20px')}
        <div class="grow" style="min-width:0">
          <div class="label">${STATE.playing ? '正在播放' : '已暂停'}</div>
          <div class="t">${s.title}</div>
          <div class="a">${s.artist} · ${a.name}</div>
          <div class="time">${mmss(STATE.elapsed)} / ${mmss(s.dur)}</div>
        </div>
        <div class="stack">
          <button class="icon-btn" data-act="prev">${ic('prev', 19)}</button>
          <button class="go" data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 24)}</button>
          <button class="icon-btn" data-act="next">${ic('next', 19)}</button>
        </div>
      </div>
      <div class="prog-line" style="margin:0 var(--s5) var(--s2)"><i style="width:${pct}%"></i></div>`
    : `<div class="hero-card" style="flex-direction:column;align-items:stretch;gap:var(--s4)">
        <div style="display:flex;align-items:center;gap:var(--s4)">
          <span style="width:46px;height:46px;display:grid;place-items:center;color:var(--fg-3);flex:0 0 auto">${ic('play2', 30)}</span>
          <div class="grow" style="min-width:0">
            <div class="t" style="font-size:var(--fs-lg)">还没有在播的歌</div>
            <div class="a">随机放一首,或者从下面挑一张专辑。</div>
          </div>
        </div>
        <button class="btn primary" data-act="shuffle-all" style="height:46px">${ic('shuffle', 18)} 随机播放</button>
      </div>`;

  /* 一条货架。**没内容就整条不出现** —— 空标题下面挂一行「暂无」只是噪音。 */
  const shelf = (title, albums, trail = '') => albums.length ? `
      <div class="section"><h2>${title}</h2>${trail ? `<span class="trail">${trail}</span>` : ''}</div>
      <div class="rail"><div class="rail-track">${albums.map((x) => `
        <div class="rail-item" data-album="${x.id}" data-morph>
          ${cover(x, 'sq')}
          <div><div class="name">${x.name}</div><div class="meta">${x.artist}</div></div>
        </div>`).join('')}</div></div>` : '';

  /* 「最近添加」那条 —— 货架从专辑换成**歌曲**(见 RECENT_ADDED_SONGS 的说明)。
     骨架与 album 货架一致,只是取歌曲字段、点一下直接播那一首。 */
  const songShelf = (title, songs, trail = '') => songs.length ? `
      <div class="section"><h2>${title}</h2>${trail ? `<span class="trail">${trail}</span>` : ''}</div>
      <div class="rail"><div class="rail-track">${songs.map((s) => {
        const a = albumOf(s);
        return `
        <div class="rail-item" data-song="${s.id}" style="flex-basis:132px">
          ${cover(a, 'sq')}
          <div><div class="name">${s.title}</div><div class="meta">${s.artist}</div></div>
        </div>`;
      }).join('')}</div></div>` : '';

  /* 底部托盘与音乐库 / 设置是**同一颗**(`bottom()`)。
     2026-10-17 补:首页当初是从音乐库那两栏搬过来的,托盘漏了 ——
     而首页是冷启动的落点,少了它这一屏就没有路去别处。 */
  return `<div class="appbar">
      <div>
        <div class="h1">首页</div>
        <div class="sub">${SERVER.name} · ${SERVER.songs} 首</div>
      </div>
      <span class="spacer"></span>
      <button class="icon-btn quiet" data-go="search">${ic('search', 21)}</button>
    </div>
    <div class="scroll">
      <div class="section" style="padding-top:0"><h2>正在播放</h2></div>
      ${now}
      ${songShelf('最近添加', RECENT_ADDED_SONGS.map(SONG_BY_ID), '10 月 12 日扫描')}
      ${shelf('最近播放', RECENT_PLAYED.map(ALBUM_BY_ID))}
      ${shelf('最常播放', MOST_PLAYED.map(ALBUM_BY_ID))}
      <div class="section"><h2>歌单</h2><span class="count">${PLAYLISTS.length} 个</span></div>
      <div class="rail" style="padding-bottom:var(--s2)"><div class="rail-track">
        ${PLAYLISTS.map((p) => `
          <div class="pl-chip" data-go="library">
            ${cover(p, '', 'width:30px;height:30px;border-radius:9px')}
            <div class="name">${p.name}</div>
            <div class="n">${p.count} 首</div>
          </div>`).join('')}
      </div></div>
      <div class="list-note">「最近播放」「最常播放」由服务器按播放统计给出,本地算不出来。
原型库只带了 6 张专辑,三条货架各摆几张示意;真实客户端会各自铺满一屏。</div>
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(s, pct, 'home')}`;
}

function screenLibrary(tab = 'songs', notConnected = false) {
  const segs = [['albums', '专辑'], ['artists', '艺人'], ['songs', '歌曲'], ['playlists', '歌单']];
  /* 未连接时库也是空的,铺的是与首页**同一块**空态(见 notConnectedState)——
     两屏各写一份必然走形。那一栏的分段控件也就不必出现:没有栏可切。 */
  if (notConnected) {
    return `<div class="appbar">
        <div>
          <div class="h1">音乐库</div>
          <div class="sub">还没有连接服务器</div>
        </div>
      </div>
      <div class="scroll">${notConnectedState()}</div>
      ${trayNoDock('library')}`;
  }
  const cur = currentSong();
  let body = '';

  /* 这一栏只管「库里有什么」:「继续收听」那张卡与「最近添加」货架
     **2026-10-17 起归首页**(见 screenHome)—— 一屏是「最近动过的」,
     一屏是全量,两处不再各铺一份。 */
  if (tab === 'albums') {
    body = `<div class="section" style="padding-top:0">
        <h2>全部专辑</h2><span class="count">${ALBUMS.length} 张</span>
        <button class="sort-btn" data-sort-for="albums">${ic('sort', 13)} ${sortLabel(ALBUM_SORTS, STATE.albumSort)}</button>
      </div>
      <div class="grid-covers">${sortedAlbums().map((a) => `
        <div class="album-tile" data-album="${a.id}" data-morph>
          ${cover(a, 'sq')}
          <div><div class="name">${a.name}</div><div class="meta">${a.artist} · ${a.year}</div></div>
        </div>`).join('')}</div>`;
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
    body = `<div class="section">
        <h2>全部歌曲</h2><span class="count">${SONGS.length} 首</span>
        <button class="sort-btn" data-sort-for="songs">${ic('sort', 13)} ${sortLabel(SONG_SORTS, STATE.songSort)}</button>
      </div>
      ${sortedSongs().map((s) => songRow(s, s.id === cur.id, null, locatedNow(s))).join('')}`;
  } else {
    body = `<div class="section"><h2>我的歌单</h2><span class="count">${PLAYLISTS.length} 个</span></div>
      ${PLAYLISTS.map((p) => `
        <div class="row" style="height:72px">
          ${cover(p, '', 'width:56px;height:56px;border-radius:16px')}
          <div class="grow"><div class="line1">${p.name}</div><div class="line2">${p.count} 首 · ${p.desc}</div></div>
          ${ic('chevron', 18)}
        </div>`).join('')}
      <div style="padding:var(--s5) var(--s5) var(--s4)">
        <button class="btn ghost" data-go="new-playlist" style="height:48px">${ic('plus', 17)} 新建歌单</button>
      </div>`;
  }

  return `<div class="appbar">
      <div>
        <div class="h1">音乐库</div>
        <div class="sub">${SERVER.name} · ${SERVER.songs} 首</div>
      </div>
      <span class="spacer"></span>
      ${tab === 'songs' ? `<button class="icon-btn quiet" data-act="locate" title="回到正在播放的那一首">${ic('locate', 21)}</button>` : ''}
      <button class="icon-btn quiet" data-go="search">${ic('search', 21)}</button>
    </div>
    <div style="padding:0 var(--s5) var(--s4)">
      <div class="segmented">${segs.map(([id, label]) =>
        `<button data-lib="${id}" aria-selected="${tab === id}">${label}</button>`).join('')}</div>
    </div>
    <div class="scroll">${body}<div style="height:var(--s5)"></div></div>
    ${bottom(cur, null, 'library')}`;
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
      <button class="icon-btn quiet" data-menu-for="album">${ic('more', 20)}</button>
    </div>
    <div class="scroll">
      <!-- 向歌词页看齐:居中、留白、只有一件主事。
           原先一行四个按钮(播放 / 随机 / 收藏 / 队列)把封面挤到左上角,
           整屏读起来全是控件 —— 现在随机与收藏进了「⋯」,
           播放一行独占,下面的曲目也不再被一条分隔线断开。 -->
      <div class="album-hero">
        ${cover(a, '', 'width:168px;height:168px;border-radius:26px')}
        <div class="title">${a.name}</div>
        ${artistIdOf(a.artist)
          ? `<div class="artist" data-artist="${artistIdOf(a.artist)}">${a.artist}</div>`
          : `<div class="artist inert">${a.artist}</div>`}
        <div class="meta"><span>${a.year}</span>·<span>${a.count} 首</span></div>
      </div>
      <div class="album-play">
        <button class="btn primary" data-song="${firstId}">${ic('play', 20)} 播放</button>
      </div>
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
          ${cover(a, 'sq')}
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
      <button class="icon-btn quiet" data-menu-for="artist">${ic('more', 20)}</button>
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

/* 播放控制区 —— 进度条 + 一排控制键,播放页与歌词页**共用一份**。
   两个页面是同一件东西的两面(点封面来回翻),控制区要是各长一个样子,
   翻过去就像换了台设备:原先歌词页是居中的三键、位置更靠下,
   播放页是铺满的五键 —— 现在就一份,五键、同样的位置、同样的间距。 */
function scrubBar(s, elapsed) {
  const pct = progressOf(s, elapsed);
  const buf = bufferedPctOf(s, elapsed);
  /* 三层轨道:未加载的底 → 已缓冲 → 已播。前两层是这里的 `i`,
     已播那一段压在最后(DOM 顺序即层级,不写 z-index),
     于是可见的正好是 [已播 → 已缓冲] 那一段,永远不会盖到已播部分上。 */
  return `<div class="scrub">
      <div class="track" data-seek>${
        buf == null ? '' : `<i class="buf" style="width:${buf}%"></i>`
      }<i class="played" style="width:${pct}%"></i><span class="knob" style="left:${pct}%"></span></div>
      <div class="times"><span>${mmss(elapsed)}</span><span>-${mmss(s.dur - elapsed)}</span></div>
    </div>`;
}

function mediaControls() {
  return `<div class="controls">
      <button class="icon-btn${STATE.shuffle ? ' on' : ''}" style="color:${STATE.shuffle ? 'var(--accent-safe)' : ''}" data-act="shuffle">${ic('shuffle', 23)}</button>
      <button class="icon-btn" data-act="prev">${ic('prev', 27)}</button>
      <button class="play-btn" data-act="toggle-play">${ic(STATE.playing ? 'pause' : 'play', 30)}</button>
      <button class="icon-btn" data-act="next">${ic('next', 27)}</button>
      <button class="icon-btn${STATE.repeat ? ' on' : ''}" style="color:${STATE.repeat ? 'var(--accent-safe)' : ''}" data-act="repeat">${ic('repeat', 23)}</button>
    </div>`;
}

function screenPlayer() {
  const s = currentSong();
  const a = albumOf(s);
  const origin = playbackOriginOf(s);
  const pct = progressOf(s, STATE.elapsed);
  const elapsed = Math.min(STATE.elapsed, s.dur);

  return `${ambient(a)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:11px;color:var(--fg-3);letter-spacing:0.1em;font-weight:660">正在播放</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet" data-menu-for="song">${ic('more', 20)}</button>
    </div>

    <!-- 这一整块都是入口:点封面、点封面四周的留白都翻到歌词。原先只有封面本身
         可点,周围那一大圈空白按下去什么也不发生 —— 而这一屏除了控件就没有别的
         去处了。封面背后不再有黑胶盘面:那一圈盘面是为了「转起来表示在放」,
         但它也把封面挤窄了,而播放状态本来就由播放键与进度条说清了。 -->
    <div class="player-hero" data-go="lyrics" role="button"
      aria-label="查看歌词" title="点这里看歌词">
      <div class="hero-cover${STATE.playing ? ' playing' : ''}">
        <span class="hero-glow" aria-hidden="true"></span>
        ${cover(a, 'sq')}
      </div>
    </div>

    <div class="player-info">
      <div class="top-row">
        <div style="min-width:0">
          <!-- 歌名同样是入口(与封面同一件事的两处来路)。它原先谁都不指向,
               而艺人 / 专辑那两条链接各有各的去处,别动。 -->
          <div class="t" data-go="lyrics" role="button" title="点歌名看歌词">${s.title}</div>
          <div class="a">${artistIdOf(s.artist)
            ? `<span class="p-link" data-artist="${artistIdOf(s.artist)}">${s.artist}</span>`
            : `<span class="p-link inert">${s.artist}</span>`}<span class="p-dot">·</span><span class="p-link" data-album="${a.id}">${a.name}</span></div>
        </div>
        <button class="icon-btn" data-act="fav" style="color:${STATE.fav.songs.has(s.id) ? 'var(--accent-safe)' : 'var(--fg-2)'}">
          ${ic(STATE.fav.songs.has(s.id) ? 'heartF' : 'heart', 26)}</button>
      </div>
      <!-- 这一首「是什么、按什么在放」。左半是**源文件**的样子(格式与码率),
           右半是**此刻这一趟**实际用的档位与来源 —— 转码那颗胶囊收进「⋯」菜单之后,
           「现在到底按哪一档在放」就没地方看了。点它直接开转码面板。 -->
      <div class="p-meta">
        <span class="p-fmt">${s.fmt ? (s.kbps ? `${s.fmt} · ${s.kbps} kbps` : s.fmt) : '—'}</span>
        <button class="q-badge" data-sheet="quality" title="切换转码档位">${ic('wave', 13)} ${origin.label}</button>
      </div>
    </div>

    ${scrubBar(s, elapsed)}
    ${mediaControls()}`;
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
            <span class="tick${STATE.quality === q.id ? ' on' : ''}">${ic('check', 14)}</span>
          </div>`).join('')}
      </div>
    </div>
  </div>`;
}

/* 缓存上限面板 —— 与转码质量同一副骨架(选项行 + 勾)。
   面板里连「已用多少」一起说:上限只有跟占用摆在一起才有意义,
   否则用户改完数字不知道现在是松了还是紧了。 */
function cacheLimitOf(id) {
  return CACHE_LIMITS.find((c) => c.id === id) || CACHE_LIMITS[3];
}

/* 体积文案。不到 1 GB 就别硬撑「0.1 GB」—— 该显示 MB 的时候显示 MB。 */
function mbLabel(mb) {
  if (mb >= 1024) {
    const gb = mb / 1024;
    return `${Number.isInteger(gb) ? gb : gb.toFixed(1)} GB`;
  }
  return `${Math.round(mb)} MB`;
}

/* 上限那一栏右边的话。0 不是「0 MB」—— 那读起来像额度用完了,
   而它说的是「压根不写盘」。 */
function cacheLimitLabel(id) {
  const mb = cacheLimitOf(id).mb;
  return mb ? mbLabel(mb) : '不缓存';
}

function sheetCache() {
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>歌曲缓存 <span>已用 ${mbLabel(STATE.cacheUsedMb)}</span></h2>
      <div class="sheet-note">听过的歌会在本机留一份,再听直接从本机取,断网也能放。上限到了会先扔掉最久没听的;<b>下载</b>是用户点名要的,不在这里面,永远不会被扔掉。开着「仅 Wi-Fi 下载」时,流量下不留新的缓存(已经留着的照旧能听)。</div>
      <div class="sheet-body">
        ${CACHE_LIMITS.map((c) => `
          <div class="qopt" data-cache="${c.id}" role="radio" aria-selected="${STATE.cacheLimit === c.id}">
            <div style="flex:1 1 auto">
              <div class="qname">${c.name}</div>
              <div class="qdesc">${c.desc}</div>
            </div>
            <span class="tick${STATE.cacheLimit === c.id ? ' on' : ''}">${ic('check', 14)}</span>
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
            ${cover(a, '', 'width:46px;height:46px;border-radius:12px')}
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

/* ---------------- 上下文菜单（「⋯」背后那张真正的纸） ----------------
   四处共用一张底板,内容按来源换:播放页当前歌、专辑页、艺人页、歌词页。
   每一项都是真动作:收藏、下载、加入队列、跳专辑 —— 不做「点了没反应」的那一种。 */
function sheetMenu() {
  const forWhat = STATE.menuFor;
  let title = '', sub = '', items = [];

  if (forWhat === 'song') {
    const s = currentSong();
    const a = albumOf(s);
    const faved = STATE.fav.songs.has(s.id);
    title = s.title; sub = `${s.artist} · ${a.name}`;
    items = [
      [faved ? 'heartF' : 'heart', faved ? '取消收藏' : '收藏这首歌', 'act:fav'],
      ['download', '下载到本机（FLAC）', 'act:dl-song'],
      ['queue', '加入播放队列', 'act:queue-add'],
      ['queue', '查看播放队列', 'sheet:queue'],
      ['route', '切换线路', 'sheet:routes'],
      ['wave', `转码质量 · ${(QUALITIES.find((x) => x.id === STATE.quality) || QUALITIES[2]).name}`, 'sheet:quality'],
      ['info', '歌曲信息', 'sheet:songInfo'],
      ['disc', '查看专辑', `album:${a.id}`],
    ];
  } else if (forWhat === 'album') {
    const a = ALBUM_BY_ID(STATE.params.album || STATE.albumId);
    const faved = STATE.fav.albums.has(a.id);
    title = a.name; sub = `${a.artist} · ${a.year}`;
    items = [
      [faved ? 'heartF' : 'heart', faved ? '取消收藏' : '收藏这张专辑', 'act:fav-album'],
      ['shuffle', '随机播放这张专辑', 'act:shuffle-album'],
      ['download', '整张下载到本机', 'act:dl-album'],
      ['queue', '加入播放队列', 'act:queue-add'],
      ['queue', '查看播放队列', 'sheet:queue'],
    ];
  } else if (forWhat === 'artist') {
    const ar = ARTIST_BY_ID(STATE.params.artist || STATE.artistId);
    const faved = STATE.fav.artists.has(ar.id);
    title = ar.name; sub = `${ar.albums} 张专辑 · ${ar.songs} 首`;
    items = [
      [faved ? 'heartF' : 'heart', faved ? '取消收藏' : '收藏这位艺人', 'act:fav-artist'],
      ['download', '下载全部歌曲', 'act:dl-artist'],
    ];
  } else {
    const s = currentSong();
    title = s.title; sub = s.artist;
    items = [['disc', '查看专辑', `album:${albumOf(s).id}`]];
  }

  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>${title} <span>${sub}</span></h2>
      <div class="sheet-body">
        ${items.map(([icon, label, target]) => `
          <div class="menu-item" data-menu-go="${target}">${ic(icon, 20)}<span>${label}</span></div>`).join('')}
      </div>
    </div>
  </div>`;
}

/* ---------------- 歌曲信息 ----------------

   「⋯」菜单里那条。铺的全是**这首歌真有的字段**:服务器随曲目给下来的
   格式 / 码率 / 体积 / 年份 / 流派 / 入库时间(应用那边在
   `subsonic_mapper.dart` 里进的正是这几个)。**缺哪一项就整行不印** ——
   写一行「未知」是拿假东西凑数,那比没有更糟。

   歌名与艺人 · 专辑在标题那一行(与其它弹层同款),所以正文里不再重复。 */
function sheetSongInfo() {
  const s = currentSong();
  const a = albumOf(s);
  const origin = playbackOriginOf(s);
  const rows = [
    s.no ? ['曲序', `第 ${s.no} 首`] : null,
    ['时长', mmss(s.dur)],
    s.fmt ? ['格式', s.kbps ? `${s.fmt} · ${s.kbps} kbps` : s.fmt] : null,
    s.sizeMB ? ['文件大小', mbLabel(s.sizeMB)] : null,
    s.year ? ['年份', `${s.year}`] : null,
    s.genre ? ['流派', s.genre] : null,
    s.added ? ['入库时间', dayLabel(s.added)] : null,
    ['实际播放', origin.label],
  ].filter(Boolean);

  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>${s.title} <span>${s.artist} · ${a.name}</span></h2>
      <div class="sheet-body">
        <div class="info-list">
          ${rows.map(([label, value]) => `
            <div class="info-row"><span class="k">${label}</span><span class="v">${value}</span></div>`).join('')}
        </div>
        <div class="menu-item" data-menu-go="album:${a.id}">${ic('disc', 20)}<span>查看专辑</span></div>
      </div>
    </div>
  </div>`;
}

   /* ---------------- 下载 ----------------
   队列是真的:点下载按钮往 STATE.downloads 记一笔,这张页铺的就是队列本身。
   进度是模拟的 —— 每次渲染往前挪一点,直到 100 停住,状态从「下载中」变「已完成」。
   条目可删,删完剩下的接着排;空队列是真实空态(带说明),不是假骨架。 */
function dlEnqueue(kind, item) {
  const name = kind === 'album' ? item.name : `${item.title} · ${item.artist}`;
  const size = kind === 'album'
    ? Math.round(tracksOf(item.id).length * 32.4)
    : Math.round(item.dur * 0.148);
  STATE.downloads.unshift({
    id: 'dl' + (++STATE.dlSeq),
    kind, name,
    /* 记下是哪一首 / 哪一张 —— 播放页那枚来源徽标要判「这一首在本机吗」
       (见 playbackOriginOf),拿 name 去比是拿文案当键,改一次文案就断。 */
    songId: kind === 'song' ? item.id : undefined,
    albumId: kind === 'album' ? item.id : undefined,
    state: 'active', pct: 0, size,
  });
}

function screenDownloads() {
  const list = STATE.downloads;
  const activeN = list.filter((d) => d.state === 'active').length;
  const totalSize = list.reduce((n, d) => n + d.size, 0);
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">下载管理</span>
      <span class="spacer"></span>
      <span style="font-size:11px;color:var(--fg-3)">${activeN ? '正在下载' : '空闲'} · ${list.length} 项</span>
    </div>
    <div class="scroll">
      ${list.length ? `
        <div class="section"><h2>队列</h2><span class="count">约 ${(totalSize / 1024).toFixed(1)} GB</span></div>
        <div class="card" style="margin:0 var(--s5)">
          ${list.map((d, i) => `
            ${i ? '<div class="divider"></div>' : ''}
            <div class="row" style="height:76px">
              <span class="set-icon" style="color:${d.state === 'done' ? 'var(--ok)' : 'var(--accent-safe)'}">
                ${ic(d.state === 'done' ? 'check' : 'download', 18)}</span>
              <div class="grow">
                <div class="line1">${d.name}</div>
                <div class="line2">${d.state === 'done'
                  ? `已完成 · FLAC · ${d.size} MB`
                  : `${d.size} MB · ${Math.round(d.pct)}%`}</div>
                <div class="prog-line" style="margin-top:6px"><i style="width:${d.state === 'done' ? 100 : d.pct}%"></i></div>
              </div>
              <button class="icon-btn quiet" data-dl-del="${d.id}">${ic('x', 16)}</button>
            </div>`).join('')}
        </div>
        <div class="list-note" style="padding-top:var(--s4)">
          下载走当前线路,存到本机的 Nordic/Music 目录。已完成的条目离线也能播。
        </div>`
      : `<div class="empty" style="padding-top:120px">
          <span class="big">队列是空的</span>
          <span class="small">专辑页和播放页的下载按钮会把内容放进这里</span>
        </div>`}
      <div style="height:var(--s5)"></div>
    </div>`;
}

/* ---------------- 新建歌单 ----------------
   表单是活的:名字打进 STATE.plName,封面色随 STATE.plHue 走,
   预览卡实时变样。保存按钮在没起名前是灰的 —— 没内容就不该能存。 */
function screenNewPlaylist() {
  const h = STATE.plHue;
  const c1 = `hsl(${h} 42% 30%)`;
  const c2 = `hsl(${h} 48% 12%)`;
  const name = STATE.plName.trim();
  const swatches = [268, 210, 168, 24, 336, 44, 186];
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">新建歌单</span>
      <span class="spacer"></span>
      <button class="pill-btn solid" data-act="create-playlist" ${name ? '' : 'disabled style="opacity:.45;cursor:default"'}>创建</button>
    </div>
    <div class="scroll" style="padding:0 var(--s5)">
      <div class="hero-card" style="${accentVars(c1)}margin-top:var(--s4)">
        <div class="cover" style="--c1:${c1};--c2:${c2};width:92px;height:92px;border-radius:20px"></div>
        <div class="grow" style="min-width:0">
          <div class="t">${name || '未命名歌单'}</div>
          <div class="a">0 首 · ${name ? '名字可用' : '起个名字就能创建'}</div>
        </div>
      </div>

      <div class="field" style="margin-top:var(--s5)">
        <label>歌单名称</label>
        <div class="input"><input id="pl-name" placeholder="例如:深夜驾驶" value="${STATE.plName}"
          autocomplete="off" spellcheck="false"></div>
      </div>

      <div class="field" style="margin-top:var(--s4)">
        <label>封面色</label>
        <div class="swatch-row">
          ${swatches.map((hh) => `
            <button class="swatch${hh === h ? ' sel' : ''}" data-hue="${hh}" aria-label="色相 ${hh}"
              style="background:linear-gradient(148deg,hsl(${hh} 42% 30%),hsl(${hh} 48% 12%))"></button>`).join('')}
        </div>
      </div>
      <div class="hint" style="padding:0 4px">创建后可以先加几首打底,以后随时从歌曲菜单里追加。</div>
      <div style="height:var(--s6)"></div>
    </div>`;
}

/* ---------------- 添加线路 ----------------
   和服务器设置共用「表单脏状态 -> 保存亮灯」的规则:
   URL 没填完整就不给按,填了才亮。 */
function screenAddRoute() {
  const url = STATE.routeUrl.trim();
  const ok = /^https?:\/\/.+/.test(url);
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">添加线路地址</span>
      <span class="spacer"></span>
      <button class="pill-btn solid" data-act="create-route" ${ok ? '' : 'disabled style="opacity:.45;cursor:default"'}>添加</button>
    </div>
    <div class="scroll" style="padding:0 var(--s5)">
      <div style="font-size:13px;color:var(--fg-2);line-height:1.7;padding:var(--s4) 0 var(--s5)">
        一个账号可以配多条线路,客户端按延迟自动择优。内外网各留一条,出门也能听。
      </div>
      <div class="field">
        <label>服务器地址</label>
        <div class="input">${ic('server', 18, 'quiet')}
          <input id="route-url" placeholder="http://192.168.1.10:4533" value="${STATE.routeUrl}"
            autocomplete="off" spellcheck="false"></div>
        <div class="hint">支持 http / https,也可以是域名或 IPv6。</div>
      </div>
      <div class="field" style="margin-top:var(--s4)">
        <label>标记</label>
        <div class="segmented">
          ${['内网', '公网', '中继'].map((t) =>
            `<button data-route-tag="${t}" aria-selected="${STATE.routeTag === t}">${t}</button>`).join('')}
        </div>
      </div>
      ${url && !ok ? `<div class="note" style="margin-top:var(--s5)">
        这个地址还不完整 —— 要以 http:// 或 https:// 开头。</div>` : ''}
      <div style="height:var(--s6)"></div>
    </div>`;
}

/* ---------------- 扫码同步 ----------------
   两半共用**同一串文本**:二维码里那串,与「复制文本」复制走的那串,是同一个东西。
   真格式在 lib/data/config_transfer.dart(`nordic://config/1/<base64url>`)。

   原型里的载荷是**假的 base64** —— 格式按真的写,内容只是给那两屏一点能看的东西。
   结尾那个 `#pw` 是**原型自己的记号**,表示这段载荷带了密码:原型没有真解码器,
   而「带不带密码」正好是那一屏上唯一分岔的地方(按钮是「填上密码」还是「连接并替换」)。 */
function syncDemoPayload(includePw) {
  const json = `{"v":1,"kind":"navidrome","name":"${SERVER.name}","user":"${SERVER.user}",`
    + `"routes":[${SERVER.routes.map((r) => `{"n":"${r.name}","u":"${r.url}","t":"${r.tag}"}`).join(',')}]`
    + (includePw ? ',"pw":"..."' : '') + '}';
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  let blob = '';
  for (let i = 0; i < json.length; i++) {
    blob += alphabet[(json.charCodeAt(i) + i * 7) % 64];
  }
  return `nordic://config/1/${blob}${includePw ? '#pw' : ''}`;
}

/* 占位二维码。**三个定位角 + 一层按种子算的伪随机模块**,密度照真实载荷估
   (3 条线路约 73×73 模块,见 config_transfer 那张体积表)。

   **必须按种子算,不能 Math.random()**:播放时 render() 每秒跑一次
   (见下面的播放计时),每帧重抽的话这块会闪 —— 与「随机排序用 randomSeed、
   不是每帧重抽」是同一条理由。 */
function qrPlaceholder(seed, modules = 25) {
  const n = modules + 8;                          // 四周各 4 模块静区,扫描器要它
  let s = (seed >>> 0) || 1;
  const bits = [];
  for (let i = 0; i < modules * modules; i++) {
    s = (s * 1664525 + 1013904223) >>> 0;         // 线性同余:同一个种子永远同一张码
    bits.push((s >>> 16) & 1);
  }
  const near = (v) => v >= modules - 8;           // 定位角连分隔符占 8 格
  const inFinder = (x, y) => (x < 8 && y < 8) || (near(x) && y < 8) || (x < 8 && near(y));
  let cells = '';
  for (let y = 0; y < modules; y++) {
    for (let x = 0; x < modules; x++) {
      if (inFinder(x, y) || !bits[y * modules + x]) continue;
      cells += `<rect x="${x + 4}" y="${y + 4}" width="1" height="1"/>`;
    }
  }
  /* 定位角:7×7 实心 + 5×5 反色 + 3×3 实心。 */
  const finder = (x, y) =>
    `<rect x="${x + 4}" y="${y + 4}" width="7" height="7"/>`
    + `<rect x="${x + 5}" y="${y + 5}" width="5" height="5" fill="#fff"/>`
    + `<rect x="${x + 6}" y="${y + 6}" width="3" height="3"/>`;
  const far = modules - 7;
  return `<svg viewBox="0 0 ${n} ${n}" width="${n}" height="${n}">
    <rect width="${n}" height="${n}" fill="#fff"/>
    <g fill="#000">${cells}${finder(0, 0)}${finder(far, 0)}${finder(0, far)}</g>
  </svg>`;
}

/* 导入那一屏。

   noCamera 为真时**整条扫码那一支都不出现**:没有相机就没有第二个选项,
   留一个只有一项的分段控件只是噪音 —— 那一版换成一句说明加粘贴框。
   (应用那边同一条判据,见 lib/data/scan_capability.dart。) */
function screenSync(noCamera = STATE.syncNoCamera) {
  const mode = noCamera ? 'paste' : STATE.syncMode;
  const text = STATE.syncText.trim();
  const ok = text.startsWith('nordic://config/1/');

  const scanPane = `
    <div class="viewfinder">
      <span class="corner tl"></span><span class="corner tr"></span>
      <span class="corner bl"></span><span class="corner br"></span>
      <span class="scanline"></span>
      <div class="vf-hint">把另一台设备上的二维码放进这个框里。</div>
    </div>
    <div class="list-note" style="padding:var(--s4) var(--s5) 0">
      扫到之后先读出配置给你看一眼,不会直接连上去。
    </div>`;

  const pastePane = `
    <div style="padding:0 var(--s5)">
      <div class="field">
        <label>配置文本</label>
        <div class="input is-multiline">
          <textarea id="sync-text" spellcheck="false" autocomplete="off"
            placeholder="nordic://config/1/...">${STATE.syncText}</textarea>
        </div>
        <div class="hint">从另一台设备的「导出配置」复制过来,或者直接扫它的二维码。</div>
      </div>
      <!-- 这句话**预渲染在这儿、平时藏着**:打字那一支不重绘(重绘会打掉焦点与
           中文输入法组合),所以它的显隐只能由输入那一支原地翻,见 #sync-text 分支。 -->
      <div class="note" data-sync-error style="margin:var(--s5) 0 0${text && !ok ? '' : ';display:none'}">
        这段文本不是 Nordic 的配置 —— 检查一下有没有复制完整。</div>
    </div>`;

  /* 读出来之后那段预览:服务器一行 + 逐条线路,与「服务器与线路」那一屏同一套行。
     两句话按「带没带密码」分岔 —— 那正是接下来要用户做的事不一样的地方。
     整块包在 data-sync-preview 里:改一下文本就等于把这次「读出来」作废,
     那一支会原地把它收掉(见 #sync-text 分支),而不是留着让人以为还算数。 */
  const preview = STATE.syncRead ? `<div data-sync-preview>
    <div class="section"><h2>读出来的配置</h2><span class="trail">1 台服务器</span></div>
    <div class="card" style="margin:0 var(--s5)">
      <div class="row">
        <span class="set-icon">${ic('server', 18)}</span>
        <div class="grow">
          <div class="line1">${SERVER.name}</div>
          <div class="line2">${SERVER.kind} · ${SERVER.user}</div>
        </div>
      </div>
      ${SERVER.routes.map((r) => `
        <div class="divider"></div>
        <div class="row">
          <span class="dot ${r.state}"></span>
          <div class="grow">
            <div class="line1">${r.name}<span class="tag">${r.tag}</span></div>
            <div class="line2">${r.url}</div>
          </div>
          ${r.ping == null ? '' : `<span class="trail">${r.ping} ms</span>`}
        </div>`).join('')}
    </div>
    ${STATE.syncHasPw
      ? `<div class="note" style="margin-top:var(--s4)">
          这段配置带着密码 —— 连上之后它就是本机唯一一份凭据,别把这张二维码留在别人手机上。</div>`
      : `<div class="list-note" style="padding:var(--s4) var(--s5) 0">
          这段配置没带密码,接下来会落到录入表单 —— 地址与账号都填好了,只差密码。</div>`}
    <div class="note" style="margin-top:var(--s4)">
      导入会替换当前这台服务器,本机留着的曲库快照与缓存会一起清掉。</div>
    <div style="padding:var(--s5)">
      <button class="btn primary" data-act="sync-connect" style="width:100%;height:48px">
        ${STATE.syncHasPw ? '连接并替换' : '填上密码'}</button>
    </div></div>` : '';

  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">扫码同步</span>
      <span class="spacer"></span>
      ${mode === 'paste'
        ? `<button class="pill-btn solid" data-act="sync-read" ${ok ? '' : 'disabled style="opacity:.45;cursor:default"'}>读取</button>`
        : ''}
    </div>
    <div class="scroll">
      ${noCamera ? '' : `<div style="padding:var(--s3) var(--s5) var(--s4)">
        <div class="segmented">
          ${[['scan', '扫码'], ['paste', '粘贴']].map(([id, label]) =>
            `<button data-sync-mode="${id}" aria-selected="${mode === id}">${label}</button>`).join('')}
        </div>
      </div>`}
      ${noCamera ? `<div style="padding:0 var(--s5) var(--s4)">
        <div class="note" style="margin:0">这台设备没有摄像头 —— 用粘贴文本一样能同步。</div>
      </div>` : ''}
      ${mode === 'scan' ? scanPane : pastePane}
      ${preview}
      <div style="height:var(--s6)"></div>
    </div>`;
}

/* 导出配置 —— 走弹层而不是新开一屏:它是「看一眼 / 复制一下」,
   不是走进去再走出来的一段路(这样新屏数也就保持在一屏)。 */
function sheetExportConfig() {
  const withPw = STATE.syncIncludePw;
  const payload = syncDemoPayload(withPw);
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>导出配置 <span>扫码带走,或复制成文本</span></h2>
      <div class="sheet-body">
        <div class="qr-tile"><div class="qr">${qrPlaceholder(withPw ? 19 : 17, 25)}</div></div>
        <div class="card" style="margin:var(--s5) var(--s5) 0">
          <div class="row" data-toggle="syncIncludePw" role="switch" aria-checked="${withPw}">
            <span class="set-icon">${ic('shield', 18)}</span>
            <div class="grow">
              <div class="line1">包含密码</div>
              <div class="line2">${withPw
                ? '扫到的人可以直接连上'
                : '只带地址与账号,新设备补一次密码'}</div>
            </div>
            <span class="switch${withPw ? ' on' : ''}"><i></i></span>
          </div>
        </div>
        ${withPw ? `<div class="note" style="margin-top:var(--s4)">
          打开之后,这张二维码与这段文本就等于密码本身 —— 别截图、别发群里。</div>` : ''}
        <div class="qr-payload">${payload}</div>
        <div style="padding:var(--s4) var(--s5) 0">
          <button class="btn ghost" data-act="sync-copy" style="width:100%;height:46px">
            ${ic('copy', 17)} 复制文本</button>
        </div>
        <div class="sheet-note" style="padding-top:var(--s4)">
          没有摄像头的设备(桌面 / 浏览器)扫不了码 —— 把这段文本复制过去,
          粘进「扫码同步」那一屏,一样能带过去。
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
  /* 每一句都是**跳转落点**,但要**两下**才算数:第一下只选中(见 STATE.pendingLine),
     同一句再点一下才跳。落点仍是那一行的**中段**而不是起点 —— 高亮用的是
     floor(比例 × 行数),起点在浮点误差下会退到上一行(点第三句、高亮停第二句)。
     胶囊里报的就是这个落点:点第二下之前,先让人知道要去哪儿。 */
  const targetOf = (i) => ((i + 0.5) / LYRICS.length) * s.dur;
  const rowTitle = (i) => (i === STATE.pendingLine ? '再点一下就跳到这一句' : '点一下选中这一句');
  return `${ambient(a)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:12px;color:var(--fg-2);font-weight:620">${s.title} · ${s.artist}</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet" data-menu-for="song">${ic('more', 20)}</button>
    </div>
    <!-- 点某一句 = **选中**它(行尾浮出那颗「跳到这句 · 2:30」);同一句再点一下才真的
         跳到那一段 —— 两下才跳,见 STATE.pendingLine。点**行以外的空白**(上下各 30%
         的内边距)回封面 —— 与「点封面看歌词」互为来路,进出都不必去够返回键。
         两条都留着:只剩返回键的话,歌词页就成了唯一一屏进得去出不来靠顶栏的地方。
         拖动滚动不会触发 click,所以翻歌词不会误退、也不会误跳。 -->
    <div class="lyrics" data-go="player" role="button" title="点一下选中,再点跳到这一句;点空白回到封面">
      ${LYRICS.map((l, i) => `<div class="lyric-line ${i === activeIx ? 'on' : i < activeIx ? 'past' : ''}${i === STATE.pendingLine ? ' sel' : ''}" data-seek-line="${i}" role="button" title="${rowTitle(i)}"><span class="txt">${l}</span>${i === STATE.pendingLine ? `<span class="jump-chip">跳到这句 · ${mmss(targetOf(i))}</span>` : ''}</div>`).join('')}
    </div>
    ${scrubBar(s, elapsed)}
    ${mediaControls()}`;
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
            ${cover(a, 'sq')}
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
    ${bottom(undefined, undefined, 'search')}`;
}

/* ---------------- 设置 ---------------- */

function screenSettings() {
  /* 开关都是活的:点一下翻转,行里立刻换勾选态。
     第一行的值不是开关而是当前档位,所以走 data-sheet 打开转码面板。

     「仅 Wi-Fi 下载」原先挤在这一栏里 —— 它管的是下载,不是播放,
     现在跟着「下载管理」一起落到下面的「存储」栏:那一栏里手动的(下载)
     与顺手的(缓存)摆在一起,两件都落在盘上的事才看得出是一件事。 */
  const rows = [
    { key: 'quality', icon: 'wave',  t: '默认转码质量', d: '移动网络下生效', value: () =>
        (QUALITIES.find((x) => x.id === STATE.quality) || QUALITIES[2]).name, sheet: 'quality' },
    { key: 'autoRoute', icon: 'route', t: '线路自动择优', value: () => STATE.autoRoute ? '已开启' : '已关闭', toggle: true, d: () => STATE.autoRoute ? '按延迟选择最快可用地址' : '每条线路要手动锁定' },
    { key: 'bgPlay',    icon: 'bell',  t: '播放时后台运行', value: () => STATE.bgPlay ? '已开启' : '已关闭', toggle: true, d: () => STATE.bgPlay ? '通知栏与锁屏可控制' : '切到后台即暂停' },
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
            <div class="grow"><div class="line1">${r.t}</div><div class="line2">${typeof r.d === 'function' ? r.d() : r.d}</div></div>
            ${r.toggle
              ? `<span class="switch${on ? ' on' : ''}"><i></i></span>`
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
        <div class="divider"></div>
        <div class="row" data-go="sync">
          <span class="set-icon">${ic('qr', 18)}</span>
          <div class="grow"><div class="line1">扫码同步</div>
            <div class="line2">扫码或粘贴,把服务器与线路带到这台设备</div></div>
          ${ic('chevron', 18)}
        </div>
        <div class="divider"></div>
        <div class="row" data-sheet="exportConfig">
          <span class="set-icon">${ic('qr', 18)}</span>
          <div class="grow"><div class="line1">导出配置</div>
            <div class="line2">二维码 · 可复制成一段文本</div></div>
          ${ic('chevron', 18)}
        </div>
      </div>

      <div class="section"><h2>存储</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" data-sheet="cache">
          <span class="set-icon">${ic('stack', 18)}</span>
          <div class="grow">
            <div class="line1">歌曲缓存</div>
            <div class="line2">${STATE.cacheLimit === 'off'
              ? '已关闭:听过的歌每次都从服务器拉'
              : '听过的歌留在本机,再听不用重新拉'}</div>
          </div>
          <span class="trail" style="color:var(--fg-2)">${cacheLimitLabel(STATE.cacheLimit)}</span>
          ${ic('chevron', 17)}
        </div>
        <div class="divider"></div>
        <div class="row" style="cursor:default">
          <span class="set-icon">${ic('disc', 18)}</span>
          <div class="grow">
            <div class="line1">已用空间</div>
            <div class="line2">${STATE.cacheLimit === 'off' || !STATE.cacheUsedMb
              ? '缓存里还没有东西'
              : `占用 ${mbLabel(STATE.cacheUsedMb)} · 上限 ${cacheLimitLabel(STATE.cacheLimit)}`}</div>
          </div>
          ${STATE.cacheUsedMb ? `<button class="btn ghost" data-act="clear-cache"
            style="width:auto;height:34px;padding:0 15px;font-size:var(--fs-sm)">清除</button>` : ''}
        </div>
        <div class="divider"></div>
        <div class="row" data-go="downloads">
          <span class="set-icon">${ic('download', 18)}</span>
          <div class="grow"><div class="line1">下载管理</div>
            <div class="line2">${STATE.downloads.length
              ? `${STATE.downloads.filter((d) => d.state === 'active').length} 个进行中 · ${STATE.downloads.length} 项`
              : '队列是空的'}</div></div>
          ${ic('chevron', 18)}
        </div>
        <div class="divider"></div>
        <div class="row" data-toggle="wifiOnly" role="switch" aria-checked="${STATE.wifiOnly !== false}">
          <span class="set-icon">${ic('wifi', 18)}</span>
          <div class="grow"><div class="line1">仅 Wi-Fi 下载</div>
            <div class="line2">${STATE.wifiOnly !== false ? '流量下不缓存' : '流量下也会预取'}</div></div>
          <span class="switch${STATE.wifiOnly !== false ? ' on' : ''}"><i></i></span>
        </div>
      </div>

      <div class="section"><h2>关于</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" data-go="about">
          <span class="set-icon">${ic('info', 18)}</span>
          <div class="grow"><div class="line1">关于 Nordic</div>
            <div class="line2">版本 · 开源许可 · 服务器与隐私</div></div>
          ${ic('chevron', 18)}
        </div>
      </div>
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(undefined, undefined, 'settings')}`;
}

/* ---------------- 关于 ----------------

   设置里「关于」那一栏的落地页。它回答的是「这是什么软件、什么版本、
   我的东西在哪儿」—— 原先这三件事在设置里一个字都没有。

   **这一屏只写真的**:版本号在应用里是从**包**里读的
   (`package_info_plus` 读出的那份就是 `pubspec.yaml` 那一行,不是另存的一份);
   服务器那行读当前配置;隐私那两条是**陈述不是开关** —— 原先它们和开关混在
   同一屏里,读起来像可以关掉的东西。 */
const ABOUT_VERSION = '1.0.43+44';

function screenAbout() {
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:11px;color:var(--fg-3);letter-spacing:0.1em;font-weight:660">关于</span>
      <span class="spacer"></span>
      <span style="width:38px"></span>
    </div>
    <div class="scroll">
      <div class="about-hero">
        <div class="about-mark">${ICON_SVG(ICON_FINAL, { px: 88 })}</div>
        <div class="about-name">Nordic</div>
        <div class="about-line">多平台 NAS 音乐播放器</div>
        <div class="about-ver">${ABOUT_VERSION}</div>
      </div>

      <div class="card" style="margin:0 var(--s5)">
        <div class="row" style="cursor:default">
          <span class="set-icon">${ic('book', 18)}</span>
          <div class="grow"><div class="line1">开源许可</div>
            <div class="line2">Flutter 与各第三方包各自的许可证</div></div>
          ${ic('chevron', 18)}
        </div>
      </div>

      <div class="section"><h2>隐私</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" style="cursor:default">
          <span class="set-icon">${ic('shield', 18)}</span>
          <div class="grow"><div class="line1">凭据仅存本机</div>
            <div class="line2">密码交给系统密钥库加密保存,不上传任何数据</div></div>
        </div>
        <div class="divider"></div>
        <div class="row" style="cursor:default">
          <span class="set-icon">${ic('wave', 18)}</span>
          <div class="grow"><div class="line1">播放记录</div>
            <div class="line2">开播报一次「正在播放」,听够一半报一次「听过」—— 只发给服务器,本机不另存</div></div>
        </div>
      </div>

      <div class="list-note" style="padding-top:var(--s4)">
        这一页上版本号只有**顶部那一处**(它是原型的示意值);应用里那一份是从
        **装上的那个包**读出来的,所以换一版装上去,这里跟着变。
      </div>
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(undefined, undefined, 'settings')}`;
}


/* 排序面板 —— 与转码面板同一副骨架(选项行 + 勾),不另造一种弹层。 */
function sheetSort() {
  const forAlbums = STATE.sortFor === 'albums';
  const options = forAlbums ? ALBUM_SORTS : SONG_SORTS;
  const current = forAlbums ? STATE.albumSort : STATE.songSort;

  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>${forAlbums ? '专辑排序' : '歌曲排序'}
        <span>只影响「${forAlbums ? '全部专辑' : '全部歌曲'}」这一栏</span></h2>
      <div class="sheet-body">
        ${options.map(([id, label]) => `
          <div class="qopt" data-sort="${id}" role="radio" aria-selected="${current === id}">
            <div style="flex:1 1 auto"><div class="qname">${label}</div></div>
            <span class="tick${current === id ? ' on' : ''}">${ic('check', 14)}</span>
          </div>`).join('')}
      </div>
    </div>
  </div>`;
}

/* ---------------- 应用图标 ----------------

   这一屏**不是应用里的页面**,是设计交付物:把 tool/app_icon.py 出好的候选与定稿
   原样摆出来挑。所有图形都走 ICON_SVG() —— 和落到 Android 上的 PNG 同一份矢量,
   所以这里看到的带厚、辉光、两端就是装机上那个东西,不是「照着画的示意图」。 */
function screenIcon() {
  const pick = (v) => `
    <div class="icon-cell${v.id === ICON_FINAL ? ' picked' : ''}">
      ${ICON_SVG(v.id, { px: 96 })}
      <span class="icon-cap"><b>${v.id}${v.id === ICON_FINAL ? ' · 已定' : ''}</b>${v.name}<br>${v.note}</span>
    </div>`;

  /* 按**真实像素尺寸**渲染,不是缩放截图 —— 「48px 还清不清楚」只能这么判。 */
  const sizes = [192, 96, 48].map((px) => `
    <div class="icon-cell">
      ${ICON_SVG(ICON_FINAL, { px })}
      <span class="icon-cap">${px}px</span>
    </div>`).join('');

  /* 遮罩预览要复现启动器的**合成结果**:先铺地面、再叠前景,一起被裁。
     所以这里显式 ground:true(前景层本身是透明底的,地面由系统铺)。 */
  const masks = ICON_MASKS.map((m) => `
    <div class="icon-cell">
      ${ICON_SVG(ICON_FINAL, { mode: 'adaptive', mask: m.shape, ground: true, px: 96 })}
      <span class="icon-cap">${m.name}</span>
    </div>`).join('');

  return `<div class="appbar">
      <div><div class="h1">应用图标</div><div class="sub">音乐元素 · 候选与定稿</div></div>
    </div>
    <div class="scroll">
      <div class="section"><h2>候选</h2><span class="count">${ICON_VARIANTS.length} 个</span></div>
      <div class="icon-grid">${ICON_VARIANTS.map(pick).join('')}</div>
      <div class="list-note" style="padding-top:var(--s3)">
        八个候选,画的是**音乐本身的东西** —— 均衡器、唱片、声波、音符;极光那套渐变与
        辉光只当材质留在图形上,所以它和应用里的玻璃与氛围还是一家的。描着强调色那颗是
        当前定稿;要换,改 tool/app_icon.py 里的 FINAL 再跑一次生成 —— 生成器是唯一真相,
        别手改 icon.js。
      </div>

      <div class="section"><h2>定稿的尺寸</h2><span class="count">48px 是判据</span></div>
      <div class="icon-row">${sizes}</div>
      <div class="list-note" style="padding-top:var(--s3)">
        启动器里最小那一档就是 48px —— 它在,整套就在。
      </div>

      <div class="section"><h2>启动器的遮罩</h2><span class="count">定稿 · 自适应</span></div>
      <div class="icon-grid">${masks}</div>
      <div class="list-note" style="padding-top:var(--s3)">
        各家启动器裁的形状不一样(也有不裁的)。这里的地面与前景是按真机的顺序合成后才裁的,
        所以弧的两端在圆形下去留多少,和装机上一致。水滴那条是近似路径,真机再校。
      </div>
      <div style="height:var(--s5)"></div>
    </div>`;
}

/* ---------------- 视图表 ---------------- */

const sheets = { quality: sheetQuality, queue: sheetQueue, routes: sheetRoutes, menu: sheetMenu, sort: sheetSort, cache: sheetCache, exportConfig: sheetExportConfig, songInfo: sheetSongInfo };

/* 弹层是叠在当前屏上的，不是某一屏专属 —— 专辑页的「队列」、设置里的
   「默认转码质量」、音乐库的「排序」都要能把同一张面板揭起来。之前只有
   播放页拼了 overlay,于是另外几处点了没反应（点了跟没点一样）——
   所以**每一屏都走这里**,而不是逐个补。 */
const withOverlay = (inner) => inner + (STATE.overlay && sheets[STATE.overlay] ? sheets[STATE.overlay]() : '');

const VIEWS = {
  servers:        () => shell(withOverlay(screenServers())),
  'server-config':() => shell(withOverlay(screenServerConfig())),
  'add-server':   () => shell(withOverlay(screenAddServer())),
  'add-route':    () => shell(withOverlay(screenAddRoute())),
  sync:           () => shell(withOverlay(screenSync())),
  downloads:      () => shell(withOverlay(screenDownloads())),
  'new-playlist': () => shell(withOverlay(screenNewPlaylist())),
  /* 首页与音乐库的未连接态同一个开关:设置页点过「移除该服务器」之后
     (STATE.removed),这两屏铺的就是应用那边 `EmptyState('还没有连接服务器')` 那一支。 */
  home:           () => shell(withOverlay(screenHome(STATE.removed))),
  /* 默认落在「歌曲」:打开音乐库多半是想找一首具体的歌(2026-10-17 用户要求)。 */
  library:        (p) => shell(withOverlay(screenLibrary((p && p.lib) || 'songs', STATE.removed))),
  album:          (p) => { const a = ALBUM_BY_ID((p && p.album) || STATE.albumId); return shell(withOverlay(screenAlbum(a.id)), { home: true, accent: a.accent, c1: a.c1 }); },
  artist:         (p) => { const ar = ARTIST_BY_ID((p && p.artist) || STATE.artistId); return shell(withOverlay(screenArtist(ar.id)), { home: true, accent: ar.accent, c1: ar.c1 }); },
  player:         () => shell(withOverlay(screenPlayer()), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 }),
  lyrics:         () => shell(withOverlay(screenLyrics()), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 }),
  search:         () => shell(withOverlay(screenSearch())),
  settings:       () => shell(withOverlay(screenSettings())),
  about:          () => shell(withOverlay(screenAbout())),
  /* 设计交付物,不对应应用里的一屏 —— 见 BOARD 的最后一条 */
  icon:           () => shell(withOverlay(screenIcon())),
};

/* ============================================================
   设计板
   ============================================================ */

const BOARD = [
  ['服务器与线路',    '线路状态 / 自动择优',  () => shell(screenServers())],
  ['服务器设置',      '一个账号，多个地址',    () => shell(screenServerConfig())],
  ['添加服务器',      '选择接入类型',         () => shell(screenAddServer())],
  ['首页',           '正在播放 + 三条货架',  () => shell(screenHome())],
  /* 未连接是首页的一个状态,不是另一屏 —— 挨着铺,与「音乐库」四栏同一套摆法。 */
  ['首页 · 未连接',  '空态 + 两个入口',      () => shell(screenHome(true))],
  ['音乐库 · 专辑',   '封面网格 + 排序',      () => shell(screenLibrary('albums'))],
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
  ['歌词',            '逐句高亮 · 两下才跳', () => shell(screenLyrics(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  ['搜索',            '输入即筛选',           () => shell(screenSearch())],
  ['设置',            '播放 / 服务器 / 存储', () => shell(screenSettings())],
  ['关于',            '许可 · 隐私 · 播放记录', () => shell(screenAbout())],
  /* 这三张是新增的整屏功能页,设计板一并铺出来 —— 它们不再是 toast,
     是真的能走进去、能提交的页面。 */
  ['下载管理',        '队列 + 进度',          () => shell(screenDownloads())],
  ['新建歌单',        '命名 + 封面色',        () => shell(screenNewPlaylist())],
  ['添加线路',        '地址 + 标记',          () => shell(screenAddRoute())],
  /* 扫码同步的三格:「没有摄像头」那一格是**必须铺的** —— 它铺的是 Windows 桌面与
     浏览器真正看到的那个样子,只在 .cjs 截图里存在的话,设计板上就没人核对得到。 */
  ['扫码同步',        '扫码 / 粘贴 + 预览',    () => shell(screenSync())],
  ['扫码同步 · 没有摄像头', '退成纯粘贴',      () => shell(screenSync(true))],
  ['导出配置',        '二维码 + 复制文本',    () => shell(screenSettings() + sheetExportConfig())],
  ['上下文菜单',      '歌曲的「⋯」',          () => shell(screenPlayer() + sheetMenu(), { home: true, accent: currentAlbum().accent, c1: currentAlbum().c1 })],
  /* 最后一格不是应用里的页面,是**设计交付物**:图标的候选与定稿。
     放最后是因为它不参与上面那条「服务器 → 首页 → 库 → 详情 → 播放」的链路
     —— 它回答的是「这个应用在启动器里长什么样」,跟界面结构无关。 */
  ['应用图标',        '音乐元素 · 候选与定稿', () => shell(screenIcon())],
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
        <p>手机竖屏，26 格（25 屏 + 应用图标），<b>深色 / 浅色两套</b>。强调色<b>从当前封面里提取</b> —— 每张专辑驱动界面的光晕、进度条与选中态，
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

/* toast 与计时器都是 stage 级 —— 一个会话一份,跨重绘存续。
   写在 render 外头,免得每次 render 都开新计时器。 */
let toastTimer = 0;
/* 「回到正在播放」那一下高亮的计时器同上:stage 级、跨重绘存续。
   连点几下只该有一次熄灭 —— 每次都开一个新的,前一个会提前把后一个摘掉。 */
let locateTimer = 0;
function toastMarkup() {
  return STATE.toast ? `<div class="toast">${STATE.toast}</div>` : '';
}

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

  /* 进 / 出**播放页与歌词页**走哪一套过渡(2026-10-18 定):

     - 从别处进播放页 / 歌词页,以及从它们退出去 —— **淡入**(0.22s / --ease,
       与切 tab 同一套)。真机反馈滑入那 320ms 有顿挫,用户要求换成这一套试试;
       原型跟着改,不然两边的手感对不上。
     - 播放页 ↔ 歌词页 —— **不过渡**:它们是同一个播放对象的两面
       (点封面互相翻),滑动会读成「进了另一个页面」。
     - 其余二级页(专辑 / 艺人 / 歌单 / 服务器…)仍是**整屏滑动**。

     方向与用途靠 <html data-nav> 分辨,View Transition 自己不知道这是进还是退。 */
  const PLAYBACK_VIEWS = ['player', 'lyrics'];
  const navKind = (nav, entering, leaving) => {
    if (nav === 'push') {
      if (PLAYBACK_VIEWS.includes(entering) && PLAYBACK_VIEWS.includes(leaving)) return 'flip';
      if (PLAYBACK_VIEWS.includes(entering)) return 'fade-in';
    }
    if (nav === 'back') {
      if (PLAYBACK_VIEWS.includes(entering) && PLAYBACK_VIEWS.includes(leaving)) return 'flip';
      if (PLAYBACK_VIEWS.includes(leaving)) return 'fade-out';
    }
    return nav;
  };

  const render = (morph = false, nav = '') => {
    const view = VIEWS[STATE.view];
    if (!view) return;
    const paint = () => {
      slot().innerHTML = view(STATE.params) + toastMarkup();
      /* 推入 / 返回时新页**不自己淡入** —— 那件事改由整格承担(滑动或淡入,见 navKind)。
         写成行内样式而不是类:行内跟着这次 paint 的节点一起生灭,
         撤标记时不会把淡入动画重新启动一遍。 */
      if (nav) {
        const screen = slot().querySelector('.screen');
        if (screen) screen.style.animation = 'none';
      }
    };

    if ((!morph && !nav) || !supportsVT) { clearMorph(); return paint(); }

    /* 起名必须在快照之前，撤名必须在快照之后，否则两端拿不到同一对元素。 */
    const named = [];
    if (morph && morphEl) { morphEl.style.viewTransitionName = 'cover-art'; named.push(morphEl); }
    /* 动的是**手机那一格**,不是整页 —— 舞台侧栏与说明文字不该跟着动。
       方向与用途靠 <html data-nav>:View Transition 自己不知道这是「进」还是「退」。 */
    if (nav) {
      slot().style.viewTransitionName = 'phone';
      document.documentElement.dataset.nav = nav;
    }

    const t = document.startViewTransition(() => {
      paint();
      if (!morph) return;
      /* 播放页与专辑页的大封面在这里点名 —— 名字只在过渡期间挂着。
         不能图省事写成标记里的静态样式：t.finished 撤名时会连静态值一起抹掉，
         第一次过渡之后那处封面就再也当不了起点或终点。 */
      const hero = slot().querySelector('.player-hero .cover, .album-hero .cover');
      if (hero) { hero.style.viewTransitionName = 'cover-art'; named.push(hero); }
    });
    t.finished.finally(() => {
      named.forEach((el) => { el.style.viewTransitionName = ''; });
      if (nav) {
        slot().style.viewTransitionName = '';
        delete document.documentElement.dataset.nav;
      }
    });
    /* 起点是一次性的，用完就丢，免得下一次 back() 把它当成起点再点一次名。 */
    morphEl = null;
  };

  /* 小气泡:点了但原型没实现的按钮,至少说一声它本该做什么。
     自动 1.6s 后消失 —— 这段时间够用户看清,又不会一直挂在屏幕上。 */
  let toastTimer = 0;
  const toast = (text) => {
    STATE.toast = text;
    render();
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => { STATE.toast = ''; render(); }, 1600);
  };

  const go = (name, params, nav = 'push') => {
    const morph = name === 'player' || name === 'album';
    const leaving = STATE.view;
    if (name !== STATE.view) STATE.history.push({ view: STATE.view, params: STATE.params });
    STATE.view = name;
    STATE.params = params || {};
    STATE.overlay = '';
    /* 歌词那层「待跳转」只在一趟里算数 —— 离开这一屏(含从别处再进来)就清掉,
       免得回来时行尾还挂着一颗上一趟留下的胶囊。 */
    if (name !== 'lyrics') STATE.pendingLine = -1;
    render(morph, navKind(nav, name, leaving));
  };

  const back = () => {
    const leaving = STATE.view;
    const prev = STATE.history.pop();
    if (prev) {
      STATE.view = prev.view;
      STATE.params = prev.params || {};
    } else {
      STATE.view = 'library';
      STATE.params = { lib: 'songs' };
    }
    STATE.overlay = '';
    STATE.pendingLine = -1;
    render(true, navKind('back', STATE.view, leaving));
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
          <li>设置里的「扫码同步 / 导出配置」把服务器与线路变成一张二维码(密码默认不带)</li>
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
    /* 缓冲带按**真实播放位置**算,不跟着手指走:边听边下与手指在哪儿无关,
       跟着跑的话「已下到哪儿」就读不出来了(往后一拖,缓冲区整条跟着挪)。
       应用那边(`PlaybackScrubber`)是同一个口径,拖动不改这一层。 */
    const realElapsed = STATE.elapsed;
    const paint = (clientX) => {
      const r = trackEl.getBoundingClientRect();
      const ratio = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
      STATE.elapsed = Math.round(ratio * s.dur);
      /* **`i.played`,不是 `i`**:轨道里多了缓冲带之后,第一个 `i` 是**缓冲带**,
         照旧写 `i` 的话拖动的就是那一条(看起来像「拖动改了缓冲进度」)。
         两条 `i` 一律按类名点。 */
      const bar = trackEl.querySelector('i.played');
      if (bar) bar.style.width = `${ratio * 100}%`;
      const bufBar = trackEl.querySelector('i.buf');
      if (bufBar) {
        const buf = bufferedPctOf(s, realElapsed);
        bufBar.style.width = buf == null ? '0%' : `${buf}%`;
      }
      const knob = trackEl.querySelector('.knob');
      if (knob) knob.style.left = `${ratio * 100}%`;
      const times = trackEl.parentElement.querySelector('.times');
      if (times && times.children.length === 2) {
        const e2 = Math.min(STATE.elapsed, s.dur);
        times.children[0].textContent = mmss(e2);
        times.children[1].textContent = `-${mmss(s.dur - e2)}`;
      }
    };
    /* 点击处补一个触觉反馈：拖动时把 .track 标记为 active，旋钮随之放大变亮 ——
       没有这一步的话，旋钮只是个静止的小点，拖起来毫不像「正握在手里」。 */
    trackEl.classList.add('active');
    trackEl.setPointerCapture(ev.pointerId);
    paint(ev.clientX);
    const move = (m) => paint(m.clientX);
    const up = () => {
      trackEl.classList.remove('active');
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
    const t = e.target.closest('[data-back],[data-tab],[data-go],[data-seek-line],[data-lib],[data-song],[data-album],[data-artist],[data-route],[data-quality],[data-set-theme],[data-sheet],[data-act],[data-scope],[data-pick-kind],[data-toggle],[data-kind-cfg],[data-menu-for],[data-menu-go],[data-dl-del],[data-hue],[data-route-tag],[data-sync-mode],[data-sort-for],[data-sort],[data-cache]');
    if (t) {
      const d = t.dataset;
      if (d.back !== undefined) return back();
      if (d.tab) { STATE.history = []; return go(d.tab, null, ''); }
      if (d.lib) { STATE.params = { lib: d.lib }; return render(); }
      if (d.song) {
        /* 从顶部播放坞点进播放页时，坞里也有同一张封面 —— 但那块的尺寸太小，
           飞过去的观感不如不加。只在从列表/网格进来时记录起点。 */
        morphEl = t.closest('[data-morph]') ? t.querySelector('.cover') : null;
        /* 换歌要重算进度：上一首听到哪儿，和这一首没有关系。
           原进度超过新歌长度的话，夹回去，免得一进去就显示成"已放完"。 */
        STATE.songId = d.song;
        STATE.elapsed = Math.min(STATE.elapsed, currentSong().dur - 1);
        /* 换歌了,上一首选中的那一句不算数(行号也会对不上)。 */
        STATE.pendingLine = -1;
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
      /* 扫码 / 粘贴换过去时把上一份预览收掉 —— 那份预览说的是**另一种**输入方式
         读出来的结果,留着会让人以为换模式也换了内容。 */
      if (d.syncMode) { STATE.syncMode = d.syncMode; STATE.syncRead = false; return render(); }
      if (d.toggle) {
        STATE[d.toggle] = STATE[d.toggle] === false;
        /* 导出那张纸上的「包含密码」一翻,粘贴框里那段也跟着换一份:
           复制走的那串与二维码里那串本来就是同一个东西,不跟着换就自相矛盾了。 */
        if (d.toggle === 'syncIncludePw') {
          STATE.syncText = syncDemoPayload(STATE.syncIncludePw);
          STATE.syncRead = false;
        }
        return render();
      }
      if (d.setTheme) { applyTheme(d.setTheme); return render(); }
      if (d.kindCfg) { STATE.serverKindCfg = d.kindCfg; STATE.serverDirty = true; return render(); }
      if (d.quality) { STATE.quality = d.quality; STATE.overlay = ''; return render(); }
      /* 换上限只是改个数 —— 已经用掉的照旧留在那儿(等它自然被淘汰)。
         顺手再夹一次:改成比现在占用还小的额度,占用立刻降到上限之下。 */
      if (d.cache) {
        STATE.cacheLimit = d.cache;
        const mb = cacheLimitOf(d.cache).mb;
        if (!mb) STATE.cacheUsedMb = 0;
        else if (STATE.cacheUsedMb > mb) STATE.cacheUsedMb = mb;
        STATE.overlay = '';
        toast(STATE.cacheLimit === 'off' ? '已关闭缓存,本机不再留音频' : `缓存上限改为 ${mbLabel(mb)}`);
        return render();
      }
      if (d.sheet) { STATE.overlay = STATE.overlay === d.sheet ? '' : d.sheet; return render(); }
      if (d.sortFor) { STATE.sortFor = d.sortFor; STATE.overlay = 'sort'; return render(); }
      if (d.sort) {
        if (STATE.sortFor === 'albums') STATE.albumSort = d.sort;
        else STATE.songSort = d.sort;
        /* 重新选一次「随机」就换一副牌 —— 同一副牌点来点去都是一样的顺序。 */
        if (d.sort === 'random') STATE.randomSeed = (STATE.randomSeed * 7 + 13) % 9973;
        STATE.overlay = '';
        return render();
      }
      /* 点某一句歌词:**两下**才算跳。第一下只选中(行尾浮出「跳到这句 · 2:30」),
         同一句再点一下才落下去;点别的句子只是改选,不跳 —— 跳转不可逆,
         手一滑就跳到别处、原来那句还回不去,所以先让人确认一次。
         落点与高亮同一套规则(见 screenLyrics):没有时间轴,按整首摊行取那一行的
         **中段** —— 取起点会在浮点误差下退到上一行。 */
      if (d.seekLine !== undefined) {
        const i = Number(d.seekLine);
        const lines = LYRICS.length;
        if (!lines || !currentSong().dur) return;
        if (STATE.pendingLine !== i) { STATE.pendingLine = i; return render(); }
        STATE.pendingLine = -1;
        STATE.elapsed = Math.round(((i + 0.5) / lines) * currentSong().dur);
        return render();
      }
      if (d.go) return go(d.go);
      /* 回到正在播放的那一首:滚到它那一行,并让它**亮一下**。
         只做一件事是不够的 —— 一千多行的列表里滚过去了,眼睛未必跟得上落点。
         亮完就把标记摘掉,不留下一个「选中」的错觉(选中的是正在放的那一首,
         不是这一行被点了)。 */
      if (d.act === 'locate') {
        STATE.locateAt = Date.now();
        render();
        /* **重绘之后**才拿节点**在 stage 里找,不是 document**:设计板那一版也铺着
           同一批 `.row.playing`(board 模式下点不着,但 document.querySelector
           会先命中它,于是滚的是板子上那一格)。 */
        const row = root.querySelector('.scroll .row.playing');
        if (row) row.scrollIntoView({ block: 'center', behavior: 'smooth' });
        clearTimeout(locateTimer);
        locateTimer = setTimeout(() => { STATE.locateAt = 0; render(); }, 1200);
        return;
      }
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
      /* 首页空态那颗「随机播放」:随便挑一首开播(原型没有真队列,示意即可)。 */
      if (d.act === 'shuffle-all') {
        const n = Math.floor(Math.random() * SONGS.length);
        STATE.songId = SONGS[n].id;
        STATE.elapsed = 0;
        STATE.playing = true;
        return render();
      }
      if (d.act === 'repeat')  { STATE.repeat  = !STATE.repeat;  return render(); }
      if (d.act === 'ping-all') {
        STATE.pinging = true;
        render();
        /* 不真的测速，但「按下去要等一下才有结果」这个节奏得对上：
           800ms 后重绘，按钮从「测速中」跳回「重新测速」。 */
        window.setTimeout(() => { if (STATE.pinging) { STATE.pinging = false; render(); } }, 800);
        return;
      }
      /* ---- 上下文菜单 / 下载 / 新建歌单 / 添加线路 ----
         之前这几处都拿 toast 搪塞,现在是真页面/真面板在背后。
         死按钮的解法不是气泡,是把按钮背后的屏补出来。 */
      if (d.menuFor) { STATE.menuFor = d.menuFor; STATE.overlay = 'menu'; return render(); }
      if (d.menuGo) {
        const [kind, val] = d.menuGo.split(':');
        STATE.overlay = '';
        if (kind === 'act') {
          if (val === 'fav') {
            const set = STATE.fav.songs;
            set.has(STATE.songId) ? set.delete(STATE.songId) : set.add(STATE.songId);
          } else if (val === 'fav-album') {
            const set = STATE.fav.albums;
            const id = STATE.params.album; if (id) set.has(id) ? set.delete(id) : set.add(id);
          } else if (val === 'fav-artist') {
            const set = STATE.fav.artists;
            const id = STATE.params.artist; if (id) set.has(id) ? set.delete(id) : set.add(id);
          } else if (val === 'queue-add') {
            toast('已加入播放队列');
          } else if (val === 'shuffle-album') {
            /* 随机播这张专辑:进播放页、打开随机、从这张专辑里挑一首起。
               原型不假装真的重排队列,但「按下之后去了哪儿」要是真的。 */
            const a = ALBUM_BY_ID(STATE.params.album || STATE.albumId);
            const mine = tracksOf(a.id);
            if (!mine.length) { toast('这张专辑还没有曲目'); return render(); }
            STATE.shuffle = true;
            STATE.songId = mine[Math.floor(Math.random() * mine.length)].id;
            STATE.elapsed = 0;
            STATE.playing = true;
            return go('player');
          } else if (val === 'dl-song') {
            dlEnqueue('song', currentSong());
            toast('已加入下载队列');
          } else if (val === 'dl-album') {
            dlEnqueue('album', ALBUM_BY_ID(STATE.params.album || STATE.albumId));
            toast('整张专辑已加入下载队列');
          } else if (val === 'dl-artist') {
            const ar = ARTIST_BY_ID(STATE.params.artist || STATE.artistId);
            songsOf(ar.name).forEach((s) => dlEnqueue('song', s));
            toast('这位艺人的歌曲已加入下载队列');
          } else if (val === 'fav') {
            toast('已更新收藏');
          }
          return render();
        }
        if (kind === 'sheet') { STATE.overlay = val; return render(); }
        if (kind === 'album') { return go('album', { album: val }); }
        return render();
      }
      if (d.dlDel) {
        STATE.downloads = STATE.downloads.filter((x) => x.id !== d.dlDel);
        return render();
      }
      if (d.hue) { STATE.plHue = +d.hue; return render(); }
      if (d.routeTag) { STATE.routeTag = d.routeTag; return render(); }
      if (d.act === 'save-server') {
        STATE.serverDirty = false;
        SERVER.name = STATE.serverName;
        SERVER.user = STATE.serverUser;
        toast('已保存');
        return render();
      }
      if (d.act === 'remove-server') {
        STATE.removed = true;
        toast('已从原型移除（刷新页面可以找回来）');
        /* 移除后退出到服务器列表 —— 停在已移除的设置页里没有意义 */
        return go('servers');
      }
      /* ---- 扫码同步 ----
         「读取」只在文本看着像 Nordic 配置时才出现(见 screenSync),所以走到这儿
         已经过了那道前缀检查;结尾那个 `#pw` 是原型自己的记号,见 syncDemoPayload。 */
      if (d.act === 'sync-read') {
        const text = STATE.syncText.trim();
        STATE.syncRead = text.startsWith('nordic://config/1/');
        STATE.syncHasPw = STATE.syncRead && text.endsWith('#pw');
        return render();
      }
      if (d.act === 'sync-connect') {
        /* 原型不真连服务器 —— 但它真把「连上了」这件事做出来:
           未连接那两块空态收掉,回到首页。 */
        STATE.removed = false;
        toast('已连接(原型)');
        return go('home');
      }
      /* 复制真的调剪贴板,不拿一个假气泡搪塞 —— 而拷贝不出来时那句话是真的有用:
         浏览器的剪贴板 API 在非安全上下文里就是会被拒。 */
      if (d.act === 'sync-copy') {
        const payload = syncDemoPayload(STATE.syncIncludePw);
        (navigator.clipboard && navigator.clipboard.writeText
          ? navigator.clipboard.writeText(payload)
          : Promise.reject(new Error('no clipboard'))
        ).then(() => toast('已复制到剪贴板'))
          .catch(() => toast('复制不了,选中下面那段文本手动复制'));
        return;
      }
      if (d.act === 'clear-cache') {
        const freed = STATE.cacheUsedMb;
        if (!freed) return;
        STATE.cacheUsedMb = 0;
        toast(`已清除缓存,释放 ${mbLabel(freed)}`);
        return render();
      }
      if (d.act === 'dl-song') { dlEnqueue('song', currentSong()); toast('已加入下载队列'); return render(); }
      if (d.act === 'dl-album') {
        dlEnqueue('album', ALBUM_BY_ID(STATE.params.album || STATE.albumId));
        toast('整张专辑已加入下载队列');
        return render();
      }
      if (d.act === 'create-playlist') {
        const name = STATE.plName.trim();
        if (!name) return;
        PLAYLISTS.push({
          id: 'p' + (PLAYLISTS.length + 1),
          name, count: 0, desc: '新建 · 还没有歌',
          c1: `hsl(${STATE.plHue} 42% 30%)`,
          c2: `hsl(${STATE.plHue} 48% 12%)`,
          accent: `hsl(${STATE.plHue} 70% 66%)`,
        });
        STATE.plName = '';
        toast(`「${name}」已创建`);
        return go('library', { lib: 'playlists' });
      }
      if (d.act === 'create-route') {
        const url = STATE.routeUrl.trim();
        if (!/^https?:\/\/.+/.test(url)) return;
        SERVER.routes.push({
          id: 'r' + (SERVER.routes.length + 1),
          name: url.replace(/^https?:\/\//, '').split(/[/:]/)[0],
          url, ping: null, state: 'ok', tag: STATE.routeTag, bars: 3,
        });
        STATE.routeUrl = '';
        toast('线路已添加,正在测速');
        return go('server-config');
      }
      return; // 其余为示意，不改变状态
    }
    if (e.target.classList.contains('sheet-scrim')) {
      STATE.overlay = '';
      render();
    }
  });

  /* 搜索框：input 走委托，因为 #search-input 会随每次重绘被整块换掉。
     重绘后要把焦点和光标位置还回去，否则打一个字就掉焦，得重新点一下才能接着打。
     新建歌单 / 添加线路的输入框同一条路 —— 写状态 + 原地改按钮,不整屏重绘。 */
  root.addEventListener('input', (e) => {
    if (e.target.id === 'search-input') {
      STATE.query = e.target.value;
      render();
      const next = slot().querySelector('#search-input');
      if (next) {
        next.focus();
        try { next.setSelectionRange(next.value.length, next.value.length); } catch { /* 某些输入源没有选区 */ }
      }
      return;
    }
    if (e.target.id === 'pl-name') {
      STATE.plName = e.target.value;
      const preview = slot().querySelector('.hero-card .t');
      if (preview) preview.textContent = STATE.plName.trim() || '未命名歌单';
      const btn = slot().querySelector('[data-act="create-playlist"]');
      if (btn) {
        const on = !!STATE.plName.trim();
        btn.disabled = !on;
        btn.style.opacity = on ? '' : '.45';
        btn.style.cursor = on ? '' : 'default';
      }
      return;
    }
    /* 扫码同步的粘贴框 —— 与上面几个输入框同一条纪律:**只改状态与那颗按钮,不重绘**。
       一重绘,焦点、中文输入法组合、光标位置全没,打一个字就得重新点一下。 */
    if (e.target.id === 'sync-text') {
      STATE.syncText = e.target.value;
      const text = STATE.syncText.trim();
      const ok = text.startsWith('nordic://config/1/');
      const btn = slot().querySelector('[data-act="sync-read"]');
      if (btn) {
        btn.disabled = !ok;
        btn.style.opacity = ok ? '' : '.45';
        btn.style.cursor = ok ? '' : 'default';
      }
      const err = slot().querySelector('[data-sync-error]');
      if (err) err.style.display = (text && !ok) ? '' : 'none';
      /* 文本一改,上一次「读出来」就作废 —— 把预览收掉,别让它挂着一份旧结果
         骗人(那句说明与那颗按钮都在块内,跟着一起走)。 */
      const pv = slot().querySelector('[data-sync-preview]');
      if (pv) { STATE.syncRead = false; pv.remove(); }
      return;
    }
    if (e.target.id === 'route-url') {
      STATE.routeUrl = e.target.value;
      const ok = /^https?:\/\/.+/.test(STATE.routeUrl.trim());
      const btn = slot().querySelector('[data-act="create-route"]');
      if (btn) {
        btn.disabled = !ok;
        btn.style.opacity = ok ? '' : '.45';
        btn.style.cursor = ok ? '' : 'default';
      }
      return;
    }
    /* 服务器设置页的三个输入框。字段一动就把脏标记立起来 + 写回 STATE 而不重绘 ——
       一重绘,输入框的焦点、中文输入法组合、光标位置全没。 */
    const f = e.target.dataset && e.target.dataset.field;
    if (f) {
      STATE[f] = e.target.value;
      STATE.serverDirty = true;
      const btn = slot().querySelector('[data-act="save-server"]');
      if (btn) { btn.disabled = false; btn.style.opacity = ''; btn.style.cursor = ''; }
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

  /* ---- 播放计时 ----
     让时间真的走：播放中每秒 +1s，进度条、时间、歌词高亮跟着挪。
     不能整屏重绘 —— 一秒一次的重绘会把唱片旋转、封面过渡、正在进行的拖动全打断。
     所以原地改样式（与 bindSeekDrag 同一招：不重绘，只动现有节点）。
     播到结尾走一次完整渲染换下一首；开了循环就原地回到 0:00 接着放。 */
  window.setInterval(() => {
    if (!STATE.playing) return;
    const el = slot();
    if (!el) return;
    const s = currentSong();
    STATE.elapsed += 1;
    if (STATE.elapsed >= s.dur) {
      if (STATE.repeat) { STATE.elapsed = 0; }
      else {
        const i = SONGS.findIndex((x) => x.id === STATE.songId);
        STATE.songId = SONGS[(i + 1) % SONGS.length].id;
        STATE.elapsed = 0;
      }
      return render();
    }
    const pct = progressOf(s, STATE.elapsed);
    /* 托盘里那条分隔线(播放坞与标签栏之间,兼作进度)与库页英雄卡下的细线 ——
       这两条本来就是「现在就播着」的进度,不走就等于明说这是静止截图。 */
    el.querySelectorAll('.tray-line i, .prog-line i')
      .forEach((x) => { x.style.width = `${pct}%`; });
    const track = el.querySelector('[data-seek]');
    if (track) {
      const bar = track.querySelector('i.played');
      if (bar) bar.style.width = `${pct}%`;
      // 缓冲带跟着位置走(见 bufferedPctOf);顶到曲尾那一档把它收成 0。
      const bufBar = track.querySelector('i.buf');
      if (bufBar) {
        const buf = bufferedPctOf(s, STATE.elapsed);
        bufBar.style.width = buf == null ? '0%' : `${buf}%`;
      }
      const knob = track.querySelector('.knob');
      if (knob) knob.style.left = `${pct}%`;
      const times = track.parentElement.querySelector('.times');
      if (times && times.children.length === 2) {
        times.children[0].textContent = mmss(STATE.elapsed);
        times.children[1].textContent = `-${mmss(s.dur - STATE.elapsed)}`;
      }
    }
    const lines = el.querySelectorAll('.lyric-line');
    if (lines.length) {
      const ix = Math.min(lines.length - 1, Math.floor((STATE.elapsed / s.dur) * lines.length));
      lines.forEach((line, i) => {
        line.classList.toggle('on', i === ix);
        line.classList.toggle('past', i < ix);
      });

      /* 高亮句自动滚到歌词框中央。歌词框可滚动,高亮只会往下走,
         不跟着滚的话,唱到后半段高亮句就飘出屏幕了,逐句高亮形同虚设。
         只在换行那一刻滚(data-lyric-ix 记住上次的行号),而不是每秒滚一次 ——
         一来每秒一次 smooth 滚动会互相打断,二来连续滚动会一直拽着用户,
         换行才滚,行与行之间留出自由浏览的间隙。 */
      const box = el.querySelector('.lyrics');
      if (box && box.dataset.lyricIx !== String(ix)) {
        box.dataset.lyricIx = String(ix);
        const line = lines[ix];
        box.scrollTo({ top: line.offsetTop - box.clientHeight / 2 + line.clientHeight / 2, behavior: 'smooth' });
      }
    }
  }, 1000);

  /* ---- 下载进度 ----
     队列里 active 的条目每次渲染往前挪一点,到 100 变 done。
    挂在播放计时旁边而不是单开计时器:下着歌的同时下歌,两件事本来就该并行。
     只在真的有下载任务时重绘 —— 空队列不值得每秒闪一次。 */
  window.setInterval(() => {
    const active = STATE.downloads.filter((d) => d.state === 'active');
    if (!active.length) return;
    active.forEach((d) => {
      d.pct = Math.min(100, d.pct + 7 + Math.random() * 9);
      if (d.pct >= 100) d.state = 'done';
    });
    render();
  }, 1200);

  render();
}

/* ---------------- 启动 ---------------- */

window.addEventListener('DOMContentLoaded', () => {
  applyTheme(STATE.theme);
  if (document.body.dataset.mode === 'board') renderBoard(document.body);
  else renderStage(document.body);
});
