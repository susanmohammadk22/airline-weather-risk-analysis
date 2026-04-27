library(tidyverse)
library(lubridate)
library(glmnet)
library(randomForest)
library(caret)
library(ggplot2)
library(scales)
# Set working directory to your project root (where model_data_clean.csv is)
setwd("C:/Users/smvic/Documents/Knowledge Mining/Hacketon/Aviation-Weather-Project")

# Verify the file exists
list.files(pattern = "model_data_clean.csv")
# STEP 1: LOAD DATA
cat("\n========================================\n")
cat("STEP 1: LOADING DATA\n")
cat("========================================\n")
# Load data
model_data <- read_csv("model_data_clean.csv", show_col_types = FALSE)

cat("Raw data loaded:", nrow(model_data), "rows\n")
model_data_clean <- model_data %>%
  filter(!is.na(propagated_delay))

cat("After removing NA propagated_delay:", nrow(model_data_clean), "rows\n")
#STEP 2: CREATE TRAIN/TEST SPLIT (70/30)
set.seed(123)  # For reproducibility
# Create 70/30 split
train_indices <- createDataPartition(model_data_clean$propagated_delay, 
                                     p = 0.7, 
                                     list = FALSE,
                                     times = 1)

train_data <- model_data[train_indices, ]
test_data <- model_data[-train_indices, ]

cat("Training set:", nrow(train_data), "rows (70%)\n")
cat("Test set:", nrow(test_data), "rows (30%)\n")

# STEP 3: PREPARE DATA FOR LASSO REGRESSION
# Function to prepare data for Lasso
prepare_lasso_data <- function(data) {
  result <- data %>%
    select(
      propagated_delay,
      tmpf, vsby, sknt, gust, ceiling_ft,
      is_JFK, is_ATL, is_ORD, is_DFW, is_LAX
    ) %>%
    drop_na()
  
  cat("  Prepared", nrow(result), "samples for Lasso\n")
  return(result)
}

# Prepare data for Lasso
lasso_features <- c("tmpf", "vsby", "sknt", "gust", "ceiling_ft",
                    "is_JFK", "is_ATL", "is_ORD", "is_DFW", "is_LAX")

# Training set
train_lasso <- train_data %>%
  select(propagated_delay, all_of(lasso_features)) %>%
  drop_na()

# Test set
test_lasso <- test_data %>%
  select(propagated_delay, all_of(lasso_features)) %>%
  drop_na()

cat("Training samples for Lasso:", nrow(train_lasso), "\n")
cat("Test samples for Lasso:", nrow(test_lasso), "\n")

# Prepare training and test sets
train_lasso <- prepare_lasso_data(train_data)
test_lasso <- prepare_lasso_data(test_data)

# Create feature matrices and target vectors
X_train <- as.matrix(train_lasso %>% select(-propagated_delay))
Y_train <- train_lasso$propagated_delay

X_test <- as.matrix(test_lasso %>% select(-propagated_delay))
Y_test <- test_lasso$propagated_delay
cat("\nTraining matrix dimensions:", dim(X_train))
cat("\nTest matrix dimensions:", dim(X_test))

# Train Lasso with cross-validation (ON TRAINING DATA ONLY)
set.seed(123)
cv_lasso <- cv.glmnet(X_train, Y_train, alpha = 1, nfolds = 10)
# Find best lambda
best_lambda <- cv_lasso$lambda.min
best_lambda_1se <- cv_lasso$lambda.1se

cat("\nBest lambda (min):", best_lambda)
cat("\nBest lambda (1se):", best_lambda_1se)
# Get coefficients
coef_lasso <- coef(cv_lasso, s = "lambda.min")
coef_matrix <- as.matrix(coef_lasso)
nonzero_indices <- which(coef_matrix != 0)
nonzero_coef <- coef_matrix[nonzero_indices]
coef_names <- rownames(coef_matrix)[nonzero_indices]

cat("\n\nNon-zero coefficients:\n")
for(i in 1:length(nonzero_coef)) {
  cat("  ", coef_names[i], ":", round(nonzero_coef[i], 4), "\n")
}

# FINAL EVALUATION ON TEST DATA (DO THIS ONCE)
test_predictions <- predict(cv_lasso, s = "lambda.min", newx = X_test)
test_rmse <- sqrt(mean((Y_test - test_predictions)^2))
test_mae <- mean(abs(Y_test - test_predictions))
test_r2 <- 1 - sum((Y_test - test_predictions)^2) / sum((Y_test - mean(Y_test))^2)

