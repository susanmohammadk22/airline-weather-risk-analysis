# Aviation Weather Project



**Challenges:** Time zone between station, updating schedule for weather data and flight data was not match. Matching data firstly in two separate data file was very challenging and then combination of flight and weather data was very hard and challenging too. In this regard I got help from AI (DeepSeek) to solve the problem.

## The Problem

A pilot flying from New York (JFK) to Dallas (DFW), then on to Los Angeles (LAX). The weather looks fine at JFK. But DFW is having thunderstorms, and LAX has heavy fog. The pilot arrives late, misses the connection, passengers are angry, and the crew exceeds legal duty hours.

**This happens thousands of times per year.** And it costs airlines millions.

I built this project to answer one question: **Which airport pairs should never be in the same pilot sequence during bad weather?**

---

## The Challenge

When I started, I had two separate datasets:

| Data | Source | Format | Problem |
|------|--------|--------|---------|
| Flights | BTS | Local time (e.g., JFK 8:30 AM) | Times are airport-specific |
| Weather | Iowa Mesonet | UTC (e.g., 13:30) | Times are global |

**The two datasets did not speak the same language.** Matching them required:
1. Converting all flight times to UTC (accounting for Daylight Saving)
2. Rounding weather observations to the nearest hour
3. Handling missing values (weather sensors don't always report)
4. Joining 1.2 million flights with 500,000 weather records

**I used AI (DeepSeek) to help debug timezone conversions and join logic.** The hardest bug: only 0.25% of flights matched initially. The cause? Weather data had `tmpf = NA` for most rows because I didn't handle `'M'` (missing) values correctly.

---

## The Solution

After cleaning, I built two models:

| Model | Purpose | Algorithm |
|-------|---------|-----------|
| **Model 1** | Predict how many minutes of delay weather will cause | Lasso Regression |
| **Model 2** | Predict whether conditions are high-risk for crews | Random Forest |

Lasso tells me how much each factor matters. Random Forest catches non-linear patterns that Lasso would miss.

---

## Findings

### 1. JFK is the highest-risk airport

| Airport | High Risk Weather (%) |
|---------|----------------------|
| JFK | **19.8%** |
| ATL | 10.9% |
| ORD | 10.7% |
| DFW | 9.9% |
| LAX | 9.9% |
| SFO | 0% |

JFK has nearly double the risk of other airports.

### 2. Low visibility destroys schedules

| Weather Condition | Average Delay | vs. Normal |
|------------------|--------------|------------|
| Low Visibility | 31.2 minutes | +4.2 min |
| Normal | 27.0 minutes | Baseline |

One low-visibility morning at JFK adds 4 minutes to every connecting flight. That ripples across the entire network.

### 3. Wind speed

From the Lasso model:

| Feature | Impact |
|---------|--------|
| Wind speed | +0.24 min per knot |
| Wind gust | +0.09 min per knot |
| Visibility | -0.11 min per mile (good visibility reduces delay) |

For every 10 knots of wind, add 2.4 minutes of buffer to your schedule.

### 4. Random Forest confirms: wind matters most

| Feature | Importance |
|---------|------------|
| Wind Gust | 13,697 |
| Wind Speed | 2,880 |
| Ceiling Height | 1,196 |
| Visibility | 929 |

Gusts are the #1 predictor of high-risk conditions. Not sustained wind. Not visibility. Gusts.

---

## The Business Recommendations

Based on these findings, I would tell an airline:

| Recommendation | Reason |
|----------------|-----|
| Avoid JFK connections during low visibility | JFK has 19.8% high-risk weather |
| Add 5-minute buffer for every 20 knots of wind | Wind speed adds 0.24 min/knot |
| Reduce scheduled connections in spring and fall | Higher risk during these seasons |
| Monitor gusts, not just sustained wind | Gusts are the #1 risk predictor |

---

## Technical Summary

| Metric | Value |
|--------|-------|
| Total flights analyzed | 1,247,034 |
| Weather match rate | 100% (after cleaning) |
| Lasso R-squared | 0.48% (expected – weather explains little delay variance) |
| Random Forest accuracy | 90.13% |


### Required R packages:

```r
install.packages(c("tidyverse", "lubridate", "glmnet", "randomForest", "caret", "httr2", "fs"))

### Data Sources

- **Flight Data:** [Bureau of Transportation Statistics (BTS)](https://www.transtats.bts.gov) – On-Time Performance database (2025)
- **Weather Data:** [Iowa Environmental Mesonet](https://mesonet.agron.iastate.edu) – ASOS 5-minute observations
- **Weather API:** [NOAA Aviation Weather Center](https://aviationweather.gov) – METAR data for quality validation
