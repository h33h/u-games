'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require.resolve('../ad-adapter.js'), 'utf8');

function page(sdk, storage = new Map()) {
  const context = vm.createContext({
    setTimeout,
    clearTimeout,
    setInterval: () => 1,
    clearInterval() {},
    localStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
    },
    YaGames: { init: () => Promise.resolve(sdk) },
  });
  context.window = context;
  vm.runInContext(source, context);
  return context;
}

function fixture(id = '123') {
  let charges = 0,
    reads = 0,
    consumes = 0;
  const product = {
    id: 'gold500',
    title: '500 золота',
    description: 'Золото',
    imageURI: 'gold.png',
    price: '99 ЯН',
    priceValue: '99',
    priceCurrencyCode: 'YAN',
    getPriceCurrencyImage: () => 'yan.png',
  };
  const payments = {
    purchase() {
      charges++;
      return Promise.resolve({ productID: 'charged' });
    },
    getPurchases() {
      reads++;
      return Promise.resolve([]);
    },
    consumePurchase() {
      consumes++;
      return Promise.resolve();
    },
    getCatalog() {
      assert.equal(this, payments);
      return Promise.resolve([product]);
    },
  };
  const sdk = {
    environment: { app: { id } },
    payments,
    getPayments() {
      assert.equal(this, sdk);
      return Promise.resolve(payments);
    },
  };
  return { sdk, product, calls: () => [charges, reads, consumes] };
}

for (const access of ['payments', 'getPayments']) {
  test(`${access}: purchase grants a local receipt without real payment`, async () => {
    const f = fixture(),
      win = page(f.sdk);
    const sdk = await win.YaGames.init();
    const payments = access === 'payments' ? sdk.payments : await sdk.getPayments();
    const receipt = await payments.purchase({ id: 'gold500', developerPayload: 'level7' });
    assert.equal(receipt.productID, 'gold500');
    assert.equal(receipt.developerPayload, 'level7');
    assert.match(receipt.purchaseToken, /^ugames-free-/);
    const second = await payments.purchase({ id: 'gold500' });
    assert.notEqual(second.purchaseToken, receipt.purchaseToken);
    assert.equal(second.developerPayload, '');
    assert.deepEqual(f.calls(), [0, 0, 0]);
  });
}

test('catalog retains product metadata but shows a zero price', async () => {
  const f = fixture();
  const sdk = await page(f.sdk).YaGames.init();
  const [product] = await sdk.payments.getCatalog();
  assert.equal(product.id, 'gold500');
  assert.equal(product.title, '500 золота');
  assert.equal(product.imageURI, 'gold.png');
  assert.equal(product.price, 'Бесплатно');
  assert.equal(product.priceValue, '0');
  assert.equal(product.priceCurrencyCode, 'YAN');
  assert.equal(product.getPriceCurrencyImage('small'), 'yan.png');
  assert.equal(f.product.priceValue, '99');
});

