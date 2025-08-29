# train_model.py - Machine Learning Model Training for Emergency Prediction
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
import joblib
import warnings
from datetime import datetime, timedelta
import json
import os

warnings.filterwarnings('ignore')

class DisasterPredictionModel:
    def __init__(self):
        self.models = {}
        self.scalers = {}
        self.label_encoders = {}
        self.feature_columns = []
        self.sri_lankan_districts = [
            'Colombo', 'Gampaha', 'Kalutara', 'Kandy', 'Matale', 'Nuwara Eliya',
            'Galle', 'Matara', 'Hambantota', 'Jaffna', 'Kilinochchi', 'Mannar',
            'Mullaitivu', 'Vavuniya', 'Batticaloa', 'Ampara', 'Trincomalee',
            'Kurunegala', 'Puttalam', 'Anuradhapura', 'Polonnaruwa', 
            'Badulla', 'Monaragala', 'Ratnapura', 'Kegalle'
        ]
        
    def generate_synthetic_data(self, n_samples=10000):
        """Generate synthetic weather and disaster data for Sri Lanka"""
        print("Generating synthetic training data...")
        
        np.random.seed(42)
        data = []
        
        for _ in range(n_samples):
            # Random district selection
            district = np.random.choice(self.sri_lankan_districts)
            
            # Seasonal patterns (monsoon vs dry season)
            month = np.random.randint(1, 13)
            is_monsoon = month in [5, 6, 7, 8, 9]  # May to September
            
            # Generate weather parameters based on season and location
            if is_monsoon:
                rainfall = np.random.exponential(50) + np.random.normal(0, 20)
                humidity = np.random.normal(85, 10)
                temperature = np.random.normal(27, 3)
            else:
                rainfall = np.random.exponential(10) + np.random.normal(0, 5)
                humidity = np.random.normal(70, 15)
                temperature = np.random.normal(30, 4)
            
            # Ensure realistic ranges
            rainfall = max(0, rainfall)
            humidity = np.clip(humidity, 30, 100)
            temperature = np.clip(temperature, 20, 40)
            
            # Other weather parameters
            pressure = np.random.normal(1013, 15)
            wind_speed = np.random.exponential(15) + np.random.normal(0, 10)
            wind_speed = max(0, wind_speed)
            
            # Geographic risk factors
            flood_prone_districts = ['Colombo', 'Gampaha', 'Kalutara', 'Ratnapura', 'Kegalle']
            landslide_prone_districts = ['Kandy', 'Matale', 'Nuwara Eliya', 'Ratnapura', 'Kegalle', 'Badulla']
            coastal_districts = ['Colombo', 'Gampaha', 'Kalutara', 'Galle', 'Matara', 'Hambantota']
            
            is_flood_prone = district in flood_prone_districts
            is_landslide_prone = district in landslide_prone_districts
            is_coastal = district in coastal_districts
            
            # Generate disaster labels based on conditions
            flood_risk = 0
            landslide_risk = 0
            cyclone_risk = 0
            
            # Flood risk calculation
            if rainfall > 80 and is_flood_prone:
                flood_risk = 1 if np.random.random() < 0.7 else 0
            elif rainfall > 60:
                flood_risk = 1 if np.random.random() < 0.3 else 0
            elif rainfall > 40 and is_flood_prone:
                flood_risk = 1 if np.random.random() < 0.2 else 0
            
            # Landslide risk calculation  
            if rainfall > 70 and is_landslide_prone:
                landslide_risk = 1 if np.random.random() < 0.6 else 0
            elif rainfall > 90:
                landslide_risk = 1 if np.random.random() < 0.4 else 0
            
            # Cyclone risk calculation
            if wind_speed > 80 and pressure < 995 and is_coastal:
                cyclone_risk = 1 if np.random.random() < 0.8 else 0
            elif wind_speed > 60 and pressure < 1000:
                cyclone_risk = 1 if np.random.random() < 0.3 else 0
            
            data.append({
                'district': district,
                'month': month,
                'temperature': temperature,
                'humidity': humidity,
                'pressure': pressure,
                'wind_speed': wind_speed,
                'rainfall': rainfall,
                'is_monsoon': is_monsoon,
                'is_flood_prone': is_flood_prone,
                'is_landslide_prone': is_landslide_prone,
                'is_coastal': is_coastal,
                'flood_risk': flood_risk,
                'landslide_risk': landslide_risk,
                'cyclone_risk': cyclone_risk
            })
        
        return pd.DataFrame(data)
    
    def preprocess_data(self, df):
        """Preprocess the data for training"""
        print("Preprocessing data...")
        
        # Encode categorical variables
        if 'district' not in self.label_encoders:
            self.label_encoders['district'] = LabelEncoder()
            df['district_encoded'] = self.label_encoders['district'].fit_transform(df['district'])
        else:
            df['district_encoded'] = self.label_encoders['district'].transform(df['district'])
        
        # Feature engineering
        df['rainfall_intensity'] = np.where(df['rainfall'] > 100, 'heavy',
                                  np.where(df['rainfall'] > 50, 'moderate', 'light'))
        
        if 'rainfall_intensity' not in self.label_encoders:
            self.label_encoders['rainfall_intensity'] = LabelEncoder()
            df['rainfall_intensity_encoded'] = self.label_encoders['rainfall_intensity'].fit_transform(df['rainfall_intensity'])
        else:
            df['rainfall_intensity_encoded'] = self.label_encoders['rainfall_intensity'].transform(df['rainfall_intensity'])
        
        # Create additional features
        df['temp_humidity_interaction'] = df['temperature'] * df['humidity'] / 100
        df['pressure_deficit'] = 1013 - df['pressure']
        df['wind_pressure_ratio'] = df['wind_speed'] / df['pressure'] * 1000
        
        # Define feature columns
        self.feature_columns = [
            'district_encoded', 'month', 'temperature', 'humidity', 'pressure', 
            'wind_speed', 'rainfall', 'is_monsoon', 'is_flood_prone', 
            'is_landslide_prone', 'is_coastal', 'rainfall_intensity_encoded',
            'temp_humidity_interaction', 'pressure_deficit', 'wind_pressure_ratio'
        ]
        
        return df
    
    def train_models(self, df):
        """Train models for different disaster types"""
        print("Training models...")
        
        X = df[self.feature_columns]
        
        # Scale features
        if 'main' not in self.scalers:
            self.scalers['main'] = StandardScaler()
            X_scaled = self.scalers['main'].fit_transform(X)
        else:
            X_scaled = self.scalers['main'].transform(X)
        
        disaster_types = ['flood', 'landslide', 'cyclone']
        
        for disaster_type in disaster_types:
            print(f"Training {disaster_type} prediction model...")
            
            y = df[f'{disaster_type}_risk']
            
            # Split data
            X_train, X_test, y_train, y_test = train_test_split(
                X_scaled, y, test_size=0.2, random_state=42, stratify=y
            )
            
            # Train Random Forest model
            rf_model = RandomForestClassifier(
                n_estimators=100,
                max_depth=10,
                min_samples_split=5,
                min_samples_leaf=2,
                random_state=42
            )
            rf_model.fit(X_train, y_train)
            
            # Train Gradient Boosting model
            gb_model = GradientBoostingClassifier(
                n_estimators=100,
                learning_rate=0.1,
                max_depth=6,
                random_state=42
            )
            gb_model.fit(X_train, y_train)
            
            # Evaluate models
            rf_score = accuracy_score(y_test, rf_model.predict(X_test))
            gb_score = accuracy_score(y_test, gb_model.predict(X_test))
            
            print(f"{disaster_type.capitalize()} Random Forest Accuracy: {rf_score:.3f}")
            print(f"{disaster_type.capitalize()} Gradient Boosting Accuracy: {gb_score:.3f}")
            
            # Choose best model
            if rf_score > gb_score:
                self.models[disaster_type] = rf_model
                print(f"Selected Random Forest for {disaster_type} prediction")
            else:
                self.models[disaster_type] = gb_model
                print(f"Selected Gradient Boosting for {disaster_type} prediction")
            
            # Print detailed evaluation
            y_pred = self.models[disaster_type].predict(X_test)
            print(f"\