import ballerina/jwt;
import ballerina/sql;

// JWT token generation
function generateJwtToken(string username) returns string|error {
    decimal expiryTime = <decimal>jwtExpiryTime;
    
    jwt:IssuerConfig issuerConfig = {
        username: username,
        issuer: jwtIssuer,
        audience: "sonicwave-users",
        expTime: expiryTime,
        signatureConfig: {
            algorithm: jwt:HS256,
            config: jwtSecret
        }
    };
    
    string jwtToken = check jwt:issue(issuerConfig);
    return jwtToken;
}

// JWT token validation
function validateJwtToken(string token) returns jwt:Payload|error {
    jwt:ValidatorConfig validatorConfig = {
        issuer: jwtIssuer,
        audience: "sonicwave-users",
        signatureConfig: {
            secret: jwtSecret
        }
    };
    
    jwt:Payload payload = check jwt:validate(token, validatorConfig);
    return payload;
}

// Database functions
function createUser(string username) returns User|error {
    sql:ExecutionResult result = check dbClient->execute(`
        INSERT INTO users (username) VALUES (${username})
    `);
    
    int|string? userId = result.lastInsertId;
    if userId is int {
        User user = {
            id: userId,
            username: username
        };
        return user;
    }
    
    return error("Failed to create user");
}

function getUserByUsername(string username) returns User|error? {
    User|sql:Error result = dbClient->queryRow(`
        SELECT id, username, created_at FROM users WHERE username = ${username}
    `);
    
    if result is sql:NoRowsError {
        return ();
    }
    
    return result;
}

function getAllSongs() returns Song[]|error {
    stream<Song, sql:Error?> songStream = dbClient->query(`
        SELECT id, title, artist, album, duration, cover_url, created_at FROM songs
    `);
    
    Song[] songs = check from Song song in songStream
        select song;
    
    return songs;
}

function getSongById(int songId) returns Song|error? {
    Song|sql:Error result = dbClient->queryRow(`
        SELECT id, title, artist, album, duration, cover_url, created_at FROM songs WHERE id = ${songId}
    `);
    
    if result is sql:NoRowsError {
        return ();
    }
    
    return result;
}

function createSong(string title, string artist, string album, string duration, string coverUrl) returns Song|error {
    sql:ExecutionResult result = check dbClient->execute(`
        INSERT INTO songs (title, artist, album, duration, cover_url) 
        VALUES (${title}, ${artist}, ${album}, ${duration}, ${coverUrl})
    `);
    
    int|string? songId = result.lastInsertId;
    if songId is int {
        Song song = {
            id: songId,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            cover_url: coverUrl
        };
        return song;
    }
    
    return error("Failed to create song");
}

// Helper function to convert Song to SongResponse
function toSongResponse(Song song) returns SongResponse {
    return {
        id: song.id.toString(),
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        coverUrl: song.cover_url ?: ""
    };
}
