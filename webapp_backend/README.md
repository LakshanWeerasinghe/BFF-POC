# SonicWave Backend

A Ballerina REST API backend for the SonicWave music library webapp.

## Features

- **JWT Authentication**: Username-only login with automatic user creation
- **SQLite Database**: Persistent file-based storage
- **Song Management**: CRUD operations for song library
- **CORS Support**: Configured for frontend integration
- **Auto-seeding**: Initial data population on first startup

## Prerequisites

- Ballerina 2201.13.1 or later
- SQLite JDBC driver (automatically managed by Ballerina)

## Configuration

The application uses the following configurable values (defined in `config.bal`):

- `dbPath`: Database file path (default: `./sonicwave.db`)
- `jwtIssuer`: JWT token issuer (default: `sonicwave-backend`)
- `jwtSecret`: JWT signing secret (default: `default-secret-key-change-in-production`)
- `jwtExpiryTime`: Token expiry in seconds (default: `86400` - 24 hours)
- `serverPort`: HTTP server port (default: `8080`)

You can override these values in `Config.toml` or via environment variables.

## Running the Application

```bash
bal run
```

The server will start on `http://localhost:8080`.

## API Endpoints

### POST /api/login
Authenticate a user (creates user if doesn't exist).

**Request:**
```json
{
  "username": "musiclover99"
}
```

**Response:**
```json
{
  "token": "<jwt-token>",
  "user": {
    "username": "musiclover99"
  }
}
```

### GET /api/songs
Get all songs (requires authentication).

**Headers:**
```
Authorization: Bearer <jwt-token>
```

**Response:**
```json
[
  {
    "id": "1",
    "title": "Midnight City",
    "artist": "M83",
    "album": "Hurry Up, We're Dreaming",
    "duration": "4:03",
    "coverUrl": "https://picsum.photos/seed/m83/400/400"
  }
]
```

### GET /api/songs/{id}
Get a single song by ID (requires authentication).

**Headers:**
```
Authorization: Bearer <jwt-token>
```

### POST /api/songs
Create a new song (requires authentication).

**Headers:**
```
Authorization: Bearer <jwt-token>
Content-Type: application/json
```

**Request:**
```json
{
  "title": "Blinding Lights",
  "artist": "The Weeknd",
  "album": "After Hours",
  "duration": "3:20",
  "coverUrl": "https://example.com/cover.jpg"
}
```

## Database Schema

### users
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `username`: TEXT NOT NULL UNIQUE
- `created_at`: TIMESTAMP DEFAULT CURRENT_TIMESTAMP

### songs
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `title`: TEXT NOT NULL
- `artist`: TEXT NOT NULL
- `album`: TEXT NOT NULL DEFAULT 'Unknown Album'
- `duration`: TEXT NOT NULL DEFAULT '0:00'
- `cover_url`: TEXT
- `created_at`: TIMESTAMP DEFAULT CURRENT_TIMESTAMP

## Initial Seed Data

On first startup, the database is populated with three songs:
1. Midnight City - M83
2. Starboy - The Weeknd
3. Blinding Lights - The Weeknd

## CORS Configuration

Allowed origins: `http://localhost:3001`
Allowed methods: `GET, POST, PUT, DELETE, OPTIONS`
Allowed headers: `Authorization, Content-Type`
