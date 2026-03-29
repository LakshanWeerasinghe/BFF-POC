# webapp_backend — Auth Integration + Song Ownership Plan

## Goal

1. Remove all auth concerns from `webapp_backend` and delegate JWT validation to `auth_service`.
2. Add song ownership: every song is owned by exactly one user. Users see and manage only their own songs.

---

## Ownership Architecture Decision

Songs need an owner. The options are:

| Option | Store | Problem |
|---|---|---|
| Username string | `songs.owner_username TEXT` | Usernames are mutable — renaming a user breaks all their song records |
| Local shadow table | `webapp_backend.users` mirrors auth users | Adds sync complexity across services for no real benefit |
| **User ID (int)** | **`songs.user_id INTEGER`** | **Stable, canonical ID from the owning service — correct pattern** |

**Decision: store `user_id` as a plain integer in the `songs` table.**

This is the standard microservices cross-service reference pattern. There is no DB-level foreign key (the two services have separate databases), but that is intentional — referential integrity is enforced at the application layer, not the DB layer. The `userId` value comes directly from the validated JWT claims issued by `auth_service`, so it is always trusted.

---

## Cascading Impact of Ownership

Adding `user_id` to songs is not a single-column addition — it cascades through the entire call chain:

```
validateAuthHeader()   currently returns  string|error  (just username)
                       must become        CallerInfo|error  (userId + username)
                                 ↓
validateWithAuthService()  must return    CallerInfo|error
                                 ↓
getAllSongs(userId)         add userId param  → WHERE user_id = ?
getSongById(songId, userId) add userId param  → WHERE id = ? AND user_id = ?
createSong(..., userId)    add userId param  → INSERT with user_id
                                 ↓
POST /api/songs            passes caller.userId to createSong
GET /api/songs             passes caller.userId to getAllSongs
GET /api/songs/{id}        passes caller.userId to getSongById
```

---

## Seed Data

The three pre-seeded songs (`Midnight City`, `Starboy`, `Blinding Lights`) have no owner. With `user_id NOT NULL`, they cannot exist without an owner.

**Decision: remove seed data.**

In an owned-songs model, pre-seeded songs do not make sense. Each user builds their own library. `seedInitialData` is deleted from `connections.bal`.

---

## Current vs Target Flow

```
Current:
  POST /api/login  →  webapp_backend issues JWT (owns auth)
  GET  /api/songs  →  webapp_backend validates JWT locally → returns ALL songs

Target:
  POST /auth/login →  auth_service issues JWT (owns auth)
  GET  /api/songs  →  webapp_backend calls auth_service /auth/validate
                   →  auth_service returns { userId, username }
                   →  webapp_backend returns only songs WHERE user_id = userId
```

---

## Part 1 — Changes Required in auth_service

### 1.1 New endpoint: `GET /auth/validate`

Validates a Bearer token and returns the caller's identity. Called by webapp_backend on every protected request.

**Request**
```
Authorization: Bearer <jwt>
```

**Response — 200 OK**
```json
{ "userId": "1", "username": "lakshan" }
```

**Response — 401 Unauthorized**
```json
{ "error": "Unauthorized" }
```

### 1.2 `types.bal` — add `ValidateResponse`

```ballerina
type ValidateResponse record {|
    string userId;
    string username;
|};
```

### 1.3 `functions.bal` — add `validateJwtToken`

Auth service now owns the full JWT lifecycle: issue + validate.

```ballerina
function validateJwtToken(string token) returns jwt:Payload|error {
    jwt:ValidatorConfig validatorConfig = {
        issuer: jwtIssuer,
        audience: "sonicwave-users",
        signatureConfig: {
            secret: jwtSecret
        }
    };
    return check jwt:validate(token, validatorConfig);
}
```

### 1.4 `main.bal` — add `GET /auth/validate` resource

