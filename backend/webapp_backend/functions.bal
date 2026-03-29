import ballerina/http;
import ballerina/sql;

// --- Auth delegation ---

// Calls auth_service to validate the Bearer token and returns the caller's identity.
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
    Song[] songs = check from Song song in songStream
        select song;
    return songs;
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
        Song song = {
            id: songId,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            cover_url: coverUrl,
            user_id: userId
        };
        return song;
    }
    return error("Failed to create song");
}

// --- Mapping ---

function toSongResponse(Song song) returns SongResponse {
    return {
        id:       song.id.toString(),
        title:    song.title,
        artist:   song.artist,
        album:    song.album,
        duration: song.duration,
        coverUrl: song.cover_url ?: "",
        ownerId:  song.user_id.toString()
    };
}
