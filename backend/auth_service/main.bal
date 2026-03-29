import ballerina/http;

@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:3001"],
        allowMethods: ["POST", "OPTIONS"],
        allowHeaders: ["Content-Type"],
        allowCredentials: true
    }
}
service /auth on new http:Listener(serverPort) {

    // POST /auth/register
    resource function post register(@http:Payload RegisterRequest request)
            returns http:Created|http:BadRequest|http:Conflict|http:InternalServerError {

        string username = request.username.trim();
        string password = request.password.trim();

        if username == "" || password == "" {
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Username and password are required"}};
        }
        if username.length() < 3 || username.length() > 50 {
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Username must be between 3 and 50 characters"}};
        }
        if password.length() < 6 {
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Password must be at least 6 characters"}};
        }

        User|error? existing = getUserByUsername(username);
        if existing is error {
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to register user"}};
        }
        if existing is User {
            return <http:Conflict>{body: <ErrorResponse>{'error: "Username already exists"}};
        }

        string salt = generateSalt();
        string hash = hashPassword(password, salt);

        User|error newUser = insertUser(username, hash, salt);
        if newUser is error {
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to register user"}};
        }

        string|error token = generateJwtToken(newUser.id, newUser.username);
        if token is error {
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to generate token"}};
        }

        return <http:Created>{body: toAuthResponse(newUser, token)};
    }

    // POST /auth/login
    resource function post login(@http:Payload LoginRequest request)
            returns http:Ok|http:BadRequest|http:Unauthorized|http:InternalServerError {

        string username = request.username.trim();
        string password = request.password.trim();

        if username == "" || password == "" {
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Username and password are required"}};
        }

        User|error? existing = getUserByUsername(username);
        if existing is error {
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Internal server error"}};
        }
        if existing is () {
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Invalid username or password"}};
        }

        User user = existing;
        if !verifyPassword(password, user.salt, user.password_hash) {
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Invalid username or password"}};
        }

        string|error token = generateJwtToken(user.id, user.username);
        if token is error {
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to generate token"}};
        }

        return <http:Ok>{body: toAuthResponse(user, token)};
    }
}
