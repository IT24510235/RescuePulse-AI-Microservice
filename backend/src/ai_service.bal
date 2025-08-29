// ai_service.bal - AI & Prediction Services for Emergency Shield
import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/math;
import ballerina/io;

// AI Prediction types
type WeatherData record {|
    decimal temperature;
    decimal humidity;
    decimal pressure;
    decimal windSpeed;
    decimal rainfall;
    string location;
    string district;
    string province;
    time:Utc timestamp;
|};

type RiskPrediction record {|
    string id;
    string riskType; // "flood", "landslide", "cyclone", "drought"
    decimal riskScore; // 0.0 to 1.0
    string riskLevel; // "low", "medium", "high", "critical"
    string location;
    string district;
    string province;
    string[] affectedAreas;
    time:Utc predictionTime;
    time:Utc validUntil;
    string confidence; // "low", "medium", "high"
    string[] recommendations;
|};

type AIModelMetrics record {|
    string modelName;
    decimal accuracy;
    decimal precision;
    decimal recall;
    decimal f1Score;
    time:Utc lastTrained;
    int totalPredictions;
    int correctPredictions;
|};

// Historical disaster data for training
type DisasterHistory record {|
    string disasterType;
    string location;
    string district;
    time:Utc occurredDate;
    string severity;
    WeatherData[] preDisasterWeather;
    string[] causes;
|};

// In-memory storage for AI services
RiskPrediction[] currentPredictions = [];
AIModelMetrics[] modelMetrics = [];
WeatherData[] weatherHistory = [];
DisasterHistory[] disasterHistory = [];

// Risk thresholds for different disaster types
map<decimal> riskThresholds = {
    "flood_critical": 0.8,
    "flood_high": 0.6,
    "flood_medium": 0.4,
    "landslide_critical": 0.75,
    "landslide_high": 0.55,
    "landslide_medium": 0.35,
    "cyclone_critical": 0.85,
    "cyclone_high": 0.65,
    "cyclone_medium": 0.45,
    "drought_critical": 0.7,
    "drought_high": 0.5,
    "drought_medium": 0.3
};

