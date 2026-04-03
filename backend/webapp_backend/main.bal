import ballerina/http;
import ballerina/log;
import ballerina/time;

@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:3001"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Authorization", "Content-Type", "X-Sonicwave-User-Auth"],
        allowCredentials: true
    }
}
service /api on new http:Listener(serverPort) {

    // GET /api/songs - Get all songs owned by the caller
    resource function get songs(
        @http:Header string? Authorization,
        @http:Header {name: "X-Sonicwave-User-Auth"} string? xSonicwaveUserAuth
    ) returns SongResponse[]|ErrorResponse|http:Unauthorized {
        log:printInfo("GET /api/songs - start");
        CallerInfo|error caller = validateAuthHeader(Authorization, xSonicwaveUserAuth);
        if caller is error {
            log:printInfo("GET /api/songs - end");
            return <http:Unauthorized>{
                body: {'error: "Unauthorized"}
            };
        }

        Song[]|error songs = getAllSongs(caller.userId);
        if songs is error {
            log:printInfo("GET /api/songs - end");
            return {'error: "Failed to retrieve songs"};
        }

        SongResponse[] songResponses = from Song song in songs
            select toSongResponse(song);
        log:printInfo("GET /api/songs - end");
        return songResponses;
    }

    // GET /api/songs/{id} - Get a song by ID (only if owned by caller)
    resource function get songs/[string id](
        @http:Header string? Authorization,
        @http:Header {name: "X-Sonicwave-User-Auth"} string? xSonicwaveUserAuth
    ) returns SongResponse|ErrorResponse|http:Unauthorized|http:NotFound {
        log:printInfo("GET /api/songs/" + id + " - start");
        CallerInfo|error caller = validateAuthHeader(Authorization, xSonicwaveUserAuth);
        if caller is error {
            log:printInfo("GET /api/songs/" + id + " - end");
            return <http:Unauthorized>{
                body: {'error: "Unauthorized"}
            };
        }

        int|error songId = int:fromString(id);
        if songId is error {
            log:printInfo("GET /api/songs/" + id + " - end");
            return <http:NotFound>{
                body: {'error: "Song not found"}
            };
        }

        Song|error? song = getSongById(songId, caller.userId);
        if song is error {
            log:printInfo("GET /api/songs/" + id + " - end");
            return {'error: "Failed to retrieve song"};
        }
        if song is () {
            log:printInfo("GET /api/songs/" + id + " - end");
            return <http:NotFound>{
                body: {'error: "Song not found"}
            };
        }

        log:printInfo("GET /api/songs/" + id + " - end");
        return toSongResponse(song);
    }

    // POST /api/songs - Create a new song owned by the caller
    resource function post songs(
        @http:Header string? Authorization,
        @http:Header {name: "X-Sonicwave-User-Auth"} string? xSonicwaveUserAuth,
        @http:Payload CreateSongRequest songRequest
    ) returns SongResponse|ErrorResponse|http:Unauthorized|http:BadRequest|http:Created {
        log:printInfo("POST /api/songs - start");
        CallerInfo|error caller = validateAuthHeader(Authorization, xSonicwaveUserAuth);
        if caller is error {
            log:printInfo("POST /api/songs - end");
            return <http:Unauthorized>{
                body: {'error: "Unauthorized"}
            };
        }

        string title = songRequest.title.trim();
        string artist = songRequest.artist.trim();

        if title == "" || artist == "" {
            log:printInfo("POST /api/songs - end");
            return <http:BadRequest>{
                body: {'error: "Title and artist are required"}
            };
        }

        string album = "";
        string? albumValue = songRequest.album;
        if albumValue is string {
            album = albumValue.trim();
        }
        if album == "" {
            album = "Unknown Album";
        }

        string duration = "";
        string? durationValue = songRequest.duration;
        if durationValue is string {
            duration = durationValue.trim();
        }
        if duration == "" {
            duration = "0:00";
        }

        string coverUrl = "";
        string? coverUrlValue = songRequest.coverUrl;
        if coverUrlValue is string {
            coverUrl = coverUrlValue.trim();
        }
        if coverUrl == "" {
            int|error timestamp = time:utcNow()[0];
            int timestampValue = timestamp is int ? timestamp : 0;
            coverUrl = string `https://picsum.photos/seed/${timestampValue}/400/400`;
        }

        Song|error newSong = createSong(title, artist, album, duration, coverUrl, caller.userId);
        if newSong is error {
            log:printInfo("POST /api/songs - end");
            return {'error: "Failed to create song"};
        }

        log:printInfo("POST /api/songs - end");
        return <http:Created>{
            body: toSongResponse(newSong)
        };
    }
}

// Resolves the user token with APIM awareness:
//   - When running behind APIM, the APIM CC token arrives in Authorization and the
//     user-scoped auth_service JWT is forwarded in X-Sonicwave-User-Auth.
//   - When called directly (dev/test, no APIM), Authorization carries the user JWT.
// In both cases the resolved token is validated against auth_service.
function validateAuthHeader(string? authorization, string? xSonicwaveUserAuth) returns CallerInfo|error {
    // Prefer the dedicated user-auth header (APIM flow) over Authorization
    string? headerToUse = xSonicwaveUserAuth ?: authorization;

    if headerToUse is () {
        return error("Missing auth header");
    }

    string headerValue = headerToUse;
    if headerValue.startsWith("Bearer ") {
        return check validateWithAuthService(headerValue.substring(7));
    }
    // Bare token (no Bearer prefix) — also accepted
    return check validateWithAuthService(headerValue);
}
