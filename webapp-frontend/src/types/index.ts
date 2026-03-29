// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export interface User {
  id: string;
  username: string;
}

// BFF strips the JWT from the body — only { user } reaches the browser.
export interface AuthResponse {
  user: User;
}

// ---------------------------------------------------------------------------
// Songs
// ---------------------------------------------------------------------------

export interface Song {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration: string;
  coverUrl: string;
  ownerId: string;
}

export interface CreateSongPayload {
  title: string;
  artist: string;
  album?: string;
  duration?: string;
  coverUrl?: string;
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

export interface ApiError {
  error: string;
}
