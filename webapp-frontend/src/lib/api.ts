import type { AuthResponse, Song, CreateSongPayload } from '../types';

// ---------------------------------------------------------------------------
// APIM mode flag and credentials
//
// These vars are embedded into the browser bundle via the `env` block in
// next.config.ts. The CC grant uses these to obtain an application-scoped
// token from APIM. Next.js rewrites (next.config.ts) forward all requests,
// including /apim/token, to the correct backend — handling self-signed TLS
// (NODE_TLS_REJECT_UNAUTHORIZED=0 in dev) and CORS.
// ---------------------------------------------------------------------------
const APIM_ENABLED     = process.env.APIM_ENABLED === 'true';
const APIM_CLIENT_ID   = process.env.APIM_CLIENT_ID   ?? '';
const APIM_CLIENT_SECRET = process.env.APIM_CLIENT_SECRET ?? '';

// ---------------------------------------------------------------------------
// CC token cache (application-scoped, 1-hour TTL)
// ---------------------------------------------------------------------------
interface TokenCache { token: string; expiresAt: number; }
let apimTokenCache: TokenCache | null = null;

async function getApimToken(): Promise<string> {
  const now = Date.now();
  if (apimTokenCache && apimTokenCache.expiresAt - now > 60_000) {
    return apimTokenCache.token;
  }

  const credentials = btoa(`${APIM_CLIENT_ID}:${APIM_CLIENT_SECRET}`);
  const res = await fetch('/apim/token', {
    method:  'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Authorization:  `Basic ${credentials}`,
    },
    body: 'grant_type=client_credentials',
  });

  if (!res.ok) throw new Error('Failed to obtain APIM application token');

  const data = await res.json() as { access_token: string; expires_in: number };
  apimTokenCache = {
    token:     data.access_token,
    expiresAt: now + (data.expires_in - 60) * 1000,
  };
  return apimTokenCache.token;
}

// ---------------------------------------------------------------------------
// Core fetch wrapper
//
// APIM mode  — two tokens per request:
//   Authorization:          Bearer <cc_token>   APIM gateway validation
//   X-Sonicwave-User-Auth:  Bearer <user_jwt>   backend user-identity check
//     • APIM validates the CC token and strips Authorization before forwarding.
//     • Both auth_service (validate) and webapp_backend read X-Sonicwave-User-Auth.
//
// Direct mode — single token:
//   Authorization: Bearer <user_jwt>   auth_service / webapp_backend validate directly
// ---------------------------------------------------------------------------
async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  };

  if (APIM_ENABLED) {
    const ccToken = await getApimToken();
    headers['Authorization'] = `Bearer ${ccToken}`;

    const userJwt = localStorage.getItem('token');
    if (userJwt) {
      headers['X-Sonicwave-User-Auth'] = `Bearer ${userJwt}`;
    }
  } else {
    const userJwt = localStorage.getItem('token');
    if (userJwt) {
      headers['Authorization'] = `Bearer ${userJwt}`;
    }
  }

  const response = await fetch(path, { ...options, headers });

  if (response.status === 401) {
    window.dispatchEvent(new CustomEvent('auth:unauthorized'));
    throw new Error('Unauthorized');
  }

  if (!response.ok) {
    let message = `Request failed with status ${response.status}`;
    try {
      const body = await response.json();
      if (typeof body?.error === 'string') message = body.error;
    } catch { /* keep status-code message */ }
    throw new Error(message);
  }

  return response.json() as Promise<T>;
}

// ---------------------------------------------------------------------------
// Auth API  (/api/auth/* → proxy → [APIM →] auth_service)
// ---------------------------------------------------------------------------
export const authApi = {
  login(username: string, password: string): Promise<AuthResponse> {
    return apiFetch('/api/auth/login', {
      method: 'POST',
      body:   JSON.stringify({ username, password }),
    });
  },

  register(username: string, password: string): Promise<AuthResponse> {
    return apiFetch('/api/auth/register', {
      method: 'POST',
      body:   JSON.stringify({ username, password }),
    });
  },

  validate(): Promise<{ userId: string; username: string }> {
    return apiFetch('/api/auth/validate');
  },
};

// ---------------------------------------------------------------------------
// Songs API  (/api/songs/* → proxy → [APIM →] webapp_backend)
// ---------------------------------------------------------------------------
export const songsApi = {
  list(): Promise<Song[]> {
    return apiFetch('/api/songs');
  },

  get(id: string): Promise<Song> {
    return apiFetch(`/api/songs/${id}`);
  },

  create(payload: CreateSongPayload): Promise<Song> {
    return apiFetch('/api/songs', {
      method: 'POST',
      body:   JSON.stringify(payload),
    });
  },
};

export type { Song, CreateSongPayload, AuthResponse };
