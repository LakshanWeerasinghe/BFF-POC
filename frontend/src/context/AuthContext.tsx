'use client';

import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react';
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

  const logout = useCallback(async () => {
    try {
      await authApi.logout(); // BFF clears the httpOnly cookie
    } catch { /* ignore network errors on logout */ }
    setUser(null);
    clearUser();
  }, []);

  // On startup: call BFF validate to check whether the session cookie is still valid.
  // If valid the BFF returns { userId, username }; if not it returns 401.
  useEffect(() => {
    authApi
      .validate()
      .then(({ userId, username }) => {
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

  // Listen for 401 events dispatched by apiFetch
  useEffect(() => {
    const handler = () => { logout(); };
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
