import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { motion } from 'motion/react';
import { Play, Clock, Disc3 } from 'lucide-react';

interface Song {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration: string;
  coverUrl: string;
}

export default function Songs() {
  const [songs, setSongs] = useState<Song[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const { token } = useAuth();

  useEffect(() => {
    const fetchSongs = async () => {
      try {
        const response = await fetch('/api/songs', {
          headers: {
            'Authorization': `Bearer ${token}`
          }
        });
        if (!response.ok) throw new Error('Failed to fetch songs');
        const data = await response.json();
        setSongs(data);
      } catch (err) {
        setError('Could not load your library.');
      } finally {
        setIsLoading(false);
      }
    };

    if (token) {
      fetchSongs();
    }
  }, [token]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-[50vh]">
        <div className="w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full animate-spin"></div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-12">
        <p className="text-red-500">{error}</p>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-3xl font-bold tracking-tight">Your Library</h1>
        <Link 
          to="/songs/add"
          className="text-sm font-medium text-orange-500 hover:text-orange-400 transition-colors"
        >
          + Add New Song
        </Link>
      </div>

      {songs.length === 0 ? (
        <div className="text-center py-20 bg-[#141414] rounded-3xl border border-white/5">
          <Disc3 className="w-16 h-16 text-white/20 mx-auto mb-4" />
          <h3 className="text-xl font-medium text-white/70 mb-2">No songs yet</h3>
          <p className="text-white/40 mb-6">Start building your library by adding your first song.</p>
          <Link 
            to="/songs/add"
            className="inline-flex items-center justify-center px-6 py-3 bg-white/10 hover:bg-white/20 text-white font-medium rounded-full transition-colors"
          >
            Add a Song
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {songs.map((song, index) => (
            <motion.div
              key={song.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.05 }}
            >
              <Link 
                to={`/songs/${song.id}`}
                className="group block bg-[#141414] rounded-2xl overflow-hidden border border-white/5 hover:border-orange-500/50 transition-all hover:shadow-[0_0_30px_rgba(255,99,33,0.15)]"
              >
                <div className="relative aspect-square overflow-hidden">
                  <img 
                    src={song.coverUrl} 
                    alt={`${song.title} cover`} 
                    className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110"
                    referrerPolicy="no-referrer"
                  />
                  <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                    <div className="w-12 h-12 rounded-full bg-orange-500 flex items-center justify-center text-black transform scale-75 group-hover:scale-100 transition-transform">
                      <Play className="w-5 h-5 ml-1" />
                    </div>
                  </div>
                </div>
                <div className="p-5">
                  <h3 className="font-bold text-lg truncate mb-1 group-hover:text-orange-500 transition-colors">{song.title}</h3>
                  <p className="text-white/60 text-sm truncate mb-3">{song.artist}</p>
                  <div className="flex items-center justify-between text-xs text-white/40 font-medium">
                    <span className="truncate max-w-[120px]">{song.album}</span>
                    <span className="flex items-center gap-1"><Clock className="w-3 h-3" /> {song.duration}</span>
                  </div>
                </div>
              </Link>
            </motion.div>
          ))}
        </div>
      )}
    </div>
  );
}
