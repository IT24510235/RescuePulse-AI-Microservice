# predict.py - Real-time Prediction Service for AI-EmergencyShield
import joblib
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import json
import os
import warnings
from flask import Flask, request, jsonify
import logging
from sklearn.preprocessing import LabelEncoder

warnings.filterwarnings('ignore')

class EmergencyPredictionService:
    def __init__(self, model_dir='ai/models'):
        self.models = {}
        self.scaler = None
        self.label_encoders = {}
        self.feature_columns = []
        self.model_dir = model_dir
        self.sri_lankan_districts = [
            'Colombo', 'Gampaha', 'Kalutara', 'Kandy', 'Matale', 'Nuwara Eliya',
            'Galle', 'Matara', 'Hambantota', 'Jaffna', 'Kilinochchi', 'Mannar',
            'Mullaitivu', 'Vavuniya', 'Batticaloa', 'Ampara', 'Trincomalee',
            'Kurunegala', 'Puttalam', 'Anuradhapura', 'Polonnaruwa', 
            'Badulla', 'Monaragala', 'Ratnapura', 'Kegalle'
        ]
        
        # Risk level thresholds
        self.risk_thresholds = {
            'flood': {'low': 0.3, 'medium': 0.5, 'high': 0.7, 'critical': 0.85},
            'landslide': {'low': 0.25, 'medium': 0.45, 'high': 0.65, 'critical': 0.8},
            'cyclone': {'low': 0.4, 'medium': 0.6, 'high': 0.75, 'critical': 0.9}
        }
        
        self.load_models()
        
    def load_models(self):
        """Load trained models and preprocessors"""
        try:
            print(f"Loading models from {self.model_dir}...")
            
            # Load individual models
            disaster_types = ['flood', 'landslide', 'cyclone']
            for disaster_type in disaster_types:
                model_path = os.path.join(self.model_dir, f'{disaster_type}_model.pkl')
                if os.path.exists(model_path):
                    self.models[disaster_type] = joblib.load(model_path)
                    print(f"Loaded {disaster_type} model")
                else:
                    print(f"Warning: {disaster_type} model not found at {model_path}")
            
            # Load scaler
            scaler_path = os.path.join(self.model_dir, 'scaler.pkl')
            if os.path.exists(scaler_path):
                self.scaler = joblib.load(scaler_path)
                print("Loaded feature scaler")
            
            # Load label encoders
            encoder_path = os.path.join(self.model_dir, 'label_encoders.pkl')
            if os.path.exists(encoder_path):
                self.label_encoders = joblib.load(encoder_path)
                print("Loaded label encoders")
            
            # Load feature columns
            features_path = os.path.join(self.model_dir, 'feature_columns.json')
            if os.path.exists(features_path):
                with open(features_path, 'r') as f:
                    self.feature_columns = json.load(f)
                print("Loaded feature columns")
            
            print("All models loaded successfully!")
            
        except Exception as e:
            print(f"Error loading models: {str(e)}")
            raise
    
    def preprocess_input(self, weather_data):
        """Preprocess input weather data for prediction"""
        try:
            # Convert to DataFrame if it's a dict
            if isinstance(weather_data, dict):
                df = pd.DataFrame([weather_data])
            else:
                df = pd.DataFrame(weather_data)
            
            # Validate required fields
            required_fields = ['district', 'temperature', 'humidity', 'pressure', 'wind_speed', 'rainfall']
            for field in required_fields:
                if field not in df.columns:
                    raise ValueError(f"Missing required field: {field}")
            
            # Add month if not provided (use current month)
            if 'month' not in df.columns:
                df['month'] = datetime.now().month
            
            # Validate district
            df['district'] = df['district'].apply(lambda x: x.title())
            invalid_districts = df[~df['district'].isin(self.sri_lankan_districts)]['district'].unique()
            if len(invalid_districts) > 0:
                raise ValueError(f"Invalid districts: {invalid_districts}")
            
            # Encode categorical variables
            df['district_encoded'] = self.label_encoders['district'].transform(df['district'])
            
            # Feature engineering
            df['rainfall_intensity'] = np.where(df['rainfall'] > 100, 'heavy',
                                      np.where(df['rainfall'] > 50, 'moderate', 'light'))
            df['rainfall_intensity_encoded'] = self.label_encoders['rainfall_intensity'].transform(df['rainfall_intensity'])
            
            # Add geographic risk factors
            flood_prone_districts = ['Colombo', 'Gampaha', 'Kalutara', 'Ratnapura', 'Kegalle']
            landslide_prone_districts = ['Kandy', 'Matale', 'Nuwara Eliya', 'Ratnapura', 'Kegalle', 'Badulla']
            coastal_districts = ['Colombo', 'Gampaha', 'Kalutara', 'Galle', 'Matara', 'Hambantota']
            
            df['is_flood_prone'] = df['district'].isin(flood_prone_districts)
            df['is_landslide_prone'] = df['district'].isin(landslide_prone_districts)
            df['is_coastal'] = df['district'].isin(coastal_districts)
            
            # Seasonal indicator
            df['is_monsoon'] = df['month'].isin([5, 6, 7, 8, 9])
            
            # Additional engineered features
            df['temp_humidity_interaction'] = df['temperature'] * df['humidity'] / 100
            df['pressure_deficit'] = 1013 - df['pressure']
            df['wind_pressure_ratio'] = df['wind_speed'] / df['pressure'] * 1000
            
            # Select only required features
            df_features = df[self.feature_columns]
            
            # Scale features
            X_scaled = self.scaler.transform(df_features)
            
            return X_scaled, df
            
        except Exception as e:
            raise ValueError(f"Error preprocessing input: {str(e)}")
    
    def predict_risk(self, weather_data):
        """Predict disaster risks for given weather data"""
        try:
            # Preprocess input
            X_scaled, df_original = self.preprocess_input(weather_data)
            
            predictions = {}
            
            for disaster_type, model in self.models.items():
                # Get probability predictions
                probabilities = model.predict_proba(X_scaled)
                risk_probabilities = probabilities[:, 1]  # Probability of disaster (class 1)
                
                # Get binary predictions
                binary_predictions = model.predict(X_scaled)
                
                predictions[disaster_type] = {
                    'risk_probability': risk_probabilities.tolist(),
                    'binary_prediction': binary_predictions.tolist(),
                    'risk_level': [self._get_risk_level(disaster_type, prob) for prob in risk_probabilities],
                    'confidence': [self._get_confidence_level(prob) for prob in risk_probabilities]
                }
            
            # Create detailed response
            detailed_predictions = []
            
            for i in range(len(df_original)):
                location_prediction = {
                    'location': df_original.iloc[i]['district'],
                    'timestamp': datetime.now().isoformat(),
                    'weather_conditions': {
                        'temperature': float(df_original.iloc[i]['temperature']),
                        'humidity': float(df_original.iloc[i]['humidity']),
                        'pressure': float(df_original.iloc[i]['pressure']),
                        'wind_speed': float(df_original.iloc[i]['wind_speed']),
                        'rainfall': float(df_original.iloc[i]['rainfall'])
                    },
                    'risk_predictions': {},
                    'recommendations': []
                }
                
                # Add predictions for each disaster type
                for disaster_type in self.models.keys():
                    prob = predictions[disaster_type]['risk_probability'][i]
                    risk_level = predictions[disaster_type]['risk_level'][i]
                    
                    location_prediction['risk_predictions'][disaster_type] = {
                        'probability': round(prob, 3),
                        'risk_level': risk_level,
                        'confidence': predictions[disaster_type]['confidence'][i],
                        'binary_prediction': bool(predictions[disaster_type]['binary_prediction'][i])
                    }
                    
                    # Add recommendations based on risk level
                    recommendations = self._get_recommendations(disaster_type, risk_level, df_original.iloc[i])
                    location_prediction['recommendations'].extend(recommendations)
                
                # Remove duplicate recommendations
                location_prediction['recommendations'] = list(set(location_prediction['recommendations']))
                
                detailed_predictions.append(location_prediction)
            
            return detailed_predictions
            
        except Exception as e:
            raise Exception(f"Error during prediction: {str(e)}")
    
    def _get_risk_level(self, disaster_type, probability):
        """Convert probability to risk level"""
        thresholds = self.risk_thresholds[disaster_type]
        
        if probability >= thresholds['critical']:
            return 'critical'
        elif probability >= thresholds['high']:
            return 'high'
        elif probability >= thresholds['medium']:
            return 'medium'
        elif probability >= thresholds['low']:
            return 'low'
        else:
            return 'minimal'
    
    def _get_confidence_level(self, probability):
        """Get confidence level based on probability"""
        if probability >= 0.8 or probability <= 0.2:
            return 'high'
        elif probability >= 0.6 or probability <= 0.4:
            return 'medium'
        else:
            return 'low'
    
    def _get_recommendations(self, disaster_type, risk_level, weather_data):
        """Get recommendations based on disaster type and risk level"""
        recommendations = []
        
        if risk_level in ['critical', 'high']:
            if disaster_type == 'flood':
                recommendations.extend([
                    "Move to higher ground immediately",
                    "Avoid walking or driving through flood waters",
                    "Monitor water levels continuously",
                    "Prepare emergency supplies"
                ])
                
                if weather_data['rainfall'] > 100:
                    recommendations.append("Heavy rainfall warning - evacuate flood-prone areas")
                    
            elif disaster_type == 'landslide':
                recommendations.extend([
                    "Evacuate steep slope areas immediately",
                    "Stay away from hillsides and cliffs",
                    "Listen for unusual sounds (rumbling, cracking)",
                    "Alert local authorities"
                ])
                
                if weather_data['rainfall'] > 75:
                    recommendations.append("Prolonged rainfall increases landslide risk significantly")
                    
            elif disaster_type == 'cyclone':
                recommendations.extend([
                    "Stay indoors and away from windows",
                    "Secure loose outdoor objects",
                    "Stock up on emergency supplies",
                    "Monitor weather updates continuously"
                ])
                
                if weather_data['wind_speed'] > 100:
                    recommendations.append("Extremely dangerous winds - take immediate shelter")
        
        elif risk_level == 'medium':
            if disaster_type == 'flood':
                recommendations.extend([
                    "Stay alert for changing weather conditions",
                    "Avoid low-lying areas",
                    "Prepare emergency kit"
                ])
            elif disaster_type == 'landslide':
                recommendations.extend([
                    "Monitor slope stability",
                    "Be prepared to evacuate if conditions worsen"
                ])
            elif disaster_type == 'cyclone':
                recommendations.extend([
                    "Monitor weather forecasts",
                    "Secure outdoor items"
                ])
        
        return recommendations
    
    def batch_predict(self, weather_data_list):
        """Predict for multiple weather data points"""
        try:
            all_predictions = []
            
            for weather_data in weather_data_list:
                prediction = self.predict_risk(weather_data)
                all_predictions.extend(prediction)
            
            return all_predictions
            
        except Exception as e:
            raise Exception(f"Error in batch prediction: {str(e)}")
    
    def get_model_info(self):
        """Get information about loaded models"""
        info = {
            'loaded_models': list(self.models.keys()),
            'model_directory': self.model_dir,
            'supported_districts': self.sri_lankan_districts,
            'feature_count': len(self.feature_columns),
            'risk_thresholds': self.risk_thresholds
        }
        
        # Add model metadata if available
        metadata_path = os.path.join(self.model_dir, 'model_metadata.json')
        if os.path.exists(metadata_path):
            with open(metadata_path, 'r') as f:
                metadata = json.load(f)
                info.update(metadata)
        
        return info