```ballerina
resource function get validate(@http:Header string? Authorization)
        returns http:Ok|http:Unauthorized {

    if Authorization is () || !Authorization.startsWith("Bearer ") {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
    }

    string token = Authorization.substring(7);
    jwt:Payload|error payload = validateJwtToken(token);
    if payload is error {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
    }

    string? username = payload.sub;
    if username is () {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
    }

    string userId = "";
    map<json>? customClaims = payload.customClaims;
    if customClaims is map<json> {
        json|error userIdClaim = customClaims["userId"];
        if userIdClaim is json {
            userId = userIdClaim.toString();
        }
    }

    return <http:Ok>{body: <ValidateResponse>{userId: userId, username: username}};
}
```

Also update CORS `allowHeaders` to include `Authorization`:
```ballerina
allowHeaders: ["Content-Type", "Authorization"]
```

---

## Part 2 — Changes in webapp_backend

### 2.1 `config.bal`

Remove JWT config, add `authServiceUrl`:

```ballerina
// Before:
configurable string dbPath        = "./sonicwave.db";
configurable string jwtSecret     = "default-secret-key-change-in-production";
configurable string jwtIssuer     = "sonicwave-backend";
configurable int    jwtExpiryTime = 86400;
configurable int    serverPort    = 8080;

// After:
configurable string dbPath         = "./sonicwave.db";
configurable string authServiceUrl = "http://localhost:9090";
configurable int    serverPort     = 8080;
```

---

### 2.2 `types.bal`

Remove all auth types. Add `CallerInfo` (used internally by auth validation) and update `Song` and `SongResponse` for ownership.

```ballerina
// REMOVE: User, LoginRequest, LoginResponse, UserResponse, JwtPayload

// ADD — caller identity returned by validateAuthHeader:
type CallerInfo record {|
    int    userId;
    string username;
|};

// UPDATE — Song DB record gains user_id:
type Song record {|
    int    id;
    string title;
    string artist;
    string album;
    string duration;
    string cover_url?;
    int    user_id;          // owner — references auth_service users.id
    string created_at?;
|};

// UPDATE — SongResponse gains ownerId for API consumers:
type SongResponse record {|
    string id;
    string title;
    string artist;
    string album;
    string duration;
    string coverUrl;
    string ownerId;          // string form of user_id
|};

// UNCHANGED:
type CreateSongRequest record {| ... |};
type ErrorResponse record {| ... |};
```

---

### 2.3 `connections.bal`

**Add** `http:Client` for auth_service.
**Remove** `users` table DDL.
**Remove** `seedInitialData` call and function (no seed data in an owned-songs model).
**Update** `songs` table DDL to include `user_id NOT NULL`.

```ballerina
import ballerina/http;
import ballerinax/java.jdbc;

final jdbc:Client dbClient       = check initDatabase();
final http:Client authServiceClient = check new (authServiceUrl);

function initDatabase() returns jdbc:Client|error {
    jdbc:Client client = check new ("jdbc:sqlite:" + dbPath, "", "");
    check createTables(client);
    // seedInitialData removed
    return client;
}

function createTables(jdbc:Client client) returns error? {
    // users table removed — owned by auth_service

    _ = check client->execute(`
        CREATE TABLE IF NOT EXISTS songs (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            title      TEXT    NOT NULL,
            artist     TEXT    NOT NULL,
            album      TEXT    NOT NULL DEFAULT 'Unknown Album',
            duration   TEXT    NOT NULL DEFAULT '0:00',
            cover_url  TEXT,
            user_id    INTEGER NOT NULL,           -- owner (auth_service users.id)
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
}
```

> `user_id` has no `REFERENCES` constraint because the `users` table lives in a different database (`auth.db`). Integrity is enforced at the application layer.

---

### 2.4 `functions.bal`

**Remove:** `generateJwtToken`, `validateJwtToken`, `createUser`, `getUserByUsername`, `import ballerina/jwt`.

**Add:** `validateWithAuthService` returning `CallerInfo`.

**Update:** `getAllSongs`, `getSongById`, `createSong` — all gain a `userId` parameter.

**Update:** `toSongResponse` — maps new `user_id` field to `ownerId`.

```ballerina
import ballerina/http;
import ballerina/sql;

