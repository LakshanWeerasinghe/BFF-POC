import { Outlet, Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Music, LogOut, LogIn, Plus, Home } from 'lucide-react';
import { motion } from 'motion/react';

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  return (
    <div className="min-h-screen bg-black text-white font-sans selection:bg-orange-500/30">
      <header className="sticky top-0 z-50 border-b border-white/10 bg-black/50 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <Link to="/" className="flex items-center gap-2 group">
              <div className="bg-orange-500 p-2 rounded-xl group-hover:scale-105 transition-transform">
                <Music className="w-5 h-5 text-black" />
              </div>
              <span className="font-bold text-xl tracking-tight">Sonic<span className="text-orange-500">Wave</span></span>
            </Link>
            
            <nav className="flex items-center gap-6">
              <Link to="/" className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2">
                <Home className="w-4 h-4" />
                <span className="hidden sm:inline">Home</span>
              </Link>
              
              {user ? (
                <>
                  <Link to="/songs" className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2">
                    <Music className="w-4 h-4" />
                    <span className="hidden sm:inline">Library</span>
                  </Link>
                  <Link to="/songs/add" className="text-sm font-medium text-white/70 hover:text-white transition-colors flex items-center gap-2">
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
                  to="/login" 
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

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -10 }}
          transition={{ duration: 0.3 }}
        >
          <Outlet />
        </motion.div>
      </main>
    </div>
  );
}
