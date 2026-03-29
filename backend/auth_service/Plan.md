# Auth Service — Implementation Plan

## Overview

A standalone Ballerina HTTP service that handles user registration, login, and JWT token issuance for the SonicWave platform. It runs independently of `webapp_backend` and uses its own SQLite database.

---

## Tech Stack

| Concern | Choice | Reason |
|---|---|---|
| Language | Ballerina `2201.13.1` | Consistent with `webapp_backend` |
| HTTP | `ballerina/http` | Standard Ballerina HTTP listener |
| Database | SQLite via `ballerinax/java.jdbc` | Same driver pattern as `webapp_backend` |
| Password hashing | SHA-256 + random salt via `ballerina/crypto` + `ballerina/uuid` | Available natively in Ballerina stdlib |
| JWT | HS256 via `ballerina/jwt` | Consistent with existing backend pattern |
| Port | `9090` | Avoids conflict with `webapp_backend` on `8080` |

---

## File Structure

Each file has a single responsibility, matching the convention used in `webapp_backend`:

```
auth_service/
├── Ballerina.toml       — package metadata + sqlite-jdbc platform dependency
├── Plan.md              — this file
├── config.bal           — all configurable values (db path, JWT secret, port)
├── types.bal            — all record type definitions
├── connections.bal      — DB client init, table creation
├── functions.bal        — password hashing, JWT, all DB operations
├── data_mappings.bal    — functions that map DB records → API response types
└── main.bal             — HTTP service, resource functions, request handling
```

---

## Database Schema

Single table. The `webapp_backend` already has a `users` table for its own tracking (username only). This service maintains its own separate DB file with credentials.

```sql
CREATE TABLE IF NOT EXISTS users (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    username     TEXT    NOT NULL UNIQUE,
    password_hash TEXT   NOT NULL,
    salt         TEXT    NOT NULL,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

DB file: `./auth.db` (configurable via `Config.toml`)

---

## API Endpoints

Base path: `/auth`
Port: `9090`

### `POST /auth/register`

Register a new user.

**Request**
```json
{ "username": "lakshan", "password": "secret123" }
```

**Validations**
- `username` — required, not blank, 3–50 characters
- `password` — required, not blank, minimum 6 characters
- `username` must not already exist → `409 Conflict`

**Response — 201 Created**

Same shape as login — the user is automatically signed in after registration:

```json
{
  "token": "<jwt>",
  "user": {
    "id": "1",
    "username": "lakshan"
  }
}
```

**Error responses**

| Status | Body |
|---|---|
| 400 Bad Request | `{ "error": "Username and password are required" }` |
| 400 Bad Request | `{ "error": "Password must be at least 6 characters" }` |
| 409 Conflict | `{ "error": "Username already exists" }` |
| 500 Internal Server Error | `{ "error": "Failed to register user" }` |
| 500 Internal Server Error | `{ "error": "Failed to generate token" }` |

---

### `POST /auth/login`

Authenticate an existing user and return a JWT token.

**Request**
```json
{ "username": "lakshan", "password": "secret123" }
```

**Validations**
- `username` and `password` required, not blank
- User must exist → `401` if not
- Password must match stored hash → `401` if not

**Response — 200 OK**
```json
{
  "token": "<jwt>",
  "user": {
    "id": "1",
    "username": "lakshan"
  }
}
```

**Error responses**

| Status | Body |
|---|---|
| 400 Bad Request | `{ "error": "Username and password are required" }` |
| 401 Unauthorized | `{ "error": "Invalid username or password" }` |
| 500 Internal Server Error | `{ "error": "Failed to generate token" }` |

> Use a generic `"Invalid username or password"` message for both "user not found" and "wrong password" — never reveal which one failed.

---

## Implementation Plan per File

### 1. `Ballerina.toml`

Copy the structure from `webapp_backend/Ballerina.toml`. Change:
- `name` → `"auth_service"`
- `title` → `"auth-service"`
- Keep the same `[[platform.java17.dependency]]` block for `sqlite-jdbc 3.41.2.2`

```toml
[package]
org = "lakshanwso2"
name = "auth_service"
version = "0.1.0"
distribution = "2201.13.1"
title = "auth-service"

[build-options]
sticky = true

[[platform.java17.dependency]]
groupId = "org.xerial"
artifactId = "sqlite-jdbc"
version = "3.41.2.2"
```

---

### 2. `config.bal`

```ballerina
configurable string dbPath        = "./auth.db";
configurable string jwtSecret     = "auth-service-secret-change-in-production";
configurable string jwtIssuer     = "sonicwave-auth";
configurable int    jwtExpiryTime = 86400;   // 24 hours in seconds
configurable int    serverPort    = 9090;
```

---

### 3. `types.bal`

**DB record (maps directly to the `users` table row):**
```ballerina
type User record {|
    int    id;
    string username;
    string password_hash;
    string salt;
    string created_at?;
|};
```

**API request types:**
```ballerina
type RegisterRequest record {|
    string username;
    string password;
|};

type LoginRequest record {|
    string username;
    string password;
|};
```

**API response types:**
```ballerina
type UserResponse record {|
    string id;
    string username;
|};

// Shared by both /auth/register and /auth/login
type AuthResponse record {|
    string token;
    UserResponse user;
|};