// --- Auth delegation ---

// Calls auth_service to validate the token and returns the caller's identity.
function validateWithAuthService(string token) returns CallerInfo|error {
    http:Response response = check authServiceClient->get(
        "/auth/validate",
        {"Authorization": "Bearer " + token}
    );
    if response.statusCode != 200 {
        return error("Unauthorized");
    }
    json body = check response.getJsonPayload();
    string userIdStr = check body.userId;
    string username  = check body.username;
    int userId       = check int:fromString(userIdStr);
    return {userId: userId, username: username};
}

// --- Song DB operations (all scoped to userId) ---

function getAllSongs(int userId) returns Song[]|error {
    stream<Song, sql:Error?> songStream = dbClient->query(`
        SELECT id, title, artist, album, duration, cover_url, user_id, created_at
        FROM songs WHERE user_id = ${userId}
    `);
    return check from Song song in songStream select song;
}

function getSongById(int songId, int userId) returns Song|error? {
    Song|sql:Error result = dbClient->queryRow(`
        SELECT id, title, artist, album, duration, cover_url, user_id, created_at
        FROM songs WHERE id = ${songId} AND user_id = ${userId}
    `);
    if result is sql:NoRowsError {
        return ();
    }
    return result;
}

function createSong(string title, string artist, string album,
                    string duration, string coverUrl, int userId) returns Song|error {
    sql:ExecutionResult result = check dbClient->execute(`
        INSERT INTO songs (title, artist, album, duration, cover_url, user_id)
        VALUES (${title}, ${artist}, ${album}, ${duration}, ${coverUrl}, ${userId})
    `);
    int|string? songId = result.lastInsertId;
    if songId is int {
        return {id: songId, title, artist, album, duration,
                cover_url: coverUrl, user_id: userId};
    }
    return error("Failed to create song");
}

// --- Mapping ---

function toSongResponse(Song song) returns SongResponse {
    return {
        id:      song.id.toString(),
        title:   song.title,
        artist:  song.artist,
        album:   song.album,
        duration: song.duration,
        coverUrl: song.cover_url ?: "",
        ownerId: song.user_id.toString()
    };
}
```

---

### 2.5 `main.bal`

**Remove:** `POST /api/login` resource function.

**Update:** `validateAuthHeader` — returns `CallerInfo|error` instead of `string|error`.

**Update:** all three resource functions — receive `CallerInfo` from `validateAuthHeader` and pass `caller.userId` to DB functions.

```ballerina
// validateAuthHeader — now returns CallerInfo
function validateAuthHeader(string? authHeader) returns CallerInfo|error {
    if authHeader is () {
        return error("Missing Authorization header");
    }
    string authHeaderValue = authHeader;
    if !authHeaderValue.startsWith("Bearer ") {
        return error("Invalid Authorization header format");
    }
    string token = authHeaderValue.substring(7);
    return check validateWithAuthService(token);
}

// GET /api/songs — scoped to the caller's songs
resource function get songs(@http:Header string? Authorization)
        returns SongResponse[]|http:Unauthorized {
    CallerInfo|error caller = validateAuthHeader(Authorization);
    if caller is error {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
    }
    Song[]|error songs = getAllSongs(caller.userId);    // <-- scoped by userId
    if songs is error {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Failed to retrieve songs"}};
    }
    return from Song song in songs select toSongResponse(song);
}

