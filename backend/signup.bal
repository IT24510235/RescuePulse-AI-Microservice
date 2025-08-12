import ballerina/http;
     import ballerina/io;
     import ballerina/lang.'string;

     type User record {|
         string username;
         string email;
         string password;
     |};

     service /auth on new http:Listener(9090) {
         resource function post signup(@http:Payload User user) returns json|error {
             // Convert user record to a string
             string userString = string:concat(user.username, ",", user.email, ",", user.password, "\n");

             // Append to users.txt
             io:WritableCharacterChannel|error channel = io:openWritableFile("./users.txt", io:APPEND);
             if channel is io:WritableCharacterChannel {
                 var result = channel.write(userString, 0);
                 check channel.close();
                 return {status: "ok", message: "User registered successfully"};
             } else {
                 return {status: "error", message: "Failed to save user"};
             }
         }
     }

     // Configure CORS
     http:ListenerConfiguration listenerConfig = {
         cors: {
             allowOrigins: ["http://localhost:63342"],
             allowMethods: ["POST"],
             allowHeaders: ["Content-Type"]
         }
     };

     service /auth on new http:Listener(9090, listenerConfig) {
         // Same resource function as above
         resource function post signup(@http:Payload User user) returns json|error {
             string userString = string:concat(user.username, ",", user.email, ",", user.password, "\n");
             io:WritableCharacterChannel|error channel = io:openWritableFile("./users.txt", io:APPEND);
             if channel is io:WritableCharacterChannel {
                 var result = channel.write(userString, 0);
                 check channel.close();
                 return {status: "ok", message: "User registered successfully"};
             } else {
                 return {status: "error", message: "Failed to save user"};
             }
         }
     }