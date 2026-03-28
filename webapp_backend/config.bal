// Database configuration
configurable string dbPath = "./sonicwave.db";

// JWT configuration
configurable string jwtIssuer = "sonicwave-backend";
configurable string jwtSecret = "default-secret-key-change-in-production";
configurable int jwtExpiryTime = 86400; // 24 hours in seconds

// Server configuration
configurable int serverPort = 8080;
