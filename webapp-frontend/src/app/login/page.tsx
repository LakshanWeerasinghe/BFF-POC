'use client';

import { useState, FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '../../context/AuthContext';
import { motion } from 'motion/react';
import { LogIn, User, Lock } from 'lucide-react';

export default function Login() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const { login } = useAuth();
  const router = useRouter();

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!username.trim() || !password) {
      setError('Username and password are required');
      return;
    }

    setIsLoading(true);
    setError('');

    try {
      await login(username.trim(), password);
      router.push('/songs');
    } catch (err: any) {
      setError(err.message === 'Unauthorized' ? 'Invalid username or password' : 'Login failed. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex items-center justify-center min-h-[70vh]">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="w-full max-w-md p-8 rounded-3xl bg-[#141414] border border-white/5 shadow-2xl"
      >
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-orange-500/10 text-orange-500 mb-4">
            <LogIn className="w-8 h-8" />
          </div>
          <h2 className="text-3xl font-bold tracking-tight">Welcome Back</h2>
          <p className="text-white/50 mt-2">Sign in to your library</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label htmlFor="username" className="block text-sm font-medium text-white/70 mb-2">
              Username
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                <User className="h-5 w-5 text-white/30" />
              </div>
              <input
                id="username"
                type="text"
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                placeholder="e.g. musiclover99"
              />
            </div>
          </div>

          <div>
            <label htmlFor="password" className="block text-sm font-medium text-white/70 mb-2">
              Password
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                <Lock className="h-5 w-5 text-white/30" />
              </div>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                placeholder="••••••••"
              />
            </div>
            {error && <p className="mt-2 text-sm text-red-500">{error}</p>}
          </div>

          <button
            type="submit"
            disabled={isLoading}
            className="w-full flex items-center justify-center py-3 px-4 border border-transparent rounded-xl text-black bg-orange-500 hover:bg-orange-600 font-bold focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 focus:ring-offset-black transition-all disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isLoading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-white/40">
          Don't have an account?{' '}
          <Link href="/register" className="text-orange-500 hover:text-orange-400 font-medium transition-colors">
            Create one
          </Link>
        </p>
      </motion.div>
    </div>
  );
}
