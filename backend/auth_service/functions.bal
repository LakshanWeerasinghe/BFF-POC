import ballerina/crypto;
import ballerina/jwt;
import ballerina/sql;
import ballerina/uuid;

// JWT token validation
function validateJwtToken(string token) returns jwt:Payload|error {
    jwt:ValidatorConfig validatorConfig = {
        issuer: jwtIssuer,
        audience: "sonicwave-users",
        signatureConfig: {
            secret: jwtSecret
        }
    };
    return check jwt:validate(token, validatorConfig);
}

// --- Password helpers ---

function generateSalt() returns string {
    return uuid:createType4AsString();
}

function hashPassword(string password, string salt) returns string {
    byte[] input = (password + salt).toBytes();
    byte[] hashed = crypto:hashSha256(input);
    return bytesToHex(hashed);
}

function verifyPassword(string password, string salt, string storedHash) returns boolean {
    return hashPassword(password, salt) == storedHash;
}

// Convert byte array to lowercase hex string
function bytesToHex(byte[] bytes) returns string {
    string result = "";
    foreach byte b in bytes {
        string hex = (<int>b).toHexString();
        result += hex.length() == 1 ? "0" + hex : hex;
    }
    return result;
}

// --- JWT ---

function generateJwtToken(int userId, string username) returns string|error {
    jwt:IssuerConfig issuerConfig = {
        username: username,
        issuer: jwtIssuer,
        audience: "sonicwave-users",
        expTime: <decimal>jwtExpiryTime,
        customClaims: {"userId": userId.toString()},
        signatureConfig: {
            algorithm: jwt:HS256,
            config: jwtSecret
        }
    };
    return check jwt:issue(issuerConfig);
}

// --- DB operations ---

function insertUser(string username, string passwordHash, string salt) returns User|error {
    sql:ExecutionResult result = check dbClient->execute(`
        INSERT INTO users (username, password_hash, salt)
        VALUES (${username}, ${passwordHash}, ${salt})
    `);
    int|string? lastId = result.lastInsertId;
    if lastId is int {
        return {id: lastId, username: username, password_hash: passwordHash, salt: salt};
    }
    return error("Failed to retrieve inserted user ID");
}

function getUserByUsername(string username) returns User|error? {
    User|sql:Error result = dbClient->queryRow(`
        SELECT id, username, password_hash, salt, created_at
        FROM users WHERE username = ${username}
    `);
    if result is sql:NoRowsError {
        return ();
    }
    return result;
}
