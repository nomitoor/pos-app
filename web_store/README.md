# Urban Thread online store

A small static website (HTML + CSS + JavaScript, no build step) that shows the
products you switch **online** in the POS app and takes **cash-on-delivery**
orders in Lahore.

| File | What it is |
|---|---|
| `index.html` | The page shell |
| `styles.css` | "Cutting table" design: pattern-paper page, measuring-tape size filter |
| `app.js` | Shop, product page, cart, checkout, order tracking |
| `config.js` | Your Supabase URL + publishable key (public by design) |
| `assets/` | Logo files |

## Before it can take real orders
1. In Supabase → **SQL Editor**, run `../supabase/store.sql` once.
2. In the POS app: sign in (Settings → Cloud backup), open a product, add a
   photo and switch on **Online store**.

## Preview on your computer
Open `index.html` in Chrome. Add `?demo=1` to the address to see sample
products without touching your database:
`index.html?demo=1`

## Put it online for free (Netlify, ~2 minutes)
1. Go to <https://app.netlify.com/drop> and sign up with your email.
2. Drag the whole **`web_store`** folder onto the page.
3. Netlify gives you an address like `https://something.netlify.app`.
   In **Site configuration → Change site name** pick e.g. `urbanthread` →
   `https://urbanthread.netlify.app`.
4. To update the site later, drag the folder again (Deploys → drag & drop).

(Cloudflare Pages works the same way: Workers & Pages → Create → Pages →
Upload assets → drag the folder → you get `urbanthread.pages.dev`.)

## Info pages (About, Contact, Delivery, Exchanges, Size guide, FAQ, Privacy)
Fill in your story, email, Instagram, shop address, hours, delivery time,
exchange rules and size charts in `config.js`. Anything left empty is hidden
or replaced with "message us on WhatsApp", so nothing made up is ever shown.
Read the privacy policy page and change it if it doesn't match how you work.

## Store settings (delivery fee, WhatsApp, open/closed)
For now change them in Supabase → **Table Editor → store_settings**:
`delivery_fee` (default 200), `free_delivery_over` (e.g. 5000, or empty),
`whatsapp` (e.g. 0300-1234567), `store_open` (true/false).
