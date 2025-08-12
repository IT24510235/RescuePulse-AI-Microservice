import ballerina/http;
import ballerina/io;
import ballerina/lang.'string;

type User record {|
    string username;
    string email;
    string password;
|};

// Configure CORS
configurable http:CorsConfig corsConfig = {
    allowOrigins: ["http://localhost:63342"],
    allowMethods: ["POST"],
    allowHeaders: ["Content-Type"]
};

listener http:Listener httpListener = new (9090, {
    cors: corsConfig
});

service /auth on httpListener {
    resource function post signup(@http:Payload User user) returns json|error {
        // Convert user record to a string
        string userString = string:concat(user.username, ",", user.email, ",", user.password, "\n");

        // Convert string to bytes for WritableByteChannel
        byte[] userBytes = userString.toBytes();

        // Append to users.txt in backend/src/logs
        io:WritableByteChannel|error channel = io:openWritableFile("./backend/src/logs/users.txt", io:APPEND);
        if channel is io:WritableByteChannel {
            var result = channel.write(userBytes, 0);
            check channel.close();
            return {status: "ok", message: "User registered successfully"};
        } else {
            return {status: "error", message: "Failed to save user: " + channel.message()};
        }
    }
}