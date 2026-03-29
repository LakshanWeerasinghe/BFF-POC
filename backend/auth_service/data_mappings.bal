function toAuthResponse(User user, string token) returns AuthResponse {
    return {
        token: token,
        user: {
            id: user.id.toString(),
            username: user.username
        }
    };
}
