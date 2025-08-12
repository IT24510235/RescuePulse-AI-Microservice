import ballerina/http;
import ballerina/io;
import ballerina/lang.'string;

type User record {|
    string username;
    string email;
    string password;
|};

listener http:Listener httpListener = new (9090);

service /auth on httpListener {

    resource function post signup(@http:Payload User user) returns http:Response|error {
        http:Response res = new;

        // Manual CORS headers
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type");

        // Convert user record to CSV-style string
        string userString = string:concat(user.username, ",", user.email, ",", user.password, "\n");
        byte[] userBytes = userString.toBytes();

        // Append to users.txt
        io:WritableByteChannel|error channel = io:openWritableFile("./backend/src/logs/users.txt", io:APPEND);
        if channel is io:WritableByteChannel {
            int _ = check channel.write(userBytes, 0); // Properly handle errors
            check channel.close();

            res.setJsonPayload({status: "ok", message: "User registered successfully"});
        } else {
            res.setJsonPayload({status: "error", message: "Failed to save user"});
        }

        return res;
    }

    // Handle OPTIONS request for CORS preflight
    resource function options signup(http:Caller caller, http:Request req) returns error? {
        http:Response res = new;
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type");
        check caller->respond(res);
    }
}
