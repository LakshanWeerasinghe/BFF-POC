import { useState, ChangeEvent, FormEvent } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { motion } from 'motion/react';
import { ArrowLeft, Music, User, Disc, Clock, Image as ImageIcon } from 'lucide-react';

export default function AddSong() {
  const [formData, setFormData] = useState({
    title: '',
    artist: '',
    album: '',
    duration: '',
    coverUrl: ''
  });
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const { token } = useAuth();
  const navigate = useNavigate();

  const handleChange = (e: ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!formData.title || !formData.artist) {
      setError('Title and artist are required');
      return;
    }

    setIsLoading(true);
    setError('');

    try {
      const response = await fetch('/api/songs', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify(formData),
      });

      if (!response.ok) throw new Error('Failed to add song');
      
      const newSong = await response.json();
      navigate(`/songs/${newSong.id}`);
    } catch (err) {
      setError('Failed to add song. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <motion.div 
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="max-w-2xl mx-auto"
    >
      <Link 
        to="/songs" 
        className="inline-flex items-center gap-2 text-white/50 hover:text-orange-500 transition-colors mb-8"
      >
        <ArrowLeft className="w-4 h-4" />
        <span className="text-sm font-medium uppercase tracking-wider">Back to Library</span>
      </Link>

      <div className="bg-[#141414] border border-white/5 rounded-3xl p-8 shadow-2xl">
        <div className="mb-8">
          <h1 className="text-3xl font-bold tracking-tight mb-2">Add New Song</h1>
          <p className="text-white/50">Expand your library with a new track.</p>
        </div>

        {error && (
          <div className="mb-6 p-4 bg-red-500/10 border border-red-500/20 text-red-500 rounded-xl text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-2">
              <label htmlFor="title" className="block text-sm font-medium text-white/70">
                Song Title *
              </label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                  <Music className="h-5 w-5 text-white/30" />
                </div>
                <input
                  id="title"
                  name="title"
                  type="text"
                  required
                  value={formData.title}
                  onChange={handleChange}
                  className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                  placeholder="e.g. Blinding Lights"
                />
              </div>
            </div>

            <div className="space-y-2">
              <label htmlFor="artist" className="block text-sm font-medium text-white/70">
                Artist *
              </label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                  <User className="h-5 w-5 text-white/30" />
                </div>
                <input
                  id="artist"
                  name="artist"
                  type="text"
                  required
                  value={formData.artist}
                  onChange={handleChange}
                  className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                  placeholder="e.g. The Weeknd"
                />
              </div>
            </div>

            <div className="space-y-2">
              <label htmlFor="album" className="block text-sm font-medium text-white/70">
                Album
              </label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                  <Disc className="h-5 w-5 text-white/30" />
                </div>
                <input
                  id="album"
                  name="album"
                  type="text"
                  value={formData.album}
                  onChange={handleChange}
                  className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                  placeholder="e.g. After Hours"
                />
              </div>
            </div>

            <div className="space-y-2">
              <label htmlFor="duration" className="block text-sm font-medium text-white/70">
                Duration
              </label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                  <Clock className="h-5 w-5 text-white/30" />
                </div>
                <input
                  id="duration"
                  name="duration"
                  type="text"
                  value={formData.duration}
                  onChange={handleChange}
                  className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                  placeholder="e.g. 3:20"
                />
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <label htmlFor="coverUrl" className="block text-sm font-medium text-white/70">
              Cover Image URL
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                <ImageIcon className="h-5 w-5 text-white/30" />
              </div>
              <input
                id="coverUrl"
                name="coverUrl"
                type="url"
                value={formData.coverUrl}
                onChange={handleChange}
                className="block w-full pl-11 pr-4 py-3 bg-black border border-white/10 rounded-xl text-white placeholder-white/30 focus:outline-none focus:ring-2 focus:ring-orange-500 focus:border-transparent transition-all"
                placeholder="https://example.com/image.jpg"
              />
            </div>
            <p className="text-xs text-white/40 mt-1">Leave empty to use a random placeholder image.</p>
          </div>

          <div className="pt-4">
            <button
              type="submit"
              disabled={isLoading}
              className="w-full flex items-center justify-center py-4 px-4 border border-transparent rounded-xl text-black bg-orange-500 hover:bg-orange-600 font-bold focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 focus:ring-offset-black transition-all disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isLoading ? 'Adding Song...' : 'Add Song to Library'}
            </button>
          </div>
        </form>
      </div>
    </motion.div>
  );
}
