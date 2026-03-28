// Database record types
type User record {|
    int id;
    string username;
    string created_at?;
|};

type Song record {|
    int id;
    string title;
    string artist;
    string album;
    string duration;
    string cover_url?;
    string created_at?;
|};

// API request/response types
type LoginRequest record {|
    string username;
|};

type LoginResponse record {|
    string token;
    UserResponse user;
|};

type UserResponse record {|
    string username;
|};

type SongResponse record {|
    string id;
    string title;
    string artist;
    string album;
    string duration;
    string coverUrl;
|};

type CreateSongRequest record {|
    string title;
    string artist;
    string album?;
    string duration?;
    string coverUrl?;
|};

type ErrorResponse record {|
    string 'error;
|};

// JWT payload type
type JwtPayload record {|
    string sub;
    int exp;
    int iat;
|};
