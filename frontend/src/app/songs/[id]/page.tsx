'use client';

import { useState, useEffect, use } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { motion } from 'motion/react';
import { ArrowLeft, Play, Heart, Share2, MoreHorizontal, Clock, Disc } from 'lucide-react';
import { songsApi } from '../../../lib/api';
import type { Song } from '../../../types';
import ProtectedRoute from '../../../components/ProtectedRoute';

function SongDetailContent({ id }: { id: string }) {
  const [song, setSong] = useState<Song | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const router = useRouter();

  useEffect(() => {
    songsApi
      .get(id)
      .then(setSong)
      .catch((err: Error) => setError(err.message || 'Could not load song details.'))
      .finally(() => setIsLoading(false));
  }, [id]);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="max-w-5xl mx-auto"
    >
      <Link
        href="/songs"
        className="inline-flex items-center gap-2 text-white/50 hover:text-orange-500 transition-colors mb-8"
      >
        <ArrowLeft className="w-4 h-4" />
        <span className="text-sm font-medium uppercase tracking-wider">Back to Library</span>
      </Link>

      {isLoading ? (
        <div className="flex items-center justify-center min-h-[50vh]">
          <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin"></div>
        </div>
      ) : error || !song ? (
        <div className="text-center py-20">
          <p className="text-red-500 mb-6">{error || 'Song not found'}</p>
          <button
            onClick={() => router.push('/songs')}
            className="px-6 py-2 bg-white/10 hover:bg-white/20 rounded-full transition-colors"
          >
            Back to Library
          </button>
        </div>
      ) : (
        <div className="flex flex-col md:flex-row gap-8 lg:gap-16 items-start">
          <motion.div
            initial={{ scale: 0.9, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ delay: 0.1 }}
            className="w-full md:w-1/3 lg:w-2/5 shrink-0"
          >
            <div className="aspect-square rounded-3xl overflow-hidden shadow-[0_20px_50px_rgba(0,0,0,0.5)] border border-white/10 relative group">
              <img
                src={song.coverUrl}
                alt={`${song.title} cover`}
                className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-105"
                referrerPolicy="no-referrer"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-60"></div>
            </div>
          </motion.div>

          <div className="flex-1 w-full py-4">
            <motion.div
              initial={{ y: 20, opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              transition={{ delay: 0.2 }}
            >
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-white/60 text-xs font-medium uppercase tracking-widest mb-4">
                <Disc className="w-3 h-3" />
                Single
              </div>

              <h1 className="text-4xl md:text-6xl font-black tracking-tighter mb-2 text-transparent bg-clip-text bg-gradient-to-br from-white to-white/60">
                {song.title}
              </h1>
              <h2 className="text-2xl md:text-3xl font-medium text-orange-500 mb-8">
                {song.artist}
              </h2>

              <div className="flex items-center gap-6 mb-10 text-white/50 text-sm font-medium">
                <div className="flex items-center gap-2">
                  <Disc className="w-4 h-4" />
                  <span>{song.album}</span>
                </div>
                <div className="flex items-center gap-2">
                  <Clock className="w-4 h-4" />
                  <span>{song.duration}</span>
                </div>
              </div>

              <div className="flex items-center gap-4">
                <button className="flex items-center justify-center w-16 h-16 bg-orange-500 text-black rounded-full hover:scale-105 hover:bg-orange-400 transition-all shadow-[0_0_30px_rgba(255,99,33,0.3)]">
                  <Play className="w-8 h-8 ml-1 fill-current" />
                </button>

                <button className="flex items-center justify-center w-12 h-12 bg-[#141414] border border-white/10 text-white rounded-full hover:border-orange-500/50 hover:text-orange-500 transition-all">
                  <Heart className="w-5 h-5" />
                </button>

                <button className="flex items-center justify-center w-12 h-12 bg-[#141414] border border-white/10 text-white rounded-full hover:border-orange-500/50 hover:text-orange-500 transition-all">
                  <Share2 className="w-5 h-5" />
                </button>

                <button className="flex items-center justify-center w-12 h-12 bg-[#141414] border border-white/10 text-white rounded-full hover:border-orange-500/50 hover:text-orange-500 transition-all ml-auto">
                  <MoreHorizontal className="w-5 h-5" />
                </button>
              </div>
            </motion.div>
          </div>
        </div>
      )}
    </motion.div>
  );
}

export default function SongDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  return (
    <ProtectedRoute>
      <SongDetailContent id={id} />
    </ProtectedRoute>
  );
}
