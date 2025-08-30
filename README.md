# RescuePulse AI Microservice

A Flask-based microservice for AI-powered risk prediction and alert prioritization.

## Purpose
- Predict risk score for emergency alerts
- Recommend priority level (High/Medium/Low)
- Integrate with main Java backend via REST

## Endpoints
- `POST /predict` → Get risk score and priority
- `GET /health` → Check if service is running

## Input (for /predict)
```json
{
  "type": "flood",
  "location": "Kelani River, Colombo"
}