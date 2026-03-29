import ballerinax/java.jdbc;

final jdbc:Client dbClient = check initDatabase();

function initDatabase() returns jdbc:Client|error {
    jdbc:Client jdbcClient = check new ("jdbc:sqlite:" + dbPath, "", "");
    check createTables(jdbcClient);
    return jdbcClient;
}

function createTables(jdbc:Client jdbcClient) returns error? {
    _ = check jdbcClient->execute(`
        CREATE TABLE IF NOT EXISTS users (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            username      TEXT    NOT NULL UNIQUE,
            password_hash TEXT    NOT NULL,
            salt          TEXT    NOT NULL,
            created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
}
