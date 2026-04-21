# Aviation Weather Project

## Overview

This project analyzes the impact of weather conditions on airline flight delays and crew duty violations. The primary objective is to identify airport pairs that should not be assigned to the same pilot sequence due to elevated weather-related operational risk.

**Key Research Questions:**
- Which weather factors most significantly affect propagated flight delays?
- Which airports face the highest weather-related operational risk?
- How can airlines optimize crew scheduling to minimize weather-induced disruptions?

---

## Data Sources

| Source | Description | Year |
|--------|-------------|------|
| **BTS On-Time Performance** | Flight schedules, delays, and performance metrics for U.S. carriers | 2025 |
| **Iowa Mesonet ASOS** | Automated surface weather observations (wind, visibility, ceiling, precipitation) | 2025 |

**Airports Analyzed:** ATL, DFW, JFK, LAX, ORD, SFO



---

## Methodology

### Variables

| Type | Variable | Description |
|------|----------|-------------|
| **Y₁** | Propagated Delay | `LATE_AIRCRAFT_DELAY` (minutes) from BTS |
| **Y₂** | High Risk (AWR) | Binary: 1 if visibility < 3 miles, ceiling < 1000 ft, or gusts > 25 knots |
| **X** | Weather Features | Temperature, visibility, wind speed, wind gust, ceiling height |
| **Control** | Airport Indicators | Binary variables for JFK, ATL, ORD, DFW, LAX |

### Models

| Model | Purpose | Algorithm |
|-------|---------|-----------|
| **Model 1** | Predict propagated delay | Lasso Regression (L1 regularization) |
| **Model 2** | Predict high-risk conditions | Random Forest Classification |

---

## Key Findings

### 1. High Risk Weather by Airport

| Airport | High Risk (%) | Risk Level |
|---------|--------------|------------|
| **JFK** | **19.8%** | 🔴 Highest |
| ATL | 10.9% | 🟠 High |
| ORD | 10.7% | 🟠 High |
| DFW | 9.9% | 🟡 Moderate |
| LAX | 9.9% | 🟡 Moderate |
| SFO | 0.0% | 🟢 Lowest |

> JFK experiences nearly **double** the high-risk weather events compared to other major airports.

### 2. Impact of Weather on Delays

| Weather Condition | Average Delay (minutes) | vs. Normal |
|-------------------|------------------------|------------|
| Low Visibility | 31.2 | +4.2 min |
| High Risk (AWR=1) | 29.5 | +2.5 min |
| Normal Conditions | 27.0 | Baseline |
| High Wind | 26.6 | -0.4 min |

### 3. Lasso Regression Results

**R-squared:** 0.69% (expected – weather explains only a small portion of total delay variation)

| Feature | Coefficient | Impact |
|---------|-------------|--------|
| `is_DFW` | +2.60 min | ❌ Increases delay |
| Wind Speed | +0.24 min/knot | ❌ Each knot adds 0.24 min |
| Wind Gust | +0.09 min/knot | ❌ Each knot adds 0.09 min |
| Visibility | -0.11 min/mile | ✅ Better visibility reduces delay |
| `is_JFK` | -5.93 min | ✅ Reduces delay (vs baseline) |
| `is_ATL` | -10.22 min | ✅ Reduces delay (vs baseline) |

### 4. Random Forest Feature Importance

| Feature | Importance | Interpretation |
|---------|------------|----------------|
| Wind Gust | 13,697 | 🔴 Most important predictor |
| Wind Speed | 2,880 | 🔴 Second most important |
| Ceiling Height | 1,196 | 🟠 Moderately important |
| Visibility | 929 | 🟠 Moderately important |
| Temperature | 187 | 🟡 Minor impact |
| Airport (JFK) | 55 | 🟡 Minor impact |

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total Flights Analyzed | 1,247,034 |
| Weather Match Rate | 100% |
| Average Propagated Delay | 27.5 minutes |
| High Risk (AWR=1) | 11.2% |
| Average Visibility | 9.4 miles |
| Average Wind Speed | 8.5 knots |
| Average Ceiling | 9,230 ft |

---

## Visualizations

| Figure | Description |
|--------|-------------|
| `p1_airport_risk.png` | High risk percentage by airport |
| `p2_delay_by_weather.png` | Average delay by weather condition |
| `p3_wind_delay.png` | Wind speed impact on delay |
| `p4_visibility_delay.png` | Visibility impact on delay |
| `p5_monthly_risk.png` | Seasonal pattern of high risk |
| `p6_lasso_coefficients.png` | Lasso regression coefficients |
| `p7_feature_importance.png` | Random Forest feature importance |

---

### Required R packages:

```r
install.packages(c("tidyverse", "lubridate", "glmnet", "randomForest", "caret", "httr2", "fs"))

### Data Sources

- **Flight Data:** [Bureau of Transportation Statistics (BTS)](https://www.transtats.bts.gov) – On-Time Performance database (2025)
- **Weather Data:** [Iowa Environmental Mesonet](https://mesonet.agron.iastate.edu) – ASOS 5-minute observations
- **Weather API:** [NOAA Aviation Weather Center](https://aviationweather.gov) – METAR data for quality validation