cat("\n=== LASSO FINAL TEST RESULTS ===\n")
cat("Test RMSE:", round(test_rmse, 2), "minutes\n")
cat("Test MAE:", round(test_mae, 2), "minutes\n")
cat("Test R-squared:", round(test_r2, 4), "\n")
# Prepare data for Random Forest
train_rf <- train_data %>%
  mutate(
    duty_violation = ifelse(CARRIER_DELAY > 15 & !is.na(CARRIER_DELAY), 1, 0)
  ) %>%
  select(duty_violation, all_of(lasso_features)) %>%
  drop_na() %>%
  mutate(duty_violation = as.factor(duty_violation))

test_rf <- test_data %>%
  mutate(
    duty_violation = ifelse(CARRIER_DELAY > 15 & !is.na(CARRIER_DELAY), 1, 0)
  ) %>%
  select(duty_violation, all_of(lasso_features)) %>%
  drop_na() %>%
  mutate(duty_violation = as.factor(duty_violation))

cat("Training samples for RF:", nrow(train_rf), "\n")
cat("Test samples for RF:", nrow(test_rf), "\n")
cat("Class distribution in training:\n")
print(table(train_rf$duty_violation))


# Cross-validation R-squared (for comparison)
cv_r2 <- max(1 - cv_lasso$cvm / var(Y_train))
cat("\nCross-validation R-squared (training):", round(cv_r2, 4))

# Sample down for faster training (if needed)
set.seed(123)
if(nrow(train_rf) > 50000) {
  train_rf <- train_rf %>% sample_n(50000)
  cat("Sampled down to 50,000 for faster training\n")
}

# Train Random Forest
set.seed(123)
rf_model <- randomForest(
  duty_violation ~ .,
  data = train_rf,
  ntree = 100,
  mtry = 3,
  importance = TRUE
)

cat("\nRandom Forest trained.\n")
print(rf_model)


# FINAL EVALUATION ON TEST DATA (DO THIS ONCE)
test_predictions_rf <- predict(rf_model, newdata = test_rf)
test_accuracy <- mean(test_predictions_rf == test_rf$duty_violation)

# Confusion matrix
conf_matrix <- table(Predicted = test_predictions_rf, Actual = test_rf$duty_violation)

# Calculate metrics if both classes exist
if(ncol(conf_matrix) == 2) {
  tp <- conf_matrix[2,2]
  fp <- conf_matrix[2,1]
  fn <- conf_matrix[1,2]
  precision <- tp / (tp + fp)
  recall <- tp / (tp + fn)
  f1 <- 2 * (precision * recall) / (precision + recall)
  
  cat("\n=== RANDOM FOREST FINAL TEST RESULTS ===\n")
  cat("Test Accuracy:", round(test_accuracy * 100, 2), "%\n")
  cat("Precision:", round(precision, 4), "\n")
  cat("Recall:", round(recall, 4), "\n")
  cat("F1 Score:", round(f1, 4), "\n")
} else {
  cat("\n=== RANDOM FOREST FINAL TEST RESULTS ===\n")
  cat("Test Accuracy:", round(test_accuracy * 100, 2), "%\n")
  cat("Note: Only one class present in test set\n")
}

cat("\nConfusion Matrix:\n")
print(conf_matrix)

# Feature importance
importance_df <- as.data.frame(importance(rf_model))
importance_df$feature <- rownames(importance_df)
importance_df <- importance_df %>%
  arrange(desc(MeanDecreaseGini))

cat("\n=== FEATURE IMPORTANCE ===\n")
print(importance_df %>% select(feature, MeanDecreaseGini) %>% head(10))
cat("STEP 5: GENERATING VISUALIZATIONS\n")

# Save model results
results <- list(
  lasso = list(
    best_lambda = best_lambda,
    best_lambda_1se = best_lambda_1se,
    rmse = test_rmse,
    r2 = test_r2,
    coefficients = data.frame(
      feature = coef_names,
      coefficient = as.numeric(nonzero_coef)
    )
  ),
  random_forest = list(
    accuracy = test_accuracy,
    feature_importance = importance_df,
    confusion_matrix = conf_matrix
  ),
  data_summary = list(
    train_size = nrow(train_data),
    test_size = nrow(test_data),
    total_clean = nrow(model_data_clean)
  )
)

