# app.py
from flask import Flask, request, jsonify
import random
from datetime import datetime

app = Flask(__name__)

# Simulated AI: Risk Prediction Logic
def predict_risk(alert_type, location, time_of_day):
    base_risk = 0
    if alert_type.lower() in ['flood', 'landslide', 'fire']:
        base_risk += 70
    elif alert_type.lower() in ['medical', 'accident']:
        base_risk += 50
    else:
        base_risk += 30

    # Location risk (e.g., flood-prone areas)
    high_risk_areas = ['kelani river', 'hikkaduwa', 'jaffna', 'badulla']
    if any(area in location.lower() for area in high_risk_areas):
        base_risk += 20

    # Time of day (night = higher risk)
    if 22 <= time_of_day < 6:
        base_risk += 15

    # Cap at 100
    return min(base_risk, 100)

@app.route('/predict', methods=['POST'])
def predict():
    data = request.json
    alert_type = data.get('type', '')
    location = data.get('location', '')
    hour = datetime.now().hour

    risk_score = predict_risk(alert_type, location, hour)

    priority = "High" if risk_score > 70 else "Medium" if risk_score > 40 else "Low"

    return jsonify({
        "risk_score": risk_score,
        "priority": priority,
        "recommended_response": f"Dispatch {'immediately' if priority == 'High' else 'within 30 mins' if priority == 'Medium' else 'within 2 hours'}"
    })

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "RescuePulse AI Microservice"})

if __name__ == '__main__':
    app.run(port=5000, debug=True)