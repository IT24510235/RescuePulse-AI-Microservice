import ballerina/io;
import ballerina/lang.'string;

type User record {|
    string fullName;
    string email;
    string password;
    string role;
    string country;
|};

function saveUser(string fullName, string email, string password, string role, string country) returns error? {
    // Create a User record
    User user = {fullName, email, password, role, country};

    // Convert user record to JSON string
    json userJson = user.toJson();
    string userString = userJson.toJsonString();

    // Append to users.txt
    string filePath = "./users.txt";
    io:WritableCharacterChannel|error channel = io:openWritableFile(filePath, io:APPEND);
    if channel is io:WritableCharacterChannel {
        var result = channel.write(userString + "\n", 0);
        check channel.close();
    } else {
        return channel;
    }
}

public function main(string... args) {
    // Example usage with form data
    string fullName = "John Doe";
    string email = "john@example.com";
    string password = "password123";
    string role = "customer";
    string country = "US";

    error? result = saveUser(fullName, email, password, role, country);
    if result is error {
        io:println("Error saving user: ", result.message());
    } else {
        io:println("User saved successfully!");
    }
}