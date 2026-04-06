'use client';

import { createContext, useContext, useState, useEffect, useCallback, useRef, ReactNode } from 'react';
import { authApi } from '../lib/api';
import type { User } from '../types';

interface AuthContextType {
  user: User | null;
  login: (username: string, password: string) => Promise<void>;
  register: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// User display info is cached in localStorage (non-sensitive).
// The actual auth token lives in an httpOnly cookie managed by the BFF.
function persistUser(user: User) {
  localStorage.setItem('user', JSON.stringify(user));
}

function clearUser() {
  localStorage.removeItem('user');
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser]         = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const isLoggingOut = useRef(false);
  // Tracks whether the user has explicitly logged out in this session.
  // Used to discard a startup validate() result that arrives AFTER logout —
  // otherwise the stale success would call setUser() again and restart the
  // login → songs → logout → validate-succeeds → login loop.
  const hasLoggedOut = useRef(false);

  const logout = useCallback(async () => {
    if (isLoggingOut.current) return;
    isLoggingOut.current = true;
    hasLoggedOut.current = true; // Prevent any in-flight validate() from re-setting user.
    try {
      await authApi.logout(); // BFF clears the httpOnly cookie
    } catch { /* ignore network errors on logout */ }
    setUser(null);
    clearUser();
    isLoggingOut.current = false;
  }, []);

  // On startup: call BFF validate to check whether the session cookie is still valid.
  // If valid the BFF returns { userId, username }; if not it returns 401.
  useEffect(() => {
    authApi
      .validate()
      .then(({ userId, username }) => {
        // Guard: if the user explicitly logged out while validate() was in-flight
        // (race condition: login → songs → 401 → logout → validate() resolves),
        // discard the result to avoid re-setting user and restarting the nav loop.
        if (hasLoggedOut.current) return;
        const u: User = { id: userId, username };
        setUser(u);
        persistUser(u);
      })
      .catch(() => {
        // Cookie absent or expired — clear any stale display cache
        clearUser();
      })
      .finally(() => setIsLoading(false));
  }, []);

  // Track the current user in a ref so the event handler (a stale closure)
  // can read the latest value without being added to the dependency array.
  const userRef = useRef<User | null>(null);
  useEffect(() => { userRef.current = user; }, [user]);

  // Listen for 401 events dispatched by apiFetch.
  // Before logging out, re-validate the session: a 401 on one endpoint
  // (e.g. /bff/songs) doesn't necessarily mean the session cookie is invalid —
  // it could be a transient error or an endpoint-specific APIM rejection.
  // If validate() also fails, the session is genuinely expired → logout.
  useEffect(() => {
    const handler = async () => {
      if (!userRef.current) return; // Already logged out — nothing to do.
      try {
        await authApi.validate();
        // validate succeeded → session still active; don't logout.
      } catch {
        // validate also failed → session is genuinely invalid.
        logout();
      }
    };
    window.addEventListener('auth:unauthorized', handler);
    return () => window.removeEventListener('auth:unauthorized', handler);
  }, [logout]);

  const login = async (username: string, password: string) => {
    const { user: u } = await authApi.login(username, password);
    setUser(u);
    persistUser(u);
  };

  const register = async (username: string, password: string) => {
    const { user: u } = await authApi.register(username, password);
    setUser(u);
    persistUser(u);
  };

  return (
    <AuthContext.Provider value={{ user, login, register, logout, isLoading }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
