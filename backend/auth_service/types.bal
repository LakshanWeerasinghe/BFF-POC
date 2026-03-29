// DB record — maps directly to the users table
type User record {|
    int    id;
    string username;
    string password_hash;
    string salt;
    string created_at?;
|};

// Request types
type RegisterRequest record {|
    string username;
    string password;
|};

type LoginRequest record {|
    string username;
    string password;
|};

// Response types
type UserResponse record {|
    string id;
    string username;
|};

// Shared by both register and login
type AuthResponse record {|
    string token;
    UserResponse user;
|};

type ErrorResponse record {|
    string 'error;
|};

type ValidateResponse record {|
    string userId;
    string username;
|};
