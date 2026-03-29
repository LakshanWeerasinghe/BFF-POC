// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export interface User {
  id: string;
  username: string;
}

export interface AuthResponse {
  token: string;
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
