import type { AuthResponse, Song, CreateSongPayload } from '../types';

// ---------------------------------------------------------------------------
// Core fetch wrapper
//
// All requests go to the Ballerina BFF via the Next.js rewrite /bff/*.
// Authentication is cookie-based — the BFF sets an httpOnly `auth_token`
// cookie on login/register and reads it on every subsequent request.
// The browser sends the cookie automatically; no token management in the FE.
// ---------------------------------------------------------------------------
async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(path, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string>),
    },
    credentials: 'include', // send the auth_token httpOnly cookie
  });

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
// Auth API  (/bff/auth/*)
// ---------------------------------------------------------------------------
export const authApi = {
  login(username: string, password: string): Promise<AuthResponse> {
    return apiFetch('/bff/auth/login', {
      method: 'POST',
      body:   JSON.stringify({ username, password }),
    });
  },

  register(username: string, password: string): Promise<AuthResponse> {
    return apiFetch('/bff/auth/register', {
      method: 'POST',
      body:   JSON.stringify({ username, password }),
    });
  },

  validate(): Promise<{ userId: string; username: string }> {
    return apiFetch('/bff/auth/validate');
  },

  logout(): Promise<void> {
    return apiFetch('/bff/auth/logout', { method: 'POST' });
  },
};

// ---------------------------------------------------------------------------
// Songs API  (/bff/songs/*)
// ---------------------------------------------------------------------------
export const songsApi = {
  list(): Promise<Song[]> {
    return apiFetch('/bff/songs');
  },

  get(id: string): Promise<Song> {
    return apiFetch(`/bff/songs/${id}`);
  },

  create(payload: CreateSongPayload): Promise<Song> {
    return apiFetch('/bff/songs', {
      method: 'POST',
      body:   JSON.stringify(payload),
    });
  },
};

export type { Song, CreateSongPayload, AuthResponse };
