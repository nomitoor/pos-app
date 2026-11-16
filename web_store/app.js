/* Urban Thread online store.
 * Reads the catalogue that the POS app syncs to Supabase and places orders
 * through the secure `place_order` function (see supabase/store.sql).
 * Add ?demo=1 to the address to preview with sample products (no database).
 */
(() => {
  'use strict';

  const CFG = window.STORE_CONFIG || {};
  const DEMO = new URLSearchParams(location.search).has('demo');
  const db = !DEMO && window.supabase
    ? window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseKey)
    : null;

  const app = document.getElementById('app');
  const SIZES = ['Extra Small', 'Small', 'Medium', 'Large', 'Extra Large', 'XXL'];
  const SHORT = { 'Extra Small': 'XS', Small: 'S', Medium: 'M', Large: 'L', 'Extra Large': 'XL', XXL: 'XXL' };
  const AREAS = ['DHA', 'Gulberg', 'Johar Town', 'Model Town', 'Bahria Town', 'Wapda Town', 'Cantt',
    'Iqbal Town', 'Faisal Town', 'Garden Town', 'Township', 'Valencia', 'Shadman', 'Samanabad',
    'Allama Iqbal Town', 'Askari', 'Lake City', 'Paragon City', 'Ichra', 'Mall Road'];

  const state = {
    designs: [],      // [{id, name, type, description, price, photos, variants: [...]}]
    byVariant: {},    // variantId -> {variant, design}
    settings: { store_open: true, delivery_fee: 200, free_delivery_over: null, whatsapp: null },
    loaded: false,
    loadError: null,
    filterType: 'All',
    // The size picked on the tape is remembered in this browser and
    // preselected on product pages.
    filterSize: (() => { try { return localStorage.getItem('ut_size') || 'All'; } catch { return 'All'; } })(),
    sort: 'new',
  };

  // ── Helpers ───────────────────────────────────────────────
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const rs = (n) => 'Rs ' + Math.round(Number(n) || 0).toLocaleString('en-PK');
  const short = (s) => (s == null || s === '' ? 'One size' : SHORT[s] || s);
  const sizeKey = (s) => {
    if (s == null || s === '') return [3, 0, ''];
    const i = SIZES.indexOf(s);
    if (i >= 0) return [0, i, ''];
    const n = parseFloat(s);
    return isNaN(n) ? [2, 0, s.toLowerCase()] : [1, n, ''];
  };
  const bySize = (a, b) => {
    const x = sizeKey(a.size), y = sizeKey(b.size);
    return x[0] - y[0] || x[1] - y[1] || x[2].localeCompare(y[2]);
  };
  const normPhone = (p) => {
    let d = String(p || '').replace(/\D/g, '');
    if (d.startsWith('0092')) d = d.slice(4);
    else if (d.startsWith('92')) d = d.slice(2);
    else if (d.startsWith('0')) d = d.slice(1);
    return /^3\d{9}$/.test(d) ? '0' + d : null;
  };
  const placeholder = (label) => `<div class="ph">${esc(label)}</div>`;

  /** Short message at the bottom; optional link, e.g. {href:'#/cart', label:'View cart'}. */
  function toast(msg, action) {
    const t = document.getElementById('toast');
    t.innerHTML = `<span>${esc(msg)}</span>${action
      ? `<a href="${esc(action.href)}" onclick="this.parentNode.hidden=true">${esc(action.label)}</a>` : ''}`;
    t.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(() => (t.hidden = true), action ? 4200 : 2600);
  }
  function bumpBadge() {
    const b = document.getElementById('cart-count');
    b.classList.remove('bump');
    void b.offsetWidth; // restart the animation
    b.classList.add('bump');
  }
  function saveSize(s) {
    try { s === 'All' ? localStorage.removeItem('ut_size') : localStorage.setItem('ut_size', s); } catch { /* private mode */ }
  }

  // ── Cart (kept in this browser) ───────────────────────────
  const CART_KEY = 'ut_cart_v1';
  const cart = {
    read() {
      try { return JSON.parse(localStorage.getItem(CART_KEY)) || []; } catch { return []; }
    },
    write(items) {
      try { localStorage.setItem(CART_KEY, JSON.stringify(items)); } catch { /* private mode */ }
      updateBadge();
    },
    add(variantId, qty) {
      const items = cart.read();
      const line = items.find((i) => i.v === variantId);
      if (line) line.q += qty; else items.push({ v: variantId, q: qty });
      cart.write(items);
    },
    set(variantId, qty) {
      cart.write(cart.read().map((i) => (i.v === variantId ? { ...i, q: qty } : i)).filter((i) => i.q > 0));
    },
    clear() { cart.write([]); },
    /** Lines with current price/stock; drops items no longer for sale. */
    lines() {
      return cart.read()
        .map((i) => ({ ...state.byVariant[i.v], qty: i.q }))
        .filter((l) => l.variant && l.variant.stock > 0)
        .map((l) => ({ ...l, qty: Math.min(l.qty, l.variant.stock) }));
    },
  };
  function updateBadge() {
    const n = cart.read().reduce((s, i) => s + i.q, 0);
    const b = document.getElementById('cart-count');
    b.textContent = n;
    b.hidden = n === 0;
  }

  function totals(lines) {
    const subtotal = lines.reduce((s, l) => s + l.variant.price * l.qty, 0);
    const s = state.settings;
    const free = s.free_delivery_over != null && subtotal >= Number(s.free_delivery_over);
    const fee = lines.length === 0 || free ? 0 : Number(s.delivery_fee || 0);
    return { subtotal, fee, total: subtotal + fee, free };
  }

  // ── Data ──────────────────────────────────────────────────
  async function load() {
    try {
      let designs, variants, settings;
      if (DEMO) {
        ({ designs, variants, settings } = demoData());
      } else {
        const [d, v, s] = await Promise.all([
          db.from('catalog_designs').select('id,name,type,description,price,photos,updated_at').eq('online', true),
          db.from('catalog_variants').select('id,design_id,size,price,stock'),
          db.from('store_settings').select('*').maybeSingle(),
        ]);
        if (d.error) throw d.error;
        if (v.error) throw v.error;
        designs = d.data; variants = v.data; settings = s.data;
      }
      if (settings) state.settings = settings;
      const byDesign = {};
      for (const v of variants) (byDesign[v.design_id] ||= []).push({ ...v, price: Number(v.price) });
      state.designs = designs
        .map((d) => ({ ...d, price: Number(d.price), photos: d.photos || [], variants: (byDesign[d.id] || []).sort(bySize) }))
        .filter((d) => d.variants.length > 0);
      state.byVariant = {};
      for (const d of state.designs) for (const v of d.variants) state.byVariant[v.id] = { variant: v, design: d };
      state.loaded = true;
    } catch (e) {
      console.error(e);
      state.loadError = e.message || String(e);
      state.loaded = true;
    }
    renderBanner();
    renderFooter();
    updateBadge();
    route();
  }

  function renderBanner() {
    const b = document.getElementById('banner');
    if (DEMO) {
      b.textContent = 'Demo preview with sample products. Orders placed here are not real.';
      b.hidden = false;
    } else if (!state.settings.store_open) {
      b.textContent = 'We are not taking orders right now. Please check back soon.';
      b.hidden = false;
    } else {
      const s = state.settings;
      b.textContent = s.free_delivery_over
        ? `Free delivery in ${CFG.city} on orders over ${rs(s.free_delivery_over)}`
        : `Cash on delivery across ${CFG.city}`;
      b.hidden = false;
    }
  }

  function renderFooter() {
    document.getElementById('year').textContent = new Date().getFullYear();
    const w = state.settings.whatsapp;
    document.getElementById('foot-contact').innerHTML = w
      ? `WhatsApp: <a href="${waLink(w, 'Hi Urban Thread!')}" target="_blank" rel="noopener">${esc(w)}</a>`
      : '';
  }

  const waLink = (phone, text) => {
    let d = String(phone).replace(/\D/g, '');
    if (d.startsWith('0')) d = '92' + d.slice(1);
    return `https://wa.me/${d}?text=${encodeURIComponent(text)}`;
  };

  // ── Router ────────────────────────────────────────────────
  function route() {
    const hash = location.hash.replace(/^#/, '') || '/';
    const [path, query] = hash.split('?');
    const parts = path.split('/').filter(Boolean);
    window.scrollTo(0, 0);
    document.title = CFG.shopName || 'Urban Thread';
    if (!state.loaded) return renderLoading();
    // Track order and the info pages still work if the catalogue didn't load.
    if (state.loadError && parts[0] !== 'track' && !INFO.includes(parts[0])) return renderLoadError();
    switch (parts[0]) {
      case undefined: return renderHome();
      case 'p': return renderProduct(Number(parts[1]));
      case 'cart': return renderCart();
      case 'checkout': return renderCheckout();
      case 'done': return renderDone(decodeURIComponent(parts[1] || ''));
      case 'track': return renderTrack(new URLSearchParams(query || ''));
      case 'about': return renderAbout();
      case 'contact': return renderContact();
      case 'delivery': return renderDelivery();
      case 'exchanges': return renderExchanges();
      case 'size-guide': return renderSizeGuide();
      case 'faq': return renderFaq();
      case 'privacy': return renderPrivacy();
      case 'terms': return renderTerms();
      default: return renderHome();
    }
  }
  window.addEventListener('hashchange', route);

  function renderLoading() {
    app.innerHTML = `<div class="grid" style="margin-top:32px">${
      '<div class="skeleton" style="aspect-ratio:4/5"></div>'.repeat(4)}</div>`;
  }

  function renderLoadError() {
    app.innerHTML = `<div class="empty">
      <h2>We couldn't load the shop</h2>
      <p>Please check your internet connection and try again.</p>
      <button class="btn primary" onclick="location.reload()">Try again</button>
    </div>`;
  }

  // ── Home ──────────────────────────────────────────────────
  function renderHome() {
    const types = ['All', ...new Set(state.designs.map((d) => d.type).filter(Boolean))];
    const sizes = ['All', ...new Set(state.designs.flatMap((d) => d.variants.map((v) => v.size)).filter(Boolean))]
      .sort((a, b) => (a === 'All' ? -1 : b === 'All' ? 1 : bySize({ size: a }, { size: b })));

    // A remembered size that no product comes in any more is dropped.
    if (!sizes.includes(state.filterSize)) { state.filterSize = 'All'; saveSize('All'); }

    let list = state.designs.filter((d) =>
      (state.filterType === 'All' || d.type === state.filterType) &&
      (state.filterSize === 'All' || d.variants.some((v) => v.size === state.filterSize && v.stock > 0)));
    const minPrice = (d) => Math.min(...d.variants.map((v) => v.price));
    if (state.sort === 'low') list.sort((a, b) => minPrice(a) - minPrice(b));
    else if (state.sort === 'high') list.sort((a, b) => minPrice(b) - minPrice(a));
    else list.sort((a, b) => String(b.updated_at || '').localeCompare(String(a.updated_at || '')) || b.id - a.id);

    // Keep the tape's sideways scroll position when re-rendering after a tap.
    const prevTape = app.querySelector('.sizebar .tape');
    const tapeScroll = prevTape ? prevTape.scrollLeft : 0;
    const fs = state.filterSize;
    // The tape unrolls once, the first time the shop is shown.
    const unroll = !renderHome.shown;
    renderHome.shown = true;
    app.innerHTML = `
      <section class="hero">
        <h1>Everyday streetwear, delivered in ${esc(CFG.city)}.</h1>
        <div class="lede">
          <p>Pick your size, order in a minute, pay when it arrives.</p>
          <p class="cod-line"><span>Cash on delivery</span> anywhere in ${esc(CFG.city)}</p>
        </div>
      </section>
      <div class="sizebar${unroll ? ' unroll' : ''}">
        <div class="tape" role="group" aria-label="Filter by size">
          <button class="end ${fs === 'All' ? 'on' : ''}" data-fsize="All" aria-pressed="${fs === 'All'}">All</button>
          ${sizes.filter((s) => s !== 'All').map((s) =>
            `<button class="mark ${s === fs ? 'on' : ''}" data-fsize="${esc(s)}" aria-pressed="${s === fs}" aria-label="Size ${esc(s)}">${esc(short(s))}</button>`).join('')}
          <span class="tail" aria-hidden="true"></span>
        </div>
      </div>
      <p class="sizehint">${fs === 'All'
        ? 'Tap your size on the tape to see only what’s in stock in it.'
        : `Showing pieces in stock in size ${esc(short(fs))}. We’ll remember it and pick it for you on each product.`}</p>
      <div class="shopbar">
        <div class="filters" role="tablist" aria-label="Category">${types.map((t) =>
          `<button class="chip ${t === state.filterType ? 'on' : ''}" role="tab" aria-selected="${t === state.filterType}" data-type="${esc(t)}">${esc(t === 'All' ? 'Everything' : t + 's')}</button>`).join('')}</div>
        <select class="select" id="sort" aria-label="Sort">
          <option value="new" ${state.sort === 'new' ? 'selected' : ''}>Newest</option>
          <option value="low" ${state.sort === 'low' ? 'selected' : ''}>Price: low to high</option>
          <option value="high" ${state.sort === 'high' ? 'selected' : ''}>Price: high to low</option>
        </select>
      </div>
      ${list.length === 0
        ? `<div class="empty">${state.designs.length === 0
          ? '<h2>New collection coming soon</h2>Check back in a few days.'
          : '<h2>Nothing in that size here</h2>Try another size on the tape, or another category.'}</div>`
        : `<p class="count">${list.length} ${list.length === 1 ? 'piece' : 'pieces'}</p><div class="grid">${list.map(cardHtml).join('')}</div>`}`;
    app.querySelector('.sizebar .tape').scrollLeft = tapeScroll;

    app.querySelectorAll('[data-type]').forEach((b) => b.addEventListener('click', () => {
      state.filterType = b.dataset.type; renderHome();
    }));
    app.querySelectorAll('[data-fsize]').forEach((b) => b.addEventListener('click', () => {
      state.filterSize = b.dataset.fsize; saveSize(state.filterSize); renderHome();
      app.querySelector(`[data-fsize="${CSS.escape(state.filterSize)}"]`)?.focus();
    }));
    app.querySelector('#sort').addEventListener('change', (e) => { state.sort = e.target.value; renderHome(); });
  }

  function priceRange(d) {
    const ps = d.variants.map((v) => v.price);
    const lo = Math.min(...ps), hi = Math.max(...ps);
    return lo === hi ? rs(lo) : `${rs(lo)} – ${Math.round(hi).toLocaleString('en-PK')}`;
  }

  function cardHtml(d) {
    const stock = d.variants.reduce((s, v) => s + v.stock, 0);
    const tag = stock <= 0 ? 'Sold out' : stock <= 3 ? 'Few left' : '';
    return `<a class="card" href="#/p/${d.id}">
      <div class="thumb">${d.photos[0]
        ? `<img src="${esc(d.photos[0])}" alt="${esc(d.name)}" loading="lazy">${d.photos[1]
          ? `<img class="alt" src="${esc(d.photos[1])}" alt="" loading="lazy">` : ''}`
        : placeholder('Photo coming soon')}${tag ? `<span class="tag${stock <= 0 ? ' out' : ''}">${tag}</span>` : ''}</div>
      <div class="info">
        <div class="type">${esc(d.type || '')}</div>
        <div class="name">${esc(d.name)}</div>
        <div class="price">${priceRange(d)}</div>
        <div class="sizes-mini">${d.variants.map((v) =>
          `<span class="${v.stock > 0 ? '' : 'out'}">${esc(short(v.size))}</span>`).join('')}</div>
      </div>
    </a>`;
  }

  // ── Product ───────────────────────────────────────────────
  function renderProduct(id) {
    const d = state.designs.find((x) => x.id === id);
    if (!d) {
      app.innerHTML = `<div class="empty"><h2>This item is no longer available</h2><a class="btn primary" href="#/">Back to shop</a></div>`;
      return;
    }
    const inStock = d.variants.filter((v) => v.stock > 0);
    const mine = inStock.find((v) => v.size === state.filterSize);
    let sel = inStock.length === 1 ? inStock[0] : mine || null;
    let qty = 1;
    let photo = 0;

    const soldOut = inStock.length === 0;
    const hasSizes = !(d.variants.length === 1 && d.variants[0].size == null);
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const draw = () => {
      const price = sel ? sel.price : null;
      const priceText = price != null ? rs(price) : priceRange(d);
      const addLabel = soldOut ? 'Sold out' : 'Add to cart';
      app.innerHTML = `
        <a class="back" href="#/"><svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M9 2 4 7l5 5" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>Back to shop</a>
        <div class="product">
          <div class="gallery">
            <div class="main ${d.photos.length > 1 ? 'multi' : ''}" ${d.photos.length > 1 ? 'tabindex="0" aria-label="Photos, swipe for more"' : ''}>${d.photos.length
              ? d.photos.map((p, i) => `<img src="${esc(p)}" alt="${i === 0 ? esc(d.name) : `${esc(d.name)}, photo ${i + 1}`}">`).join('')
              : placeholder('Photo coming soon')}</div>
            ${d.photos.length > 1 ? `<div class="thumbs">${d.photos.map((p, i) =>
              `<button class="${i === photo ? 'on' : ''}" data-photo="${i}" aria-label="Photo ${i + 1}"><img src="${esc(p)}" alt=""></button>`).join('')}</div>` : ''}
          </div>
          <div class="pinfo">
            <div class="ptype">${esc(d.type || '')}</div>
            <h1>${esc(d.name)}</h1>
            <div class="pprice">${priceText}</div>
            ${!hasSizes ? '' : `
              <div class="sizehead"><span class="label" id="size-label">Size</span><a href="#/size-guide">Size guide</a></div>
              <div class="sizes"><div class="tape" role="group" aria-labelledby="size-label">
                <span class="end" aria-hidden="true"></span>
                ${d.variants.map((v) =>
                `<button class="mark ${sel && sel.id === v.id ? 'on' : ''}" data-size="${v.id}" aria-pressed="${!!(sel && sel.id === v.id)}" ${v.stock > 0 ? '' : 'disabled'}>${esc(short(v.size))}</button>`).join('')}
                <span class="tail" aria-hidden="true"></span></div></div>`}
            <div class="stocknote ${sel && sel.stock <= 3 ? 'low' : ''}">${sel ? (sel.stock <= 3 ? `Only ${sel.stock} left in this size` : sel === mine ? 'Your size is in stock' : 'In stock') : inStock.length ? 'Choose your size on the tape' : 'Sold out'}</div>
            <div class="row">
              <div class="qty"><button data-q="-1" aria-label="Less">−</button><span>${qty}</span><button data-q="1" aria-label="More">+</button></div>
              <button class="btn primary js-add" style="flex:1" ${soldOut ? 'disabled' : ''}>${addLabel}</button>
            </div>
            ${d.description ? `<div class="desc">${esc(d.description)}</div>` : ''}
            <ul class="assure"><li><strong>Pay cash</strong> when it arrives at your door</li><li><strong>Delivery</strong> anywhere in ${esc(CFG.city)}</li></ul>
            ${state.settings.whatsapp ? `<a class="btn ghost block" style="margin-top:8px" target="_blank" rel="noopener"
              href="${waLink(state.settings.whatsapp, `Hi! I have a question about ${d.name}.`)}">Ask on WhatsApp</a>` : ''}
          </div>
        </div>
        <div class="buybar-space"></div>
        <div class="buybar">
          <div class="qty"><button data-q="-1" aria-label="Less">−</button><span>${qty}</span><button data-q="1" aria-label="More">+</button></div>
          <button class="btn primary js-add" ${soldOut ? 'disabled' : ''}>
            <span>${addLabel}</span>${sel ? `<span class="bb-price">${rs(sel.price * qty)}</span>` : ''}</button>
        </div>`;

      // Gallery: a swipeable strip; thumbnails jump to a photo.
      const track = app.querySelector('.gallery .main');
      const imgs = track.querySelectorAll('img');
      const offsetOf = (i) => (imgs[i] ? imgs[i].offsetLeft - imgs[0].offsetLeft : 0);
      if (photo) track.scrollLeft = offsetOf(photo);
      const markThumb = () => app.querySelectorAll('[data-photo]').forEach((b) => b.classList.toggle('on', +b.dataset.photo === photo));
      if (imgs.length > 1) {
        track.addEventListener('scroll', () => {
          const step = offsetOf(1) || 1;
          const i = Math.max(0, Math.min(imgs.length - 1, Math.round(track.scrollLeft / step)));
          if (i !== photo) { photo = i; markThumb(); }
        }, { passive: true });
      }
      app.querySelectorAll('[data-photo]').forEach((b) => b.addEventListener('click', () => {
        photo = +b.dataset.photo; markThumb();
        track.scrollTo({ left: offsetOf(photo), behavior: reduceMotion ? 'auto' : 'smooth' });
      }));
      app.querySelectorAll('[data-size]').forEach((b) => b.addEventListener('click', () => {
        sel = d.variants.find((v) => v.id === +b.dataset.size);
        qty = Math.min(qty, sel.stock);
        draw();
      }));
      app.querySelectorAll('[data-q]').forEach((b) => b.addEventListener('click', () => {
        const max = sel ? sel.stock : 10;
        qty = Math.max(1, Math.min(max, qty + +b.dataset.q));
        draw();
      }));
      app.querySelectorAll('.js-add').forEach((b) => b.addEventListener('click', () => {
        if (!sel) return nudgeSize();
        const inCart = (cart.read().find((i) => i.v === sel.id) || { q: 0 }).q;
        if (inCart + qty > sel.stock) {
          toast(`Only ${sel.stock} available in this size`);
          return;
        }
        cart.add(sel.id, qty);
        bumpBadge();
        toast(`Added ${d.name} (${short(sel.size)}) to cart`, { href: '#/cart', label: 'View cart' });
      }));
    };

    // "Add to cart" with no size chosen: bring the tape into view and shake it.
    function nudgeSize() {
      const tape = app.querySelector('.sizes .tape');
      const note = app.querySelector('.stocknote');
      note.textContent = 'Choose your size first';
      note.classList.add('low');
      if (!tape) return;
      const r = tape.getBoundingClientRect();
      if (r.top < 80 || r.bottom > innerHeight - 100) {
        tape.scrollIntoView({ block: 'center', behavior: reduceMotion ? 'auto' : 'smooth' });
      }
      tape.classList.remove('nudge');
      void tape.offsetWidth; // restart the animation
      tape.classList.add('nudge');
      tape.querySelector('.mark:not(:disabled)')?.focus({ preventScroll: true });
    }
    draw();
  }

  // ── Cart ──────────────────────────────────────────────────
  function renderCart() {
    const lines = cart.lines();
    if (lines.length === 0) {
      app.innerHTML = `<h1 class="page-title">Your cart</h1><div class="empty"><h2>Your cart is empty</h2>Pick something from the shop to get started.<br><a class="btn primary" href="#/">Start shopping</a></div>`;
      return;
    }
    const t = totals(lines);
    app.innerHTML = `
      <h1 class="page-title">Your cart</h1>
      <div class="cols">
        <div class="lines">${lines.map((l) => `
          <div class="line">
            ${l.design.photos[0] ? `<img src="${esc(l.design.photos[0])}" alt="">` : '<div class="ph"></div>'}
            <div>
              <div class="lname">${esc(l.design.name)}</div>
              <div class="lmeta"><span class="sizechip">${esc(short(l.variant.size))}</span>${rs(l.variant.price)} each</div>
              <div class="controls">
                <div class="qty"><button data-dec="${l.variant.id}" aria-label="One less">−</button><span>${l.qty}</span><button data-inc="${l.variant.id}" aria-label="One more">+</button></div>
                <button class="linkbtn" data-rm="${l.variant.id}">Remove</button>
              </div>
            </div>
            <div class="lprice">${rs(l.variant.price * l.qty)}</div>
          </div>`).join('')}
        </div>
        <div class="slip">
          ${summaryHtml(t)}
          <a class="btn primary block" style="margin-top:18px" href="#/checkout" ${state.settings.store_open ? '' : 'aria-disabled="true"'}>Checkout</a>
          <p class="note">You pay cash when your order arrives.</p>
        </div>
      </div>`;
    const qtyOf = (id) => cart.read().find((i) => i.v === id)?.q || 0;
    app.querySelectorAll('[data-inc]').forEach((b) => b.addEventListener('click', () => {
      const id = +b.dataset.inc, max = state.byVariant[id].variant.stock;
      if (qtyOf(id) >= max) return toast(`Only ${max} available`);
      cart.set(id, qtyOf(id) + 1); renderCart();
    }));
    app.querySelectorAll('[data-dec]').forEach((b) => b.addEventListener('click', () => {
      const id = +b.dataset.dec; cart.set(id, qtyOf(id) - 1); renderCart();
    }));
    app.querySelectorAll('[data-rm]').forEach((b) => b.addEventListener('click', () => {
      cart.set(+b.dataset.rm, 0); renderCart();
    }));
  }

  function summaryHtml(t) {
    const s = state.settings;
    return `
      <div class="sum"><span>Subtotal</span><span>${rs(t.subtotal)}</span></div>
      <div class="sum"><span>Delivery</span><span>${t.free ? 'Free' : rs(t.fee)}</span></div>
      ${s.free_delivery_over ? `<div class="freebar">
        <div class="tape meter" aria-hidden="true"><span class="fill" style="width:${Math.min(100, (t.subtotal / s.free_delivery_over) * 100)}%"></span></div>
        <p class="note">${t.free ? 'Your order gets free delivery.'
          : `Add ${rs(s.free_delivery_over - t.subtotal)} more for free delivery.`}</p></div>` : ''}
      <div class="sum total"><span>Total</span><span>${rs(t.total)}</span></div>`;
  }

  // ── Checkout ──────────────────────────────────────────────
  function renderCheckout() {
    const lines = cart.lines();
    if (lines.length === 0) { location.hash = '#/cart'; return; }
    if (!state.settings.store_open) {
      app.innerHTML = `<div class="empty"><h2>We're not taking orders right now</h2><p>Please try again later.</p></div>`;
      return;
    }
    const saved = (() => { try { return JSON.parse(localStorage.getItem('ut_customer')) || {}; } catch { return {}; } })();
    const t = totals(lines);
    app.innerHTML = `
      <h1 class="page-title">Checkout</h1>
      <div class="cols">
        <form class="panel" id="form" novalidate>
          <div class="field"><label class="label" for="name">Full name</label>
            <input class="input" id="name" autocomplete="name" required value="${esc(saved.name || '')}"></div>
          <div class="field"><label class="label" for="phone">Mobile number</label>
            <input class="input" id="phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="03XX-XXXXXXX" required value="${esc(saved.phone || '')}"></div>
          <div class="field"><label class="label" for="area">Area in ${esc(CFG.city)}</label>
            <input class="input" id="area" list="areas" placeholder="e.g. Johar Town" value="${esc(saved.area || '')}">
            <datalist id="areas">${AREAS.map((a) => `<option value="${esc(a)}">`).join('')}</datalist></div>
          <div class="field"><label class="label" for="address">Full address</label>
            <textarea class="input" id="address" autocomplete="street-address" placeholder="House no., street, block, nearby landmark" required>${esc(saved.address || '')}</textarea></div>
          <div class="field"><label class="label" for="notes">Notes (optional)</label>
            <input class="input" id="notes" placeholder="e.g. call before coming"></div>
          <div class="cod"><strong>Cash on delivery</strong>
            <div class="note">Pay when your order arrives. We'll call or WhatsApp you to confirm.</div></div>
          <button class="btn primary block" id="place" type="submit">Place order, ${rs(t.total)}</button>
          <p class="note">By placing your order you agree to our <a href="#/terms">terms and conditions</a>. We only use your details to confirm and deliver your order (<a href="#/privacy">privacy policy</a>).</p>
          <div class="error" id="err" hidden></div>
        </form>
        <div class="slip first-on-phone">
          <h2 class="slip-title">Your order</h2>
          ${lines.map((l) => `<div class="sum item"><span>${l.qty} × ${esc(l.design.name)} <span class="sizechip">${esc(short(l.variant.size))}</span></span><span>${rs(l.variant.price * l.qty)}</span></div>`).join('')}
          <div class="slip-cut"></div>
          ${summaryHtml(t)}
        </div>
      </div>`;

    const form = app.querySelector('#form');
    const err = app.querySelector('#err');
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const v = (id) => form.querySelector('#' + id).value.trim();
      const data = { name: v('name'), phone: v('phone'), area: v('area'), address: v('address'), notes: v('notes') };
      const problem = data.name.length < 2 ? 'Please enter your name.'
        : !normPhone(data.phone) ? 'Please enter a valid mobile number (03XX-XXXXXXX).'
        : data.address.length < 8 ? 'Please enter your full delivery address.' : null;
      if (problem) { err.textContent = problem; err.hidden = false; return; }

      const btn = form.querySelector('#place');
      btn.disabled = true; btn.textContent = 'Placing order…'; err.hidden = true;
      try {
        const items = cart.lines().map((l) => ({ variant_id: l.variant.id, quantity: l.qty }));
        let result;
        if (DEMO) {
          await new Promise((r) => setTimeout(r, 600));
          result = { order_no: 'UT-DEMO-' + Math.floor(1000 + Math.random() * 9000), total: totals(cart.lines()).total };
        } else {
          const { data: res, error } = await db.rpc('place_order', {
            p_name: data.name, p_phone: data.phone, p_address: data.address,
            p_area: data.area, p_notes: data.notes, p_items: items,
          });
          if (error) throw error;
          result = res;
        }
        try {
          localStorage.setItem('ut_customer', JSON.stringify({ name: data.name, phone: data.phone, area: data.area, address: data.address }));
          localStorage.setItem('ut_last_order', JSON.stringify({ no: result.order_no, phone: normPhone(data.phone), total: result.total }));
        } catch { /* ignore */ }
        cart.clear();
        location.hash = '#/done/' + encodeURIComponent(result.order_no);
      } catch (e2) {
        console.error(e2);
        err.textContent = e2.message || 'Something went wrong. Please try again.';
        err.hidden = false;
        btn.disabled = false; btn.textContent = `Place order, ${rs(totals(cart.lines()).total)}`;
      }
    });
  }

  // ── Order placed ──────────────────────────────────────────
  function renderDone(no) {
    const last = (() => { try { return JSON.parse(localStorage.getItem('ut_last_order')) || {}; } catch { return {}; } })();
    const w = state.settings.whatsapp;
    app.innerHTML = `
      <div class="success">
        <h1>Order placed</h1>
        <div class="stamp"><small>Order number</small><div class="orderno">${esc(no)}</div></div>
        ${last.no === no ? `<p>Total to pay on delivery: <strong>${rs(last.total)}</strong></p>` : ''}
        <p class="muted">We'll call or WhatsApp you shortly to confirm your order.</p>
        <div class="actions">
          <a class="btn primary" href="#/track?no=${encodeURIComponent(no)}&phone=${encodeURIComponent(last.phone || '')}">Track this order</a>
          ${w ? `<a class="btn ghost" target="_blank" rel="noopener" href="${waLink(w, `Hi! I just placed order ${no}.`)}">Message us on WhatsApp</a>` : ''}
          <a class="btn ghost" href="#/">Continue shopping</a>
        </div>
      </div>`;
  }

  // ── Track order ───────────────────────────────────────────
  const STEPS = [
    ['pending', 'Order received'],
    ['confirmed', 'Confirmed'],
    ['packed', 'Packed'],
    ['out_for_delivery', 'Out for delivery'],
    ['delivered', 'Delivered'],
  ];

  function renderTrack(params) {
    const last = (() => { try { return JSON.parse(localStorage.getItem('ut_last_order')) || {}; } catch { return {}; } })();
    const no = params.get('no') || last.no || '';
    const phone = params.get('phone') || last.phone || '';
    app.innerHTML = `
      <h1 class="page-title">Track your order</h1>
      <form class="panel track" id="tform">
        <div class="field"><label class="label" for="tno">Order number</label>
          <input class="input" id="tno" placeholder="UT-251113-1234" value="${esc(no)}" required></div>
        <div class="field"><label class="label" for="tphone">Mobile number used for the order</label>
          <input class="input" id="tphone" type="tel" placeholder="03XX-XXXXXXX" value="${esc(phone)}" required></div>
        <button class="btn primary block" type="submit">Check status</button>
      </form>
      <div id="tresult" class="track track-result"></div>`;
    const form = app.querySelector('#tform');
    const out = app.querySelector('#tresult');
    const check = async () => {
      const n = form.querySelector('#tno').value.trim();
      const p = form.querySelector('#tphone').value.trim();
      if (!n || !normPhone(p)) { out.innerHTML = '<div class="error">Enter your order number and mobile number.</div>'; return; }
      out.innerHTML = '<div class="skeleton" style="height:160px"></div>';
      try {
        let o;
        if (DEMO) {
          o = { order_no: n, status: 'packed', total: last.total || 4400, items: [{ name: 'Classic Hoodie', size: 'Medium', quantity: 2, price: 2200 }] };
        } else {
          const { data, error } = await db.rpc('track_order', { p_order_no: n, p_phone: p });
          if (error) throw error;
          o = data;
        }
        if (!o) { out.innerHTML = '<div class="panel">No order found with that number and mobile. Please check both.</div>'; return; }
        out.innerHTML = trackHtml(o);
      } catch (e) {
        out.innerHTML = `<div class="error">${esc(e.message || 'Could not check right now.')}</div>`;
      }
    };
    form.addEventListener('submit', (e) => { e.preventDefault(); check(); });
    if (no && phone) check();
  }

  function trackHtml(o) {
    const cancelled = o.status === 'cancelled' || o.status === 'rejected';
    const reached = STEPS.findIndex(([k]) => k === o.status);
    return `<div class="panel">
      <div class="sum"><strong>${esc(o.order_no)}</strong><strong>${rs(o.total)}</strong></div>
      ${(o.items || []).map((i) => `<div class="sum muted"><span>${i.quantity} × ${esc(i.name)} (${esc(short(i.size))})</span><span>${rs(i.price * i.quantity)}</span></div>`).join('')}
      ${cancelled
        ? `<div class="cancelled">Order ${o.status === 'rejected' ? 'could not be accepted' : 'cancelled'}${o.status_note ? `<div class="note">${esc(o.status_note)}</div>` : ''}</div>`
        : `<div class="progress">
            <div class="tape meter" aria-hidden="true"><span class="fill" style="width:${reached < 0 ? 0 : reached === STEPS.length - 1 ? 100 : ((reached + 0.5) / STEPS.length) * 100}%"></span></div>
            <ol>${STEPS.map(([, label], i) => `<li class="${i <= reached ? 'done' : ''}${i === reached ? ' current' : ''}"${i === reached ? ' aria-current="step"' : ''}>${label}</li>`).join('')}</ol>
          </div>`}
    </div>`;
  }

  // ── Info pages ────────────────────────────────────────────
  // Facts come from config.js (story, contact details, exchange rules,
  // size charts) and store_settings (WhatsApp, delivery fee). Anything not
  // filled in is left out or replaced with "message us", never guessed.
  const INFO = ['about', 'contact', 'delivery', 'exchanges', 'size-guide', 'faq', 'privacy', 'terms'];
  const HELP = [
    ['delivery', 'Delivery and payment'],
    ['exchanges', 'Exchanges'],
    ['size-guide', 'Size guide'],
    ['faq', 'FAQ'],
    ['contact', 'Contact us'],
  ];
  const list = (a) => (Array.isArray(a) ? a.filter(Boolean) : []);
  const waBtn = (text, label = 'Message us on WhatsApp', cls = 'primary') => state.settings.whatsapp
    ? `<a class="btn ${cls}" target="_blank" rel="noopener" href="${waLink(state.settings.whatsapp, text)}">${label}</a>` : '';
  const stepsHtml = (steps) => `<ol class="steps-n">${steps.map(([t, d]) =>
    `<li><div><strong>${t}</strong>${d ? `<p>${d}</p>` : ''}</div></li>`).join('')}</ol>`;
  const city = esc(CFG.city);

  function infoPage(key, title, lede, body) {
    document.title = `${title} | ${CFG.shopName || 'Urban Thread'}`;
    const inHelp = HELP.some(([k]) => k === key);
    app.innerHTML = `<article class="info info-${key}">
      <h1 class="page-title">${esc(title)}</h1>
      ${lede ? `<p class="lede">${lede}</p>` : ''}
      ${inHelp ? `<nav class="helpnav" aria-label="Help pages">${HELP.map(([k, l]) =>
        `<a href="#/${k}" class="chip ${k === key ? 'on' : ''}"${k === key ? ' aria-current="page"' : ''}>${l}</a>`).join('')}</nav>` : ''}
      <div class="prose">${body}</div>
    </article>`;
    // On phones the help menu scrolls sideways; bring the current page's pill into view.
    const on = app.querySelector('.helpnav .on');
    if (on) on.parentNode.scrollLeft = on.offsetLeft - on.parentNode.offsetLeft - 16;
    return app.querySelector('.prose');
  }

  function renderAbout() {
    const types = [...new Set(state.designs.map((d) => d.type).filter(Boolean))].map((t) => t.toLowerCase() + 's');
    const range = types.length > 1 ? `${types.slice(0, -1).join(', ')} and ${types[types.length - 1]}` : types[0] || 'clothes';
    const story = list(CFG.about).length ? list(CFG.about)
      : [`Urban Thread is a ${CFG.city} streetwear brand. We sell everyday ${range}, and deliver them to your door with cash on delivery.`];
    const facts = [
      ['Based in', CFG.city],
      ['Payment', 'Cash on delivery'],
      ['Delivery', `Anywhere in ${CFG.city}`],
      state.settings.whatsapp && ['WhatsApp', state.settings.whatsapp],
      CFG.instagram && ['Instagram', '@' + CFG.instagram],
    ].filter(Boolean);
    infoPage('about', 'About us', null, `
      <div class="about">
        <div>
          ${story.map((p) => `<p class="story">${esc(p)}</p>`).join('')}
          <h2>How ordering works</h2>
          ${stepsHtml([
            ['Pick your size and order', 'It takes about a minute. You get an order number straight away.'],
            ['We confirm with you', 'We call or WhatsApp you to check the order and your address.'],
            ['Pay when it arrives', 'Your order comes to your door. You pay cash on delivery.'],
          ])}
          <div class="actions-row"><a class="btn primary" href="#/">Shop the collection</a><a class="btn ghost" href="#/contact">Contact us</a></div>
        </div>
        <aside class="carelabel" aria-label="Urban Thread at a glance">
          <img src="assets/mark_on_dark.png" alt="">
          <ul>${facts.map(([k, v]) => `<li><small>${esc(k)}</small>${esc(v)}</li>`).join('')}</ul>
        </aside>
      </div>`);
  }

  function renderContact() {
    const w = state.settings.whatsapp;
    const tel = (n) => 'tel:' + String(n).replace(/[^\d+]/g, '');
    const cards = [
      w && `<div class="ccard"><h2>WhatsApp</h2><p>The quickest way to reach us.</p>
        <a class="value" target="_blank" rel="noopener" href="${waLink(w, `Hi ${CFG.shopName || 'Urban Thread'}!`)}">${esc(w)}</a></div>`,
      (CFG.phone || w) && `<div class="ccard"><h2>Call</h2><p>${CFG.hours ? esc(CFG.hours) : 'Give us a ring.'}</p>
        <a class="value" href="${tel(CFG.phone || w)}">${esc(CFG.phone || w)}</a></div>`,
      CFG.email && `<div class="ccard"><h2>Email</h2><p>For anything that needs more detail.</p>
        <a class="value" href="mailto:${esc(CFG.email)}">${esc(CFG.email)}</a></div>`,
      CFG.instagram && `<div class="ccard"><h2>Instagram</h2><p>New pieces and restocks.</p>
        <a class="value" target="_blank" rel="noopener" href="https://instagram.com/${encodeURIComponent(CFG.instagram)}">@${esc(CFG.instagram)}</a></div>`,
      CFG.address && `<div class="ccard"><h2>Visit</h2><p>${esc(CFG.address)}${CFG.hours ? `<br>${esc(CFG.hours)}` : ''}</p>
        <a class="value" target="_blank" rel="noopener" href="https://maps.google.com/?q=${encodeURIComponent(CFG.address)}">Open in Maps</a></div>`,
    ].filter(Boolean);
    const prose = infoPage('contact', 'Contact us',
      w ? 'Questions about sizes, an order or an exchange? Message us on WhatsApp and we’ll get back to you.' : null, `
      ${cards.length ? `<div class="contact-grid">${cards.join('')}</div>`
        : '<p>Contact details are coming soon.</p>'}
      ${w ? `
        <h2>Send us a message</h2>
        <form class="panel waform" id="waform">
          <div class="field"><label class="label" for="c-order">Order number (if it’s about an order)</label>
            <input class="input" id="c-order" placeholder="UT-251113-1234"></div>
          <div class="field"><label class="label" for="c-msg">Your message</label>
            <textarea class="input" id="c-msg" required placeholder="e.g. Is the Classic Hoodie true to size?"></textarea></div>
          <button class="btn primary block" type="submit">Send on WhatsApp</button>
          <p class="note">This opens WhatsApp with your message ready to send.</p>
          <div class="error" id="c-err" hidden></div>
        </form>` : ''}`);
    const form = prose.querySelector('#waform');
    form && form.addEventListener('submit', (e) => {
      e.preventDefault();
      const msg = form.querySelector('#c-msg').value.trim();
      const no = form.querySelector('#c-order').value.trim();
      const err = form.querySelector('#c-err');
      if (!msg) { err.textContent = 'Write your message first.'; err.hidden = false; return; }
      err.hidden = true;
      window.open(waLink(w, (no ? `Order ${no}: ` : '') + msg), '_blank', 'noopener');
    });
  }

  function renderDelivery() {
    const s = state.settings;
    const fee = Number(s.delivery_fee || 0);
    const facts = [
      ['Delivery charge', fee ? rs(fee) : 'Free'],
      s.free_delivery_over && fee ? ['Free delivery', `On orders over ${rs(s.free_delivery_over)}`] : null,
      ['Delivery time', CFG.deliveryTime || 'Confirmed when we call you'],
      ['Payment', 'Cash on delivery'],
    ].filter(Boolean);
    infoPage('delivery', 'Delivery and payment', `We deliver anywhere in ${city}, and you pay cash when your order arrives.`, `
      <div class="facts">${facts.map(([k, v]) => `<div class="fact"><small>${esc(k)}</small><strong>${esc(v)}</strong></div>`).join('')}</div>
      <h2>Where we deliver</h2>
      <p>Anywhere in ${city}, including ${AREAS.slice(0, 10).map(esc).join(', ')} and more. We don’t deliver outside ${city} yet.</p>
      <h2>How cash on delivery works</h2>
      ${stepsHtml([
        ['Place your order', 'You get an order number on screen straight away.'],
        ['We confirm it', 'We call or WhatsApp you to check your order and address.'],
        ['It’s packed and sent out', 'Check where it is any time on the <a href="#/track">Track order</a> page.'],
        ['Pay when it arrives', 'Pay the total in cash at your door. It helps to have the exact amount ready.'],
      ])}
      <h2>Paying</h2>
      <p>We only take cash on delivery for now. You don’t need a card or a bank account to order.</p>`);
  }

  function renderExchanges() {
    const days = Number(CFG.exchangeDays) || 0;
    const rules = list(CFG.exchangeRules);
    infoPage('exchanges', 'Exchanges', 'Wrong size? Message us and we’ll help you swap it.', `
      <h2>How to ask for an exchange</h2>
      ${stepsHtml([
        ['Message us', `Send us your order number on WhatsApp${days ? ` within ${days} days of delivery` : ''}.`],
        ['Tell us what you’d like instead', 'For example the same piece in a different size.'],
        ['We’ll arrange it', 'We’ll reply with the next steps.'],
      ])}
      ${rules.length ? `<h2>Things to know</h2><ul>${rules.map((r) => `<li>${esc(r)}</li>`).join('')}</ul>` : ''}
      <p>Not sure which size to pick next time? See the <a href="#/size-guide">size guide</a>.</p>
      <div class="actions-row">${waBtn('Hi! I’d like to exchange an item from order ', 'Ask for an exchange')}</div>`);
  }

  function renderSizeGuide() {
    const charts = list(CFG.sizeCharts).filter((c) => c && Array.isArray(c.rows) && c.rows.length);
    // Line drawings with the tape laid where each measurement is taken.
    const tee = `<svg viewBox="0 0 250 210" aria-hidden="true">
      <path d="M78 18 Q110 36 142 18 L190 40 L172 84 L152 75 L152 196 L68 196 L68 75 L48 84 L30 40 Z" fill="#fff" stroke="#1b2140" stroke-width="2.5" stroke-linejoin="round"/>
      <rect x="64" y="86" width="92" height="14" class="tp"/><text x="110" y="122" class="tl">Chest</text>
      <path d="M142 18 H212 M152 196 H212" stroke="#1b2140" stroke-width="1.2" stroke-dasharray="3 3"/>
      <rect x="204" y="18" width="14" height="178" class="tp"/><text x="234" y="107" class="tl" transform="rotate(90 234 107)">Length</text></svg>`;
    const trouser = `<svg viewBox="0 0 250 210" aria-hidden="true">
      <path d="M62 14 H158 L170 196 H124 L110 74 L96 196 H50 Z" fill="#fff" stroke="#1b2140" stroke-width="2.5" stroke-linejoin="round"/>
      <rect x="60" y="20" width="100" height="14" class="tp"/><text x="110" y="56" class="tl">Waist</text>
      <path d="M158 14 H212 M170 196 H212" stroke="#1b2140" stroke-width="1.2" stroke-dasharray="3 3"/>
      <rect x="204" y="14" width="14" height="182" class="tp"/><text x="234" y="105" class="tl" transform="rotate(90 234 105)">Length</text></svg>`;
    infoPage('size-guide', 'Size guide', 'Find your size once, then pick it on the tape. The shop remembers it for next time.', `
      <h2>How to measure</h2>
      <p>The easiest way is to measure clothes that already fit you well. Lay them flat on a table and smooth them out.</p>
      <div class="measure">
        <figure>${tee}<figcaption><strong>Tops</strong>
          <span><b>Chest:</b> straight across, from armpit to armpit.</span>
          <span><b>Length:</b> from the top of the shoulder down to the hem.</span></figcaption></figure>
        <figure>${trouser}<figcaption><strong>Trousers</strong>
          <span><b>Waist:</b> straight across the top of the waistband.</span>
          <span><b>Length:</b> from the waistband down to the hem, along the outside of the leg.</span></figcaption></figure>
      </div>
      ${charts.length ? `<h2>Size charts</h2>${charts.map((c) => `
        <h3>${esc(c.title || '')}</h3>
        <div class="table-wrap"><table class="chart">
          <thead><tr><th scope="col">Size</th>${list(c.columns).map((h) => `<th scope="col">${esc(h)}</th>`).join('')}</tr></thead>
          <tbody>${c.rows.map(([sz, ...vals]) => `<tr><th scope="row">${esc(short(sz))}</th>${vals.map((v) => `<td>${esc(v)}</td>`).join('')}</tr>`).join('')}</tbody>
        </table></div>
        ${c.unit ? `<p class="note">Measurements in ${esc(c.unit)}.</p>` : ''}`).join('')}`
      : `<div class="callout"><strong>Not sure which size to pick?</strong>
          <p>Send us your measurements on WhatsApp and we’ll tell you which size fits.</p>
          ${waBtn('Hi! Can you help me pick a size? My measurements are: ', 'Ask us about sizing')}</div>`}`);
  }

  function renderFaq() {
    const s = state.settings;
    const fee = Number(s.delivery_fee || 0);
    const qa = [
      ['How do I pay?', 'Cash on delivery. You pay in cash when your order arrives at your door. You don’t need a card or bank account.'],
      ['Where do you deliver?', `Anywhere in ${city}. We don’t deliver outside ${city} yet.`],
      ['How much is delivery?', (fee ? `${rs(fee)} per order.` : 'Delivery is free.')
        + (s.free_delivery_over && fee ? ` It’s free on orders over ${rs(s.free_delivery_over)}.` : '')],
      ['How long does delivery take?', CFG.deliveryTime
        ? `Usually ${esc(CFG.deliveryTime)}. We confirm it when we call you about your order.`
        : 'We’ll tell you when we call or WhatsApp you to confirm your order.'],
      ['How do I know my order went through?', 'You’ll see an order number as soon as you place it, and we’ll call or WhatsApp you to confirm.'],
      ['How do I track my order?', 'Go to <a href="#/track">Track order</a> and enter your order number and the mobile number you ordered with.'],
      ['How do I find my size?', 'See the <a href="#/size-guide">size guide</a>. Once you pick your size on the tape, the shop remembers it and picks it for you on each product.'],
      ['What if it doesn’t fit?', 'Message us and we’ll help you swap it. See <a href="#/exchanges">Exchanges</a>.'],
      ['Can I change or cancel my order?', 'Message us on WhatsApp with your order number as soon as you can, ideally before it’s sent out.'],
    ];
    infoPage('faq', 'FAQ', null, `
      <div class="faq">${qa.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join('')}</div>
      <div class="callout"><strong>Didn’t find your answer?</strong><p>Ask us directly.</p>
        <a class="btn primary" href="#/contact">Contact us</a></div>`);
  }

  function renderPrivacy() {
    const name = esc(CFG.shopName || 'Urban Thread');
    infoPage('privacy', 'Privacy policy', `What we collect when you order from ${name}, and why.`, `
      <p class="note">Last updated 14 November 2026</p>
      <h2>What we collect</h2>
      <p>When you place an order we collect your name, mobile number, area, delivery address and any notes you add, along with what you ordered.</p>
      <h2>Why we collect it</h2>
      <ul>
        <li>To confirm your order with you by phone or WhatsApp.</li>
        <li>To deliver your order to your address.</li>
        <li>To let you track your order with your order number and mobile number.</li>
      </ul>
      <h2>Who we share it with</h2>
      <p>We don’t sell your details. We only share your name, number and address with whoever delivers your order. Your order details are stored securely in our order system.</p>
      <h2>What this website keeps on your device</h2>
      <p>To save you retyping, your browser keeps your cart, the size you picked on the tape and the delivery details you last used. They stay on your device and you can remove them by clearing this site’s data in your browser.</p>
      <p>This website doesn’t use advertising or tracking cookies. Fonts are loaded from Google Fonts.</p>
      <h2>Your choices</h2>
      <p>To see, correct or delete the details we hold about you, <a href="#/contact">contact us</a>.</p>
      <p>See also our <a href="#/terms">terms and conditions</a>.</p>`);
  }

  // Written from how this store actually works: COD only, Lahore only,
  // orders confirmed by phone/WhatsApp, orders can be cancelled or not accepted.
  function renderTerms() {
    const name = esc(CFG.shopName || 'Urban Thread');
    infoPage('terms', 'Terms and conditions', `The rules for ordering from ${name}. Please read them before you place an order.`, `
      <p class="note">Last updated 14 November 2026</p>

      <h2>Using this website</h2>
      <p>By placing an order on this website you agree to these terms. “We”, “us” and “our” mean ${name}. “You” means the person placing the order.</p>

      <h2>Orders</h2>
      <ul>
        <li>When you place an order you get an order number. This means we’ve received it, not that it’s accepted yet.</li>
        <li>We call or WhatsApp you to confirm your order and address. Your order is accepted once we’ve confirmed it with you.</li>
        <li>We may cancel or not accept an order if we can’t reach you, if the address can’t be delivered to, if an item has sold out, or if the order details look wrong. If this happens we’ll tell you.</li>
        <li>To change or cancel an order, message us with your order number as soon as you can, ideally before it’s sent out.</li>
      </ul>

      <h2>Prices</h2>
      <ul>
        <li>All prices are in Pakistani rupees (Rs).</li>
        <li>The total you see at checkout includes the delivery charge. That is the amount you pay on delivery.</li>
        <li>Prices can change, but the price of an order we’ve confirmed with you won’t.</li>
        <li>If a price is clearly shown by mistake, we’ll contact you before sending your order, and you can choose to cancel it.</li>
      </ul>

      <h2>Payment</h2>
      <p>We only accept cash on delivery. You pay the full order total in cash when your order arrives.</p>

      <h2>Delivery</h2>
      <ul>
        <li>We deliver within ${city} only. See <a href="#/delivery">Delivery and payment</a> for charges${CFG.deliveryTime ? ' and delivery times' : ''}.</li>
        <li>Please make sure someone is available to receive the order and pay at the address you gave.</li>
        <li>If we can’t deliver after trying to reach you, we may cancel the order.</li>
        <li>If an order is refused at the door without a good reason, we may stop accepting cash-on-delivery orders from that mobile number.</li>
      </ul>

      <h2>Products</h2>
      <ul>
        <li>We try to show every piece accurately, but colours can look slightly different on different screens.</li>
        <li>Stock is limited. An item can sell out between the time you order and the time we confirm it. If that happens, we’ll tell you and you won’t be charged for it.</li>
        <li>Use the <a href="#/size-guide">size guide</a> to help you choose. If something doesn’t fit, see <a href="#/exchanges">Exchanges</a>.</li>
      </ul>

      <h2>Exchanges</h2>
      <p>How exchanges work is explained on the <a href="#/exchanges">Exchanges</a> page, which forms part of these terms.</p>

      <h2>Your information</h2>
      <p>How we use the details you give us is explained in our <a href="#/privacy">privacy policy</a>.</p>

      <h2>Changes to these terms</h2>
      <p>We may update these terms from time to time. The version on this page when you place your order is the one that applies to it.</p>

      <h2>Law</h2>
      <p>These terms are governed by the laws of Pakistan.</p>

      <h2>Questions</h2>
      <p>If anything here isn’t clear, <a href="#/contact">contact us</a> before you order.</p>`);
  }

  // ── Demo data (only with ?demo=1) ─────────────────────────
  function demoData() {
    // Flat-lay illustrations in assets/demo/ (pattern paper + measuring tape)
    // stand in for product photos.
    const img = (name) => `assets/demo/${name}.jpg`;
    const designs = [
      { id: 1, name: 'Classic Hoodie', type: 'Hoodie', price: 2200, photos: [img('hoodie-front'), img('hoodie-back')], description: 'Heavyweight cotton fleece, relaxed fit.', updated_at: '2026-11-13' },
      { id: 2, name: 'Slim Fit Trouser', type: 'Trouser', price: 1800, photos: [img('trouser')], description: 'Stretch twill with a tapered leg.', updated_at: '2026-11-12' },
      { id: 3, name: 'Graphic Tee', type: 'T-Shirt', price: 950, photos: [img('tee')], description: 'Soft cotton jersey with a Lahore 042 print.', updated_at: '2026-11-11' },
      { id: 4, name: 'Crew Sweatshirt', type: 'Sweatshirt', price: 1900, photos: [img('sweatshirt')], updated_at: '2026-11-10' },
    ];
    const variants = [
      { id: 11, design_id: 1, size: 'Small', price: 2200, stock: 6 },
      { id: 12, design_id: 1, size: 'Medium', price: 2200, stock: 0 },
      { id: 13, design_id: 1, size: 'Large', price: 2200, stock: 10 },
      { id: 14, design_id: 1, size: 'Extra Large', price: 2400, stock: 2 },
      { id: 21, design_id: 2, size: '30', price: 1800, stock: 4 },
      { id: 22, design_id: 2, size: '32', price: 1800, stock: 3 },
      { id: 23, design_id: 2, size: '34', price: 1800, stock: 1 },
      { id: 31, design_id: 3, size: 'Medium', price: 950, stock: 2 },
      { id: 41, design_id: 4, size: 'Large', price: 1900, stock: 8 },
    ];
    return { designs, variants, settings: { store_open: true, delivery_fee: 200, free_delivery_over: 5000, whatsapp: '0300-1234567' } };
  }

  // A photo that fails to load is hidden (its dark frame stays) instead of
  // showing a broken-image icon and alt text.
  document.addEventListener('error', (e) => {
    const el = e.target;
    if (el instanceof HTMLImageElement && !el.closest('.brand, .footer')) {
      el.style.visibility = 'hidden';
    }
  }, true);

  load();
})();
