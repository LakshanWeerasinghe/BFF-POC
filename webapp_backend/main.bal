import ballerina/http;
import ballerina/time;

// CORS configuration
@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:3001"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Authorization", "Content-Type"],
        allowCredentials: true
    }
}
service /api on new http:Listener(serverPort) {

    // POST /api/login - Authenticate user
    resource function post login(@http:Payload LoginRequest loginRequest) returns LoginResponse|ErrorResponse|http:BadRequest {
        string username = loginRequest.username.trim();
        
        if username == "" {
            return <http:BadRequest>{
                body: {
                    'error: "Username is required"
                }
            };
        }
        
        // Check if user exists
        User|error? existingUser = getUserByUsername(username);
        
        if existingUser is error {
            return {
                'error: "Internal server error"
            };
        }
        
        // Create user if doesn't exist
        if existingUser is () {
            User|error newUser = createUser(username);
            if newUser is error {
                return {
                    'error: "Failed to create user"
                };
            }
        }
        
        // Generate JWT token
        string|error token = generateJwtToken(username);
        if token is error {
            return {
                'error: "Failed to generate token"
            };
        }
        
        return {
            token: token,
            user: {
                username: username
            }
        };
    }

    // GET /api/songs - Get all songs
    resource function get songs(@http:Header string? Authorization) returns SongResponse[]|ErrorResponse|http:Unauthorized {
        // Validate JWT token
        string|error username = validateAuthHeader(Authorization);
        if username is error {
            return <http:Unauthorized>{
                body: {
                    'error: "Unauthorized"
                }
            };
        }
        
        // Get all songs
        Song[]|error songs = getAllSongs();
        if songs is error {
            return {
                'error: "Failed to retrieve songs"
            };
        }
        
        // Convert to response format
        SongResponse[] songResponses = from Song song in songs
            select toSongResponse(song);
        
        return songResponses;
    }

    // GET /api/songs/{id} - Get song by ID
    resource function get songs/[string id](@http:Header string? Authorization) returns SongResponse|ErrorResponse|http:Unauthorized|http:NotFound {
        // Validate JWT token
        string|error username = validateAuthHeader(Authorization);
        if username is error {
            return <http:Unauthorized>{
                body: {
                    'error: "Unauthorized"
                }
            };
        }
        
        // Parse song ID
        int|error songId = int:fromString(id);
        if songId is error {
            return <http:NotFound>{
                body: {
                    'error: "Song not found"
                }
            };
        }
        
        // Get song by ID
        Song|error? song = getSongById(songId);
        if song is error {
            return {
                'error: "Failed to retrieve song"
            };
        }
        
        if song is () {
            return <http:NotFound>{
                body: {
                    'error: "Song not found"
                }
            };
        }
        
        return toSongResponse(song);
    }

    // POST /api/songs - Create new song
    resource function post songs(@http:Header string? Authorization, @http:Payload CreateSongRequest songRequest) returns SongResponse|ErrorResponse|http:Unauthorized|http:BadRequest|http:Created {
        // Validate JWT token
        string|error username = validateAuthHeader(Authorization);
        if username is error {
            return <http:Unauthorized>{
                body: {
                    'error: "Unauthorized"
                }
            };
        }
        
        // Validate required fields
        string title = songRequest.title.trim();
        string artist = songRequest.artist.trim();
        
        if title == "" || artist == "" {
            return <http:BadRequest>{
                body: {
                    'error: "Title and artist are required"
                }
            };
        }
        
        // Set defaults for optional fields
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
        
        // Create song
        Song|error newSong = createSong(title, artist, album, duration, coverUrl);
        if newSong is error {
            return {
                'error: "Failed to create song"
            };
        }
        
        return <http:Created>{
            body: toSongResponse(newSong)
        };
    }
}

// Helper function to validate Authorization header
function validateAuthHeader(string? authHeader) returns string|error {
    if authHeader is () {
        return error("Missing Authorization header");
    }
    
    string authHeaderValue = authHeader;
    if !authHeaderValue.startsWith("Bearer ") {
        return error("Invalid Authorization header format");
    }
    
    string token = authHeaderValue.substring(7);
    var payload = validateJwtToken(token);
    
    if payload is error {
        return error("Invalid token");
    }
    
    string? subject = payload.sub;
    if subject is () {
        return error("Invalid token payload");
    }
    
    return subject;
}
