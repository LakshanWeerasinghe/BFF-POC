import ballerina/http;
import ballerinax/java.jdbc;

// SQLite database client
final jdbc:Client dbClient = check initDatabase();

// HTTP client for auth_service token validation
final http:Client authServiceClient = check new (authServiceUrl);

function initDatabase() returns jdbc:Client|error {
    jdbc:Client jdbcClient = check new ("jdbc:sqlite:" + dbPath, "", "");
    check createTables(jdbcClient);
    return jdbcClient;
}

function createTables(jdbc:Client jdbcClient) returns error? {
    _ = check jdbcClient->execute(`
        CREATE TABLE IF NOT EXISTS songs (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            title      TEXT    NOT NULL,
            artist     TEXT    NOT NULL,
            album      TEXT    NOT NULL DEFAULT 'Unknown Album',
            duration   TEXT    NOT NULL DEFAULT '0:00',
            cover_url  TEXT,
            user_id    INTEGER NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
}