# Save as RDS
saveRDS(results, "model_results.rds")

# Save coefficients as CSV
write_csv(results$lasso$coefficients, "lasso_coefficients.csv")
write_csv(importance_df, "rf_feature_importance.csv")

cat("\n========================================\n")
cat("RESULTS SAVED\n")
cat("========================================\n")
cat("  - model_results.rds\n")
cat("  - lasso_coefficients.csv\n")
cat("  - rf_feature_importance.csv\n")

cat("Total clean flights:", format(nrow(model_data_clean), big.mark = ","), "\n")
cat("Training set:", format(nrow(train_data), big.mark = ","), "\n")
cat("Test set:", format(nrow(test_data), big.mark = ","), "\n")

cat("\n=== LASSO PERFORMANCE ===\n")
cat("RMSE:", round(test_rmse, 2), "minutes\n")
cat("R-squared:", round(test_r2, 4), "\n")

cat("\n=== RANDOM FOREST PERFORMANCE ===\n")
cat("Accuracy:", round(test_accuracy * 100, 2), "%\n")
if(exists("f1")) cat("F1 Score:", round(f1, 4), "\n")

cat("\n=== TOP 3 FEATURES (Random Forest) ===\n")
top_features <- importance_df %>% head(3)
for(i in 1:nrow(top_features)) {
  cat("  ", i, ".", top_features$feature[i], "-", 
      round(top_features$MeanDecreaseGini[i], 0), "\n")
}

# STEP 5: GENERATE VISUALIZATIONS
# Create output directory
if (!dir.exists("output")) dir.create("output")
if (!dir.exists("output/figures")) dir.create("output/figures")

# FIGURE 1: High Risk by Airport (using test data for honest representation)
airport_risk_test <- test_data %>%
  filter(!is.na(AWR)) %>%
  group_by(ORIGIN) %>%
  summarise(
    high_risk_pct = mean(AWR, na.rm = TRUE) * 100
  ) %>%
  mutate(ORIGIN = factor(ORIGIN, levels = ORIGIN[order(high_risk_pct, decreasing = TRUE)]))

p1 <- ggplot(airport_risk_test, aes(x = ORIGIN, y = high_risk_pct, fill = ORIGIN)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = paste0(round(high_risk_pct, 1), "%")), 
            vjust = -0.5, size = 5, fontface = "bold") +
  scale_fill_manual(values = c("JFK" = "#E41A1C", "ATL" = "#FF7F00", 
                               "ORD" = "#377EB8", "DFW" = "#4DAF4A", 
                               "LAX" = "#984EA3", "SFO" = "#A65628")) +
  labs(title = "High Risk Weather Events by Airport (Test Data)",
       subtitle = "Percentage of flights with hazardous weather conditions",
       x = "Airport", y = "High Risk (%)") +
  theme_minimal() + theme(legend.position = "none")

ggsave("output/figures/p1_airport_risk.png", p1, width = 8, height = 6, dpi = 300)

# FIGURE 2: Lasso Coefficients
coef_plot_data <- data.frame(
  feature = c("Wind Speed", "Wind Gust", "Temperature", "Visibility", 
              "Ceiling Height", "JFK", "ATL", "DFW", "LAX"),
  coefficient = c(0.241, 0.088, -0.045, -0.108, -0.008, -5.934, -10.222, 2.602, -3.608)
) %>%
  mutate(direction = ifelse(coefficient > 0, "Increases Delay", "Decreases Delay"))

p2 <- ggplot(coef_plot_data, aes(x = reorder(feature, coefficient), y = coefficient, fill = direction)) +
  geom_col(width = 0.7) +
  coord_flip() +
  scale_fill_manual(values = c("Increases Delay" = "#E41A1C", "Decreases Delay" = "#4DAF4A")) +
  labs(title = "Lasso Regression: Weather Impact on Propagated Delay",
       x = "Feature", y = "Coefficient (minutes)") +
  theme_minimal() + theme(legend.position = "bottom")

ggsave("output/figures/p2_lasso_coefficients.png", p2, width = 8, height = 6, dpi = 300)

