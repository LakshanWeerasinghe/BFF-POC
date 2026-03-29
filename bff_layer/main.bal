import ballerina/http;

@http:ServiceConfig {
    cors: {
        allowOrigins: [allowedOrigin],
        allowMethods: ["GET", "POST", "OPTIONS"],
        allowHeaders: ["Content-Type"],
        allowCredentials: true
    }
}
service /bff on new http:Listener(serverPort) {

    // ── Auth ──────────────────────────────────────────────────────────────────

    resource function post auth/login(http:Request req) returns http:Response {
        return handleLogin(req);
    }

    resource function post auth/register(http:Request req) returns http:Response {
        return handleRegister(req);
    }

    resource function get auth/validate(http:Request req) returns http:Response {
        return handleValidate(req);
    }

    resource function post auth/logout(http:Request req) returns http:Response {
        return handleLogout(req);
    }

    // ── Songs ─────────────────────────────────────────────────────────────────

    resource function get songs(http:Request req) returns http:Response {
        return handleGetSongs(req);
    }

    resource function post songs(http:Request req) returns http:Response {
        return handleCreateSong(req);
    }

    resource function get songs/[string id](http:Request req) returns http:Response {
        return handleGetSongById(req, id);
    }
}
