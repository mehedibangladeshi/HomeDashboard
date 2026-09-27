import { randomUUID } from 'node:crypto';

export async function seedLocal(status) {
  const url = new URL(status.API_URL);
  if (!['localhost', '127.0.0.1'].includes(url.hostname)) {
    throw new Error('Fixture data must never be installed in a cloud project.');
  }
  const key = status.SERVICE_ROLE_KEY;
  async function request(path, body, token = key, method = 'POST') {
    const response = await fetch(`${status.API_URL}${path}`, {
      method,
      headers: {
        apikey: status.ANON_KEY,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`Local fixture request failed (${response.status}): ${await response.text()}`);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }
  const users = (await request('/auth/v1/admin/users', undefined, key, 'GET')).users;
  const identities = {};
  for (const name of ['owner', 'manager', 'member', 'other']) {
    const email = `${name}@home.test`;
    let user = users.find(candidate => candidate.email === email);
    // Password exists only in local fixtures; UI still uses real email links.
    const password = `Local-${randomUUID()}-aA1!`;
    if (!user) {
      user = await request('/auth/v1/admin/users', {
        email, password, email_confirm: true,
        user_metadata: { full_name: `Test ${name}` },
      });
    }
    identities[name] = user.id;
  }
  for (const [name, title] of [['owner', 'Test Family'], ['other', 'Isolated Test Home']]) {
    const membership = await request(`/rest/v1/memberships?user_id=eq.${identities[name]}`, undefined, key, 'GET');
    if (membership.length) continue;
    const link = await request('/auth/v1/admin/generate_link', { type: 'magiclink', email: `${name}@home.test` });
    const session = await request('/auth/v1/verify', { token_hash: link.hashed_token, type: 'magiclink' });
    const householdId = await request('/rest/v1/rpc/create_household', {
      household_name: title, currency: 'BDT', timezone: 'Asia/Dhaka',
    }, session.access_token);
    if (name !== 'owner') continue;
    await request('/rest/v1/memberships', ['manager', 'member'].map(role => ({
      household_id: householdId, user_id: identities[role], role,
    })));
    const categories = await request(`/rest/v1/categories?household_id=eq.${householdId}`, undefined, key, 'GET');
    await request('/rest/v1/rpc/create_purchase', {
      p_client_mutation_id: '10000000-0000-4000-8000-000000000001',
      p_household_id: householdId, p_summary: 'Weekly groceries', p_total_minor: 245000,
      p_currency_code: 'BDT', p_incurred_at: new Date().toISOString(),
      p_payer_user_id: identities.owner,
      p_category_id: categories.find(category => category.name === 'Groceries').id,
      p_payment_source_id: null, p_note: 'Local sample data',
      p_items: [{ name: 'Weekly groceries', amount_minor: 245000 }],
    }, session.access_token);
    await request('/rest/v1/rpc/create_chore', {
      p_household_id: householdId, p_title: 'Take out recycling', p_description: null,
      p_assignee_user_id: identities.member, p_frequency: 'weekly',
      p_starts_at: new Date(Date.now() + 7200000).toISOString(),
    }, session.access_token);
    await request('/rest/v1/household_events', {
      household_id: householdId, title: 'Family dinner',
      starts_at: new Date(Date.now() + 86400000).toISOString(),
      ends_at: new Date(Date.now() + 90000000).toISOString(), created_by: identities.owner,
    }, session.access_token);
  }
}
