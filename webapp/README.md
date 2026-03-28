# SonicWave — Local Development Guide

## Prerequisites

- [Node.js](https://nodejs.org/) v22+
- npm (bundled with Node.js)

## Setup

1. Install dependencies:

   ```bash
   npm install
   ```

2. (Optional) Create a `.env.local` file if you need Gemini API support:

   ```bash
   cp .env.example .env.local
   ```

   Then set your `GEMINI_API_KEY` inside `.env.local`. This is not required for the core app to run locally.

## Running in Development

```bash
npm run dev
```

Starts the Express + Vite dev server at **http://localhost:3001** with hot module reloading.

## Running in Production

1. Build the frontend:

   ```bash
   npm run build
   ```

2. Start the server:

   ```bash
   npm run start
   ```

The app will be available at **http://localhost:3001**, serving the compiled frontend from `/dist`.

## Available Scripts

| Script | Description |
|---|---|
| `npm run dev` | Start dev server with HMR (uses `tsx`) |
| `npm run build` | Build frontend for production |
| `npm run start` | Run production server |
| `npm run preview` | Preview the production build locally |
| `npm run lint` | Type-check with TypeScript |
| `npm run clean` | Remove the `dist` directory |

## Logging In

The app uses **mock authentication** — no real credentials are required. Enter any username on the login page to sign in.

## API Endpoints

All endpoints except `/api/login` require an `Authorization: Bearer <token>` header.

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/login` | Authenticate and get a token |
| `GET` | `/api/songs` | List all songs |
| `GET` | `/api/songs/:id` | Get a song by ID |
| `POST` | `/api/songs` | Add a new song |

> **Note:** Song data is stored in-memory and resets every time the server restarts.