// GET /api/songs/{id} — only returns song if it belongs to the caller
resource function get songs/[string id](@http:Header string? Authorization)
        returns SongResponse|http:Unauthorized|http:NotFound {
    CallerInfo|error caller = validateAuthHeader(Authorization);
    if caller is error {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
    }
    int|error songId = int:fromString(id);
    if songId is error {
        return <http:NotFound>{body: <ErrorResponse>{'error: "Song not found"}};
    }
    Song|error? song = getSongById(songId, caller.userId);  // <-- ownership check
    if song is error || song is () {
        return <http:NotFound>{body: <ErrorResponse>{'error: "Song not found"}};
    }
    return toSongResponse(song);
}

// POST /api/songs — stamps the new song with the caller's userId
resource function post songs(@http:Header string? Authorization,
                              @http:Payload CreateSongRequest songRequest)
        returns http:Created|http:Unauthorized|http:BadRequest {
    CallerInfo|error caller = validateAuthHeader(Authorization);
    if caller is error {
        return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
    }
    // ... validation of title/artist/album/duration/coverUrl unchanged ...
    Song|error newSong = createSong(title, artist, album,
                                    duration, coverUrl, caller.userId);  // <-- sets owner
    if newSong is error {
        return <http:BadRequest>{body: <ErrorResponse>{'error: "Failed to create song"}};
    }
    return <http:Created>{body: toSongResponse(newSong)};
}
```

> **Note on `GET /api/songs/{id}` ownership:** the query uses `WHERE id = ? AND user_id = ?`. If the song exists but belongs to another user, it returns `404` (not `403`). This avoids leaking the existence of other users' songs.

---

## Part 3 — Implementation Order

| Step | Service | File | Action |
|---|---|---|---|
| 1 | auth_service | `types.bal` | Add `ValidateResponse` |
| 2 | auth_service | `functions.bal` | Add `validateJwtToken` |
| 3 | auth_service | `main.bal` | Add `GET /auth/validate`; update CORS `allowHeaders` |
| 4 | webapp_backend | `config.bal` | Remove JWT config; add `authServiceUrl` |
| 5 | webapp_backend | `types.bal` | Remove auth types; add `CallerInfo`; add `user_id` to `Song`; add `ownerId` to `SongResponse` |
| 6 | webapp_backend | `connections.bal` | Add `http:Client`; remove `users` DDL; add `user_id` column to `songs` DDL; remove `seedInitialData` |
| 7 | webapp_backend | `functions.bal` | Remove JWT/user functions; add `validateWithAuthService`; update `getAllSongs`, `getSongById`, `createSong`, `toSongResponse` |
| 8 | webapp_backend | `main.bal` | Remove `POST /api/login`; update `validateAuthHeader` return type; update all resource functions to use `CallerInfo` |
| 9 | webapp_backend | `Config.toml` | Remove JWT config; add `authServiceUrl` |

---

## Part 4 — Resulting Architecture

```
React SPA / Express BFF (port 3001)
         │
         ├── POST /auth/register ──────────────────► auth_service (:9090)
         ├── POST /auth/login    ──────────────────►   auth.db: users(id, username, password_hash, salt)
         │                                             issues JWT with { sub: username, userId: id }
         │
         └── GET|POST /api/songs ──────────────────► webapp_backend (:8080)
                  (Bearer token)                        │
                                                        │  GET /auth/validate
                                                        ├──────────────────► auth_service
                                                        │  ← { userId, username }
                                                        │
                                                        └── sonicwave.db
                                                             songs(id, title, artist, album,
                                                                   duration, cover_url, user_id)
                                                             user_id references auth_service users.id
                                                             (no FK constraint — cross-service ref by ID)
```

---

## Part 5 — Config.toml Updates

**webapp_backend/Config.toml:**
```toml
dbPath         = "./sonicwave.db"
authServiceUrl = "http://localhost:9090"
serverPort     = 8080
```

**auth_service/Config.toml** — no change.

---

## Part 6 — Key Design Rules Enforced

| Rule | Where enforced |
|---|---|
| Songs always have an owner | `user_id NOT NULL` in DDL + required in `createSong` |
| Users see only their songs | `WHERE user_id = ?` in `getAllSongs` |
| Users cannot access others' songs | `WHERE id = ? AND user_id = ?` in `getSongById` |
| Other users' songs return 404 not 403 | Prevents leaking existence of other users' data |
| No seed data | Removed — owned songs must be created by a real user |
| No DB foreign key across services | Intentional — each service owns its DB |
| `userId` always comes from validated JWT | Never trusted from request body or query param |
