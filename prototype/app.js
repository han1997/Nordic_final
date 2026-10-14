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

const SONGS = [
  { id: 's1', title: '可能',     artist: '程响', album: '可能', albumId: 'a1', dur: 218, fmt: 'FLAC', kbps: 780, fav: true  },
  { id: 's2', title: '人间烟火', artist: '程响', album: '可能', albumId: 'a1', dur: 245, fmt: 'FLAC', kbps: 812, fav: false },
  { id: 's3', title: '四季予你', artist: '程响', album: '可能', albumId: 'a1', dur: 232, fmt: 'FLAC', kbps: 764, fav: false },
  { id: 's4', title: '等你归来', artist: '程响', album: '可能', albumId: 'a1', dur: 258, fmt: 'FLAC', kbps: 798, fav: true  },
  { id: 's5', title: '时光洪流', artist: '程响', album: '可能', albumId: 'a1', dur: 224, fmt: 'FLAC', kbps: 770, fav: false },
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
  { id: 'p2', name: '工作专注',     count: 58, desc: '器乐为主,无人声干扰',   c1: '#14342E', c2: '#08170F', accent: '#4FD8C4' },
  { id: 'p3', name: '华语民谣精选', count: 41, desc: '长期收藏,持续更新',     c1: '#4A2E2A', c2: '#180F0E', accent: '#E0796A' },
  { id: 'p4', name: '电子脉冲',     count: 27, desc: '高能量,适合运动',       c1: '#1E2A5E', c2: '#0C1024', accent: '#7B8CFF' },
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
  { id: 'original', name: '原音直出', desc: '不转码,按原始文件播放。仅建议在局域网使用。', tag: '无损' },
  { id: 'high',     name: '高质量',   desc: '转码为 320 kbps。音质接近原始,流量约减半。' },
  { id: 'medium',   name: '均衡',     desc: '转码为 192 kbps。移动网络下推荐,拖动进度更快。' },
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
};

const THEMES = [
  { id: 'dark',  name: '深色', desc: '近黑底,靠光晕撑层次' },
  { id: 'light', name: '浅色', desc: '浅灰底,靠留白与描边' },
];

/* ---- 强调色 ----
   --accent      画描边 / 光晕 / 选中底色,保留封面原色
   --accent-safe 只用来画文字。浅色底上,黄 / 绿 / 青这类高亮色对比度不够,
                 压深一档再用;深色底原样使用。 */
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
const currentSong = () => SONGS.find((x) => x.id === STATE.songId) || SONGS[0];
const currentAlbum = () => albumOf(currentSong());

