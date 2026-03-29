'use client';

import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react';
import { authApi } from '../lib/api';
import type { User } from '../types';

interface AuthContextType {
  user: User | null;
  token: string | null;
  login: (username: string, password: string) => Promise<void>;
  register: (username: string, password: string) => Promise<void>;
  logout: () => void;
  isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

function persistSession(token: string, user: User) {
  localStorage.setItem('token', token);
  localStorage.setItem('user', JSON.stringify(user));
}

function clearSession() {
  localStorage.removeItem('token');
  localStorage.removeItem('user');
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const logout = useCallback(() => {
    setToken(null);
    setUser(null);
    clearSession();
  }, []);

  // Validate the stored token on startup — clear state if expired or invalid
  useEffect(() => {
    const storedToken = localStorage.getItem('token');
    const storedUser = localStorage.getItem('user');

    if (!storedToken || !storedUser) {
      setIsLoading(false);
      return;
    }

    authApi
      .validate()
      .then(() => {
        setToken(storedToken);
        setUser(JSON.parse(storedUser));
      })
      .catch(() => {
        // Token is expired or invalid — force a clean state
        clearSession();
      })
      .finally(() => setIsLoading(false));
  }, []);

  // Listen for 401 events dispatched by the API client
  useEffect(() => {
    window.addEventListener('auth:unauthorized', logout);
    return () => window.removeEventListener('auth:unauthorized', logout);
  }, [logout]);

  const login = async (username: string, password: string) => {
    const data = await authApi.login(username, password);
    setToken(data.token);
    setUser(data.user);
    persistSession(data.token, data.user);
  };

  const register = async (username: string, password: string) => {
    const data = await authApi.register(username, password);
    setToken(data.token);
    setUser(data.user);
    persistSession(data.token, data.user);
  };

  return (
    <AuthContext.Provider value={{ user, token, login, register, logout, isLoading }}>
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
