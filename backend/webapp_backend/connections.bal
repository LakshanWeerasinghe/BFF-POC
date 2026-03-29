import ballerinax/java.jdbc;

// Initialize SQLite database connection
final jdbc:Client dbClient = check initDatabase();

function initDatabase() returns jdbc:Client|error {
    jdbc:Client jdbcClient = check new ("jdbc:sqlite:" + dbPath, 
        "", "");
    
    // Create tables if they don't exist
    check createTables(jdbcClient);
    
    // Seed initial data
    check seedInitialData(jdbcClient);
    
    return jdbcClient;
}

function createTables(jdbc:Client jdbcClient) returns error? {
    // Create users table
    _ = check jdbcClient->execute(`
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
    
    // Create songs table
    _ = check jdbcClient->execute(`
        CREATE TABLE IF NOT EXISTS songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL DEFAULT 'Unknown Album',
            duration TEXT NOT NULL DEFAULT '0:00',
            cover_url TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `);
}

function seedInitialData(jdbc:Client jdbcClient) returns error? {
    // Check if songs table is empty
    int songCount = check jdbcClient->queryRow(`SELECT COUNT(*) as count FROM songs`);
    
    if songCount == 0 {
        // Insert initial seed data
        _ = check jdbcClient->execute(`
            INSERT INTO songs (title, artist, album, duration, cover_url) VALUES
            ('Midnight City', 'M83', 'Hurry Up, We''re Dreaming', '4:03', 'https://picsum.photos/seed/m83/400/400')
        `);
        
        _ = check jdbcClient->execute(`
            INSERT INTO songs (title, artist, album, duration, cover_url) VALUES
            ('Starboy', 'The Weeknd', 'Starboy', '3:50', 'https://picsum.photos/seed/starboy/400/400')
        `);
        
        _ = check jdbcClient->execute(`
            INSERT INTO songs (title, artist, album, duration, cover_url) VALUES
            ('Blinding Lights', 'The Weeknd', 'After Hours', '3:20', 'https://picsum.photos/seed/blinding/400/400')
        `);
    }
}