# FIGURE 3: Feature Importance
p3 <- importance_df %>%
  head(8) %>%
  mutate(feature = factor(feature, levels = feature[order(MeanDecreaseGini)])) %>%
  ggplot(aes(x = feature, y = MeanDecreaseGini, fill = feature)) +
  geom_col(width = 0.7) +
  coord_flip() +
  scale_fill_viridis_d(guide = "none") +
  labs(title = "Random Forest: Feature Importance",
       x = "Feature", y = "Mean Decrease Gini") +
  theme_minimal()

ggsave("output/figures/p3_feature_importance.png", p3, width = 8, height = 6, dpi = 300)

# FIGURE 4: Monthly Risk Pattern (Test Data)
p4 <- test_data %>%
  filter(!is.na(AWR), !is.na(dep_local)) %>%
  mutate(month = month(dep_local, label = TRUE)) %>%
  group_by(month) %>%
  summarise(high_risk_pct = mean(AWR, na.rm = TRUE) * 100) %>%
  ggplot(aes(x = month, y = high_risk_pct, group = 1)) +
  geom_line(size = 1.2, color = "#E41A1C") +
  geom_point(size = 3, color = "#E41A1C") +
  labs(title = "Seasonal Pattern of High Risk Weather Events (Test Data)",
       x = "Month", y = "High Risk (%)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave("output/figures/p4_monthly_risk.png", p4, width = 10, height = 6, dpi = 300)

# FIGURE 5: Wind Speed Impact (Test Data)
wind_test <- test_data %>%
  filter(!is.na(sknt), !is.na(propagated_delay), sknt <= 40) %>%
  mutate(wind_cat = cut(sknt, breaks = c(0, 10, 15, 20, 25, 100),
                        labels = c("0-10", "11-15", "16-20", "21-25", "25+"))) %>%
  group_by(wind_cat) %>%
  summarise(avg_delay = mean(propagated_delay, na.rm = TRUE))

p5 <- ggplot(wind_test, aes(x = wind_cat, y = avg_delay, fill = wind_cat)) +
  geom_col(width = 0.7) +
  labs(title = "Wind Speed Impact on Propagated Delay (Test Data)",
       x = "Wind Speed (knots)", y = "Average Delay (minutes)") +
  theme_minimal() + theme(legend.position = "none")

ggsave("output/figures/p5_wind_delay.png", p5, width = 8, height = 6, dpi = 300)

cat("\n✅ All visualizations saved to output/figures/\n")

print(p1)
print(p2)
print(p3)
print(p4)
print(p5)

# STEP 6: SUMMARY REPORT
# Summary statistics from TEST DATA (honest representation)
test_summary <- test_data %>%
  summarise(
    Total_Flights = n(),
    Avg_Propagated_Delay = mean(propagated_delay, na.rm = TRUE),
    High_Risk_Pct = mean(AWR, na.rm = TRUE) * 100,
    Avg_Visibility = mean(vsby, na.rm = TRUE),
    Avg_Wind_Speed = mean(sknt, na.rm = TRUE)
  )

cat("\n=== TEST DATA SUMMARY (Unseen Data) ===\n")
cat("Total flights in test set:", format(test_summary$Total_Flights, big.mark = ","), "\n")
cat("Average propagated delay:", round(test_summary$Avg_Propagated_Delay, 1), "minutes\n")
cat("High risk percentage:", round(test_summary$High_Risk_Pct, 1), "%\n")
cat("Average visibility:", round(test_summary$Avg_Visibility, 1), "miles\n")
cat("Average wind speed:", round(test_summary$Avg_Wind_Speed, 1), "knots\n")

cat("\n=== MODEL PERFORMANCE SUMMARY ===\n")
cat("LASSO REGRESSION:\n")
cat("  - Test RMSE:", round(test_rmse, 2), "minutes\n")
cat("  - Test R-squared:", round(test_r2, 4), "\n")
cat("  - Interpretation: Weather explains", round(test_r2 * 100, 2), "% of delay variance\n\n")

cat("RANDOM FOREST CLASSIFIER:\n")
cat("  - Test Accuracy:", round(test_accuracy * 100, 2), "%\n")
cat("  - F1 Score:", round(f1, 4), "\n")
cat("  - Most important feature:", importance_df$feature[1], "\n")
# Save test summary as CSV
write_csv(test_summary, "output/test_summary.csv")
cat("✅ Test summary saved to output/test_summary.csv\n")

