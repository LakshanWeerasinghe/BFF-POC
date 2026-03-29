// Auth service response returned by APIM after login / register
type AuthResponse record {|
    string token;
    UserRecord user;
|};

type UserRecord record {|
    string id;
    string username;
|};

// APIM /oauth2/token response (open record — APIM also returns scope, token_type, etc.)
type TokenResponse record {
    string access_token;
    int    expires_in;
};
