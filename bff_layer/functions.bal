import ballerina/http;
import ballerina/log;
import ballerina/time;

// ─── APIM CC token cache ───────────────────────────────────────────────────────
// Simple in-memory cache per process. For multiple BFF instances each fetches
// its own token — APIM issues and accepts multiple valid CC tokens concurrently.

string  cachedCcToken     = "";
decimal cachedCcExpiresAt = 0d;

function getCcToken() returns string|error {
    time:Utc now     = time:utcNow();
    decimal  nowSecs = <decimal>now[0] + now[1];

    if cachedCcToken.length() > 0 && cachedCcExpiresAt - nowSecs > 60d {
        return cachedCcToken;
    }

    string credentials = (apimClientId + ":" + apimClientSecret).toBytes().toBase64();

    http:Request tokenReq = new;
    tokenReq.setPayload("grant_type=client_credentials", "application/x-www-form-urlencoded");
    tokenReq.addHeader("Authorization", "Basic " + credentials);

    http:Response tokenRes = check apimTokenClient->post("/oauth2/token", tokenReq);
    json          body     = check tokenRes.getJsonPayload();
    TokenResponse data     = check body.cloneWithType(TokenResponse);

    time:Utc newNow = time:utcNow();
    cachedCcToken     = data.access_token;
    cachedCcExpiresAt = <decimal>newNow[0] + newNow[1] + <decimal>data.expires_in;

    log:printInfo("Refreshed APIM CC token");
    return cachedCcToken;
}

// ─── Auth handlers ─────────────────────────────────────────────────────────────

function handleLogin(http:Request req) returns http:Response {
    return doAuthPassThrough(req, "/library/0.9.0/login");
}

function handleRegister(http:Request req) returns http:Response {
    return doAuthPassThrough(req, "/library/0.9.0/register");
}