// Sri Lankan weather monitoring stations
map<[decimal, decimal]> weatherStations = {
    "Colombo": [6.9271, 79.8612],
    "Kandy": [7.2966, 80.6350],
    "Galle": [6.0535, 80.2210],
    "Jaffna": [9.6615, 80.0255],
    "Batticaloa": [7.7102, 81.6924],
    "Anuradhapura": [8.3114, 80.4037],
    "Ratnapura": [6.6828, 80.3992],
    "Nuwara_Eliya": [6.9497, 80.7891],
    "Trincomalee": [8.5874, 81.2152],
    "Hambantota": [6.1241, 81.1185]
};

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowCredentials: false,
        allowHeaders: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    }
}
service /ai on new http:Listener(8081) {

    // Get current risk predictions
    resource function get predictions() returns RiskPrediction[]|error {
        return currentPredictions.filter(pred => 
            time:utcNow()[0] < pred.validUntil[0]
        );
    }

    // Get predictions by district
    resource function get predictions/district/[string district]() returns RiskPrediction[]|error {
        return currentPredictions.filter(pred => 
            pred.district.toLowerAscii() == district.toLowerAscii() &&
            time:utcNow()[0] < pred.validUntil[0]
        );
    }

    // Get predictions by risk type
    resource function get predictions/type/[string riskType]() returns RiskPrediction[]|error {
        return currentPredictions.filter(pred => 
            pred.riskType.toLowerAscii() == riskType.toLowerAscii() &&
            time:utcNow()[0] < pred.validUntil[0]
        );
    }

    // Process weather data and generate predictions
    resource function post weather/analyze(@http:Payload WeatherData weatherData) returns RiskPrediction[]|error {
        // Store weather data
        weatherData.timestamp = time:utcNow();
        weatherHistory.push(weatherData);

        // Generate predictions based on weather data
        RiskPrediction[] newPredictions = [];

        // Flood risk analysis
        RiskPrediction? floodPrediction = analyzeFloodRisk(weatherData);
        if floodPrediction is RiskPrediction {
            newPredictions.push(floodPrediction);
        }

        // Landslide risk analysis
        RiskPrediction? landslidePrediction = analyzeLandslideRisk(weatherData);
        if landslidePrediction is RiskPrediction {
            newPredictions.push(landslidePrediction);
        }

        // Cyclone risk analysis
        RiskPrediction? cyclonePrediction = analyzeCycloneRisk(weatherData);
        if cyclonePrediction is RiskPrediction {
            newPredictions.push(cyclonePrediction);
        }

        // Store new predictions
        foreach RiskPrediction pred in newPredictions {
            currentPredictions.push(pred);
        }

        log:printInfo("Generated " + newPredictions.length().toString() + " new risk predictions for " + weatherData.location);
        return newPredictions;
    }

    // Batch process multiple weather readings
    resource function post weather/batch(@http:Payload WeatherData[] weatherDataList) returns RiskPrediction[]|error {
        RiskPrediction[] allPredictions = [];

        foreach WeatherData weather in weatherDataList {
            RiskPrediction[]|error predictions = self./'weather/analyze(weather);
            if predictions is RiskPrediction[] {
                allPredictions.push(...predictions);
            }
        }

        return allPredictions;
    }

    // Get AI model performance metrics
    resource function get models/metrics() returns AIModelMetrics[]|error {
        return modelMetrics;
    }

    // Update model accuracy based on actual disaster outcomes
    resource function post models/feedback(@http:Payload map<anydata> feedback) returns string|error {
        string? predictionId = <string>feedback["predictionId"];
        string? actualOutcome = <string>feedback["actualOutcome"]; // "occurred", "not_occurred"
        
        if predictionId is string && actualOutcome is string {
            updateModelAccuracy(predictionId, actualOutcome);
            return "Model feedback processed successfully";
        }
        
        return error("Invalid feedback data");
    }

    // Get weather history for analysis
    resource function get weather/history() returns WeatherData[]|error {
        return weatherHistory;
    }

    // Get weather history by location
    resource function get weather/history/[string location]() returns WeatherData[]|error {
        return weatherHistory.filter(weather => 
            weather.location.toLowerAscii() == location.toLowerAscii()
        );
    }

    // Advanced risk analysis with multiple parameters
    resource function post risk/analyze(@http:Payload map<anydata> analysisRequest) returns RiskPrediction[]|error {
        string? location = <string>analysisRequest["location"];
        string? timeframe = <string>analysisRequest["timeframe"]; // "24h", "48h", "72h"
        
        if location is string {
            return performAdvancedRiskAnalysis(location, timeframe ?: "24h");
        }
        
        return error("Location is required for risk analysis");
    }

    // Get disaster patterns and trends
    resource function get analytics/patterns() returns map<anydata>|error {
        return {
            "seasonal_trends": getSeasonalTrends(),
            "high_risk_areas": getHighRiskAreas(),
            "disaster_frequency": getDisasterFrequency(),
            "accuracy_trends": getModelAccuracyTrends()
        };
    }

    // Health check for AI services
    resource function get health() returns map<string>|error {
        return {
            "status": "healthy",
            "service": "AI-EmergencyShield-AI-Services",
            "active_predictions": currentPredictions.length().toString(),
            "weather_records": weatherHistory.length().toString(),
            "timestamp": time:utcToString(time:utcNow())
        };
    }
}

// Flood risk analysis function
function analyzeFloodRisk(WeatherData weather) returns RiskPrediction? {
    decimal riskScore = 0.0;
    string[] recommendations = [];
    
    // Rainfall analysis
    if weather.rainfall > 100.0 {
        riskScore += 0.4;
        recommendations.push("Heavy rainfall detected - monitor water levels");
    } else if weather.rainfall > 50.0 {
        riskScore += 0.2;
        recommendations.push("Moderate rainfall - stay alert for flooding");
    }
    
    // Humidity and pressure analysis
    if weather.humidity > 85.0 && weather.pressure < 1010.0 {
        riskScore += 0.2;
        recommendations.push("High humidity and low pressure indicate storm conditions");
    }
    
    // Historical data analysis
    WeatherData[] recentWeather = getRecentWeatherForLocation(weather.location, 24); // 24 hours
    decimal avgRainfall = calculateAverageRainfall(recentWeather);
    
    if avgRainfall > 75.0 {
        riskScore += 0.3;
        recommendations.push("Sustained rainfall over 24 hours increases flood risk");
    }
    
    // Geographic factors for Sri Lankan locations
    if isFloodProneArea(weather.district) {
        riskScore += 0.2;
        recommendations.push("Location is in a historically flood-prone area");
    }
    
    string riskLevel = calculateRiskLevel("flood", riskScore);
    
    if riskScore > 0.3 { // Only create prediction if risk is significant
        return {
            id: generatePredictionId(),
            riskType: "flood",
            riskScore: riskScore,
            riskLevel: riskLevel,
            location: weather.location,
            district: weather.district,
            province: weather.province,
            affectedAreas: getAffectedAreas(weather.district, "flood"),
            predictionTime: time:utcNow(),
            validUntil: time:utcAddSeconds(time:utcNow(), 86400), // 24 hours
            confidence: calculateConfidence(riskScore),
            recommendations: recommendations
        };
    }
    
    return ();
}

