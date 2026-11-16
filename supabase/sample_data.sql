-- Sample products so the online store has something to show while you
-- set up real ones. Run AFTER store.sql: SQL Editor → New query → paste → Run.
--
-- • Uses ids 900001+ so they never clash with products from the POS.
-- • Photos are simple placeholder images (placehold.co).
-- • IMPORTANT: once you sign in to the POS as the shop owner, the POS syncs
--   its own products and REMOVES anything it doesn't know, including these
--   samples. That's expected: the POS is the master list.
-- • To remove them yourself, run the DELETE at the bottom.

insert into public.catalog_designs (id, name, type, description, price, photos, online, updated_at)
values
  (900001, 'Classic Hoodie', 'Hoodie',
   'Heavyweight cotton fleece hoodie with a relaxed fit and brushed inside. Perfect for Lahore winters.',
   2200,
   array['https://placehold.co/800x1000/2b2416/a68d50.png?text=Classic+Hoodie',
         'https://placehold.co/800x1000/1b1b1b/f5ece0.png?text=Hoodie+Back'],
   true, now()),
  (900002, 'Slim Fit Trouser', 'Trouser',
   'Stretch cotton twill with a tapered leg. Smart enough for work, easy for weekends.',
   1800,
   array['https://placehold.co/800x1000/23272e/f5ece0.png?text=Slim+Trouser'],
   true, now() - interval '1 hour'),
  (900003, 'Graphic Tee', 'T-Shirt',
   'Soft 100% cotton tee with the Urban Thread print.',
   950,
   array['https://placehold.co/800x1000/3a2a22/f5ece0.png?text=Graphic+Tee'],
   true, now() - interval '2 hours'),
  (900004, 'Crew Sweatshirt', 'Sweatshirt',
   'Midweight crew-neck sweatshirt in a clean, minimal cut.',
   1900,
   array['https://placehold.co/800x1000/262f28/f5ece0.png?text=Crew+Sweatshirt'],
   true, now() - interval '3 hours'),
  (900005, 'Denim Jacket', 'Jacket',
   'Classic trucker jacket in washed denim.',
   3800,
   array['https://placehold.co/800x1000/1c2433/f5ece0.png?text=Denim+Jacket'],
   true, now() - interval '4 hours'),
  (900006, 'Oxford Shirt', 'Shirt',
   'Button-down Oxford shirt, breathable and easy to iron.',
   1650,
   array['https://placehold.co/800x1000/2e2a24/a68d50.png?text=Oxford+Shirt'],
   true, now() - interval '5 hours')
on conflict (id) do update set
  name = excluded.name, type = excluded.type, description = excluded.description,
  price = excluded.price, photos = excluded.photos, online = excluded.online,
  updated_at = excluded.updated_at;

insert into public.catalog_variants (id, design_id, size, price, stock, updated_at)
values
  -- Classic Hoodie: Medium sold out, XL costs more
  (9000011, 900001, 'Small',       2200, 6,  now()),
  (9000012, 900001, 'Medium',      2200, 0,  now()),
  (9000013, 900001, 'Large',       2200, 10, now()),
  (9000014, 900001, 'Extra Large', 2400, 2,  now()),
  -- Slim Fit Trouser: waist sizes
  (9000021, 900002, '30', 1800, 4, now()),
  (9000022, 900002, '32', 1800, 3, now()),
  (9000023, 900002, '34', 1800, 1, now()),
  (9000024, 900002, '36', 1800, 0, now()),
  -- Graphic Tee: only a few left → "Few left" tag
  (9000031, 900003, 'Medium', 950, 2, now()),
  (9000032, 900003, 'Large',  950, 1, now()),
  -- Crew Sweatshirt
  (9000041, 900004, 'Small',  1900, 5, now()),
  (9000042, 900004, 'Medium', 1900, 7, now()),
  (9000043, 900004, 'Large',  1900, 8, now()),
  -- Denim Jacket
  (9000051, 900005, 'Medium',      3800, 3, now()),
  (9000052, 900005, 'Large',       3800, 4, now()),
  (9000053, 900005, 'Extra Large', 3800, 2, now()),
  -- Oxford Shirt
  (9000061, 900006, 'Small',       1650, 4, now()),
  (9000062, 900006, 'Medium',      1650, 6, now()),
  (9000063, 900006, 'Large',       1650, 5, now()),
  (9000064, 900006, 'XXL',         1750, 2, now())
on conflict (id) do update set
  design_id = excluded.design_id, size = excluded.size, price = excluded.price,
  stock = excluded.stock, updated_at = excluded.updated_at;

-- Optional: show a WhatsApp number on the website and free delivery over
-- Rs 5,000. Uncomment and edit to use.
-- update public.store_settings
--   set whatsapp = '0300-1234567', free_delivery_over = 5000
--   where id = 1;

-- ─── To remove the samples later ───
-- delete from public.catalog_designs where id between 900001 and 900999;
-- (their sizes are removed automatically)
