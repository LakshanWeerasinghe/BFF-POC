// Caller identity returned by auth validation
type CallerInfo record {|
    int    userId;
    string username;
|};

// Database record types
type Song record {|
    int    id;
    string title;
    string artist;
    string album;
    string duration;
    string cover_url?;
    int    user_id;
    string created_at?;
|};

// API request/response types
type SongResponse record {|
    string id;
    string title;
    string artist;
    string album;
    string duration;
    string coverUrl;
    string ownerId;
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