test('receipts survive reload, are isolated by game and are consumed locally', async () => {
  const storage = new Map(),
    f = fixture();
  const payments = (await page(f.sdk, storage).YaGames.init()).payments;
  const receipt = await payments.purchase({ id: 'gold500' });
  receipt.purchaseData.productID = 'tampered';
  const reloaded = (await page(fixture().sdk, storage).YaGames.init()).payments;
  const pending = await reloaded.getPurchases();
  assert.equal(pending.length, 1);
  assert.equal(pending[0].productID, 'gold500');
  pending[0].purchaseData.productID = 'tampered';
  assert.equal((await reloaded.getPurchases())[0].productID, 'gold500');
  const other = (await page(fixture('456').sdk, storage).YaGames.init()).payments;
  assert.equal((await other.getPurchases()).length, 0);
  await reloaded.consumePurchase(receipt.purchaseToken);
  assert.equal((await reloaded.getPurchases()).length, 0);
  const afterReload = (await page(fixture().sdk, storage).YaGames.init()).payments;
  assert.equal((await afterReload.getPurchases()).length, 0);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('invalid requests never reach real purchase or consumption', async () => {
  const f = fixture(),
    sdk = await page(f.sdk).YaGames.init();
  for (const data of [undefined, {}, { id: '' }, { id: 42 }]) {
    await assert.rejects(sdk.payments.purchase(data), /product/i);
  }
  await assert.rejects(sdk.payments.consumePurchase('real-token'), /purchase/i);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

for (const mode of ['init', 'getPayments']) {
  test(`signed ${mode} still grants a local receipt without inventing a server signature`, async () => {
    const f = fixture(),
      win = page(f.sdk);
    const sdk = await win.YaGames.init(mode === 'init' ? { signed: true } : undefined);
    const payments = mode === 'init' ? sdk.payments : await sdk.getPayments({ signed: true });
    const receipt = await payments.purchase({ id: 'gold500' });
    assert.equal(receipt.productID, 'gold500');
    assert.equal(receipt.signature, undefined);
    const pending = await payments.getPurchases();
    assert.equal(pending.length, 1);
    assert.equal(pending.signature, undefined);
    assert.equal(win.__UGamesAdapter.payments.signedRequested, true);
    assert.equal(win.__UGamesAdapter.payments.signatureAvailable, false);
    assert.deepEqual(f.calls(), [0, 0, 0]);
  });
}

test('late payments publication and repeated init remain protected', async () => {
  const f = fixture(),
    original = f.sdk.payments;
  delete f.sdk.payments;
  const win = page(f.sdk),
    sdk = await win.YaGames.init();
  sdk.payments = original;
  await sdk.payments.purchase({ id: 'gold500' });
  await win.YaGames.init();
  assert.equal((await sdk.payments.getPurchases()).length, 1);
  sdk.payments.purchase = () => {
    throw new Error('real payment');
  };
  await win.YaGames.init();
  await sdk.payments.purchase({ id: 'gold500' });
  assert.equal((await sdk.payments.getPurchases()).length, 2);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('frozen payments are supported through a local facade', async () => {
  const f = fixture();
  Object.freeze(f.sdk.payments);
  const win = page(f.sdk),
    sdk = await win.YaGames.init();
  const receipt = await sdk.payments.purchase('gold500');
  assert.equal(receipt.productID, 'gold500');
  assert.equal(win.__UGamesAdapter.status, 'active');
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('unavailable local storage still allows free purchases in memory', async () => {
  const f = fixture(),
    win = page(f.sdk);
  win.localStorage = {
    getItem() {
      throw new Error('denied');
    },
    setItem() {
      throw new Error('denied');
    },
  };
  const sdk = await win.YaGames.init();
  const receipt = await sdk.payments.purchase({ id: 'gold500' });
  assert.equal((await sdk.payments.getPurchases()).length, 1);
  await sdk.payments.consumePurchase(receipt.purchaseToken);
  assert.equal((await sdk.payments.getPurchases()).length, 0);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('reinitializing in signed mode preserves local receipts and reports the signature limitation', async () => {
  const f = fixture(),
    win = page(f.sdk);
  await win.YaGames.init();
  const sdk = await win.YaGames.init({ signed: true });
  const first = await sdk.payments.purchase('gold500');
  const payments = await sdk.getPayments();
  const second = await payments.purchase({ id: 'gold500' });
  assert.equal(first.signature, undefined);
  assert.equal(second.signature, undefined);
  assert.equal((await payments.getPurchases()).length, 2);
  assert.equal(win.__UGamesAdapter.payments.signedRequested, true);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('SDK exposing only getPayments is protected before its first purchase', async () => {
  const f = fixture();
  delete f.sdk.payments;
  const sdk = await page(f.sdk).YaGames.init();
  const payments = await sdk.getPayments();
  const receipt = await payments.purchase({ id: 'gold500' });
  assert.equal(receipt.productID, 'gold500');
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('payments published with a property descriptor are protected synchronously', async () => {
  const f = fixture(),
    original = f.sdk.payments;
  delete f.sdk.payments;
  const win = page(f.sdk);
  win.fixturePayments = original;
  win.sdk = await win.YaGames.init();
  const receipt = await vm.runInContext(
    "Object.defineProperty(sdk, 'payments', { value: fixturePayments }); sdk.payments.purchase({ id: 'gold500' });",
    win,
  );
  assert.equal(receipt.productID, 'gold500');
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('legacy string purchase and SDK purchaseData serialize like native SDK receipts', async () => {
  const f = fixture(),
    sdk = await page(f.sdk).YaGames.init();
  const receipt = await sdk.payments.purchase('gold500');
  assert.equal(receipt.purchaseData.productID, 'gold500');
  assert.equal(receipt.purchaseData.purchaseToken, receipt.purchaseToken);
  const serialized = JSON.parse(JSON.stringify(receipt));
  assert.deepEqual(Object.keys(serialized).sort(), [
    'developerPayload',
    'productID',
    'purchaseToken',
  ]);
  assert.equal(serialized.productID, 'gold500');
  assert.equal(serialized.developerPayload, '');
  const pending = JSON.parse(JSON.stringify(await sdk.payments.getPurchases()));
  assert.deepEqual(pending, [serialized]);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('invalid payload is rejected with a diagnostic and does not create a receipt', async () => {
  const f = fixture(),
    win = page(f.sdk),
    sdk = await win.YaGames.init();
  await assert.rejects(
    sdk.payments.purchase({ id: 'gold500', developerPayload: { secret: 'no' } }),
    (error) => error.code === 'INVALID_DEVELOPER_PAYLOAD',
  );
  assert.equal((await sdk.payments.getPurchases()).length, 0);
  assert.equal(win.__UGamesAdapter.payments.lastError, 'INVALID_DEVELOPER_PAYLOAD');
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('free purchase does not require provider initialization or authorization', async () => {
  const f = fixture();
  delete f.sdk.payments;
  let initializations = 0;
  f.sdk.getPayments = () => {
    initializations++;
    return Promise.reject(new Error('Unauthorized'));
  };
  const win = page(f.sdk),
    sdk = await win.YaGames.init();
  const payments = await sdk.getPayments({ signed: true });
  const receipt = await payments.purchase('gold500');
  assert.equal(receipt.productID, 'gold500');
  assert.equal(initializations, 0);
  await assert.rejects(payments.getCatalog(), /Unauthorized/);
  assert.equal(initializations, 1);
  assert.equal(win.__UGamesAdapter.payments.lastError, 'CATALOG_UNAVAILABLE');
  await payments.consumePurchase(receipt.purchaseToken);
  assert.equal((await payments.getPurchases()).length, 0);
  assert.equal(win.__UGamesAdapter.payments.consumed, 1);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('catalog retains metadata supplied through prototype getters', async () => {
  const f = fixture();
  const product = Object.create({
    get id() {
      return 'gold500';
    },
    get title() {
      return '500 золота';
    },
    get description() {
      return 'Золото';
    },
    get imageURI() {
      return 'gold.png';
    },
    get priceCurrencyCode() {
      return 'YAN';
    },
    getPriceCurrencyImage(size) {
      assert.equal(this, product);
      return size + '.png';
    },
  });
  f.sdk.payments.getCatalog = () => Promise.resolve([product]);
  const sdk = await page(f.sdk).YaGames.init();
  const [entry] = await sdk.payments.getCatalog();
  assert.equal(entry.id, 'gold500');
  assert.equal(entry.title, '500 золота');
  assert.equal(entry.description, 'Золото');
  assert.equal(entry.imageURI, 'gold.png');
  assert.equal(entry.priceCurrencyCode, 'YAN');
  assert.equal(entry.getPriceCurrencyImage('svg'), 'svg.png');
  assert.equal(entry.priceValue, '0');
});

test('unknown consumption token has a diagnostic and preserves pending purchases', async () => {
  const f = fixture(),
    win = page(f.sdk),
    sdk = await win.YaGames.init();
  await sdk.payments.purchase('gold500');
  await assert.rejects(
    sdk.payments.consumePurchase('real-token'),
    (error) => error.code === 'UNKNOWN_LOCAL_PURCHASE',
  );
  assert.equal((await sdk.payments.getPurchases()).length, 1);
  assert.equal(win.__UGamesAdapter.payments.lastError, 'UNKNOWN_LOCAL_PURCHASE');
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('local payment availability is independent of portal availability and other SDK checks retain their receiver', async () => {
  const f = fixture(),
    checks = [];
  f.sdk.isAvailableMethod = function (method) {
    assert.equal(this, f.sdk);
    checks.push(method);
    return Promise.resolve(method === 'leaderboards.getLeaderboardEntries');
  };
  const sdk = await page(f.sdk).YaGames.init();
  for (const method of [
    'getPayments',
    'payments.purchase',
    'payments.getPurchases',
    'payments.consumePurchase',
    'payments.getCatalog',
  ]) {
    assert.equal(await sdk.isAvailableMethod(method), true);
  }
  assert.equal(await sdk.isAvailableMethod('leaderboards.getLeaderboardEntries'), true);
  assert.equal(await sdk.isAvailableMethod('payments.unknownMethod'), false);
  assert.deepEqual(checks, ['leaderboards.getLeaderboardEntries', 'payments.unknownMethod']);
  assert.deepEqual(f.calls(), [0, 0, 0]);
});

test('two live pages share purchases without overwriting or consuming each others receipts', async () => {
  const storage = new Map();
  const a = (await page(fixture().sdk, storage).YaGames.init()).payments;
  const b = (await page(fixture().sdk, storage).YaGames.init()).payments;
  const one = await a.purchase('one');
  const two = await b.purchase('two');
  assert.deepEqual(
    Array.from(await a.getPurchases(), (p) => p.productID),
    ['one', 'two'],
  );
  assert.deepEqual(
    Array.from(await b.getPurchases(), (p) => p.productID),
    ['one', 'two'],
  );
  await a.consumePurchase(one.purchaseToken);
  assert.deepEqual(
    Array.from(await b.getPurchases(), (p) => p.productID),
    ['two'],
  );
  const reloaded = (await page(fixture().sdk, storage).YaGames.init()).payments;
  assert.deepEqual(
    Array.from(await reloaded.getPurchases(), (p) => p.productID),
    ['two'],
  );
  await b.consumePurchase(two.purchaseToken);
  assert.equal((await reloaded.getPurchases()).length, 0);
});