type ErrorResponse record {|
    string 'error;
|};
```

---

### 4. `connections.bal`

Imports: `ballerinax/java.jdbc`

Responsibilities:
- Declare the module-level `final jdbc:Client dbClient`
- `initDatabase()` — opens the JDBC connection and calls `createTables()`
- `createTables()` — executes the `CREATE TABLE IF NOT EXISTS` DDL for `users`

Pattern: identical to `webapp_backend/connections.bal`. No seed data needed — users are created via the register endpoint.

```ballerina
import ballerinax/java.jdbc;

final jdbc:Client dbClient = check initDatabase();

function initDatabase() returns jdbc:Client|error {
    jdbc:Client client = check new ("jdbc:sqlite:" + dbPath, "", "");
    check createTables(client);
    return client;
}

function createTables(jdbc:Client client) returns error? {
    _ = check client->execute(`
        CREATE TABLE IF NOT EXISTS users (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            username      TEXT    NOT NULL UNIQUE,
            password_hash TEXT    NOT NULL,
            salt          TEXT    NOT NULL,
            created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
}
```

---

### 5. `functions.bal`

Imports: `ballerina/jwt`, `ballerina/crypto`, `ballerina/uuid`, `ballerina/sql`

#### Password hashing

Use SHA-256 with a UUID v4 salt. The salt is generated once at registration and stored in the DB alongside the hash.

```ballerina
// Generate a random salt (called once at registration)
function generateSalt() returns string {
    return uuid:createType4AsString();
}

// Hash a password with a given salt
function hashPassword(string password, string salt) returns string {
    byte[] input = (password + salt).toBytes();
    byte[] hashed = crypto:hashSha256(input);
    return hashed.toBase16();
}

// Verify a password against a stored hash+salt
function verifyPassword(string password, string salt, string storedHash) returns boolean {
    return hashPassword(password, salt) == storedHash;
}
```

#### JWT generation

Same `jwt:issue` pattern as `webapp_backend`:

```ballerina
function generateJwtToken(int userId, string username) returns string|error {
    jwt:IssuerConfig issuerConfig = {
        username: username,
        issuer: jwtIssuer,
        audience: "sonicwave-users",
        expTime: <decimal>jwtExpiryTime,
        customClaims: { "userId": userId.toString() },
        signatureConfig: {
            algorithm: jwt:HS256,
            config: jwtSecret
        }
    };
    return check jwt:issue(issuerConfig);
}
```

#### DB operations

```
insertUser(username, passwordHash, salt)  → User|error
getUserByUsername(username)               → User|error?
```

- `insertUser` — executes `INSERT INTO users`, reads back `lastInsertId`, returns the full `User` record.
- `getUserByUsername` — `queryRow` with `sql:NoRowsError` guard returning `()` (nil) when not found, matching the pattern in `webapp_backend/functions.bal`.

---

### 6. `data_mappings.bal`

Single mapping function shared by both register and login:

```ballerina
function toAuthResponse(User user, string token) returns AuthResponse {
    return {
        token: token,
        user: {
            id: user.id.toString(),
            username: user.username
        }
    };
}
```

---

### 7. `main.bal`

Imports: `ballerina/http`

CORS config: allow `http://localhost:3001` (the BFF), matching `webapp_backend`.

```
@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:3001"],
        allowMethods: ["POST", "OPTIONS"],
        allowHeaders: ["Content-Type"],
        allowCredentials: true
    }
}
service /auth on new http:Listener(serverPort)
```

#### `POST /auth/register` logic

1. Trim and validate `username` and `password`.
2. Check `username` length (3–50 chars) and `password` minimum length (6 chars).
3. Call `getUserByUsername(username)` — if a user is returned, return `409 Conflict`.
4. Call `generateSalt()`, then `hashPassword(password, salt)`.
5. Call `insertUser(username, hash, salt)`.
6. Call `generateJwtToken(newUser.id, newUser.username)`.
7. Return `201 Created` with `toAuthResponse(newUser, token)`.

#### `POST /auth/login` logic

1. Trim and validate `username` and `password`.
2. Call `getUserByUsername(username)` — if `()`, return `401` (generic message).
3. Call `verifyPassword(password, user.salt, user.password_hash)` — if false, return `401` (same generic message).
4. Call `generateJwtToken(user.id, user.username)`.
5. Return `200 OK` with `toAuthResponse(user, token)`.

---

## Config.toml (runtime overrides)

Create `auth_service/Config.toml` for local development:

```toml
dbPath        = "./auth.db"
jwtSecret     = "auth-service-secret-change-in-production"
jwtIssuer     = "sonicwave-auth"
jwtExpiryTime = 86400
serverPort    = 9090
```

---

## Running the Service

```bash
cd backend/auth_service
bal run
```

Server starts at `http://localhost:9090`.

---

## Implementation Steps (Ordered)

| Step | File | Action |
|---|---|---|
| 1 | `Ballerina.toml` | Add package metadata and sqlite-jdbc platform dependency |
| 2 | `config.bal` | Define all configurable values |
| 3 | `types.bal` | Define all record types (DB + request + response) |
| 4 | `connections.bal` | DB client init and `CREATE TABLE IF NOT EXISTS` |
| 5 | `functions.bal` | Password hashing helpers, JWT generation, `insertUser`, `getUserByUsername` |
| 6 | `data_mappings.bal` | `toRegisterResponse` mapping function |
| 7 | `main.bal` | HTTP service with `/auth/register` and `/auth/login` resource functions |
| 8 | `Config.toml` | Local runtime config values |
