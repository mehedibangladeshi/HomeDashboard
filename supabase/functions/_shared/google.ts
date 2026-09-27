type TokenResponse = {
  access_token: string;
  expires_in: number;
  refresh_token?: string;
};

function encryptionKey(): Promise<CryptoKey> {
  const encoded = Deno.env.get("TOKEN_ENCRYPTION_KEY");
  if (!encoded) throw new Error("TOKEN_ENCRYPTION_KEY is not configured");
  const bytes = Uint8Array.from(
    atob(encoded),
    (character) => character.charCodeAt(0),
  );
  if (bytes.length !== 32) {
    throw new Error("TOKEN_ENCRYPTION_KEY must be 32 bytes in base64");
  }
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

export async function encryptSecret(value: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await encryptionKey(),
    new TextEncoder().encode(value),
  );
  return JSON.stringify({
    iv: btoa(String.fromCharCode(...iv)),
    value: btoa(String.fromCharCode(...new Uint8Array(encrypted))),
  });
}

export async function decryptSecret(payload: string): Promise<string> {
  const parsed = JSON.parse(payload);
  const iv = Uint8Array.from(
    atob(parsed.iv),
    (character) => character.charCodeAt(0),
  );
  const encrypted = Uint8Array.from(
    atob(parsed.value),
    (character) => character.charCodeAt(0),
  );
  const clear = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    await encryptionKey(),
    encrypted,
  );
  return new TextDecoder().decode(clear);
}

export async function exchangeCode(code: string): Promise<TokenResponse> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: Deno.env.get("GOOGLE_CLIENT_ID")!,
      client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
      redirect_uri: Deno.env.get("GOOGLE_OAUTH_REDIRECT_URL")!,
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) {
    throw new Error(`Google code exchange failed (${response.status})`);
  }
  return response.json();
}

export async function refreshAccessToken(
  encryptedRefreshToken: string,
): Promise<string> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: await decryptSecret(encryptedRefreshToken),
      client_id: Deno.env.get("GOOGLE_CLIENT_ID")!,
      client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
      grant_type: "refresh_token",
    }),
  });
  if (!response.ok) {
    throw new Error(`Google token refresh failed (${response.status})`);
  }
  return (await response.json()).access_token;
}

export async function googleRequest<T>(
  accessToken: string,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(
    `https://www.googleapis.com/calendar/v3${path}`,
    {
      ...init,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    },
  );
  if (!response.ok) {
    const error = new Error(
      `Google Calendar request failed (${response.status})`,
    );
    Object.assign(error, { status: response.status });
    throw error;
  }
  return response.status === 204 ? (undefined as T) : response.json();
}

export function googleDateTime(value: string) {
  return { dateTime: new Date(value).toISOString() };
}
