/* ============================================================
   Nordic — 原型数据、图标与屏幕
   ------------------------------------------------------------
   index.html 用它铺「设计板」(所有屏并排);
   player.html 用它跑「交互流」(真机尺寸,可点击走完整条链路)。
   ============================================================ */

/* ---------------- 图标 ---------------- */

const ICONS = {
  back:   '<path d="M15 18l-6-6 6-6"/>',
  more:   '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
  play:   '<path d="M8 5.5v13l11-6.5z" fill="currentColor" stroke="none"/>',
  pause:  '<rect x="7" y="5.5" width="3.6" height="13" rx="1.3" fill="currentColor" stroke="none"/><rect x="13.4" y="5.5" width="3.6" height="13" rx="1.3" fill="currentColor" stroke="none"/>',
  next:   '<path d="M6 5.8l9 6.2-9 6.2z" fill="currentColor" stroke="none"/><rect x="16" y="5.8" width="2.4" height="12.4" rx="1.2" fill="currentColor" stroke="none"/>',
  prev:   '<path d="M18 5.8l-9 6.2 9 6.2z" fill="currentColor" stroke="none"/><rect x="5.6" y="5.8" width="2.4" height="12.4" rx="1.2" fill="currentColor" stroke="none"/>',
  shuffle:'<path d="M4 7h3.2l9.6 10H20"/><path d="M4 17h3.2l9.6-10H20"/><path d="M17.4 4.4L20 7l-2.6 2.6M17.4 14.4L20 17l-2.6 2.6"/>',
  repeat: '<path d="M7 7h10a3 3 0 0 1 3 3v1"/><path d="M17 17H7a3 3 0 0 1-3-3v-1"/><path d="M4.6 11.4L7 13.8l2.4-2.4M16.6 9.6L19 12l2.4-2.4"/>',
  heart:  '<path d="M12 19.6s-6.8-4.5-6.8-9.3A4.2 4.2 0 0 1 12 7.4a4.2 4.2 0 0 1 6.8 2.9c0 4.8-6.8 9.3-6.8 9.3z"/>',
  heartF: '<path d="M12 19.6s-6.8-4.5-6.8-9.3A4.2 4.2 0 0 1 12 7.4a4.2 4.2 0 0 1 6.8 2.9c0 4.8-6.8 9.3-6.8 9.3z" fill="currentColor" stroke="none"/>',
  search: '<circle cx="11" cy="11" r="6.2"/><path d="M15.6 15.6L20 20"/>',
  queue:  '<path d="M4 7h11M4 12h11M4 17h7"/><path d="M17.5 11.4v6.9a2.1 2.1 0 1 1-2.1-2.1"/>',
  lyrics: '<path d="M9.6 7.5H5.4v5.2h4.2v-2.1c0-1.1.5-1.8 1.7-2.3M19 7.5h-4.2v5.2H19v-2.1c0-1.1.5-1.8 1.7-2.3"/>',
  server: '<rect x="4" y="4.4" width="16" height="6.2" rx="2.1"/><rect x="4" y="13.4" width="16" height="6.2" rx="2.1"/><path d="M7.6 7.5h.01M7.6 16.5h.01"/>',
  gear:   '<circle cx="12" cy="12" r="3"/><path d="M12 3.6v2.1M12 18.3v2.1M4.9 7.8l1.8 1M17.3 15.2l1.8 1M4.9 16.2l1.8-1M17.3 8.8l1.8-1"/>',
  plus:   '<path d="M12 5v14M5 12h14"/>',
  check:  '<path d="M5 12.6l4.6 4.4L19 7.4"/>',
  wifi:   '<path d="M4 9.4a12 12 0 0 1 16 0M7.2 12.9a7.6 7.6 0 0 1 9.6 0M10.2 16.3a3.3 3.3 0 0 1 3.6 0"/><circle cx="12" cy="19.4" r="1.05" fill="currentColor" stroke="none"/>',
  cell:   '<rect x="3" y="14" width="3" height="6" rx="1"/><rect x="8" y="10.5" width="3" height="9.5" rx="1"/><rect x="13" y="7" width="3" height="13" rx="1"/><rect x="18" y="4" width="3" height="16" rx="1"/>',
  battery:'<rect x="3" y="8" width="16.5" height="8" rx="2.4"/><rect x="5" y="10" width="11.5" height="4" rx="1.2" fill="currentColor" stroke="none"/><path d="M21.4 11v2"/>',
  gauge:  '<path d="M4 17.5a8 8 0 1 1 16 0"/><path d="M12 17.5l4.4-5.4"/>',
  route:  '<circle cx="6" cy="6.5" r="2.3"/><circle cx="18" cy="17.5" r="2.3"/><path d="M8.3 6.5h5.2a3 3 0 0 1 0 6H9a3 3 0 0 0 0 6h6.7"/>',
  chevron:'<path d="M9.5 6l6 6-6 6"/>',
  x:      '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  refresh:'<path d="M19.6 11.4a7.8 7.8 0 1 0-2.1 5.7"/><path d="M19.8 5.6v5.8h-5.8"/>',
  sort:   '<path d="M4 7h9M4 12h6M4 17h4"/><path d="M17 6.5v11M17 17.5l3-3M17 17.5l-3-3"/>',
  download:'<path d="M12 4v9.6"/><path d="M8.2 10.6L12 14.4l3.8-3.8"/><path d="M5 19.2h14"/>',
  disc:   '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.3"/>',
  wave:   '<path d="M4 12h2.2M9 6.5v11M14 9v6M19.5 12H22"/>',
  book:   '<path d="M4 5.5A2 2 0 0 1 6 3.5h13v15H6a2 2 0 0 0-2 2z"/><path d="M4 18.5V5.5"/>',
};

