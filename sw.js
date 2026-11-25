/* GARO AI service worker: makes the site installable and opens the app shell fast. It never caches account data,
   chat traffic, the AI server, Supabase or any other site. */
const V='garo-shell-v1', SHELL=['./','index.html','site.webmanifest','garoai-icon-192.png','garoai-icon-512.png','garoai-logo.png','favicon.ico'];
self.addEventListener('install',e=>{ e.waitUntil(caches.open(V).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))).then(()=>self.skipWaiting())); });
self.addEventListener('activate',e=>{ e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('garo-shell-')&&k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim())); });
self.addEventListener('fetch',e=>{
  const r=e.request, u=new URL(r.url);
  if(r.method!=='GET'||u.origin!==self.location.origin) return;
  if(r.mode==='navigate'){   /* newest page when online, saved copy when offline */
    e.respondWith(fetch(r).then(res=>{ if(res.ok){ const cp=res.clone(); caches.open(V).then(c=>c.put('index.html',cp)); } return res; }).catch(()=>caches.match('index.html').then(m=>m||caches.match('./'))));
    return;
  }
  if(/\.(png|jpg|jpeg|ico|svg|webmanifest|woff2?)$/i.test(u.pathname)){   /* static files: saved copy first, refreshed in the background */
    e.respondWith(caches.match(r).then(m=>{ const net=fetch(r).then(res=>{ if(res.ok){ const cp=res.clone(); caches.open(V).then(c=>c.put(r,cp)); } return res; }).catch(()=>m); return m||net; }));
  }
});
