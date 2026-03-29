# Auth Handler — Delegating Authentication to a Separate Service

## The Problem

Currently the Ballerina backend (`webapp_backend`) both **issues** and **validates** JWT tokens using a single shared secret (`jwtSecret`, HS256). The same secret is used in `generateJwtToken` and `validateJwtToken` in `functions.bal`.

```
Current flow:
  Client  →  POST /api/login  →  Ballerina backend  →  generates JWT with jwtSecret
  Client  →  GET  /api/songs  →  Ballerina backend  →  validates JWT with same jwtSecret
```

When a **separate auth service** takes over login and token issuance, the Ballerina backend no longer has access to the signing secret (nor should it — that is the auth service's concern). It still needs to be able to **verify** that a token is genuine and has not been tampered with. That is a different operation from issuing tokens.

---

## The Core Challenge: Symmetric vs Asymmetric Keys

| Mode | Algorithm | Who can verify |
|---|---|---|
| Symmetric (current) | HS256 | Anyone who holds the secret — so the secret must be shared |
| Asymmetric (standard) | RS256 / ES256 | Anyone with the **public key** — the private key stays with the auth service only |

Moving to an asymmetric algorithm is the foundation of every industry-standard approach.

---

## Industry Standard: OAuth 2.0 + OIDC + JWKS

### What these are

- **OAuth 2.0** (RFC 6749) — the authorisation delegation framework. Defines how a client obtains tokens from an authorisation server.
- **OpenID Connect (OIDC)** — a thin identity layer on top of OAuth 2.0. Adds a standard `id_token` (a JWT) carrying the user's identity claims.
- **JWKS** (JSON Web Key Sets, RFC 7517) — the standard format for an auth service to **publish its public keys** so that any resource server can validate tokens without ever receiving a private key or secret.

An OIDC-compliant auth service exposes a discovery document at:
```
GET /.well-known/openid-configuration
```
which advertises (among other things) a `jwks_uri`:
```json
{
  "issuer": "https://auth.sonicwave.io",
  "jwks_uri": "https://auth.sonicwave.io/.well-known/jwks.json",
  ...
}
```

The `jwks.json` endpoint returns the auth service's current public key(s):
```json
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "kid": "key-id-1",
      "alg": "RS256",
      "n":   "<modulus>",
      "e":   "AQAB"
    }
  ]
}
```

Any service that receives a JWT simply fetches this endpoint, finds the matching key (by `kid` in the token header), and verifies the signature — **without needing any secret**.

---

## Approaches for the Ballerina Backend

### Approach 1 — JWKS-Based Validation (Recommended)

The auth service signs tokens with RS256 (or ES256) using its private key and publishes the corresponding public keys at a JWKS endpoint. The Ballerina backend fetches and caches those keys to validate incoming tokens.

**What changes in the Ballerina backend:**

1. **Remove** `generateJwtToken` from `functions.bal` entirely. Token issuance is no longer the backend's responsibility.
2. **Remove** `POST /api/login` from `main.bal` (or keep it as a thin redirect/proxy to the auth service login endpoint if needed by the BFF).
3. **Replace** the `validateJwtToken` function:

   ```ballerina
   // Before (HS256 shared secret)
   function validateJwtToken(string token) returns jwt:Payload|error {
       jwt:ValidatorConfig validatorConfig = {
           issuer: jwtIssuer,
           audience: "sonicwave-users",
           signatureConfig: {
               secret: jwtSecret          // <-- shared secret
           }
       };
       return check jwt:validate(token, validatorConfig);
   }

   // After (RS256 via JWKS)
   function validateJwtToken(string token) returns jwt:Payload|error {
       jwt:ValidatorConfig validatorConfig = {
           issuer: "https://auth.sonicwave.io",   // auth service issuer
           audience: "sonicwave-api",              // audience for this resource server
           signatureConfig: {
               jwksConfig: {
                   url: "https://auth.sonicwave.io/.well-known/jwks.json",
                   cacheConfig: {
                       capacity: 10,
                       evictionFactor: 0.25,
                       defaultMaxAge: 900   // cache keys for 15 minutes
                   }
               }
           }
       };
       return check jwt:validate(token, validatorConfig);
   }
   ```

4. **Update `config.bal`** to replace `jwtSecret` / `jwtIssuer` with:
   ```ballerina
   configurable string authIssuer  = "https://auth.sonicwave.io";
   configurable string authJwksUrl = "https://auth.sonicwave.io/.well-known/jwks.json";
   configurable string jwtAudience = "sonicwave-api";
   ```

**Why this is the right approach:**
- The private key never leaves the auth service. A compromised backend cannot forge tokens.
- It is completely standard — any OIDC-compliant provider (Auth0, Keycloak, AWS Cognito, Google, Azure AD) works without code changes, only config changes.
- JWKS key caching means validation is fast (no network call per request after initial fetch).
- Key rotation is handled automatically: when the auth service rotates keys it publishes the new key in JWKS alongside the old one; the backend picks it up on the next cache miss.

---

### Approach 2 — Token Introspection (RFC 7662)

Instead of validating the token locally, the backend calls the auth service's introspection endpoint on every request:

```
POST https://auth.sonicwave.io/oauth2/introspect
Authorization: Basic <client-credentials>
Content-Type: application/x-www-form-urlencoded

token=<the-jwt>
```

Response:
```json
{ "active": true, "sub": "testuser", "exp": 1774788221, ... }
```

**When to use this:**
- When you need **real-time revocation** — a user logs out, the auth service marks the token inactive, and the next introspection call returns `"active": false`. JWKS-based local validation cannot detect revocation mid-token-lifetime.
- When the token is opaque (not a JWT) and has no payload to inspect locally.

**Trade-off:** Every authenticated request adds a network round-trip to the auth service. This can be mitigated by caching introspection results for a short TTL (e.g. 30 seconds).

---

### Approach 3 — Shared Secret Migration (Not Recommended for Production)

Both the auth service and the Ballerina backend use the same HS256 secret. This is the minimal-change option: only the `jwtIssuer` value in the validator config needs updating.

**Why to avoid this:**
- The secret must be distributed to every service that validates tokens. More services = wider blast radius if the secret leaks.
- Key rotation requires coordinated redeployment of all services simultaneously.
- It does not scale to multiple resource servers or third-party integrations.

This is only acceptable as a temporary bridge during a migration period.

---

## Updated Architecture with a Separate Auth Service

```
┌─────────────────────────────────────────────────────────────────┐
│                        Auth Service                             │
│   POST /api/login → issues RS256 JWT                           │
│   GET  /.well-known/jwks.json → publishes public key           │
└───────────────┬─────────────────────────────┬───────────────────┘
                │ issues token                │ JWKS public key
                ▼                             ▼ (cached, ~15 min TTL)
┌───────────────────────┐        ┌────────────────────────────────┐
│   React SPA           │        │   Ballerina Backend            │
│   (webapp-frontend)   │        │   (webapp_backend, port 8080)  │
│                       │        │                                │
│  stores JWT in        │        │  validates JWT signature       │
│  localStorage         │        │  against cached JWKS key       │
│                       │        │  serves songs data             │
└────────┬──────────────┘        └────────────────────────────────┘
         │                                       ▲
         │ all requests via Express BFF          │
         ▼                                       │
┌───────────────────────┐                        │
│   Express BFF         │  proxies /api/* ───────┘
│   (port 3001)         │
└───────────────────────┘
```

### Login flow (with separate auth service)

```
1. User submits username in React frontend
2. React calls  POST /api/login  on Express BFF
3. Express BFF proxies to auth service  POST /auth/login
4. Auth service creates/looks up user, signs JWT with RS256 private key, returns token
5. Token flows back through BFF to the React frontend
6. React stores token in localStorage

On subsequent requests:
7. React sends  GET /api/songs  with  Authorization: Bearer <token>
8. Express BFF proxies to  GET /api/songs  on Ballerina backend
9. Ballerina backend validates token:
   a. Decodes JWT header, reads  kid  (key ID)
   b. Fetches JWKS from auth service (or uses cache)
   c. Finds matching public key by  kid
   d. Verifies RS256 signature
   e. Checks  iss, aud, exp  claims
10. If valid → returns song data. If invalid → 401.
```

---

## Key JWT Claims the Backend Must Validate

Regardless of approach, the backend must always verify these claims:

| Claim | Purpose | Expected value |
|---|---|---|
| `iss` (issuer) | Confirms the token was issued by the trusted auth service | `"https://auth.sonicwave.io"` |
| `aud` (audience) | Confirms the token was intended for this specific resource server | `"sonicwave-api"` |
| `exp` (expiry) | Confirms the token has not expired | must be in the future |
| `sub` (subject) | The user identity to use in application logic | e.g. `"testuser"` |
| signature | Confirms the token has not been tampered with | verified via JWKS or secret |

The `aud` claim is important — a token issued for the auth service itself or for a different resource server should be rejected even if the signature is valid.

---

## What Changes in Each Layer

| Layer | Current | After separating auth |
|---|---|---|
| Auth service | Does not exist — Ballerina backend handles login | Owns login, user creation, JWT issuance, JWKS endpoint |
| Ballerina backend | Issues + validates HS256 tokens | Validates RS256 tokens via JWKS only. No login route. |
| Express BFF | Proxies `/api/login` to Ballerina | Proxies `/api/login` to auth service; proxies `/api/songs` to Ballerina backend |
| React frontend | No changes needed | No changes needed — it only sees tokens and stores them |

---

## Recommended Provider Options

If the auth service is a third-party or managed identity provider, the JWKS approach works out of the box with any of these:

| Provider | JWKS URL pattern |
|---|---|
| Auth0 | `https://<tenant>.auth0.com/.well-known/jwks.json` |
| Keycloak | `https://<host>/realms/<realm>/protocol/openid-connect/certs` |
| AWS Cognito | `https://cognito-idp.<region>.amazonaws.com/<pool-id>/.well-known/jwks.json` |
| Azure AD | `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys` |
| Google | `https://www.googleapis.com/oauth2/v3/certs` |

Only the `authJwksUrl`, `authIssuer`, and `jwtAudience` config values in `config.bal` need to change — the validation logic stays the same.

---

## WSO2 API Manager + WSO2 Identity Server

### Corrected Architecture

The Express BFF is part of the **frontend application** — it serves the React SPA and proxies API calls on behalf of the browser. It is not a separate backend service.

WSO2 APIM sits between the **frontend application (BFF)** and the **Ballerina backend**. WSO2 Identity Server acts as the Key Manager — it owns user identity, issues JWT access tokens, and exposes a JWKS endpoint that APIM uses to validate those tokens.

The Ballerina backend has **no JWT validation responsibility**. APIM is the sole trust enforcement point. If a request reaches the Ballerina backend, APIM has already validated it.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Frontend Application                          │
│                                                                  │
│   ┌──────────────┐   browser calls   ┌──────────────────────┐  │
│   │  React SPA   │ ────────────────► │   Express BFF        │  │
│   │  (browser)   │ ◄──────────────── │   (port 3001)        │  │
│   └──────────────┘                   └──────────┬───────────┘  │
│                                                  │              │
└──────────────────────────────────────────────────┼──────────────┘
                                                   │
                                    Bearer <IS JWT> │
                                                   ▼
                              ┌────────────────────────────────────┐
                              │       WSO2 APIM Gateway            │
                              │                                    │
                              │  Validates JWT via WSO2 IS JWKS   │
                              │  Enforces subscription & policies  │
                              │  Forwards clean request to backend │
                              └──────────────┬─────────────────────┘
                                             │
                                             │  (no Authorization header)
                                             ▼
                              ┌────────────────────────────────────┐
                              │   Ballerina Backend (port 8080)    │
                              │                                    │
                              │   No JWT validation                │
                              │   Trusts APIM as the security      │
                              │   boundary — serves business logic  │
                              └────────────────────────────────────┘

                              ┌────────────────────────────────────┐
                              │       WSO2 Identity Server         │
                              │                                    │
                              │   User management & login UI       │
                              │   Issues OAuth2 JWT access tokens  │
                              │   JWKS: /oauth2/jwks               │
                              │   Token endpoint: /oauth2/token    │
                              │   Introspect: /oauth2/introspect   │
                              └────────────────────────────────────┘
```

---

### Yes — WSO2 IS Works as the Auth Handler

WSO2 IS is a full OIDC-compliant identity provider and is the **native Key Manager for WSO2 APIM**. They integrate directly — APIM ships with built-in support for WSO2 IS as a Key Manager, so no custom adapter is needed. WSO2 IS handles:

- User registration and login (login UI, SSO, MFA)
- OAuth2 token issuance (JWT access tokens, refresh tokens)
- JWKS endpoint for token validation by APIM
- Token revocation and session management
- User claims and attribute management

---

### WSO2 APIM Components

| Component | Default port | Role |
|---|---|---|
| **API Gateway** | 8243 (HTTPS), 8280 (HTTP) | Intercepts all API traffic, validates tokens, enforces policies |
| **Publisher Portal** | 9443 | Define and publish APIs |
| **Developer Portal** | 9443 | Register apps, subscribe to APIs, get client credentials |
| **Admin Portal** | 9443 | Configure Key Managers, throttling policies, etc. |
| **Key Manager (WSO2 IS)** | 9443 (separate IS node) | Issues and validates OAuth2 tokens |

---

### How Token Validation Works at the APIM Gateway

WSO2 APIM supports two validation modes and selects automatically based on token format:

#### JWT Access Tokens (offline validation — preferred)

WSO2 IS can issue **JWT access tokens** (enabled by default from IS 5.10+). When a JWT arrives at the gateway:

1. Gateway reads the `kid` from the JWT header.
2. Gateway looks up its local JWKS cache (populated from WSO2 IS JWKS endpoint: `https://<is-host>:9443/oauth2/jwks`).
3. Verifies the RS256 signature locally — **no call to IS per request**.
4. Validates `iss`, `aud`, `exp`, and the API subscription claim.
5. If valid → forwards to backend. If invalid → returns `401` without touching the backend.

The JWKS cache refreshes on a configured interval and on `kid` miss (key rotation).

#### Opaque (reference) tokens (online validation)

If IS is configured to issue opaque tokens, APIM calls IS's introspection endpoint per request:
```
POST https://<is-host>:9443/oauth2/introspect
```
Higher latency but provides real-time revocation. Not needed if JWT access tokens are used.

---

### Login Flow — Authorization Code + PKCE (Recommended)

For the BFF pattern, Authorization Code + PKCE is the right flow. The BFF acts as a **confidential OAuth2 client** — it holds the `client_secret` securely on the server side, which the browser never sees.

```
1.  User clicks Login in React SPA
2.  React SPA calls Express BFF: GET /auth/login
3.  Express BFF generates a PKCE code_verifier + code_challenge,
    stores code_verifier in server-side session, and redirects browser to:

    https://<is-host>:9443/oauth2/authorize
      ?response_type=code
      &client_id=<client_id>
      &redirect_uri=http://localhost:3001/auth/callback
      &scope=openid profile
      &code_challenge=<code_challenge>
      &code_challenge_method=S256

4.  Browser lands on WSO2 IS login page
5.  User enters credentials and authenticates
6.  IS redirects browser back to:
    http://localhost:3001/auth/callback?code=<auth_code>

7.  Express BFF receives the auth code, exchanges it with IS:
    POST https://<is-host>:9443/oauth2/token
      grant_type=authorization_code
      &code=<auth_code>
      &redirect_uri=http://localhost:3001/auth/callback
      &client_id=<client_id>
      &client_secret=<client_secret>
      &code_verifier=<code_verifier>

8.  IS returns:
    { "access_token": "<JWT>", "refresh_token": "...", "id_token": "...", "expires_in": 3600 }

9.  Express BFF stores tokens in a server-side session (or httpOnly cookie)
    and returns user info to the React SPA
10. React SPA updates UI to show logged-in state
```

The browser never holds the `access_token` directly — the BFF manages it. For API calls, the BFF attaches the token server-side before proxying to APIM.

---

### Authenticated API Call Flow

```
1.  React SPA calls Express BFF: GET /api/songs
2.  Express BFF retrieves the stored access_token from session
3.  Express BFF forwards to APIM:
    GET https://<apim-gateway>:8243/sonicwave/v1/songs
    Authorization: Bearer <IS JWT access token>

4.  APIM gateway validates the token:
    a. Decodes JWT header, reads kid
    b. Fetches WSO2 IS JWKS (cached): https://<is-host>:9443/oauth2/jwks
    c. Verifies RS256 signature
    d. Checks iss (IS issuer), exp, aud, subscription validity

5.  If valid:
    a. APIM strips the Authorization header
    b. Forwards the request to the Ballerina backend:
       GET http://<ballerina-host>:8080/api/songs
       (no Authorization header — APIM has already enforced security)

6.  Ballerina backend processes the request and returns songs
    (no token validation, no auth check)

7.  Response flows back: Ballerina → APIM → Express BFF → React SPA
```

---

### What Changes in the Ballerina Backend

Because APIM is the trust boundary, the Ballerina backend removes **all** JWT validation code:

**Remove from `functions.bal`:**
- `generateJwtToken` function
- `validateJwtToken` function

**Remove from `main.bal`:**
- `POST /api/login` route (login is handled by WSO2 IS via the BFF)
- All `Authorization` header reads
- All `requireAuth` / auth middleware calls

**Resource functions become straightforward:**

```ballerina
// Before — with auth check
resource function get songs(http:Request req) returns SongResponse[]|http:Unauthorized {
    string|error token = extractToken(req);
    if token is error { return <http:Unauthorized>{}; }
    // validate token...
    return getSongs();
}

// After — APIM handles auth, backend just serves data
resource function get songs() returns SongResponse[] {
    return getSongs();
}
```

**Remove from `config.bal`:**
- `jwtSecret`
- `jwtIssuer`
- Any JWT-related config

The Ballerina backend becomes a clean, auth-free data service reachable only through APIM.

---

### Step-by-Step Setup

#### 1. Set up WSO2 Identity Server

1. Download and start WSO2 IS (runs on port 9443).
2. Log into the IS Management Console: `https://localhost:9443/carbon`
3. Enable JWT access tokens (IS 5.10+ enables this by default).
4. Create a user account for testing (or configure a user store).

#### 2. Register WSO2 IS as a Key Manager in WSO2 APIM

1. Log into APIM Admin Portal: `https://localhost:9443/admin`
2. **Key Managers** → **Add Key Manager**
3. Fill in:
   - **Name**: `WSO2-IS`
   - **Key Manager Type**: `WSO2 Identity Server`
   - **Well-known URL**:
     ```
     https://<is-host>:9443/oauth2/oidcdiscovery/.well-known/openid-configuration
     ```
   - Click **Import** — APIM auto-discovers token endpoint, JWKS URL, introspect URL from the well-known document.
4. Save. APIM will now route token operations through WSO2 IS.

#### 3. Publish the SonicWave API in APIM

1. Log into Publisher Portal: `https://localhost:9443/publisher`
2. **Create API** → **Start from Scratch**
3. Set:
   - **Name**: `SonicWaveAPI`
   - **Context**: `/sonicwave`
   - **Version**: `v1`
   - **Endpoint**: `http://<ballerina-host>:8080`
4. Add resources matching the Ballerina backend:
   - `GET /api/songs`
   - `GET /api/songs/{id}`
   - `POST /api/songs`
5. Under **Runtime** → **API Security**: enable **OAuth2**, select `WSO2-IS` as the Key Manager.
6. **Deploy** and **Publish** the API.

#### 4. Create an Application and Subscribe in Developer Portal

1. Log into Developer Portal: `https://localhost:9443/devportal`
2. **Applications** → **Add New Application**
   - **Name**: `SonicWaveApp`
   - **Throttling tier**: `Unlimited`
3. Open the application → **Subscriptions** → subscribe to `SonicWaveAPI v1`.
4. **Production Keys** → **Generate Keys**
   - Select Key Manager: `WSO2-IS`
   - Grant types: `Authorization Code`, `Refresh Token`
   - Callback URL: `http://localhost:3001/auth/callback`
   - Click **Generate** — this registers an OAuth2 client in WSO2 IS and returns a `client_id` and `client_secret`.
5. Note the `client_id` and `client_secret` — these go into the Express BFF config.

#### 5. Configure the Express BFF

Add to the BFF's environment config (`.env.local`):

```
IS_BASE_URL=https://localhost:9443
APIM_GATEWAY_URL=https://localhost:8243/sonicwave/v1
OAUTH_CLIENT_ID=<client_id from Developer Portal>
OAUTH_CLIENT_SECRET=<client_secret from Developer Portal>
OAUTH_REDIRECT_URI=http://localhost:3001/auth/callback
OAUTH_SCOPES=openid profile
```

The BFF gains two new routes alongside its existing proxy:
- `GET /auth/login` — builds the IS authorization URL and redirects the browser
- `GET /auth/callback` — exchanges the auth code for tokens, stores them in session

For subsequent `/api/*` calls, the BFF reads the stored `access_token` from session and injects it as the `Authorization: Bearer` header before proxying to APIM.

---

### Responsibility of Each Layer

| Layer | Owns | Does NOT do |
|---|---|---|
| **WSO2 IS** | User identity, login UI, token issuance, JWKS, token revocation | API traffic routing |
| **WSO2 APIM Gateway** | JWT validation (against IS JWKS), subscription enforcement, rate limiting, threat protection | Issuing tokens, serving business data |
| **Express BFF** | OAuth2 Authorization Code flow, token storage (session), SPA serving, API proxying to APIM | Token validation, business logic |
| **React SPA** | UI, triggering login redirect, displaying data | Holding tokens, API calls (BFF does this) |
| **Ballerina Backend** | Songs data, business logic | Any auth or token validation |

---

### Network-Level Hardening

APIM absorbs all auth responsibility at the application layer, but the Ballerina backend must also be hardened at the network layer so that nothing can bypass APIM and call it directly:

- **Private network**: backend is on an internal subnet, not reachable from the internet or the BFF directly — only from APIM.
- **IP allowlist**: backend firewall accepts inbound connections only from APIM gateway node IP(s).
- **Mutual TLS (mTLS)**: APIM presents a client certificate to the backend; backend rejects connections without it.

These are complementary — application-level JWT validation at APIM plus network isolation at the backend gives defence in depth.

---

### Summary of Changes Across the Stack

| Aspect | Current (self-contained) | With APIM + WSO2 IS |
|---|---|---|
| Who issues tokens | Ballerina backend (`generateJwtToken`) | WSO2 IS via OAuth2 Authorization Code flow |
| Who validates tokens | Ballerina backend (`validateJwtToken`) | WSO2 APIM Gateway (against IS JWKS) |
| Login route | `POST /api/login` on Ballerina | IS login UI; BFF handles the OAuth2 code exchange |
| Token storage | React `localStorage` (access token) | Express BFF server-side session (access token never in browser) |
| Ballerina backend auth code | Present (`validateJwtToken`, auth middleware) | Removed entirely |
| Express BFF role | Dumb proxy for `/api/*` | OAuth2 client (login flow) + token-injecting proxy to APIM |

---

## Key Manager Options for WSO2 APIM

### Option 1 — APIM Resident (Integrated) Key Manager

WSO2 APIM ships with a built-in Key Manager called the **Resident Key Manager**. It is enabled by default and requires no additional software installation or configuration. APIM itself handles token issuance, validation, and OAuth2 application registration.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Frontend Application                          │
│   React SPA  ←──►  Express BFF (port 3001)                     │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Bearer <token issued by APIM itself>
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│               WSO2 APIM (all-in-one)                            │
│                                                                  │
│   ┌─────────────────────────┐  ┌──────────────────────────┐    │
│   │   API Gateway           │  │  Resident Key Manager    │    │
│   │   - validates tokens    │  │  - issues tokens         │    │
│   │   - enforces policies   │  │  - /oauth2/token         │    │
│   │   - forwards to backend │  │  - /oauth2/jwks          │    │
│   └─────────────────────────┘  └──────────────────────────┘    │
│                                                                  │
│   Developer Portal  ──  app registration, key generation        │
└──────────────────────────────┬──────────────────────────────────┘
                               │ clean request (no auth header)
                               ▼
                  ┌────────────────────────────┐
                  │  Ballerina Backend (:8080) │
                  │  no JWT validation         │
                  └────────────────────────────┘
```

**How it works:**

- Tokens are issued by APIM's own OAuth2 token endpoint: `https://<apim-host>:9443/oauth2/token`
- The gateway validates tokens it issued itself — it knows the signing key internally, no JWKS fetch needed
- The Developer Portal is where the BFF's OAuth2 application is registered to get a `client_id` and `client_secret`
- Supported grant types: Authorization Code, Client Credentials, Password, Refresh Token, JWT Bearer

**Setup — what is different from the WSO2 IS setup:**

Nothing extra to install. The only difference in setup steps is:

1. Skip the "Register WSO2 IS as Key Manager" step entirely — the Resident Key Manager is already active.
2. In the Developer Portal under **Production Keys**, the Key Manager dropdown shows `Resident Key Manager` — select that when generating keys.
3. The BFF's `IS_BASE_URL` and `APIM_GATEWAY_URL` both point to the same APIM host:
   ```
   OAUTH_TOKEN_URL=https://<apim-host>:9443/oauth2/token
   OAUTH_AUTHORIZE_URL=https://<apim-host>:9443/oauth2/authorize
   OAUTH_JWKS_URL=https://<apim-host>:9443/oauth2/jwks
   ```

**When to choose this:**
- You want the simplest possible setup with one product to deploy and maintain.
- You do not need advanced identity features (MFA, SSO across multiple apps, federated login, user provisioning).
- The application manages its own user base through APIM's user store (backed by the embedded H2 or an LDAP/AD you connect).

---

### Option 2 — WSO2 Identity Server (Separate)

Covered in detail in the previous section. Choose this when you need enterprise identity features — MFA, federation with corporate LDAP/AD, SSO across multiple applications, or fine-grained user attribute management — while still using WSO2's native tooling.

---

### Option 3 — Keycloak

An open-source identity provider by Red Hat, widely used in enterprise environments. APIM supports Keycloak as an external Key Manager via the OIDC well-known discovery document.

**Keycloak well-known URL:**
```
https://<keycloak-host>/realms/<realm>/.well-known/openid-configuration
```

**Notable characteristics:**
- Free and open-source, large community
- Strong support for federation (LDAP, Active Directory, SAML, social login)
- Realm-based multi-tenancy
- Rich admin UI for user and client management
- Fine-grained authorisation policies (UMA 2.0)

**APIM Key Manager registration:**
1. Admin Portal → Key Managers → Add Key Manager
2. Type: `Keycloak`
3. Well-known URL: `https://<keycloak-host>/realms/<realm>/.well-known/openid-configuration`
4. APIM auto-populates token, introspect, and JWKS endpoints from the discovery document.

---

### Option 4 — Auth0

A cloud-managed identity platform. Suitable when you want zero infrastructure to manage for the identity layer.

**Auth0 well-known URL:**
```
https://<tenant>.auth0.com/.well-known/openid-configuration
```

**Notable characteristics:**
- Fully managed SaaS — no servers to operate
- Generous free tier for low-volume applications
- Extensive social login providers out of the box
- Actions/Rules for customising token claims
- Strong support for machine-to-machine (M2M) flows

**APIM Key Manager registration:**
1. Admin Portal → Key Managers → Add Key Manager
2. Type: `Auth0`  *(or generic `OIDC` if the Auth0 type is not listed)*
3. Well-known URL: `https://<tenant>.auth0.com/.well-known/openid-configuration`

---

### Option 5 — Okta

Another cloud-managed identity platform, common in enterprise SaaS contexts.

**Okta well-known URL:**
```
https://<okta-domain>/oauth2/default/.well-known/openid-configuration
```

**Notable characteristics:**
- Strong enterprise integrations (HR systems, Active Directory sync, SCIM provisioning)
- Lifecycle management (automated onboarding/offboarding)
- Adaptive MFA with risk-based step-up
- Developer-friendly SDKs

**APIM Key Manager registration:**
1. Admin Portal → Key Managers → Add Key Manager
2. Type: `Okta` *(or generic `OIDC`)*
3. Well-known URL: `https://<okta-domain>/oauth2/default/.well-known/openid-configuration`

---

### Option 6 — AWS Cognito

Amazon's managed identity service. Natural choice when the rest of the infrastructure runs on AWS.

**Cognito well-known URL:**
```
https://cognito-idp.<region>.amazonaws.com/<user-pool-id>/.well-known/openid-configuration
```

**Notable characteristics:**
- Native integration with AWS services (API Gateway, ALB, Lambda authorisers)
- Scales automatically
- User Pools (authentication) and Identity Pools (federated access to AWS resources) are separate concepts
- Pricing is per-MAU (monthly active user)

**APIM Key Manager registration:**
1. Admin Portal → Key Managers → Add Key Manager
2. Type: generic `OIDC`
3. Well-known URL: Cognito well-known URL above

---

### Option 7 — Azure AD / Microsoft Entra ID

Microsoft's identity platform. The obvious choice when the organisation is on Microsoft 365 or Azure.

**Azure AD well-known URL:**
```
https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration
```

**Notable characteristics:**
- SSO with Microsoft 365, Teams, and all Azure-integrated enterprise apps
- Conditional Access policies (device compliance, location, risk score)
- Groups and roles mapped directly from Azure AD into JWT claims
- Guest/B2B access for external collaborators

**APIM Key Manager registration:**
1. Admin Portal → Key Managers → Add Key Manager
2. Type: generic `OIDC`
3. Well-known URL: Azure AD well-known URL above

---

### Option 8 — Any OIDC-Compliant Provider

If your identity provider is not in the list above, APIM supports a **generic OIDC** Key Manager type. As long as the provider:
- Exposes a `/.well-known/openid-configuration` discovery document
- Issues RS256 or ES256 JWTs
- Publishes a JWKS endpoint

it can be registered as a Key Manager with no custom code.

---

### Comparison

| Key Manager | Hosting | Best for | Extra infra? |
|---|---|---|---|
| **Resident (Integrated)** | Embedded in APIM | Simple setups, single app, no advanced identity needs | None |
| **WSO2 IS** | Self-hosted | Enterprise, WSO2-native stack, advanced SSO/MFA | Separate IS node |
| **Keycloak** | Self-hosted or cloud | Open-source preference, multi-realm, LDAP/AD federation | Separate Keycloak node |
| **Auth0** | SaaS | Minimal ops, rapid development, social login | None |
| **Okta** | SaaS | Enterprise SaaS, HR integration, lifecycle management | None |
| **AWS Cognito** | SaaS (AWS) | AWS-native infrastructure | None |
| **Azure AD** | SaaS (Microsoft) | Microsoft 365 / Azure organisations | None |
| **Generic OIDC** | Any | Any standards-compliant provider not listed above | Depends on provider |

**In every case the Ballerina backend requires zero changes** — it never validates tokens regardless of which Key Manager is active. The Key Manager choice only affects the APIM configuration and the BFF's OAuth2 endpoints.

---

### Using the Resident Key Manager — What Changes in the BFF vs WSO2 IS

The only practical difference when using the Resident Key Manager versus WSO2 IS is where the BFF points for the OAuth2 endpoints. The flow and code are identical.

| Config | With Resident KM | With WSO2 IS |
|---|---|---|
| `OAUTH_TOKEN_URL` | `https://<apim>:9443/oauth2/token` | `https://<is>:9443/oauth2/token` |
| `OAUTH_AUTHORIZE_URL` | `https://<apim>:9443/oauth2/authorize` | `https://<is>:9443/oauth2/authorize` |
| `OAUTH_JWKS_URL` | `https://<apim>:9443/oauth2/jwks` | `https://<is>:9443/oauth2/jwks` |
| Infrastructure | APIM only | APIM + separate IS node |
| App registration | APIM Developer Portal | APIM Developer Portal (keys provisioned on IS) |