function ic(name, size = 22, cls = '') {
  return `<svg class="ic ${cls}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
}

/* ---------------- 数据 ---------------- */

const SERVER = {
  name: '客厅 Navidrome',
  kind: 'Navidrome',
  user: 'hhy',
  routes: [
    { id: 'lan',  name: '局域网直连', url: 'http://192.168.10.4:4533',  ping: 12,   state: 'ok',  tag: '内网' },
    { id: 'ddns', name: '外网域名',   url: 'https://music.example.com', ping: 86,   state: 'ok',  tag: '公网' },
    { id: 'v6',   name: 'IPv6 直连',  url: 'http://[240e:390:…]:4533',  ping: null, state: 'bad', tag: '公网' },
  ],
};

const ALBUMS = [
  { id: 'a1', name: '可能',                 artist: '程响',         year: 2022, count: 8,  c1: '#3A2A46', c2: '#151020', accent: '#B98BFF', mark: '可能' },
  { id: 'a2', name: 'Ultraviolet',          artist: '3LAU',         year: 2018, count: 1,  c1: '#1E2A5E', c2: '#0C1024', accent: '#6E8BFF', mark: 'UV' },
  { id: 'a3', name: '秋色',                 artist: '拾光乐队',      year: 2021, count: 11, c1: '#5A3B22', c2: '#1E1409', accent: '#E0A45C', mark: '秋' },
  { id: 'a4', name: 'Islands',              artist: 'King Crimson', year: 1971, count: 6,  c1: '#123832', c2: '#08171A', accent: '#4FD8C4', mark: 'Is' },
  { id: 'a5', name: '山丘',                 artist: '李宗盛',        year: 2013, count: 5,  c1: '#4A2E2A', c2: '#180F0E', accent: '#E0796A', mark: '山丘' },
  { id: 'a6', name: 'Random Access Memories', artist: 'Daft Punk',   year: 2013, count: 13, c1: '#3B3B3B', c2: '#111111', accent: '#D9D9D9', mark: 'RAM' },
];

const SONGS = [
  { id: 's1', title: '可能',     artist: '程响', album: '可能', albumId: 'a1', dur: 218, fmt: 'FLAC', kbps: 780, fav: true  },
  { id: 's2', title: '人间烟火', artist: '程响', album: '可能', albumId: 'a1', dur: 245, fmt: 'FLAC', kbps: 812, fav: false },
  { id: 's3', title: '四季予你', artist: '程响', album: '可能', albumId: 'a1', dur: 232, fmt: 'FLAC', kbps: 764, fav: false },
  { id: 's4', title: '等你归来', artist: '程响', album: '可能', albumId: 'a1', dur: 258, fmt: 'FLAC', kbps: 798, fav: true  },
  { id: 's5', title: '时光洪流', artist: '程响', album: '可能', albumId: 'a1', dur: 224, fmt: 'FLAC', kbps: 770, fav: false },
];

const ARTISTS = [
  { id: 'ar1', name: '程响',         albums: 6,  c1: '#3A2A46', c2: '#151020' },
  { id: 'ar2', name: '陈奕迅',       albums: 24, c1: '#22304A', c2: '#0D1220' },
  { id: 'ar3', name: '李宗盛',       albums: 12, c1: '#4A2E2A', c2: '#180F0E' },
  { id: 'ar4', name: 'King Crimson', albums: 9,  c1: '#123832', c2: '#08171A' },
  { id: 'ar5', name: '3LAU',         albums: 3,  c1: '#1E2A5E', c2: '#0C1024' },
  { id: 'ar6', name: '柳爽',         albums: 4,  c1: '#2E2438', c2: '#120E1A' },
];

const PLAYLISTS = [
  { id: 'p1', name: '深夜通勤',     count: 32, desc: '低速、情绪化、适合夜色', c1: '#1B2440', c2: '#0A0F1C' },
  { id: 'p2', name: '工作专注',     count: 58, desc: '器乐为主,无人声干扰',   c1: '#14342E', c2: '#08170F' },
  { id: 'p3', name: '华语民谣精选', count: 41, desc: '长期收藏,持续更新',     c1: '#4A2E2A', c2: '#180F0E' },
  { id: 'p4', name: '电子脉冲',     count: 27, desc: '高能量,适合运动',       c1: '#1E2A5E', c2: '#0C1024' },
];

/* 歌词为中性占位文字,不使用任何真实歌词 */
const LYRICS = [
  '夜色铺开得像一条河', '我数着路灯慢慢走过',
  '风把声音吹得很轻', '有些话就不必再说',
  '远处的窗口亮着灯火', '每扇门后都有自己的歌',
  '我把耳机调得再大一点', '让世界安静地退后',
  '这条路我走过很多次', '每次都想停下又不肯',
];

const QUALITIES = [
  { id: 'original', name: '原音直出', desc: '不转码,按原始文件播放。仅建议在局域网使用。', tag: '无损' },
  { id: 'high',     name: '高质量',   desc: '转码为 320 kbps。音质接近原始,流量约减半。' },
  { id: 'medium',   name: '均衡',     desc: '转码为 192 kbps。移动网络下推荐,拖动进度更快。' },
  { id: 'low',      name: '省流',     desc: '转码为 96 kbps。弱网或流量紧张时使用。' },
];

const STATE = {
  quality: 'medium',
  routeId: 'lan',
  view: 'servers',
  albumId: 'a1',
  songId: 's1',
  params: {},
  overlay: '',
  history: [],
};

/* ---------------- 小工具 ---------------- */

const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

function cover(item, cls = '', mark = null, extra = '') {
  const style = `--c1:${item.c1};--c2:${item.c2};--accent:${item.accent || '#6E8BFF'};${extra}`;
  const m = mark ?? item.mark ?? (item.name || item.title || '').slice(0, 2);
  return `<div class="cover ${cls}" style="${style}"><span class="cover-mark">${m}</span></div>`;
}

function statusbar() {
  return `<div class="statusbar">
    <span>22:41</span>
    <span class="sb-right">${ic('cell', 15)}${ic('wifi', 15)}${ic('battery', 22)}</span>
  </div>`;
}

function shell(inner, accent) {
  return `<div class="phone" ${accent ? `style="--accent:${accent}"` : ''}>${statusbar()}${inner}</div>`;
}

function tabbar(active) {
  const tabs = [['servers', 'server', '服务器'], ['library', 'book', '音乐库'], ['search', 'search', '搜索'], ['settings', 'gear', '设置']];
  return `<nav class="tabbar">${tabs.map(([id, icon, label]) =>
    `<button data-tab="${id}" aria-selected="${active === id}">${ic(icon, 21)}<span>${label}</span></button>`
  ).join('')}</nav>`;
}

function dock(song = SONGS[0], pct = 38) {
  const a = ALBUMS.find((x) => x.id === song.albumId) || ALBUMS[0];
  return `<div class="dock" data-go="player">
    ${cover(a, '', song.title.slice(0, 2), 'width:42px;height:42px;border-radius:11px')}
    <div class="grow">
      <div class="line1">${song.title}</div>
      <div class="line2">${song.artist}</div>
    </div>
    <button class="icon-btn" data-act="toggle-play">${ic('pause', 24)}</button>
    <button class="icon-btn" data-act="next">${ic('next', 22)}</button>
    <div class="dock-progress"><i style="width:${pct}%"></i></div>
  </div>`;
}

/* ---------------- 服务器与线路 ---------------- */

function routeRows(routes, withCheck) {
  return routes.map((r) => {
    const sel = r.id === STATE.routeId;
    const ping = r.state === 'bad'
      ? `<span class="ping" style="color:var(--bad)">不可用</span>`
      : `<span class="ping">${r.ping} ms</span>`;
    return `<div class="route ${sel ? 'selected' : ''}" data-route="${r.id}" ${withCheck ? `role="radio" aria-selected="${sel}"` : ''}>
      <span class="dot ${r.state}"></span>
      <div class="grow">
        <div class="rname">${r.name}<span class="tag">${r.tag}</span></div>
        <div class="rurl">${r.url}</div>
      </div>
      ${ping}
      ${withCheck ? `<span class="tick ${sel ? 'on' : ''}">${ic('check', 13)}</span>` : ''}
    </div>`;
  }).join('');
}

function screenServers() {
  const best = SERVER.routes.filter((r) => r.state === 'ok').sort((a, b) => a.ping - b.ping)[0];
  return `<div class="screen">
    <div class="appbar">
      <span class="title">服务器</span><span class="spacer"></span>
      <button class="icon-btn quiet" data-go="settings">${ic('gear', 21)}</button>
    </div>
    <div class="scroll">
      <div class="server-card">
        <div class="badge">ND</div>
        <div class="grow">
          <div style="font-size:15px;font-weight:640">${SERVER.name}</div>
          <div class="st"><span class="dot ok"></span>${SERVER.kind} · ${SERVER.user} · 已选「${best.name}」${best.ping} ms</div>
        </div>
        <button class="icon-btn quiet" data-go="server-config">${ic('more', 20)}</button>
      </div>

      <div class="group-label">线路 · 同一音乐库多地址</div>
      <div class="card" style="margin:0 var(--s-5)">${routeRows(SERVER.routes, true)}</div>
      <div style="padding:var(--s-4) var(--s-5) 0">
        <button class="text-btn ghost" data-go="server-config"
          style="width:100%;justify-content:center;height:44px;border:1px dashed var(--hairline-ink);border-radius:13px">
          ${ic('plus', 18)} 添加线路
        </button>
      </div>

      <div class="group-label">其他服务器</div>
      <div class="card" style="margin:0 var(--s-5)">
        <div class="row" data-go="library">
          <div class="badge" style="background:var(--surface-3);color:var(--ink)">飞牛</div>
          <div class="grow"><div class="line1">飞牛音乐</div><div class="line2">192.168.10.9 · 未连接</div></div>
          ${ic('chevron', 18)}
        </div>
      </div>

      <div style="padding:var(--s-5) var(--s-5) var(--s-6)">
        <button class="btn-primary" data-go="add-server">${ic('plus', 20)} 添加服务器</button>
      </div>
    </div>
    ${dock()}
    ${tabbar('servers')}
  </div>`;
}

function screenServerConfig() {
  return `<div class="screen">
    <div class="appbar">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="title" style="font-size:17px">服务器设置</span><span class="spacer"></span>
      <button class="text-btn solid" style="height:32px">保存</button>
    </div>
    <div class="scroll">
      <div style="padding:var(--s-2) var(--s-5);display:flex;flex-direction:column;gap:var(--s-4)">
        <div class="field"><label>服务器类型</label>
          <div class="segmented"><button aria-selected="true">Navidrome</button><button>Subsonic</button><button>飞牛音乐</button></div>
        </div>
        <div class="field"><label>名称</label><div class="input"><input value="客厅 Navidrome"></div></div>
        <div class="field"><label>用户名</label><div class="input"><input value="hhy"></div></div>
        <div class="field"><label>密码</label><div class="input"><input type="password" value="password"></div>
          <div class="hint">凭据仅存本机,登录时以密码派生令牌,不落明文。</div></div>
      </div>

      <div class="group-label">线路 · 一个账号,多个地址</div>
      <div class="card" style="margin:0 var(--s-5)">${routeRows(SERVER.routes, false)}</div>
      <div style="padding:var(--s-3) var(--s-5) 0">
        <button class="text-btn ghost"
          style="width:100%;justify-content:center;height:44px;border:1px dashed var(--hairline-ink);border-radius:13px">
          ${ic('plus', 17)} 添加线路地址
        </button>
      </div>

      <div style="padding:var(--s-6) var(--s-5) 0">
        <div class="card" style="padding:var(--s-4)">
          <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
            ${ic('gauge', 19, 'quiet')}<span style="font-weight:640;font-size:14px">线路择优</span>
            <span class="grow"></span><span style="font-size:11px;color:var(--ink-tertiary)">上次 2 分钟前</span>
          </div>
          <div style="font-size:13px;color:var(--ink-secondary);line-height:1.6">
            播放时自动选择延迟最低的可用线路;线路中断会自动切换并续播。也可手动锁定某条线路。
          </div>
          <div style="display:flex;align-items:center;margin-top:12px">
            <button class="text-btn ghost" style="padding-left:0">${ic('refresh', 17)} 重新测速</button>
            <span class="grow"></span>
            <span style="font-size:11px;color:var(--ok)">已启用自动择优</span>
          </div>
        </div>
      </div>

      <div style="padding:var(--s-5) var(--s-5) var(--s-6)">
        <button class="text-btn ghost" style="color:var(--bad);padding-left:4px">移除该服务器</button>
      </div>
    </div>
  </div>`;
}

function screenAddServer() {
  const kinds = [
    ['ND', 'Navidrome', '开源音乐服务器,Subsonic 兼容', true],
    ['SU', 'Subsonic / OpenSubsonic', 'Airsonic、Gonic、Ampache 等', false],
    ['FN', '飞牛音乐', 'fnOS 自带音乐服务', false],
  ];
  return `<div class="screen">
    <div class="appbar">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="title" style="font-size:17px">添加服务器</span>
    </div>
    <div class="scroll" style="padding:0 var(--s-5)">
      <div style="font-size:13px;color:var(--ink-secondary);line-height:1.6;padding:0 0 var(--s-5)">
        选择服务器类型。不确定的话选 Subsonic —— 大多数兼容服务器都能用它接入。
      </div>
      ${kinds.map(([m, name, desc, on]) => `
        <div class="card" style="margin-bottom:var(--s-2);background:${on ? 'color-mix(in srgb, var(--accent) 7%, transparent)' : 'var(--surface-1)'};border-color:${on ? 'color-mix(in srgb, var(--accent) 46%, transparent)' : 'var(--hairline)'}">
          <div class="row" style="height:auto;padding:var(--s-4)">
            <div class="badge" style="${on ? 'background:var(--accent);color:var(--accent-ink)' : 'background:var(--surface-3);color:var(--ink)'}">${m}</div>
            <div class="grow"><div class="line1">${name}</div><div class="line2">${desc}</div></div>
            ${on ? `<span class="tick on">${ic('check', 13)}</span>` : ''}
          </div>
        </div>`).join('')}
      <div style="padding:var(--s-5) 0 var(--s-6)">
        <button class="btn-primary" data-go="server-config">下一步</button>
      </div>
    </div>
  </div>`;
}

/* ---------------- 音乐库 ---------------- */

function songRow(s, playing = false) {
  const a = ALBUMS.find((x) => x.id === s.albumId) || ALBUMS[0];
  return `<div class="row ${playing ? 'playing' : ''}" data-song="${s.id}">
    ${cover(a, '', s.title.slice(0, 2), 'width:50px;height:50px;border-radius:11px')}
    <div class="grow">
      <div class="line1">${s.title}</div>
      <div class="line2">${s.artist} · ${a.name} · ${s.fmt}</div>
    </div>
    ${playing ? `<span class="bars"><i></i><i></i><i></i></span>` : ''}
    <span class="trail">${mmss(s.dur)}</span>
  </div>`;
}

function screenLibrary(tab = 'albums') {
  const segs = [['albums', '专辑'], ['artists', '艺人'], ['songs', '歌曲'], ['playlists', '歌单']];
  let body = '';

  if (tab === 'albums') {
    body = `<div class="grid-covers">${ALBUMS.slice(0, 4).map((a) => `
        <div class="album-tile" data-album="${a.id}">
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.artist} · ${a.year}</div></div>
        </div>`).join('')}</div>
      <div class="rail">
        <div class="rail-title"><h3>最近添加</h3><span>扫描于 10 月 12 日</span></div>
        <div class="rail-track">${ALBUMS.slice(2).map((a) => `
          <div class="rail-item" data-album="${a.id}">
            ${cover(a, 'sq', a.mark)}
            <div><div class="name">${a.name}</div><div class="meta">${a.artist}</div></div>
          </div>`).join('')}</div>
      </div>`;
  } else if (tab === 'artists') {
    body = ARTISTS.map((ar) => `
      <div class="row" style="height:66px" data-album="a1">
        <div class="avatar" style="background:linear-gradient(142deg,${ar.c1},${ar.c2})">${ar.name.slice(0, 2)}</div>
        <div class="grow"><div class="line1">${ar.name}</div><div class="line2">${ar.albums} 张专辑</div></div>
        ${ic('chevron', 18)}
      </div>`).join('');
  } else if (tab === 'songs') {
    body = SONGS.concat(SONGS).slice(0, 8).map((s, i) => songRow(s, i === 0)).join('');
  } else {
    body = PLAYLISTS.map((p) => `
      <div class="row" style="height:66px">
        <div class="cover" style="--c1:${p.c1};--c2:${p.c2};width:50px;height:50px;border-radius:12px"></div>
        <div class="grow"><div class="line1">${p.name}</div><div class="line2">${p.count} 首 · ${p.desc}</div></div>
        ${ic('chevron', 18)}
      </div>`).join('');
  }

  return `<div class="screen">
    <div class="appbar">
      <span class="title">音乐库</span><span class="spacer"></span>
      <button class="icon-btn quiet" data-go="search">${ic('search', 21)}</button>
      <button class="icon-btn quiet">${ic('sort', 21)}</button>
    </div>
    <div style="padding:var(--s-2) var(--s-5) var(--s-3)">
      <div class="segmented">${segs.map(([id, label]) =>
        `<button data-lib="${id}" aria-selected="${tab === id}">${label}</button>`).join('')}</div>
    </div>
    <div class="scroll">${body}<div style="height:var(--s-6)"></div></div>
    ${dock()}
    ${tabbar('library')}
  </div>`;
}

function screenAlbum(id) {
  const a = ALBUMS.find((x) => x.id === id) || ALBUMS[0];
  return `<div class="screen">
    <div class="scroll">
      <div style="position:relative;padding:var(--s-2) 0 var(--s-5)">
        <div style="position:absolute;inset:-120px 0 40% 0;background:radial-gradient(58% 60% at 50% 30%,color-mix(in srgb, ${a.accent} 26%, transparent),transparent 70%);filter:blur(30px);pointer-events:none"></div>
        <div class="appbar" style="position:relative">
          <button class="icon-btn" data-back>${ic('back', 22)}</button>
          <span class="spacer"></span>
          <button class="icon-btn quiet">${ic('download', 21)}</button>
          <button class="icon-btn quiet">${ic('more', 20)}</button>
        </div>
        <div style="display:flex;gap:var(--s-4);padding:var(--s-2) var(--s-5) var(--s-5);position:relative;align-items:flex-end">
          ${cover(a, 'sq', a.mark, 'width:128px;height:128px;border-radius:18px')}
          <div style="min-width:0">
            <div style="font-size:26px;font-weight:700;letter-spacing:-0.025em;line-height:1.15">${a.name}</div>
            <div style="font-size:14px;color:var(--ink-secondary);margin-top:6px">${a.artist}</div>
            <div style="font-size:12px;color:var(--ink-tertiary);margin-top:8px">${a.year} · ${a.count} 首 · FLAC</div>
          </div>
        </div>
        <div style="display:flex;align-items:center;gap:var(--s-2);padding:0 var(--s-5);position:relative">
          <button class="btn-primary" style="height:46px;width:auto;flex:0 0 auto;padding:0 26px" data-song="s1">${ic('play', 20)} 播放</button>
          <button class="icon-btn" style="background:var(--surface-2)">${ic('shuffle', 20)}</button>
          <button class="icon-btn" style="background:var(--surface-2)">${ic('heart', 20)}</button>
          <span class="grow"></span>
          <button class="icon-btn quiet">${ic('queue', 21)}</button>
        </div>
      </div>
      <div>${SONGS.map((s, i) => `
        <div class="row ${i === 0 ? 'playing' : ''}" data-song="${s.id}">
          <span class="trail" style="width:18px;text-align:right">${i + 1}</span>
          <div class="grow"><div class="line1">${s.title}</div><div class="line2">${s.fmt} · ${s.kbps} kbps</div></div>
          ${i === 0 ? `<span class="bars"><i></i><i></i><i></i></span>` : ''}
          <span class="trail">${mmss(s.dur)}</span>
        </div>`).join('')}</div>
      <div style="height:var(--s-6)"></div>
    </div>
    ${dock(SONGS[0])}
  </div>`;
}

/* ---------------- 播放 ---------------- */

function screenPlayer(overlay = '') {
  const s = SONGS.find((x) => x.id === STATE.songId) || SONGS[0];
  const a = ALBUMS.find((x) => x.id === s.albumId) || ALBUMS[0];
  const pct = 38, elapsed = Math.round(s.dur * pct / 100);
  const q = QUALITIES.find((x) => x.id === STATE.quality) || QUALITIES[2];
  const route = SERVER.routes.find((r) => r.id === STATE.routeId) || SERVER.routes[0];
  const codec = STATE.quality === 'original' ? 'FLAC' : 'MP3';

  return `<div class="screen" style="--accent:${a.accent}">
    <div class="appbar">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:11px;color:var(--ink-tertiary);letter-spacing:0.06em;text-transform:uppercase">正在播放</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>

    <div class="player-hero">
      <div class="glow"></div>
      ${cover(a, 'sq', a.mark, 'border-radius:20px')}
    </div>

    <div class="player-info">
      <div class="top-row">
        <div style="min-width:0">
          <div class="t">${s.title}</div>
          <div class="a">${s.artist} · ${a.name}</div>
        </div>
        <button class="icon-btn" style="color:${s.fav ? a.accent : 'var(--ink-secondary)'}" data-act="fav">${ic(s.fav ? 'heartF' : 'heart', 23)}</button>
      </div>
    </div>

    <div class="scrub">
      <div class="track"><i style="width:${pct}%"></i><span class="knob" style="left:${pct}%"></span></div>
      <div class="times"><span>${mmss(elapsed)}</span><span>-${mmss(s.dur - elapsed)}</span></div>
    </div>

    <div class="controls">
      <button class="icon-btn" data-act="shuffle">${ic('shuffle', 23)}</button>
      <button class="icon-btn" data-act="prev">${ic('prev', 26)}</button>
      <button class="play-btn" data-act="toggle-play">${ic('pause', 27)}</button>
      <button class="icon-btn" data-act="next">${ic('next', 26)}</button>
      <button class="icon-btn" data-act="repeat">${ic('repeat', 23)}</button>
    </div>

    <div style="display:flex;align-items:center;gap:var(--s-2);padding:0 var(--s-5) var(--s-4)">
      <button class="quality-chip on" data-sheet="quality">${ic('wave', 15)} ${q.name} · ${codec}</button>
      <span class="grow"></span>
      <button class="quality-chip" data-go="lyrics">${ic('lyrics', 15)} 歌词</button>
      <button class="quality-chip" data-sheet="queue">${ic('queue', 15)} 队列</button>
    </div>

    <div style="display:flex;align-items:center;gap:8px;padding:0 var(--s-5) var(--s-3);font-size:11px;color:var(--ink-tertiary)">
      <span class="dot ok"></span>线路「${route.name}」· ${route.ping} ms · 自动择优
    </div>
  </div>${overlay}`;
}

function sheetQuality() {
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>转码质量</h2>
      <div style="font-size:12px;color:var(--ink-tertiary);padding:0 var(--s-5) var(--s-3);line-height:1.6">
        原始文件为 FLAC ${SONGS[0].kbps} kbps。转码档位由服务器实时转码后推送。
      </div>
      <div class="sheet-body">
        ${QUALITIES.map((q) => `
          <div class="qopt" data-quality="${q.id}" role="radio" aria-selected="${STATE.quality === q.id}">
            <div style="flex:1 1 auto">
              <div class="qname">${q.name}${q.tag ? `<span class="tag">${q.tag}</span>` : ''}</div>
              <div class="qdesc">${q.desc}</div>
            </div>
            <span class="tick ${STATE.quality === q.id ? 'on' : ''}">${ic('check', 13)}</span>
          </div>`).join('')}
      </div>
      <div style="padding:var(--s-2) var(--s-5) 0;font-size:11px;color:var(--ink-tertiary);line-height:1.6">
        切到转码档位后,拖动进度会重新向服务器请求该时间点的音频,可能有短暂停顿。
      </div>
    </div>
  </div>`;
}

