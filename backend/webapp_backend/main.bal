import ballerina/http;
import ballerina/time;

@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:3001"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Authorization", "Content-Type"],
        allowCredentials: true
    }
}
service /api on new http:Listener(serverPort) {

    // GET /api/songs - Get all songs owned by the caller
    resource function get songs(@http:Header string? Authorization) returns SongResponse[]|ErrorResponse|http:Unauthorized {
        CallerInfo|error caller = validateAuthHeader(Authorization);
        if caller is error {
            return <http:Unauthorized>{
                body: {'error: "Unauthorized"}
            };
        }

        Song[]|error songs = getAllSongs(caller.userId);
        if songs is error {
            return {'error: "Failed to retrieve songs"};
        }

        SongResponse[] songResponses = from Song song in songs
            select toSongResponse(song);
        return songResponses;
    }

    // GET /api/songs/{id} - Get a song by ID (only if owned by caller)
    resource function get songs/[string id](@http:Header string? Authorization) returns SongResponse|ErrorResponse|http:Unauthorized|http:NotFound {
        CallerInfo|error caller = validateAuthHeader(Authorization);
        if caller is error {
            return <http:Unauthorized>{
                body: {'error: "Unauthorized"}
            };
        }

        int|error songId = int:fromString(id);
        if songId is error {
            return <http:NotFound>{
                body: {'error: "Song not found"}
            };
        }

        Song|error? song = getSongById(songId, caller.userId);
        if song is error {
            return {'error: "Failed to retrieve song"};
        }
        if song is () {
            return <http:NotFound>{
                body: {'error: "Song not found"}
            };
        }

        return toSongResponse(song);
    }

    // POST /api/songs - Create a new song owned by the caller
    resource function post songs(@http:Header string? Authorization, @http:Payload CreateSongRequest songRequest) returns SongResponse|ErrorResponse|http:Unauthorized|http:BadRequest|http:Created {
        CallerInfo|error caller = validateAuthHeader(Authorization);
        if caller is error {
            return <http:Unauthorized>{
                body: {'error: "Unauthorized"}
            };
        }

        string title = songRequest.title.trim();
        string artist = songRequest.artist.trim();

        if title == "" || artist == "" {
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
            return {'error: "Failed to create song"};
        }

        return <http:Created>{
            body: toSongResponse(newSong)
        };
    }
}

// Validates the Authorization header by delegating to auth_service.
// Returns CallerInfo (userId + username) on success, error on failure.
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