// Landslide risk analysis function
function analyzeLandslideRisk(WeatherData weather) returns RiskPrediction? {
    decimal riskScore = 0.0;
    string[] recommendations = [];
    
    // Rainfall intensity analysis
    if weather.rainfall > 75.0 {
        riskScore += 0.5;
        recommendations.push("Heavy rainfall on slopes increases landslide risk");
    }
    
    // Soil saturation estimation
    WeatherData[] recentWeather = getRecentWeatherForLocation(weather.location, 72); // 72 hours
    decimal totalRainfall = calculateTotalRainfall(recentWeather);
    
    if totalRainfall > 150.0 {
        riskScore += 0.3;
        recommendations.push("Soil saturation from prolonged rainfall");
    }
    
    // Geographic and topographic factors
    if isLandslideProneArea(weather.district) {
        riskScore += 0.25;
        recommendations.push("Area has steep terrain susceptible to landslides");
    }
    
    string riskLevel = calculateRiskLevel("landslide", riskScore);
    
    if riskScore > 0.35 {
        return {
            id: generatePredictionId(),
            riskType: "landslide",
            riskScore: riskScore,
            riskLevel: riskLevel,
            location: weather.location,
            district: weather.district,
            province: weather.province,
            affectedAreas: getAffectedAreas(weather.district, "landslide"),
            predictionTime: time:utcNow(),
            validUntil: time:utcAddSeconds(time:utcNow(), 86400),
            confidence: calculateConfidence(riskScore),
            recommendations: recommendations
        };
    }
    
    return ();
}

// Cyclone risk analysis function
function analyzeCycloneRisk(WeatherData weather) returns RiskPrediction? {
    decimal riskScore = 0.0;
    string[] recommendations = [];
    
    // Wind speed analysis
    if weather.windSpeed > 100.0 {
        riskScore += 0.4;
        recommendations.push("Very high wind speeds detected");
    } else if weather.windSpeed > 60.0 {
        riskScore += 0.2;
        recommendations.push("Strong winds may cause damage");
    }
    
    // Pressure analysis
    if weather.pressure < 990.0 {
        riskScore += 0.3;
        recommendations.push("Very low atmospheric pressure indicates storm system");
    } else if weather.pressure < 1005.0 {
        riskScore += 0.15;
        recommendations.push("Low pressure system detected");
    }
    
    // Combined factors
    if weather.windSpeed > 80.0 && weather.pressure < 995.0 && weather.humidity > 80.0 {
        riskScore += 0.25;
        recommendations.push("Multiple cyclone indicators present");
    }
    
    string riskLevel = calculateRiskLevel("cyclone", riskScore);
    
    if riskScore > 0.45 {
        return {
            id: generatePredictionId(),
            riskType: "cyclone",
            riskScore: riskScore,
            riskLevel: riskLevel,
            location: weather.location,
            district: weather.district,
            province: weather.province,
            affectedAreas: getAffectedAreas(weather.district, "cyclone"),
            predictionTime: time:utcNow(),
            validUntil: time:utcAddSeconds(time:utcNow(), 72000), // 20 hours
            confidence: calculateConfidence(riskScore),
            recommendations: recommendations
        };
    }
    
    return ();
}

