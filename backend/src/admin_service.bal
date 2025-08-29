import ballerina/http;

service /admin on new http:Listener(8080) {

    // Get Notifications for Admin
    resource function get notifications(http:Caller caller) returns error? {
        // Example: Fetch notifications from DB or another service
        string[] notifications = ["New user registered", "Server health check passed"];
        
        // Send the response back to the frontend
        check caller->respond(notifications);
    }
}
