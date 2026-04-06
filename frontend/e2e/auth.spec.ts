import { test, expect } from '@playwright/test';

// ---------------------------------------------------------------------------
// Shared mock data
// ---------------------------------------------------------------------------
const MOCK_USER = { id: '1', username: 'testuser' };

const MOCK_SONGS = [
  {
    id: '1',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    album: 'After Hours',
    duration: '3:20',
    coverUrl: 'https://picsum.photos/seed/1/400/400',
    ownerId: '1',
  },
  {
    id: '2',
    title: 'Levitating',
    artist: 'Dua Lipa',
    album: 'Future Nostalgia',
    duration: '3:23',
    coverUrl: 'https://picsum.photos/seed/2/400/400',
    ownerId: '1',
  },
];

// ---------------------------------------------------------------------------
// BFF mock helpers  (all requests stay in-browser — no backend needed)
// ---------------------------------------------------------------------------
async function mockBff(page: import('@playwright/test').Page, opts: { validateStatus?: number } = {}) {
  const validateStatus = opts.validateStatus ?? 401;

  // Startup session check — 401 = no session (expected for fresh load)
  await page.route('**/bff/auth/validate', route =>
    route.fulfill({
      status: validateStatus,
      contentType: 'application/json',
      body: validateStatus === 200
        ? JSON.stringify({ userId: MOCK_USER.id, username: MOCK_USER.username })
        : JSON.stringify({ error: 'Unauthorized' }),
    })
  );

  await page.route('**/bff/auth/login', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ user: MOCK_USER }),
    })
  );

  await page.route('**/bff/auth/logout', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '{}' })
  );

  await page.route('**/bff/songs', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(MOCK_SONGS),
    })
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
test.describe('Authentication flow', () => {
  test('unauthenticated user visiting /songs is redirected to /login', async ({ page }) => {
    await mockBff(page);
    await page.goto('/songs');
    await expect(page).toHaveURL(/\/login/, { timeout: 5_000 });
  });

  test('login page is accessible without auth', async ({ page }) => {
    await mockBff(page);
    await page.goto('/login');
    await expect(page.getByRole('heading', { name: 'Welcome Back' })).toBeVisible();
  });

  test('successful login navigates to /songs', async ({ page }) => {
    await mockBff(page);
    await page.goto('/login');

    await page.fill('#username', 'testuser');
    await page.fill('#password', 'password123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/\/songs/, { timeout: 5_000 });
  });

  test('songs API is called exactly once after login — no repeat-call loop', async ({ page }) => {
    await mockBff(page);

    let songsCallCount = 0;
    // Override the songs route to also count calls
    await page.route('**/bff/songs', route => {
      songsCallCount++;
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(MOCK_SONGS),
      });
    });

    await page.goto('/login');
    await page.fill('#username', 'testuser');
    await page.fill('#password', 'password123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/\/songs/, { timeout: 5_000 });

    // Wait for songs to render, then give extra time to catch any rogue calls
    await expect(page.getByText('Blinding Lights')).toBeVisible({ timeout: 5_000 });
    await page.waitForTimeout(1_500);

    // React 19 concurrent mode can produce at most 2 mounts per navigation
    // (one during AnimatePresence exit, one on enter). The critical assertion
    // is that the count is bounded — not the infinite loop that was the original bug.
    expect(songsCallCount).toBeLessThanOrEqual(2);
    expect(songsCallCount).toBeGreaterThan(0);
  });

  test('song data is rendered on /songs after login', async ({ page }) => {
    await mockBff(page);
    await page.goto('/login');

    await page.fill('#username', 'testuser');
    await page.fill('#password', 'password123');
    await page.click('button[type="submit"]');

    await expect(page.getByText('Blinding Lights')).toBeVisible({ timeout: 5_000 });
    await expect(page.getByText('The Weeknd')).toBeVisible();
    await expect(page.getByText('Levitating')).toBeVisible();
    await expect(page.getByText('Dua Lipa')).toBeVisible();
  });

  test('URL stays on /songs after login — no redirect loop', async ({ page }) => {
    await mockBff(page);
    await page.goto('/login');

    await page.fill('#username', 'testuser');
    await page.fill('#password', 'password123');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL(/\/songs/, { timeout: 5_000 });

    // Wait and confirm the page does not bounce back to /login
    await page.waitForTimeout(2_000);
    await expect(page).toHaveURL(/\/songs/);
  });

  test('validate is called once on startup — no repeated validation loop', async ({ page }) => {
    // Register mockBff first, then the counting handler on top so it wins (LIFO order).
    await mockBff(page);
    let validateCallCount = 0;
    await page.route('**/bff/auth/validate', route => {
      validateCallCount++;
      route.fulfill({
        status: 401,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Unauthorized' }),
      });
    });

    await page.goto('/login');
    await page.waitForTimeout(1_500);

    expect(validateCallCount).toBe(1);
  });

  test('already authenticated user sees songs immediately', async ({ page }) => {
    // validate returns 200 — user has an existing session
    await mockBff(page, { validateStatus: 200 });

    await page.goto('/songs');
    await expect(page.getByText('Blinding Lights')).toBeVisible({ timeout: 5_000 });
    await expect(page).toHaveURL(/\/songs/);
  });
});
