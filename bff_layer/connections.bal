import ballerina/http;

// APIM token endpoint client — TLS verification disabled for self-signed dev cert.
// In production replace with: secureSocket: { cert: "/path/to/ca.crt" }
final http:Client apimTokenClient = check new (apimTokenUrl, {
    secureSocket: {enable: false}
});

// APIM gateway client (all /library/0.9.0/* calls)
final http:Client apimGatewayClient = check new (apimGatewayUrl, {
    secureSocket: {enable: false}
});
