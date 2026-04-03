import ballerina/http;
import ballerina/log;

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
        log:printInfo("POST /bff/auth/login - start");
        http:Response response = handleLogin(req);
        log:printInfo("POST /bff/auth/login - end");
        return response;
    }

    resource function post auth/register(http:Request req) returns http:Response {
        log:printInfo("POST /bff/auth/register - start");
        http:Response response = handleRegister(req);
        log:printInfo("POST /bff/auth/register - end");
        return response;
    }

    resource function get auth/validate(http:Request req) returns http:Response {
        log:printInfo("GET /bff/auth/validate - start");
        http:Response response = handleValidate(req);
        log:printInfo("GET /bff/auth/validate - end");
        return response;
    }

    resource function post auth/logout(http:Request req) returns http:Response {
        log:printInfo("POST /bff/auth/logout - start");
        http:Response response = handleLogout(req);
        log:printInfo("POST /bff/auth/logout - end");
        return response;
    }

    // ── Songs ─────────────────────────────────────────────────────────────────

    resource function get songs(http:Request req) returns http:Response {
        log:printInfo("GET /bff/songs - start");
        http:Response response = handleGetSongs(req);
        log:printInfo("GET /bff/songs - end");
        return response;
    }

    resource function post songs(http:Request req) returns http:Response {
        log:printInfo("POST /bff/songs - start");
        http:Response response = handleCreateSong(req);
        log:printInfo("POST /bff/songs - end");
        return response;
    }

    resource function get songs/[string id](http:Request req) returns http:Response {
        log:printInfo("GET /bff/songs/" + id + " - start");
        http:Response response = handleGetSongById(req, id);
        log:printInfo("GET /bff/songs/" + id + " - end");
        return response;
    }
}
