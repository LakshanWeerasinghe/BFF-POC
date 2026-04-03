import ballerina/http;
import ballerina/jwt;
import ballerina/log;

@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:3001"],
        allowMethods: ["GET", "POST", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization", "X-Sonicwave-User-Auth"],
        allowCredentials: true
    }
}
service /auth on new http:Listener(serverPort) {

    // POST /auth/register
    resource function post register(@http:Payload RegisterRequest request)
            returns http:Created|http:BadRequest|http:Conflict|http:InternalServerError {
        log:printInfo("POST /auth/register - start");
        string username = request.username.trim();
        string password = request.password.trim();

        if username == "" || password == "" {
            log:printInfo("POST /auth/register - end");
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Username and password are required"}};
        }
        if username.length() < 3 || username.length() > 50 {
            log:printInfo("POST /auth/register - end");
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Username must be between 3 and 50 characters"}};
        }
        if password.length() < 6 {
            log:printInfo("POST /auth/register - end");
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Password must be at least 6 characters"}};
        }

        User|error? existing = getUserByUsername(username);
        if existing is error {
            log:printInfo("POST /auth/register - end");
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to register user"}};
        }
        if existing is User {
            log:printInfo("POST /auth/register - end");
            return <http:Conflict>{body: <ErrorResponse>{'error: "Username already exists"}};
        }

        string salt = generateSalt();
        string hash = hashPassword(password, salt);

        User|error newUser = insertUser(username, hash, salt);
        if newUser is error {
            log:printInfo("POST /auth/register - end");
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to register user"}};
        }

        string|error token = generateJwtToken(newUser.id, newUser.username);
        if token is error {
            log:printInfo("POST /auth/register - end");
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to generate token"}};
        }

        log:printInfo("POST /auth/register - end");
        return <http:Created>{body: toAuthResponse(newUser, token)};
    }

    // GET /auth/validate — called by webapp_backend (direct) and via APIM (browser startup check)
    //
    // Two flows reach this endpoint:
    //   1. Direct (webapp_backend → auth_service):
    //      Authorization: Bearer <user_jwt>
    //   2. Via APIM (browser → BFF → APIM → auth_service):
    //      APIM strips Authorization (which held the CC token) before forwarding.
    //      BFF put the user JWT in X-Sonicwave-User-Auth which APIM passes through.
    //
    // Precedence: X-Sonicwave-User-Auth > Authorization
    resource function get validate(
            @http:Header string? Authorization,
            @http:Header {name: "X-Sonicwave-User-Auth"} string? xSonicwaveUserAuth)
            returns http:Ok|http:Unauthorized {
        log:printInfo("GET /auth/validate - start");
        string? rawHeader = xSonicwaveUserAuth ?: Authorization;
        if rawHeader is () {
            log:printInfo("GET /auth/validate - end");
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
        }

        string token = rawHeader.startsWith("Bearer ") ? rawHeader.substring(7) : rawHeader;
        jwt:Payload|error payload = validateJwtToken(token);
        if payload is error {
            log:printInfo("GET /auth/validate - end");
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
        }

        string? username = payload.sub;
        if username is () {
            log:printInfo("GET /auth/validate - end");
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Unauthorized"}};
        }

        string userId = "";
        anydata userIdData = payload["userId"];
        if userIdData is string {
            userId = userIdData;
        }

        log:printInfo("GET /auth/validate - end");
        return <http:Ok>{body: <ValidateResponse>{userId: userId, username: username}};
    }

    // POST /auth/login
    resource function post login(@http:Payload LoginRequest request)
            returns http:Ok|http:BadRequest|http:Unauthorized|http:InternalServerError {
        log:printInfo("POST /auth/login - start");
        string username = request.username.trim();
        string password = request.password.trim();

        if username == "" || password == "" {
            log:printInfo("POST /auth/login - end");
            return <http:BadRequest>{body: <ErrorResponse>{'error: "Username and password are required"}};
        }

        User|error? existing = getUserByUsername(username);
        if existing is error {
            log:printInfo("POST /auth/login - end");
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Internal server error"}};
        }
        if existing is () {
            log:printInfo("POST /auth/login - end");
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Invalid username or password"}};
        }

        User user = existing;
        if !verifyPassword(password, user.salt, user.password_hash) {
            log:printInfo("POST /auth/login - end");
            return <http:Unauthorized>{body: <ErrorResponse>{'error: "Invalid username or password"}};
        }

        string|error token = generateJwtToken(user.id, user.username);
        if token is error {
            log:printInfo("POST /auth/login - end");
            return <http:InternalServerError>{body: <ErrorResponse>{'error: "Failed to generate token"}};
        }

        log:printInfo("POST /auth/login - end");
        return <http:Ok>{body: toAuthResponse(user, token)};
    }
}
