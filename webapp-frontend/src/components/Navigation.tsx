'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '../context/AuthContext';
import { Music, LogOut, LogIn, Plus, Home } from 'lucide-react';

export default function Navigation() {
  const { user, logout } = useAuth();
  const router = useRouter();

  const handleLogout = () => {
    logout();
    router.push('/');
  };

  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-black/50 backdrop-blur-md">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <Link href="/" className="flex items-center gap-2 group">
            <div className="bg-orange-500 p-2 rounded-xl group-hover:scale-105 transition-transform">
              <Music className="w-5 h-5 text-black" />
            </div>
            <span className="font-bold text-xl tracking-tight">Sonic<span className="text-orange-500">Wave</span></span>
          </Link>
          
          <nav className="flex items-center gap-6">
            <Link href="/" className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2">
              <Home className="w-4 h-4" />
              <span className="hidden sm:inline">Home</span>
            </Link>
            
            {user ? (
              <>
                <Link href="/songs" className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2">
                  <Music className="w-4 h-4" />
                  <span className="hidden sm:inline">Library</span>
                </Link>
                <Link href="/songs/add" className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2">
                  <Plus className="w-4 h-4" />
                  <span className="hidden sm:inline">Add Song</span>
                </Link>
                <div className="h-4 w-px bg-white/20 mx-2"></div>
                <div className="flex items-center gap-4">
                  <span className="text-sm text-orange-500 font-medium hidden sm:inline">
                    @{user.username}
                  </span>
                  <button 
                    onClick={handleLogout}
                    className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2"
                  >
                    <LogOut className="w-4 h-4" />
                    <span className="hidden sm:inline">Logout</span>
                  </button>
                </div>
              </>
            ) : (
              <Link 
                href="/login" 
                className="bg-orange-500 hover:bg-orange-600 text-black text-sm font-semibold py-2 px-4 rounded-full transition-colors flex items-center gap-2"
              >
                <LogIn className="w-4 h-4" />
                Login
              </Link>
            )}
          </nav>
        </div>
      </div>
    </header>
  );
}
