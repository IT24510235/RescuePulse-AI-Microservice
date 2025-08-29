// ai_service_test.bal - Test cases for AI & Prediction Services
import ballerina/test;
import ballerina/http;
import ballerina/io;
import ballerina/time;

// Test service client
http:Client aiServiceClient = check new ("http://localhost:8081");
http:Client predictionServiceClient = check new ("http://localhost:5000");

// Sample weather data for testing
WeatherData sampleWeatherData = {
    temperature: 28.5,
    humidity: 85.0,
    pressure: 1008.5,
    windSpeed: 45.0,
    rainfall: 85.0,
    location: "Colombo",
    district: "Colombo",
    province: "Western",
    timestamp: time:utcNow()
};

WeatherData extremeWeatherData = {
    temperature: 32.0,
    humidity: 95.0,
    pressure: 985.0,
    windSpeed: 120.0,
    rainfall: 150.0,
    location: "Ratnapura",
    district: "Ratnapura", 
    province: "Sabaragamuwa",
    timestamp: time:utcNow()
};

// Test AI service health check
@test:Config {}
function testAIServiceHealth() returns error? {
    http:Response response = check aiServiceClient->get("/ai/health");
    test:assertEquals(response.statusCode, 200);
    
    json responseBody = check response.getJsonPayload();
    test:assertEquals(responseBody.status, "healthy");
    io:println("✓ AI Service health check passed");
}

// Test weather data analysis
@test:Config {}
function testWeatherAnalysis() returns error? {
    http:Response response = check aiServiceClient->post("/ai/weather/analyze", sampleWeatherData);
    test:assertEquals(response.statusCode, 200);
    
    RiskPrediction[] predictions = check response.getJsonPayload();
    test:assertTrue(predictions.length() >= 0);
    
    foreach RiskPrediction prediction in predictions {
        test:assertTrue(prediction.riskScore >= 0.0 && prediction.riskScore <= 1.0);
        test:assertTrue(prediction.riskLevel is "low"|"medium"|"high"|"critical");
        test:assertEquals(prediction.district, "Colombo");
    }
    
    io:println("✓ Weather analysis test passed");
}

// Test extreme weather conditions
@test:Config {}
function testExtremeWeatherAnalysis() returns error? {
    http:Response response = check aiServiceClient->post("/ai/weather/analyze", extremeWeatherData);
    test:assertEquals(response.statusCode, 200);
    
    RiskPrediction[] predictions = check response.getJsonPayload();
    test:assertTrue(predictions.length() > 0);
    
    // Should generate high-risk predictions for extreme weather
    boolean hasHighRisk = false;
    foreach RiskPrediction prediction in predictions {
        if prediction.riskLevel == "high" || prediction.riskLevel == "critical" {
            hasHighRisk = true;
            break;
        }
    }
    test:assertTrue(hasHighRisk, "Extreme weather should generate high-risk predictions");
    
    io:println("✓ Extreme weather analysis test passed");
}

// Test batch weather processing
@test:Config {}
function testBatchWeatherProcessing() returns error? {
    WeatherData[] batchData = [sampleWeatherData, extremeWeatherData];
    
    http:Response response = check aiServiceClient->post("/ai/weather/batch", batchData);
    test:assertEquals(response.statusCode, 200);
    
    RiskPrediction[] predictions = check response.getJsonPayload();
    test:assertTrue(predictions.length() >= 0);
    
    io:println("✓ Batch weather processing test passed");
}

// Test prediction filtering by district
@test:Config {}
function testPredictionsByDistrict() returns error? {
    // First, generate some predictions
    _ = check aiServiceClient->post("/ai/weather/analyze", sampleWeatherData);
    
    // Then retrieve predictions for specific district
    http:Response response = check aiServiceClient->get("/ai/predictions/district/Colombo");
    test:assertEquals(response.statusCode, 200);
    
    RiskPrediction[] predictions = check response.getJsonPayload();
    
    foreach RiskPrediction prediction in predictions {
        test:assertEquals(prediction.district, "Colombo");
    }
    
    io:println("✓ Predictions by district test passed");
}

// Test prediction filtering by risk type
@test:Config {}
function testPredictionsByRiskType() returns error? {
    // Generate predictions first
    _ = check aiServiceClient->post("/ai/weather/analyze", extremeWeatherData);
    
    // Test different risk types
    string[] riskTypes = ["flood", "landslide", "cyclone"];
    
    foreach string riskType in riskTypes {
        http:Response response = check aiServiceClient->get("/ai/predictions/type/" + riskType);
        test:assertEquals(response.statusCode, 200);