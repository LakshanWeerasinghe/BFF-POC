'use client';

import Link from 'next/link';
import { useAuth } from '../context/AuthContext';
import { motion } from 'motion/react';
import { PlayCircle, Music, Headphones } from 'lucide-react';

export default function Home() {
  const { user } = useAuth();

  return (
    <div className="flex flex-col items-center justify-center min-h-[80vh] text-center">
      <motion.div
        initial={{ scale: 0.9, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.5 }}
        className="max-w-3xl"
      >
        <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-orange-500/10 border border-orange-500/20 text-orange-500 mb-8">
          <Headphones className="w-4 h-4" />
          <span className="text-sm font-medium tracking-wide uppercase">Your Personal Library</span>
        </div>
        
        <h1 className="text-5xl md:text-7xl font-black tracking-tighter mb-6 leading-tight">
          Discover the <br />
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-orange-400 to-orange-600">
            Sonic Wave
          </span>
        </h1>
        
        <p className="text-lg md:text-xl text-white/60 mb-10 max-w-2xl mx-auto leading-relaxed">
          A modern, intuitive platform to view, manage, and add your favorite songs. 
          Experience music management in a sleek, dark-themed environment.
        </p>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
          {user ? (
            <Link 
              href="/songs" 
              className="group relative inline-flex items-center justify-center gap-2 px-8 py-4 bg-orange-500 text-black font-bold rounded-full overflow-hidden transition-transform hover:scale-105"
            >
              <div className="absolute inset-0 bg-white/20 translate-y-full group-hover:translate-y-0 transition-transform"></div>
              <PlayCircle className="w-5 h-5 relative z-10" />
              <span className="relative z-10">Browse Library</span>
            </Link>
          ) : (
            <Link 
              href="/login" 
              className="group relative inline-flex items-center justify-center gap-2 px-8 py-4 bg-orange-500 text-black font-bold rounded-full overflow-hidden transition-transform hover:scale-105"
            >
              <div className="absolute inset-0 bg-white/20 translate-y-full group-hover:translate-y-0 transition-transform"></div>
              <PlayCircle className="w-5 h-5 relative z-10" />
              <span className="relative z-10">Get Started</span>
            </Link>
          )}
          
          <div className="flex items-center gap-2 px-8 py-4 text-white/60 font-medium">
            <Music className="w-5 h-5" />
            <span>High Quality Audio</span>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