# Flask API for the prediction service
app = Flask(__name__)
app.logger.setLevel(logging.INFO)

# Initialize prediction service
try:
    prediction_service = EmergencyPredictionService()
    print("Prediction service initialized successfully!")
except Exception as e:
    print(f"Failed to initialize prediction service: {str(e)}")
    prediction_service = None

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    if prediction_service is None:
        return jsonify({'status': 'unhealthy', 'error': 'Models not loaded'}), 500
    
    return jsonify({
        'status': 'healthy',
        'service': 'AI-EmergencyShield-Prediction-Service',
        'timestamp': datetime.now().isoformat(),
        'loaded_models': list(prediction_service.models.keys())
    })

@app.route('/predict', methods=['POST'])
def predict():
    """Single prediction endpoint"""
    if prediction_service is None:
        return jsonify({'error': 'Prediction service not available'}), 500
    
    try:
        weather_data = request.json
        
        if not weather_data:
            return jsonify({'error': 'No weather data provided'}), 400
        
        predictions = prediction_service.predict_risk(weather_data)
        
        return jsonify({
            'success': True,
            'predictions': predictions,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        app.logger.error(f"Prediction error: {str(e)}")
        return jsonify({'error': str(e)}), 400

@app.route('/predict/batch', methods=['POST'])
def batch_predict():
    """Batch prediction endpoint"""
    if prediction_service is None:
        return jsonify({'error': 'Prediction service not available'}), 500
    
    try:
        weather_data_list = request.json
        
        if not weather_data_list or not isinstance(weather_data_list, list):
            return jsonify({'error': 'Invalid weather data list provided'}), 400
        
        predictions = prediction_service.batch_predict(weather_data_list)
        
        return jsonify({
            'success': True,
            'predictions': predictions,
            'count': len(predictions),
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        app.logger.error(f"Batch prediction error: {str(e)}")
        return jsonify({'error': str(e)}), 400

@app.route('/model/info', methods=['GET'])
def model_info():
    """Get model information"""
    if prediction_service is None:
        return jsonify({'error': 'Prediction service not available'}), 500
    
    try:
        info = prediction_service.get_model_info()
        return jsonify(info)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/districts', methods=['GET'])
def get_districts():
    """Get supported Sri Lankan districts"""
    if prediction_service is None:
        return jsonify({'error': 'Prediction service not available'}), 500
    
    return jsonify({
        'districts': prediction_service.sri_lankan_districts,
        'count': len(prediction_service.sri_lankan_districts)
    })

if __name__ == '__main__':
    print("Starting AI-EmergencyShield Prediction Service...")
    print("=" * 50)
    
    if prediction_service is None:
        print("ERROR: Failed to initialize prediction service!")
        print("Please ensure models are trained and saved properly.")
        exit(1)
    
    print("Service ready!")
    print("Available endpoints:")
    print("- GET  /health          - Health check")
    print("- POST /predict         - Single prediction")
    print("- POST /predict/batch   - Batch predictions")
    print("- GET  /model/info      - Model information")
    print("- GET  /districts       - Supported districts")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, debug=True)