// Pass-through for login and register.
// Forwards the JSON body to APIM with the CC token, receives { token, user } from
// auth_service, moves `token` into an httpOnly cookie, returns only { user }.
function doAuthPassThrough(http:Request req, string apimPath) returns http:Response {
    http:Response res = new;

    string|error ccToken = getCcToken();
    if ccToken is error {
        log:printError("Failed to obtain CC token", 'error = ccToken);
        res.statusCode = 500;
        res.setJsonPayload({"error": "Service temporarily unavailable"});
        return res;
    }

    json|error reqBody = req.getJsonPayload();
    if reqBody is error {
        res.statusCode = 400;
        res.setJsonPayload({"error": "Invalid request body"});
        return res;
    }

    http:Request apimReq = new;
    apimReq.setJsonPayload(reqBody);
    apimReq.addHeader("Authorization", "Bearer " + ccToken);

    http:Response|http:ClientError apimRes = apimGatewayClient->post(apimPath, apimReq);
    if apimRes is http:ClientError {
        log:printError("APIM call failed", 'error = apimRes);
        res.statusCode = 502;
        res.setJsonPayload({"error": "Upstream service error"});
        return res;
    }

    // Forward non-2xx (e.g. 401 wrong password, 409 conflict) unchanged
    if apimRes.statusCode < 200 || apimRes.statusCode >= 300 {
        res.statusCode = apimRes.statusCode;
        json|error errBody = apimRes.getJsonPayload();
        if errBody is json {
            res.setJsonPayload(errBody);
        }
        return res;
    }

    json|error respBody = apimRes.getJsonPayload();
    if respBody is error {
        res.statusCode = 502;
        res.setJsonPayload({"error": "Invalid upstream response"});
        return res;
    }

    AuthResponse|error authData = respBody.cloneWithType(AuthResponse);
    if authData is error {
        res.statusCode = 502;
        res.setJsonPayload({"error": "Invalid upstream response format"});
        return res;
    }

    // Token Handler Pattern: move the JWT out of the body into an httpOnly cookie
    setAuthCookie(res, authData.token, cookieMaxAge);
    res.setJsonPayload({"user": {"id": authData.user.id, "username": authData.user.username}});
    return res;
}

function handleValidate(http:Request req) returns http:Response {
    http:Response res = new;

    string|error userToken = readAuthCookie(req);
    if userToken is error {
        res.statusCode = 401;
        res.setJsonPayload({"error": "Unauthorized"});
        return res;
    }

    string|error ccToken = getCcToken();
    if ccToken is error {
        res.statusCode = 500;
        res.setJsonPayload({"error": "Service temporarily unavailable"});
        return res;
    }

    map<string|string[]> headers = {
        "Authorization": "Bearer " + ccToken,
        "X-Sonicwave-User-Auth": "Bearer " + userToken
    };

    http:Response|http:ClientError apimRes = apimGatewayClient->get("/library/0.9.0/validate", headers);
    if apimRes is http:ClientError {
        res.statusCode = 502;
        res.setJsonPayload({"error": "Upstream service error"});
        return res;
    }

    res.statusCode = apimRes.statusCode;
    json|error body = apimRes.getJsonPayload();
    if body is json {
        res.setJsonPayload(body);
    }
    return res;
}

function handleLogout(http:Request req) returns http:Response {
    http:Response res = new;
    clearAuthCookie(res);
    res.setJsonPayload({"message": "Logged out"});
    return res;
}

// ─── Song handlers ─────────────────────────────────────────────────────────────

function handleGetSongs(http:Request req) returns http:Response {
    return doAuthenticatedGet(req, "/library/0.9.0/songs");
}

function handleGetSongById(http:Request req, string id) returns http:Response {
    return doAuthenticatedGet(req, "/library/0.9.0/songs/" + id);
}

// Shared GET proxy — reads session cookie, injects both auth headers, forwards to APIM.
function doAuthenticatedGet(http:Request req, string apimPath) returns http:Response {
    http:Response res = new;

    string|error userToken = readAuthCookie(req);
    if userToken is error {
        res.statusCode = 401;
        res.setJsonPayload({"error": "Unauthorized"});
        return res;
    }

    string|error ccToken = getCcToken();
    if ccToken is error {
        res.statusCode = 500;
        res.setJsonPayload({"error": "Service temporarily unavailable"});
        return res;
    }

    map<string|string[]> headers = {
        "Authorization": "Bearer " + ccToken,
        "X-Sonicwave-User-Auth": "Bearer " + userToken
    };

    http:Response|http:ClientError apimRes = apimGatewayClient->get(apimPath, headers);
    if apimRes is http:ClientError {
        res.statusCode = 502;
        res.setJsonPayload({"error": "Upstream service error"});
        return res;
    }

    res.statusCode = apimRes.statusCode;
    json|error body = apimRes.getJsonPayload();
    if body is json {
        res.setJsonPayload(body);
    }
    return res;
}

function handleCreateSong(http:Request req) returns http:Response {
    http:Response res = new;

    string|error userToken = readAuthCookie(req);
    if userToken is error {
        res.statusCode = 401;
        res.setJsonPayload({"error": "Unauthorized"});
        return res;
    }

    string|error ccToken = getCcToken();
    if ccToken is error {
        res.statusCode = 500;
        res.setJsonPayload({"error": "Service temporarily unavailable"});
        return res;
    }

    json|error reqBody = req.getJsonPayload();
    if reqBody is error {
        res.statusCode = 400;
        res.setJsonPayload({"error": "Invalid request body"});
        return res;
    }

    http:Request apimReq = new;
    apimReq.setJsonPayload(reqBody);
    apimReq.addHeader("Authorization", "Bearer " + ccToken);
    apimReq.addHeader("X-Sonicwave-User-Auth", "Bearer " + userToken);

    http:Response|http:ClientError apimRes = apimGatewayClient->post("/library/0.9.0/songs", apimReq);
    if apimRes is http:ClientError {
        res.statusCode = 502;
        res.setJsonPayload({"error": "Upstream service error"});
        return res;
    }

    res.statusCode = apimRes.statusCode;
    json|error respBody = apimRes.getJsonPayload();
    if respBody is json {
        res.setJsonPayload(respBody);
    }
    return res;
}
