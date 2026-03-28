import express from 'express';
import { createServer as createViteServer } from 'vite';
import path from 'path';

const app = express();
const PORT = 3001;

app.use(express.json());

// In-memory mock database
interface Song {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration: string;
  coverUrl: string;
}

let songs: Song[] = [
  {
    id: '1',
    title: 'Midnight City',
    artist: 'M83',
    album: "Hurry Up, We're Dreaming",
    duration: '4:03',
    coverUrl: 'https://picsum.photos/seed/m83/400/400'
  },
  {
    id: '2',
    title: 'Starboy',
    artist: 'The Weeknd',
    album: 'Starboy',
    duration: '3:50',
    coverUrl: 'https://picsum.photos/seed/starboy/400/400'
  },
  {
    id: '3',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    album: 'After Hours',
    duration: '3:20',
    coverUrl: 'https://picsum.photos/seed/blinding/400/400'
  }
];

// Simple auth middleware (mock)
const requireAuth = (req: express.Request, res: express.Response, next: express.NextFunction) => {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    next();
  } else {
    res.status(401).json({ error: 'Unauthorized' });
  }
};

// API Routes
app.post('/api/login', (req, res) => {
  const { username } = req.body;
  if (username) {
    res.json({ token: 'mock-jwt-token-123', user: { username } });
  } else {
    res.status(400).json({ error: 'Username is required' });
  }
});

app.get('/api/songs', requireAuth, (req, res) => {
  res.json(songs);
});

app.get('/api/songs/:id', requireAuth, (req, res) => {
  const song = songs.find(s => s.id === req.params.id);
  if (song) {
    res.json(song);
  } else {
    res.status(404).json({ error: 'Song not found' });
  }
});

app.post('/api/songs', requireAuth, (req, res) => {
  const { title, artist, album, duration, coverUrl } = req.body;
  if (!title || !artist) {
    return res.status(400).json({ error: 'Title and artist are required' });
  }
  
  const newSong: Song = {
    id: Date.now().toString(),
    title,
    artist,
    album: album || 'Unknown Album',
    duration: duration || '0:00',
    coverUrl: coverUrl || `https://picsum.photos/seed/${Date.now()}/400/400`
  };
  
  songs.push(newSong);
  res.status(201).json(newSong);
});

// Vite middleware setup
async function startServer() {
  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