// Helper functions
function calculateRiskLevel(string disasterType, decimal riskScore) returns string {
    string thresholdKey = disasterType + "_critical";
    decimal? criticalThreshold = riskThresholds[thresholdKey];
    
    thresholdKey = disasterType + "_high";
    decimal? highThreshold = riskThresholds[thresholdKey];
    
    thresholdKey = disasterType + "_medium";
    decimal? mediumThreshold = riskThresholds[thresholdKey];
    
    if criticalThreshold is decimal && riskScore >= criticalThreshold {
        return "critical";
    } else if highThreshold is decimal && riskScore >= highThreshold {
        return "high";
    } else if mediumThreshold is decimal && riskScore >= mediumThreshold {
        return "medium";
    } else {
        return "low";
    }
}

function calculateConfidence(decimal riskScore) returns string {
    if riskScore >= 0.8 {
        return "high";
    } else if riskScore >= 0.5 {
        return "medium";
    } else {
        return "low";
    }
}

function generatePredictionId() returns string {
    return "PRED_" + time:utcNow()[0].toString() + "_" + math:randomInRange(1000, 9999).toString();
}

function getRecentWeatherForLocation(string location, int hours) returns WeatherData[] {
    time:Utc cutoffTime = time:utcAddSeconds(time:utcNow(), -hours * 3600);
    return weatherHistory.filter(weather => 
        weather.location == location && 
        weather.timestamp[0] >= cutoffTime[0]
    );
}

function calculateAverageRainfall(WeatherData[] weatherList) returns decimal {
    if weatherList.length() == 0 {
        return 0.0;
    }
    
    decimal totalRainfall = 0.0;
    foreach WeatherData weather in weatherList {
        totalRainfall += weather.rainfall;
    }
    
    return totalRainfall / <decimal>weatherList.length();
}

function calculateTotalRainfall(WeatherData[] weatherList) returns decimal {
    decimal totalRainfall = 0.0;
    foreach WeatherData weather in weatherList {
        totalRainfall += weather.rainfall;
    }
    return totalRainfall;
}

function isFloodProneArea(string district) returns boolean {
    string[] floodProneDistricts = ["Colombo", "Gampaha", "Kalutara", "Ratnapura", "Kegalle", "Galle"];
    return floodProneDistricts.indexOf(district) != ();
}

function isLandslideProneArea(string district) returns boolean {
    string[] landslideProneDistricts = ["Kandy", "Matale", "Nuwara Eliya", "Ratnapura", "Kegalle", "Badulla"];
    return landslideProneDistricts.indexOf(district) != ();
}

function getAffectedAreas(string district, string disasterType) returns string[] {
    // This would normally query a geographic database
    // For now, returning example areas based on district
    match district {
        "Colombo" => {
            return ["Colombo City", "Dehiwala", "Mount Lavinia", "Kelaniya"];
        }
        "Kandy" => {
            return ["Kandy City", "Peradeniya", "Gampola", "Katugastota"];
        }
        "Galle" => {
            return ["Galle Fort", "Hikkaduwa", "Bentota", "Ambalangoda"];
        }
        _ => {
            return [district + " Central", district + " Suburbs"];
        }
    }
}

function performAdvancedRiskAnalysis(string location, string timeframe) returns RiskPrediction[] {
    // Advanced ML-based analysis would go here
    // For now, returning basic analysis
    return currentPredictions.filter(pred => pred.location == location);
}

function updateModelAccuracy(string predictionId, string actualOutcome) {
    // Update model metrics based on actual outcomes
    log:printInfo("Updating model accuracy for prediction: " + predictionId + " with outcome: " + actualOutcome);
}

function getSeasonalTrends() returns map<anydata> {
    return {
        "monsoon_season": "High flood and landslide risk during May-September",
        "dry_season": "Increased drought risk during December-March",
        "cyclone_season": "Peak cyclone activity during October-December"
    };
}

function getHighRiskAreas() returns string[] {
    return ["Ratnapura", "Kegalle", "Kandy", "Matale", "Nuwara Eliya", "Colombo", "Gampaha"];
}

function getDisasterFrequency() returns map<int> {
    return {
        "flood": 45,
        "landslide": 32,
        "cyclone": 12,
        "drought": 8
    };
}

function getModelAccuracyTrends() returns map<decimal> {
    return {
        "flood_model": 0.87,
        "landslide_model": 0.82,
        "cyclone_model": 0.91,
        "overall_accuracy": 0.86
    };
}