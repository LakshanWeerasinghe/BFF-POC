import ballerina/http;

const string COOKIE_NAME = "auth_token";

// Reads the raw auth_service JWT from the incoming request cookie.
// Returns error if the cookie is absent or empty.
function readAuthCookie(http:Request req) returns string|error {
    http:Cookie[] cookies = req.getCookies();
    foreach http:Cookie c in cookies {
        if c.name == COOKIE_NAME {
            string? val = c.value;
            if val is string && val.length() > 0 {
                return val;
            }
        }
    }
    return error("auth_token cookie not found");
}

// cookie is sent on same-site navigations and safe cross-site top-level GETs.
function setAuthCookie(http:Response res, string token, int maxAge) {
    http:Cookie cookie = new (COOKIE_NAME, token, path = "/", maxAge = maxAge, httpOnly = true);
    res.addCookie(cookie);
}

// Clears the auth cookie in the browser by setting Max-Age=0 directly.
// Ballerina's addCookie silently drops Max-Age=0, so we write the header manually.
function clearAuthCookie(http:Response res) {
    res.setHeader("Set-Cookie", COOKIE_NAME + "=deleted; Path=/; Max-Age=0; HttpOnly");
}