function sheetQueue() {
  const cur = SONGS.find((x) => x.id === STATE.songId) || SONGS[0];
  return `<div class="sheet-scrim">
    <div class="sheet">
      <div class="handle"></div>
      <h2>播放队列 <span style="font-size:12px;color:var(--ink-tertiary);font-weight:600">${SONGS.length} 首</span></h2>
      <div class="sheet-body">
        ${SONGS.map((s) => {
          const a = ALBUMS.find((x) => x.id === s.albumId) || ALBUMS[0];
          const on = s.id === cur.id;
          return `<div class="row ${on ? 'playing' : ''}" data-song="${s.id}">
            <span style="width:16px;color:var(--accent);display:flex">${on ? ic('wave', 15) : ''}</span>
            ${cover(a, '', s.title.slice(0, 2), 'width:44px;height:44px;border-radius:10px')}
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
      <h2>线路 <span style="font-size:12px;color:var(--ink-tertiary);font-weight:600">自动择优已开启</span></h2>
      <div class="sheet-body">
        <div class="card" style="margin:0 var(--s-5)">${routeRows(SERVER.routes, true)}</div>
        <div style="padding:var(--s-4) var(--s-5);font-size:11px;color:var(--ink-tertiary);line-height:1.6">
          播放时优先走延迟最低的可用线路。手动锁定后不再自动切换。
        </div>
      </div>
    </div>
  </div>`;
}

/* ---------------- 歌词 ---------------- */

function screenLyrics() {
  const s = SONGS.find((x) => x.id === STATE.songId) || SONGS[0];
  const a = ALBUMS.find((x) => x.id === s.albumId) || ALBUMS[0];
  return `<div class="screen" style="--accent:${a.accent}">
    <div class="appbar">
      <button class="icon-btn" data-back>${ic('back', 22)}</button>
      <span class="spacer"></span>
      <span style="font-size:11px;color:var(--ink-tertiary)">${s.title} · ${s.artist}</span>
      <span class="spacer"></span>
      <button class="icon-btn quiet">${ic('more', 20)}</button>
    </div>
    <div class="lyrics">
      ${LYRICS.map((l, i) => `<div class="lyric-line ${i === 3 ? 'on' : ''}">${l}</div>`).join('')}
    </div>
    <div class="scrub" style="padding-bottom:var(--s-4)">
      <div class="track" style="height:4px"><i style="width:38%"></i></div>
      <div class="times"><span>1:23</span><span>-2:15</span></div>
    </div>
    <div style="display:flex;align-items:center;justify-content:center;gap:var(--s-6);padding:0 var(--s-6) var(--s-6)">
      <button class="icon-btn" data-act="prev">${ic('prev', 24)}</button>
      <button class="icon-btn" style="width:52px;height:52px;background:var(--ink);color:var(--bg)" data-act="toggle-play">${ic('pause', 24)}</button>
      <button class="icon-btn" data-act="next">${ic('next', 24)}</button>
    </div>
  </div>`;
}

/* ---------------- 搜索 ---------------- */

function screenSearch() {
  return `<div class="screen">
    <div class="appbar"><span class="title">搜索</span></div>
    <div class="searchbar">
      ${ic('search', 19)}<input placeholder="歌曲、专辑、艺人…" value="程响">
      <button class="icon-btn quiet" style="width:22px;height:22px">${ic('x', 15)}</button>
    </div>
    <div class="chip-row">
      <span class="chip" aria-selected="true">全部</span>
      <span class="chip">歌曲</span><span class="chip">专辑</span><span class="chip">艺人</span>
    </div>
    <div class="scroll">
      <div class="group-label">最匹配</div>
      ${songRow(SONGS[0])}
      ${songRow(SONGS[1])}
      <div class="group-label">专辑</div>
      <div class="rail-track" style="padding-bottom:var(--s-4)">${ALBUMS.slice(0, 3).map((a) => `
        <div class="rail-item" data-album="${a.id}">
          ${cover(a, 'sq', a.mark)}
          <div><div class="name">${a.name}</div><div class="meta">${a.artist}</div></div>
        </div>`).join('')}</div>
      <div class="group-label">艺人</div>
      ${ARTISTS.slice(0, 2).map((ar) => `
        <div class="row" style="height:64px">
          <div class="avatar" style="background:linear-gradient(142deg,${ar.c1},${ar.c2})">${ar.name.slice(0, 2)}</div>
          <div class="grow"><div class="line1">${ar.name}</div><div class="line2">${ar.albums} 张专辑</div></div>
          ${ic('chevron', 18)}
        </div>`).join('')}
      <div style="height:var(--s-6)"></div>
    </div>
    ${dock()}
    ${tabbar('search')}
  </div>`;
}

/* ---------------- 设置 ---------------- */

function screenSettings() {
  return `<div class="screen">
    <div class="appbar"><span class="title">设置</span></div>
    <div class="scroll">
      <div class="group-label">播放</div>
      <div class="card" style="margin:0 var(--s-5)">
        <div class="row" data-sheet="quality">
          <div class="grow"><div class="line1">默认转码质量</div><div class="line2">移动网络下生效</div></div>
          <span class="trail" style="color:var(--ink-secondary)">均衡</span>${ic('chevron', 18)}
        </div>
        <div class="divider"></div>
        <div class="row">
          <div class="grow"><div class="line1">线路自动择优</div><div class="line2">按延迟选择最快可用地址</div></div>
          <span class="tick on">${ic('check', 12)}</span>
        </div>
        <div class="divider"></div>
        <div class="row">
          <div class="grow"><div class="line1">播放时保持后台运行</div></div>
          <span class="tick on">${ic('check', 12)}</span>
        </div>
      </div>
      <div class="group-label">服务器</div>
      <div class="card" style="margin:0 var(--s-5)">
        <div class="row" data-go="servers">
          <div class="grow"><div class="line1">${SERVER.name}</div><div class="line2">${SERVER.kind} · ${SERVER.routes.length} 条线路</div></div>
          ${ic('chevron', 18)}
        </div>
        <div class="divider"></div>
        <div class="row" data-go="add-server">
          <div class="grow"><div class="line1">添加服务器</div></div>${ic('plus', 18)}
        </div>
      </div>
      <div class="group-label">关于</div>
      <div class="card" style="margin:0 var(--s-5)">
        <div class="row"><div class="grow"><div class="line1">版本</div></div><span class="trail">原型 v1</span></div>
      </div>
      <div style="height:var(--s-6)"></div>
    </div>
    ${dock()}
    ${tabbar('settings')}
  </div>`;
}

/* ---------------- 视图表 ---------------- */

const sheets = { quality: sheetQuality, queue: sheetQueue, routes: sheetRoutes };

const VIEWS = {
  servers: () => screenServers(),
  'server-config': () => screenServerConfig(),
  'add-server': () => screenAddServer(),
  library: (p) => screenLibrary((p && p.lib) || 'albums'),
  album: (p) => screenAlbum((p && p.album) || STATE.albumId),
  player: () => screenPlayer(STATE.overlay ? sheets[STATE.overlay]() : ''),
  lyrics: () => screenLyrics(),
  search: () => screenSearch(),
  settings: () => screenSettings(),
};

/* ============================================================
   设计板
   ============================================================ */

const BOARD = [
  ['服务器与线路', '填服务器 → 看线路状态', () => shell(screenServers())],
  ['服务器设置 · 多线路', '一个账号,多个地址', () => shell(screenServerConfig())],
  ['添加服务器', '选择接入类型', () => shell(screenAddServer())],
  ['音乐库 · 专辑', '封面网格 + 最近添加', () => shell(screenLibrary('albums'))],
  ['音乐库 · 艺人', '圆形头像列表', () => shell(screenLibrary('artists'))],
  ['音乐库 · 歌曲', '带封面与格式', () => shell(screenLibrary('songs'))],
  ['音乐库 · 歌单', '用户歌单列表', () => shell(screenLibrary('playlists'))],
  ['专辑详情', '大封面 + 曲目', () => shell(screenAlbum('a1'))],
  ['播放页', '封面主导 + 随封面取色', () => shell(screenPlayer())],
  ['转码质量', '四档位,含说明', () => shell(screenPlayer(sheetQuality()))],
  ['播放队列', '当前队列管理', () => shell(screenPlayer(sheetQueue()))],
  ['线路切换', '播放中改线路', () => shell(screenPlayer(sheetRoutes()))],
  ['歌词', '逐句高亮', () => shell(screenLyrics())],
  ['搜索', '跨歌曲 / 专辑 / 艺人', () => shell(screenSearch())],
  ['设置', '播放与服务器', () => shell(screenSettings())],
];

function renderBoard(root) {
  root.innerHTML = `
    <div class="board-head">
      <h1>Nordic — 音乐播放器原型</h1>
      <p>手机竖屏。深色沉浸 + <b>随封面取色</b>的强调色 —— 每张专辑驱动界面自己的主色(见各屏进度条、选中态与光晕)。
         本页是所有屏的并排设计板;<b>要点击走完整条链路,请开 <a href="player.html" style="color:var(--accent)">player.html</a></b>。</p>
    </div>
    <div class="board">${BOARD.map(([title, sub, fn]) => `
      <div class="board-col">
        <div class="frame-label"><b>${title}</b> · ${sub}</div>
        ${fn()}
      </div>`).join('')}</div>`;
}

/* ============================================================
   交互流
   ============================================================ */

function renderStage(root) {
  const slot = () => root.querySelector('#phone-slot');

  const render = () => {
    const view = VIEWS[STATE.view];
    if (!view) return;
    slot().innerHTML = view(STATE.params);
  };

  const go = (name, params) => {
    if (name !== STATE.view) {
      STATE.history.push({ view: STATE.view, params: STATE.params });
    }
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
      STATE.view = 'servers';
      STATE.params = {};
    }
    STATE.overlay = '';
    render();
  };

  root.innerHTML = `
    <div class="stage">
      <aside class="stage-side">
        <h2>可点击原型</h2>
        <ol>
          <li>服务器页可见 3 条线路,已自动选中延迟最低的那条</li>
          <li>点「音乐库」切换 专辑 / 艺人 / 歌曲 / 歌单</li>
          <li>点专辑 → 点任意歌曲 → 进播放页</li>
          <li>点「均衡 · MP3」胶囊切换转码质量</li>
          <li>点「队列」「歌词」查看对应界面</li>
        </ol>
        <div style="border-top:1px solid var(--hairline);padding-top:14px">
          <h2 style="margin-bottom:6px">随封面取色</h2>
          每张专辑驱动界面的强调色。举例:
          <div class="swatches" id="sw"></div>
          <div style="margin-top:12px;font-size:11px;color:var(--ink-tertiary)">
            返回:左上角按钮,或键盘 <span class="kbd">←</span>
          </div>
        </div>
      </aside>
      <div id="phone-slot"></div>
    </div>`;

  root.querySelector('#sw').innerHTML = ALBUMS.slice(0, 6).map((a) =>
    `<span class="sw" title="${a.name}" style="background:linear-gradient(142deg,${a.c1},${a.c2})"></span>`).join('');

  slot().addEventListener('click', (e) => {
    const t = e.target.closest('[data-back],[data-tab],[data-go],[data-lib],[data-song],[data-album],[data-route],[data-quality],[data-sheet],[data-act]');
    if (t) {
      const d = t.dataset;
      if (d.back !== undefined) return back();
      if (d.tab) { STATE.history = []; return go(d.tab); }
      if (d.lib) { STATE.params = { lib: d.lib }; return render(); }
      if (d.song) { STATE.songId = d.song; return go('player'); }
      if (d.album) { STATE.albumId = d.album; return go('album', { album: d.album }); }
      if (d.route) { STATE.routeId = d.route; return render(); }
      if (d.quality) { STATE.quality = d.quality; STATE.overlay = ''; return render(); }
      if (d.sheet) { STATE.overlay = d.sheet; return render(); }
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
  if (document.body.dataset.mode === 'board') renderBoard(document.body);
  else renderStage(document.body);
});