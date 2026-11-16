// Urban Thread online store settings.
// The publishable key is meant to be public: your data is protected by the
// database rules in supabase/store.sql, not by hiding this key.
window.STORE_CONFIG = {
  supabaseUrl: 'https://fqxnsybzrplycikmanei.supabase.co',
  supabaseKey: 'sb_publishable_d5LIDDwLDbuZ7ehvBsZdfw_aKZ9zHeS',
  shopName: 'Urban Thread',
  city: 'Lahore',

  // ── Info pages (About, Contact, Delivery, Exchanges, Size guide, FAQ) ──
  // Leave anything empty ('' or []) and the page leaves it out or falls back
  // to "message us on WhatsApp". Nothing here is shown until you fill it in.
  // The WhatsApp number, delivery fee and free-delivery amount come from the
  // store_settings table in Supabase, not from here.

  // Your story, one paragraph per item. Empty = a short default line.
  about: [
    // 'Urban Thread started in 2024 in ...',
  ],

  email: '',          // e.g. 'hello@urbanthread.pk'
  phone: '',          // call number, if different from WhatsApp, e.g. '0300-1234567'
  instagram: '',      // handle without @, e.g. 'urbanthread.pk'
  address: '',        // shop address, only if customers can visit
  hours: '',          // e.g. 'Monday to Saturday, 12 pm to 9 pm'

  deliveryTime: '',   // e.g. '2 to 3 working days'

  // Exchanges. exchangeDays: 0 means the page doesn't promise a number of days.
  exchangeDays: 0,    // e.g. 7
  exchangeRules: [
    // 'Items must be unworn, unwashed and have their tags on.',
    // 'Delivery charges are not refunded.',
  ],

  // Size charts. Empty = the size guide shows how to measure and asks
  // customers to message their measurements instead.
  sizeCharts: [
    // { title: 'Hoodies and sweatshirts', unit: 'inches',
    //   columns: ['Chest', 'Length'],
    //   rows: [['S', 40, 26], ['M', 42, 27], ['L', 44, 28], ['XL', 46, 29]] },
  ],
};