function cover(item, cls = '', mark = null, extra = '') {
  const accent = item.accent || '#7C8CFF';
  const style = `--c1:${item.c1};--c2:${item.c2};${accentVars(accent)}${extra}`;
  const m = String(mark ?? item.mark ?? (item.name || item.title || '').slice(0, 2));
  const len = m.length > 4 ? 4 : m.length;
  return `<div class="cover ${cls}" style="${style}">
    <span class="cover-mark" data-len="${len}">${m}</span>
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

/* 组装一整台手机:外框 + 灵动岛 + 状态栏 + 内容 */
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

function dock(song = SONGS[0], pct = 38) {
  const a = albumOf(song);
  return `<div class="dock" data-go="player">
    ${cover(a, '', song.title.slice(0, 2), 'width:46px;height:46px;border-radius:13px')}
    <div class="grow">
      <div class="line1">${song.title}</div>
      <div class="line2">${song.artist} · ${a.name}</div>
    </div>
    <button class="icon-btn" data-act="toggle-play">${ic('pause', 25)}</button>
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
  const best = SERVER.routes.filter((r) => r.state === 'ok').sort((a, b) => a.ping - b.ping)[0];
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
        <button class="chip" style="height:30px">${ic('refresh', 14)} 重新测速</button>
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
        <div class="field"><label>用户名</label>
          <div class="input">${ic('server', 18, 'quiet')}<input value="hhy"></div>
        </div>
        <div class="field"><label>密码</label>
          <div class="input"><input type="password" value="password"></div>
          <div class="hint">凭据只存在本机,登录时用密码派生令牌,不保存明文。</div>
        </div>
      </div>

      <div class="section">
        <h2>线路</h2>
        <span class="count">一个账号,多个地址</span>
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
          播放时自动走延迟最低的可用线路;线路中断会自动换到下一条并接着放。也可以手动锁定某一条。
        </div>
        <div style="display:flex;align-items:center;gap:var(--s2);margin-top:var(--s4)">
          <button class="chip" style="height:32px">${ic('refresh', 14)} 立即测速</button>
          <span class="spacer" style="flex:1"></span>
          <span style="font-size:11px;color:var(--ok)">3 条线路中 2 条可用</span>
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
    ['ND', 'Navidrome', '开源音乐服务器,Subsonic 兼容', '#7C8CFF', true],
    ['SU', 'Subsonic / OpenSubsonic', 'Airsonic、Gonic、Ampache 等', '#4FD8C4', false],
    ['FN', '飞牛音乐', 'fnOS 自带的音乐服务', '#FFA45C', false],
  ];
  return `<div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="h1">添加服务器</span>
    </div>
    <div class="scroll" style="padding:0 var(--s5)">
      <div style="font-size:13px;color:var(--fg-2);line-height:1.7;padding:var(--s2) 0 var(--s5)">
        选择接入类型。不确定的话选 Subsonic —— 大多数兼容服务器都能用它接进来。
      </div>
      ${kinds.map(([m, name, desc, col, on]) => `
        <div class="card" data-go="server-config" style="margin-bottom:var(--s3);padding:var(--s4);
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
        </div>`).join('')}
      <div style="padding:var(--s5) 0 var(--s6)">
        <button class="btn primary" data-go="server-config">下一步</button>
      </div>
      <div class="note">飞牛音乐的接入基于社区逆向的接口,官方没有公开 API,可用性随系统版本变化。</div>
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
  let body = '';

  if (tab === 'albums') {
    body = `<div class="hero-card" style="${accentVars(curA.accent)}">
        ${cover(curA, '', curA.mark, 'width:92px;height:92px;border-radius:20px')}
        <div class="grow" style="min-width:0">
          <div class="label">继续收听</div>
          <div class="t">${curA.name}</div>
          <div class="a">${curA.artist} · 播到 ${mmss(83)} / ${mmss(cur.dur)}</div>
        </div>
        <button class="go" data-song="${cur.id}">${ic('play', 20)}</button>
      </div>
      <div class="section"><h2>全部专辑</h2><span class="count">${ALBUMS.length} 张</span></div>
      <div class="grid-covers">${ALBUMS.slice(0, 4).map((a) => `
        <div class="album-tile" data-album="${a.id}">
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
    body = `<div class="section"><h2>全部歌曲</h2><span class="count">${SERVER.songs} 首</span><span class="spacer" style="flex:1"></span>
        <button class="chip" style="height:30px">${ic('sort', 14)} 默认</button></div>
      ${SONGS.concat(SONGS).slice(0, 8).map((s, i) => songRow(s, i === 0)).join('')}`;
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
    ${bottom(cur, 38, 'library')}`;
}

function screenAlbum(id) {
  const a = ALBUMS.find((x) => x.id === id) || ALBUMS[0];
  const tracks = SONGS.map((s, i) => `
    <div class="row ${i === 0 ? 'playing' : ''}" data-song="${s.id}">
      <span class="track-no">${i === 0 ? '' : i + 1}</span>
      ${i === 0 ? `<span class="bars" style="width:20px;justify-content:flex-end"><i></i><i></i><i></i></span>` : ''}
      <div class="grow">
        <div class="line1">${s.title}</div>
        <div class="line2">${s.fmt} · ${s.kbps} kbps</div>
      </div>
      <span class="trail">${mmss(s.dur)}</span>
    </div>`).join('');

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
          <div class="artist">${a.artist}</div>
          <div class="meta"><span>${a.year}</span>·<span>${a.count} 首</span>·<span>FLAC 无损</span></div>
        </div>
      </div>
      <div class="action-row">
        <button class="btn primary" data-song="s1">${ic('play', 20)} 播放</button>
        <button class="icon-btn halo" style="width:48px;height:48px">${ic('shuffle', 20)}</button>
        <button class="icon-btn halo" style="width:48px;height:48px">${ic('heart', 20)}</button>
        <button class="icon-btn halo" style="width:48px;height:48px" data-sheet="queue">${ic('queue', 20)}</button>
      </div>
      <div class="divider"></div>
      ${tracks}
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(SONGS[0])}`;
}

function screenArtist(id) {
  const ar = ARTISTS.find((x) => x.id === id) || ARTISTS[0];
  const alb = { c1: ar.c1, c2: ar.c2, accent: ar.accent };
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
        <button class="btn primary" data-song="s1">${ic('play', 20)} 播放热门</button>
        <button class="icon-btn halo" style="width:48px;height:48px">${ic('shuffle', 20)}</button>
        <button class="icon-btn halo" style="width:48px;height:48px">${ic('heart', 20)}</button>
      </div>
      <div class="section"><h2>热门歌曲</h2></div>
      ${SONGS.slice(0, 3).map((s, i) => `
        <div class="row" data-song="${s.id}">
          <span class="track-no">${i + 1}</span>
          <div class="grow"><div class="line1">${s.title}</div><div class="line2">${s.album} · ${s.fmt}</div></div>
          <span class="trail">${mmss(s.dur)}</span>
        </div>`).join('')}
      <div class="section"><h2>专辑</h2><span class="count">${ar.albums} 张</span></div>
      <div class="rail"><div class="rail-track">${ALBUMS.slice(0, 4).map((a) => `
        <div class="rail-item" data-album="${a.id}">
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.year}</div></div>
        </div>`).join('')}</div></div>
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom(SONGS[0])}`;
}

/* ---------------- 播放 ---------------- */

function screenPlayer(overlay = '') {
  const s = currentSong();
  const a = albumOf(s);
  const pct = 38, elapsed = Math.round(s.dur * pct / 100);
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

    <div class="player-hero">${cover(a, 'sq', a.mark)}</div>

    <div class="player-info">
      <div class="top-row">
        <div style="min-width:0">
          <div class="t">${s.title}</div>
          <div class="a" data-album="${a.id}">${s.artist} · ${a.name}</div>
        </div>
        <button class="icon-btn" style="color:${s.fav ? a.accent : 'var(--fg-2)'}" data-act="fav">
          ${ic(s.fav ? 'heartF' : 'heart', 25)}</button>
      </div>
    </div>

    <div class="scrub">
      <div class="track"><i style="width:${pct}%"></i><span class="knob" style="left:${pct}%"></span></div>
      <div class="times"><span>${mmss(elapsed)}</span><span>-${mmss(s.dur - elapsed)}</span></div>
    </div>

    <div class="controls">
      <button class="icon-btn" data-act="shuffle">${ic('shuffle', 23)}</button>
      <button class="icon-btn" data-act="prev">${ic('prev', 27)}</button>
      <button class="play-btn" data-act="toggle-play">${ic('pause', 30)}</button>
      <button class="icon-btn" data-act="next">${ic('next', 27)}</button>
      <button class="icon-btn" data-act="repeat">${ic('repeat', 23)}</button>
    </div>

    <div class="chip-row-b">
      <button class="quality-chip on" data-sheet="quality">${ic('wave', 15)} ${q.name} · ${codec}</button>
      <span class="spacer" style="flex:1"></span>
      <button class="quality-chip" data-go="lyrics">${ic('lyrics', 15)} 歌词</button>
      <button class="quality-chip" data-sheet="queue">${ic('queue', 15)} 队列</button>
    </div>

    <div class="route-line">
      <span class="dot ${route.state}"></span>
      线路 <b>${route.name}</b> · ${route.ping} ms · 自动择优
    </div>
    ${overlay}`;
}

function sheetQuality() {
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>转码质量 <span>原文件 FLAC ${SONGS[0].kbps} kbps</span></h2>
      <div class="sheet-note">档位由服务器实时转码后推送。切到转码档后拖动进度会重新请求音频,可能有短暂停顿。</div>
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
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>播放队列 <span>${SONGS.length} 首 · 还有 ${SONGS.length - 1} 首</span></h2>
      <div class="sheet-body">
        ${SONGS.map((s) => {
          const on = s.id === cur.id;
          const a = albumOf(s);
          return `<div class="row ${on ? 'playing' : ''}" data-song="${s.id}">
            <span style="width:18px;flex:0 0 auto;display:flex;color:var(--accent-safe)">${on ? ic('wave', 16) : ''}</span>
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
          播放时优先走延迟最低的可用线路,当前线路中断会自动换到下一条并接着放。手动锁定后不再自动切换。
        </div>
      </div>
    </div>
  </div>`;
}

/* ---------------- 歌词 ---------------- */

function screenLyrics() {
  const s = currentSong();
  const a = albumOf(s);
  return `${ambient(a)}
    <div class="appbar nav">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:12px;color:var(--fg-2);font-weight:620">${s.title} · ${s.artist}</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>
    <div class="lyrics">
      ${LYRICS.map((l, i) => `<div class="lyric-line ${i === 3 ? 'on' : ''}">${l}</div>`).join('')}
    </div>
    <div class="scrub" style="padding-bottom:var(--s5)">
      <div class="track" style="height:5px"><i style="width:38%"></i></div>
      <div class="times"><span>1:23</span><span>-2:15</span></div>
    </div>
    <div style="display:flex;align-items:center;justify-content:center;gap:var(--s7);
      padding:0 var(--s6) var(--s5);position:relative;z-index:1">
      <button class="icon-btn" data-act="prev" style="width:52px;height:52px">${ic('prev', 26)}</button>
      <button class="play-btn" style="width:64px;height:64px;border-radius:var(--r-full);display:grid;place-items:center;
        color:var(--accent-ink);background:linear-gradient(155deg,color-mix(in srgb,var(--accent) 88%,#fff),var(--accent));
        box-shadow:0 18px 36px -12px color-mix(in srgb,var(--accent) 78%,transparent),inset 0 1px 0 rgba(255,255,255,.45)"
        data-act="toggle-play">${ic('pause', 27)}</button>
      <button class="icon-btn" data-act="next" style="width:52px;height:52px">${ic('next', 26)}</button>
    </div>`;
}

/* ---------------- 搜索 ---------------- */

function screenSearch() {
  return `<div class="appbar">
      <div><div class="h1">搜索</div></div>
    </div>
    <div class="searchfield">
      ${ic('search', 19)}
      <input placeholder="歌曲、专辑、艺人" value="程响">
      <button class="clr">${ic('x', 16)}</button>
    </div>
    <div class="chip-row">
      <span class="chip" aria-selected="true">全部</span>
      <span class="chip">歌曲</span><span class="chip">专辑</span><span class="chip">艺人</span><span class="chip">歌单</span>
    </div>
    <div class="scroll">
      <div class="section" style="padding-top:0"><h2>最匹配</h2><span class="count">6 条结果</span></div>
      ${songRow(SONGS[0])}
      ${songRow(SONGS[1])}
      <div class="section"><h2>专辑</h2></div>
      <div class="rail" style="padding-top:0"><div class="rail-track">${ALBUMS.slice(0, 3).map((a) => `
        <div class="rail-item" data-album="${a.id}">
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.artist}</div></div>
        </div>`).join('')}</div></div>
      <div class="section"><h2>艺人</h2></div>
      ${ARTISTS.slice(0, 2).map((ar) => `
        <div class="row" data-artist="${ar.id}">
          ${avatar(ar)}
          <div class="grow"><div class="line1">${ar.name}</div><div class="line2">${ar.albums} 张专辑</div></div>
          ${ic('chevron', 18)}
        </div>`).join('')}
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom()}`;
}

/* ---------------- 设置 ---------------- */

function screenSettings() {
  const rows = [
    [['wave', '默认转码质量', '移动网络下生效'], '均衡'],
    [['route', '线路自动择优', '按延迟选择最快可用地址'], 'on'],
    [['bell', '播放时后台运行', '通知栏与锁屏可控制'], 'on'],
    [['download', '仅 Wi-Fi 下载', '避免消耗移动流量'], 'off'],
  ];
  const themeRow = `
      <div class="section" style="padding-top:var(--s2)"><h2>外观</h2></div>
      <div class="card" style="margin:0 var(--s5)">
        <div class="row" style="cursor:default">
          <span class="set-icon">${ic('theme', 18)}</span>
          <div class="grow"><div class="line1">主题</div><div class="line2">深色 / 浅色,跟随当前封面取色</div></div>
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
        ${rows.map(([[icon, t, d], v], i) => `
          ${i ? '<div class="divider"></div>' : ''}
          <div class="row" ${i === 0 ? 'data-sheet="quality"' : ''}>
            <span class="set-icon">${ic(icon, 18)}</span>
            <div class="grow"><div class="line1">${t}</div><div class="line2">${d}</div></div>
            ${v === 'on'  ? `<span class="tick on">${ic('check', 13)}</span>`
            : v === 'off' ? `<span class="tick">${ic('check', 13)}</span>`
            : `<span class="trail" style="color:var(--fg-2)">${v}</span>`}
            ${i === 0 ? ic('chevron', 17) : ''}
          </div>`).join('')}
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
          <div class="grow"><div class="line1">凭据仅存本机</div><div class="line2">不保存明文密码,不上传任何数据</div></div>
        </div>
      </div>
      <div style="height:var(--s5)"></div>
    </div>
    ${bottom()}`;
}

/* ---------------- 视图表 ---------------- */

const sheets = { quality: sheetQuality, queue: sheetQueue, routes: sheetRoutes };

const VIEWS = {
  servers:        () => shell(screenServers()),
  'server-config':() => shell(screenServerConfig()),
  'add-server':   () => shell(screenAddServer()),
  library:        (p) => shell(screenLibrary((p && p.lib) || 'albums')),
  album:          (p) => shell(screenAlbum((p && p.album) || STATE.albumId), { home: true }),
  artist:         (p) => shell(screenArtist((p && p.artist) || STATE.artistId), { home: true }),
  player:         () => shell(screenPlayer(STATE.overlay ? sheets[STATE.overlay]() : ''), { home: true }),
  lyrics:         () => shell(screenLyrics(), { home: true }),
  search:         () => shell(screenSearch()),
  settings:       () => shell(screenSettings()),
};

/* ============================================================
   设计板
   ============================================================ */

const BOARD = [
  ['服务器与线路',    '线路状态 / 自动择优',  () => shell(screenServers())],
  ['服务器设置',      '一个账号,多个地址',    () => shell(screenServerConfig())],
  ['添加服务器',      '选择接入类型',         () => shell(screenAddServer())],
  ['音乐库 · 专辑',   '继续收听 + 封面网格',  () => shell(screenLibrary('albums'))],
  ['音乐库 · 艺人',   '方块头像 + 常听',      () => shell(screenLibrary('artists'))],
  ['音乐库 · 歌曲',   '全部歌曲',             () => shell(screenLibrary('songs'))],
  ['音乐库 · 歌单',   '我的歌单',             () => shell(screenLibrary('playlists'))],
  ['专辑详情',        '氛围背景 + 曲目',      () => shell(screenAlbum('a1'), { home: true })],
  ['艺人详情',        '热门 + 专辑',          () => shell(screenArtist('ar1'), { home: true })],
  ['播放页',          '封面主导 + 封面取色',  () => shell(screenPlayer(), { home: true })],
  ['转码质量',        '四档位,含说明',       () => shell(screenPlayer(sheetQuality()), { home: true })],
  ['播放队列',        '队列管理',             () => shell(screenPlayer(sheetQueue()), { home: true })],
  ['线路切换',        '播放中改线路',         () => shell(screenPlayer(sheetRoutes()), { home: true })],
  ['歌词',            '逐句高亮',             () => shell(screenLyrics(), { home: true })],
  ['搜索',            '歌曲 / 专辑 / 艺人',   () => shell(screenSearch())],
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
  const prev = STATE.theme;
  const dark = (STATE.theme = 'dark', boardFrames());
  const light = (STATE.theme = 'light', boardFrames());
  STATE.theme = prev;
  root.innerHTML = `
    <div class="board-wrap">
      <div class="board-head">
        <h1>Nordic — 音乐播放器原型</h1>
        <p>手机竖屏,16 屏,<b>深色 / 浅色两套</b>。强调色<b>从当前封面里提取</b> —— 每张专辑驱动界面的光晕、进度条与选中态,
          所以每张专辑有自己的气质。深色靠发光撑层次,浅色把发光几乎关掉、改用留白与描边;两套共用同一份结构,差异全部落在 token 上。
          这是并排铺开的设计板;<b>要点击走完整条链路,请开 <a href="player.html">player.html</a></b>,那边的设置里可以实时切换主题。</p>
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

  const render = () => {
    const view = VIEWS[STATE.view];
    if (view) slot().innerHTML = view(STATE.params);
  };

  const go = (name, params) => {
    if (name !== STATE.view) STATE.history.push({ view: STATE.view, params: STATE.params });
    STATE.view = name;
    STATE.params = params || {};
    STATE.overlay = '';
    render();
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
    render();
  };

  root.innerHTML = `
    <div class="stage">
      <aside class="stage-side">
        <h2>可点击原型</h2>
        <ol>
          <li>服务器页有 3 条线路,已自动选中延迟最低的局域网直连</li>
          <li>点「音乐库」切换 专辑 / 艺人 / 歌曲 / 歌单</li>
          <li>点专辑或艺人进详情页;点歌曲进播放页</li>
          <li>点「均衡 · MP3」胶囊切换转码质量</li>
          <li>播放页里点「队列」「歌词」看对应界面</li>
        </ol>
        <div style="border-top:1px solid var(--line);padding-top:16px">
          <h2 style="margin-bottom:8px">主题</h2>
          <div class="segmented" style="margin-bottom:16px">
            ${THEMES.map((t) => `<button data-set-theme="${t.id}" aria-selected="${STATE.theme === t.id}">${t.name}</button>`).join('')}
          </div>
        </div>
        <div style="border-top:1px solid var(--line);padding-top:16px">
          <h2 style="margin-bottom:6px">随封面取色</h2>
          每张专辑给界面一套自己的强调色:
          <div class="swatches" id="sw"></div>
          <div style="margin-top:14px;font-size:11px;color:var(--fg-3)">
            返回:左上角按钮,或键盘 <span class="kbd">←</span> / <span class="kbd">Esc</span>
          </div>
        </div>
      </aside>
      <div id="phone-slot"></div>
    </div>`;

  root.querySelector('#sw').innerHTML = ALBUMS.map((a) =>
    `<span class="sw" title="${a.name}" style="background:linear-gradient(148deg,${a.c1},${a.accent})"></span>`).join('');

  /* 监听挂在舞台根上而不是 #phone-slot 上 —— 侧栏是 #phone-slot 的兄弟节点,
     挂在内层会让侧栏里的主题按钮点不动。 */
  root.addEventListener('click', (e) => {
    /* 注意:委托选择器里不能出现 [data-theme] —— applyTheme() 把 data-theme 写在
       <body> 上,而 body 是所有点击的祖先。closest() 在没命中更近的 [data-*] 元素时
       会一路匹配到 body,于是「点遮罩关闭弹层」这条分支永远走不到(点遮罩会变成
       重新应用一次主题)。所以主题按钮改用独立属性 data-set-theme。 */
    const t = e.target.closest('[data-back],[data-tab],[data-go],[data-lib],[data-song],[data-album],[data-artist],[data-route],[data-quality],[data-set-theme],[data-sheet],[data-act]');
    if (t) {
      const d = t.dataset;
      if (d.back !== undefined) return back();
      if (d.tab) { STATE.history = []; return go(d.tab); }
      if (d.lib) { STATE.params = { lib: d.lib }; return render(); }
      if (d.song) { STATE.songId = d.song; return go('player'); }
      if (d.album) { STATE.albumId = d.album; return go('album', { album: d.album }); }
      if (d.artist) { STATE.artistId = d.artist; return go('artist', { artist: d.artist }); }
      if (d.route) { STATE.routeId = d.route; return render(); }
      if (d.setTheme) { applyTheme(d.setTheme); return render(); }
      if (d.quality) { STATE.quality = d.quality; STATE.overlay = ''; return render(); }
      if (d.sheet) { STATE.overlay = STATE.overlay === d.sheet ? '' : d.sheet; return render(); }
      if (d.go) return go(d.go);
      if (d.act === 'fav') {
        const s = SONGS.find((x) => x.id === STATE.songId);
        if (s) s.fav = !s.fav;
        return render();
      }
      return; // 其余播放控制为示意,不改变状态
    }
    if (e.target.classList.contains('sheet-scrim')) {
      STATE.overlay = '';
      render();
    }
  });

  document.addEventListener('keydown', (e) => {
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