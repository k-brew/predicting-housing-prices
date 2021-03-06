---
   title: "Predicting Housing Prices"
author: "Kyle Brewster"
date: '2022-05-30'
output: html_document
---
   
   # 01 - Briefly explain why being able to predict whether my model underpredicted a house's price means that your model "beats" my model.
   
   If I am able to predict if the model is under-predicting, then that means I would grouped the data in very similar groups as the model that predicted `undervalued`. Along the way, I will also gather an idea of how confident the models' prediction of `undervalued` is. With this information, by the end of my modeling I will have (in theory) predicted whether an observation is `undervalued` by its defined characteristics, but also would have an idea of "how much" and "in which direction" the difference between the actual and suggested validation of an observation (i.e. 3>1)

# 02 - Use two different models to predict undervalued

```{r loading_data}
housing = read.csv("final-data.csv")
```

Since we are attempting to predict a T/F value, we will be using methods of classification.

To get an overview of the data
```{r skim}
# For handy viewing from environment
skimr::skim(housing) -> skim_df
skimr::skim(housing)
```

Looking at the description of the data, we can see that a `NA` value is assigned to observations that do not possess the amenity described by the variable. Thinking about `bsmt_qual` for example, a house without a basement would have a `NA` value for the variable and would not necessarily suggest a missing/incomplete response (although the `complete_rate` would need to be considered at the same time).

Only two numeric variables are missing values while several while several of the character variables are also missing data. We can formally call all variables with missing values with the following commands:

```{r}
library(dplyr)
skim_df %>% filter(skim_type=="numeric" & n_missing>0)  -> num_na 
skim_df %>% filter(skim_type=="character" & n_missing>0)-> char_na
num_na
char_na
```

Even though the `complete_rate` for a few of these values is small enough to perhaps consider removing from the data in some contexts, we must remember that such is to be expected since not all houses having a pool, fencing, a fireplace, etc. We can also consider similar logic for the numeric variables. Not all houses have garages, streets connected to the property, or masonry veneer areas that can be quantified since they do not exist. Therefore we will assume that a missing value for the numeric variables with missing values indicates the observation does not possess the given feature and will replace those values with `zero`

## Cleaning

After looking at the data, there are a few things we should change before modeling:

- Convert variables from character class to factors
- Replace `NA` values
- Add log transformation variables
- Normalizing data (with min/max scaling)

```{r fresh_start_chunk}
# Including again to have single chunk to run for cleaning/wrangling
housing = read.csv("final-data.csv")
# For comparing original and modified data frames
clean_house <- housing
# Loading packages

pacman::p_load(  # package manager
   dplyr,        # for wrangling/cleaning/syntax
   magrittr,     # le pipe
   tidyverse,    # modeling
   caret         # also modeling
)

# Converting character variables to factors
clean_house[sapply(clean_house, is.character)] <- lapply(
   clean_house[sapply(clean_house, is.character)], as.factor)

# Removing NA's for numeric and factor variables
clean_house %<>% mutate(
   across(where(is.numeric),~replace_na(.,0)),
   across(where(is.factor),~fct_explicit_na(.,'none')))

# Define min-max normalization function
min_max_norm <- function(x) {
   (x - min(x)) / (max(x) - min(x))}

# Applying function to all non-factor variables
clean_house %<>% mutate_if(is.integer, min_max_norm) %>%
   mutate(id = seq(nrow(.)),  
          undervalued = as.factor(undervalued))

# Splitting into training and testing sets by 80-20 splitting
set.seed(123)
train = clean_house %>% mutate(undervalued = as.factor(undervalued)) %>%
   sample_frac(0.8) 
test  = anti_join(clean_house, train, by = 'id')

# Dropping ID variable
train %<>% select(-c("id"))
test %<>% select(-c("id"))
```

If desired, can also run the code below to get overview of data to check for other issues before moving forward (should have all numeric and factor variable classes at this point)
```{r eval=FALSE}
str(train)
```


## Modeling

### Binary Logistic Regression

Let's  take a look at how our predictions would perform if only using regression methods are used to make predictions, first using all variables in the data.

```{r}
# GLM model using all variables
glm_mod_all = glm(
   undervalued ~.,
   data = train,
   family = "binomial")
summary(glm_mod_all)
```

Now let's narrow down the number of variables used to include only those considered above to be statistically significant.

```{r}
# Same modeling but only with significant variables
glm_mod_sig = glm(
   undervalued ~ 
      ms_sub_class+lot_area+land_contour+lot_config+
      bldg_type+overall_qual+mas_vnr_area+bsmt_fin_type1+
      bsmt_fin_sf1+bsmt_fin_sf2+bsmt_unf_sf+bsmt_full_bath+
      kitchen_qual,
   data = train,
   family = "binomial"
)
summary(glm_mod_sig)
```

Now let's adjust the GLM model once more to remove some extra noise

```{r message=FALSE, warning=FALSE}
glm_mod_fin = glm(
   undervalued ~ 
     overall_qual + bsmt_fin_sf1 + kitchen_qual + bldg_type,
   family = "binomial",
   data = train)

cbind(
   coef(glm_mod_fin),
   odds_ratio=exp(coef(glm_mod_fin)),
   exp(confint(glm_mod_fin))
)
```
To determine what we should have for the cutoff value, we can create multiple classification tables and look at the differences between accuracy, sensitivity, and specificity and then choose a value that minimizes the marginal differences between these measures. We want to minimize the error that the final version of this model has when applied to new data, lest we sacrifice generalization of the model for higher performance in training (i.e. overfitting and the bias-variance tradeoff).


```{r}
# Cutoff Value set to 0.3
train$predprob <- round(fitted(glm_mod_fin),2)
class.table = table(Actual = train$undervalued,
                    Predicted = train$predprob>0.3)
class.table

# Cutoff Value set to 0.5
train$predprob <- round(fitted(glm_mod_fin),2)
class.table = table(Actual = train$undervalued,
                    Predicted = train$predprob>0.5)
class.table

# Cutoff Value set to 0.7
train$predprob <- round(fitted(glm_mod_fin),2)
class.table = table(Actual = train$undervalued,
                    Predicted = train$predprob>0.7)
class.table
```
We can see a significant variation in model predictions by adjusting these values. Let's now take a look at some metrics to judge the strength of our model.

*__Accuracy__* can be calculated by taking the sum of the correct predictions divided by the total number of observations (i.e. sum(top-left+bottom-right)/n.total.obs)
```{r}
m1_0.3 = (82+513)/1168
m2_0.5 = (437+276)/1168
m3_0.7 = (610+20)/1168
metric = "accuracy"
accuracy_metrics = cbind.data.frame(metric, m1_0.3, m2_0.5, m3_0.7)
```

*__Sensitivity__* can be calculated by the number of correct positive assessments of `undervalued` observations by the total number of values predicted to be `undervalued` (i.e. bottom-right/sum(across-bottom))

```{r}
513/(36+513) -> m1_0.3
276/(273+276) -> m2_0.5
20/(529+20) -> m3_0.7
metric = "senstivity"
accuracy_metrics2 = cbind.data.frame(metric, m1_0.3, m2_0.5, m3_0.7)
```

*__Specificity__* can be calculated by dividing the accurately predicted observations that were *not* `undervalued`  by the total number of values predicted not to be `undervalued` (i.e. top-left/sum(across-top))

```{r}
82/(537+82) -> m1_0.3
437/619 -> m2_0.5
610/619 -> m3_0.7
metric = "specificity"
accuracy_metrics3 = cbind.data.frame(metric, m1_0.3, m2_0.5, m3_0.7)

# Overview of measurement metrics
rbind(accuracy_metrics, accuracy_metrics2, accuracy_metrics3)
```

It is important to consider the cutoff value that we use in the modeling because we face a tradeoff between bias and variance when applying the models to the real world or on a testing set. We can see that resulting variation in the table presenting an overview of the metrics above and note a few things:
   
   - The cutoff value of 0.5 has the greatest accuracy of our selected models
- Sensitivity increases significantly for smaller cutoff values
- Specificity increases with higher cutoff values

To save some extra scripting time and potential risk of typos, we can also save this [as a template](https://www.lexjansen.com/nesug/nesug10/hl/hl07.pdf) we can use for future calculations, where:
   
   - `TN` = Number of true negative assessments
- `TP` = Number of true positive assessments
- `FP` = Number of false positives
- `FN` = Number of false negatives
- `(TP + FP)` = Total observations with positive assessments
- `(FN + TN)` = Total observations wit negative assessments
- `N = (TP + TN + FP + FN)` = Total number of observations

```{r eval=FALSE}
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
```

We could also run the create a model similar to the coding shown below if we wanted to methodologically determine the best variables to select including in our regression models.

```{r eval=FALSE}
# GLM modeling using step-wise selection of variables
glm.step <- MASS::stepAIC(glm_mod_all, trace = FALSE,
                          data = train, steps = 1000) # 1000 by default
glm.step$annova
```

Since we know from the results of the preceding chunks, however, we can see that  regression might not be the best attempt to make predictions considering the tradeoffs we would have to make and can opt to save the computational time/effort for other models we expect to perform better.

Even though we know that regression might not be the best type of model to use in this context, we can still gain some insight from our calculations. For example, when determining which variables we were going to include, several of the factor variables had individual levels that were considered statistically significant but not the variable as a whole. Perhaps this indicates that there are specific features that carry more weight in home valuation than other feature. If so, then perhaps decision trees can help model out data with greater accuracy

### Decision Trees and Random Forest

Let's see what happens if we algorithmically build a model, this time using decision trees to predict our outcome. 
algorithmically

```{r message=FALSE, warning=FALSE, results='hide'}
# Refreshing our training and testing sets
set.seed(123)
train = clean_house %>% mutate(undervalued = as.factor(undervalued)) %>%
   sample_frac(0.8) 
test  = anti_join(clean_house, train, by = 'id')

# Dropping ID variable
train %<>% select(-c("id"))
test %<>% select(-c("id"))
```


```{r message=FALSE, warning=FALSE}
pacman::p_load(tidymodels,
               rpart.plot)

# Chunk takes ~5 minutes to execute

default_cv = train %>% vfold_cv(v =5)
default_tree = decision_tree(mode ="classification",
                             cost_complexity = tune(),
                             tree_depth = tune()) %>%
               set_engine("rpart")
               
# Defining recipe
default_recipe = recipe(undervalued ~., data = train)
# Defining workflow
default_flow = workflow() %>%
  add_model(default_tree) %>%
  add_recipe(default_recipe)
# Tuning
default_cv_fit = default_flow %>%
  tune_grid(
    default_cv,
    grid = expand_grid(
      cost_complexity = seq(0, 0.15, by = 0.01),
      tree_depth = c(1,2,5,10),
    ),
    metrics = metric_set(accuracy, roc_auc))
# Fitting and selecting best model
best_flow = default_flow %>%
  finalize_workflow(select_best(default_cv_fit, metric = "accuracy")) %>%
  fit(data = train)
best_tree = best_flow %>% extract_fit_parsnip()
best_tree$fit %>% rpart.plot::rpart.plot(roundint=F)
# Summary statistics and plotting
printcp(best_tree$fit)
best_tree$fit$variable.importance

# Predicting values
as.data.frame(predict(best_tree, new_data=train)) -> df1
```

Looking at our first decision tree, there are several things worth considering:

- The `neighborhood` variables was ranked as the greatest variable of importance.
   - This might be good to know if we use this model on future data on housing from the same selection of neighborhoods, but wouldn't perform well on data from other areas where the distinction between neighborhood is less explanatory
- The significant variables are different than those suggested and used in our previous model

For the next trees, we will omit the `neighborhood` variable in an effort to produce a model that is more generalizable. While we could likely develop a way to preserve the information that this variable contributes to the data (like by creating an additional variable(s) with metrics pertaining to the given neighborhood such as crime-rate, median income, average education, neighborhood demographics, etc.), it could provide insight if create a model that cannot look to the neighborhood of an observation.

```{r}
set.seed(123)
train_hold = clean_house %>%
   select(-c("neighborhood")) %>%
   mutate(undervalued = as.factor(undervalued)) %>%
   sample_frac(0.8) 
test_hold = anti_join(clean_house, train_hold, by = 'id')

train_hold %<>% select(-c("id"))
test_hold %<>% select(-c("id"))
```

And now to plant another tree
```{r message=FALSE, warning=FALSE}
default_recipe = recipe(undervalued ~., data = train_hold)
default_flow = workflow() %>%
   add_model(default_tree) %>%
   add_recipe(default_recipe)
default_cv_fit = default_flow %>%
   tune_grid(
      default_cv,
      grid = expand_grid(
         cost_complexity = seq(0, 0.15, by = 0.01),
         tree_depth = c(1,2,5,10),),
      metrics = metric_set(accuracy, roc_auc))
best_flow = default_flow %>%
   finalize_workflow(select_best(default_cv_fit, metric = "accuracy")) %>%
   fit(data = train_hold)
best_tree2 = best_flow %>% extract_fit_parsnip()
best_tree2$fit %>% rpart.plot::rpart.plot(roundint=F)
# Summary and plotting
printcp(best_tree2$fit)
best_tree2$fit$variable.importance
# Predicting values
as.data.frame(predict(best_tree2, new_data=train_hold)) -> df2
```

By removing the `neighborhood` variable, we can note several differences in the resulting model construction. The variable `gr_liv_area` (above-ground living area in squared feet) was used instead of `neighborhood`. We can also see removing the one-column also changed the listed variables of importance that were generated. For example, in the second tree we see `functional` and `sale_type` that do not appear in the first tree and see variables like `year_built` and `ms_zoning` that appear in the first tree but not the second. 

From this seemingly small change, we can gather some additional insight into the story that is hiding in our data. Obviously the `neighboorhood` variable must hold some importance since its commission changes the resulting tree, but I believe there is additional information that the `neighboorhood` could carry.

While the name of a neighborhood is nothing more than a logical arrangement of letters and spaces, geographic boundaries could imply several characteristics that would apply to a home being sold within those boundaries. Even if the floor-plan and characteristics of two given homes are 100% similar apart from the neighborhood, there could still be differences that affect sale prices

- *Crime rates*
   - A quick online search could determine reports of crimes for a given geographic area, knowledge of which could affect the price one is willing to pay for a home if house is located in crime-heavy area
- *Public education jurisdiction*
   - Results in distinct differences determined by specific boundaries. Even the side of the street a home is on could determine if their children attend an A-rated school versus a D-rated school
- *Community*
   - Not as black-and-white as education or crime, but could potentially provide some explanatory effect
- Examples: Willingness to pay more than would otherwise in order to live close to family, friends, cultural significance (e.g. Spanish-speaking), class-status/"prestige", etc
- Aforementioned examples could potentially result in consumer willingness to pay a price either higher or lower than they would otherwise accept
- *Presences of Homeowners Association*
   - Because who the hell wants to be told what color they are allowed to paint their house, or if they are able to have a garden on their property that is visible from the street, or how long their grass is "allowed" to grow? This is America!       - (unless we are looking at data from another country)

Before moving on to another model, let's first consider the predictions from the previous trees.
```{r df1}
df1 %<>% rename(pred_tree = names(.)[1])
# Creating confusion matrix
table(Actual = train$undervalued,
      Predicted = df1$pred_tree)

TN = 390
TP = 389
FP = 229
FN = 160
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
metrics_tree1 = rbind(Sensitivity,Specificity,Accuracy)
metrics_tree1 
```

```{r df2}
df2 %<>% rename(pred_tree = names(.)[1])
table(Actual = train_hold$undervalued,
      Predicted = df2$pred_tree)
TN = 446
TP = 333
FP = 173
FN = 216
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
metrics_tree2 = rbind(Sensitivity,Specificity,Accuracy)
metrics_tree2
```

Looks like we were able to produce more stable models with decent accuracy (on the training set at least, we will have to see how it performs on testing). If the single decision trees produced these different results, let's see how an ensemble of trees (i.e. random forest) will perform

### Random Forest

I saw the values of the training/testing sets when `unique(test$neighborhood)` were both the same, so I figured that it would be good practice to keep the `neighborhood` variable for the random forest modeling. If there was an uneven distribution of neighborhoods in both sets, then we would need to consider a different resampling method or removing the variable.

```{r message=FALSE, warning=FALSE}
# Refreshing our training and testing sets
set.seed(123)
train = clean_house %>% mutate(undervalued = as.factor(undervalued)) %>%
   sample_frac(0.8) 
test  = anti_join(clean_house, train, by = 'id')
train %<>% select(-c("id"))
test %<>% select(-c("id"))

library(randomForest)
mod_rf = randomForest(formula = undervalued ~ .,
                      data = train,
                      importance = T,
                      ntree = 100)
importance(mod_rf)
train$pred_rf = predict(mod_rf, type="response", newdata = train)
# Creating confusion matrix
table(Actual = train$undervalued,
      Predicted = train$pred_rf)
```
Looks like the neighborhood ended up being a significant variable according to the random forest model. Good thing we kept it!  
   
   ### Testing 
   
   First with the most-recently constructed random forest model
```{r}
test$pred_rf = predict(mod_rf, type="response", newdata = test)
table(Actual = test$undervalued, 
      Predicted = test$pred_rf)
```

```{r}
TN = 93
TP = 89
FP = 42
FN = 68
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
metrics_rf = rbind(Sensitivity,Specificity,Accuracy)
metrics_rf
```
Not quite the same performance as with training, but we can compare these results to the test predictions of the other models as well.

GLM model with cutoff value of 0.5
```{r}
# refreshing sets
set.seed(123)
train = clean_house %>% mutate(undervalued = as.factor(undervalued)) %>%
   sample_frac(0.8) 
test  = anti_join(clean_house, train, by = 'id')
train %<>% select(-c("id"))
test %<>% select(-c("id"))

glm_mod_fin = glm(
   undervalued ~ 
      overall_qual + bsmt_fin_sf1 + kitchen_qual + bldg_type,
   family = "binomial",
   data = test)

# Cutoff Value set to 0.5
test$predprob <- round(fitted(glm_mod_fin),2)
table(Actual = test$undervalued,
      Predicted = test$predprob>0.5)
```

```{r}
TN = 60
TP = 122
FP = 75
FN = 35
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
metrics_glm = rbind(Sensitivity,Specificity,Accuracy)
metrics_glm 
```


Single tree (with Neighborhood)
```{r}
# Predicting values
as.data.frame(predict(best_tree, new_data=test)) -> df1

df1 %<>% rename(pred_tree = names(.)[1])
# Creating confusion matrix
table(Actual = test$undervalued,
      Predicted = df1$pred_tree)
```

```{r}
TN = 84
TP = 94
FP = 51
FN = 63
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
metrics_tree1 = rbind(Sensitivity,Specificity,Accuracy)
metrics_tree1 
```


Single tree (without Neighborhood)
```{r}
# Predicting values
as.data.frame(predict(best_tree2, new_data=test_hold)) -> df2
df2 %<>% rename(pred_tree = names(.)[1])
# Creating confusion matrix
table(Actual = test_hold$undervalued,
      Predicted = df2$pred_tree)
```

```{r}
TN = 97
TP = 82
FP = 38
FN = 75
Sensitivity = TP/(TP + FN)
# (Number of true positive assessment)/(Number of
#  all positive assessment)
Specificity = TN/(TN + FP)
# (Number of true negative assessment)/(Number of 
#  all negative assessment)
Accuracy   = (TN + TP)/(TN+TP+FN+FP) 
# (Number of correct assessments)/Number of
#  all assessments)
metrics_tree2 = rbind(Sensitivity,Specificity,Accuracy)
metrics_tree2 
```

# 03 - How did you do? Compare your models' levels of accuracy to the null classifier?

```{r}
as.data.frame(cbind(metrics_glm,
                    metrics_tree1,metrics_tree2,metrics_rf)) -> comp_df
comp_df %>% rename("GLM" = 1,
                   "Tree #1" = 2,
                   "Tree #3" = 3,
                   "Random Forest"=4)
```

As mentioned above, the random forest model performed the best on the training data, but not as well as we would have hoped for on the testing data. Something we could consider doing would be to create bins when attempting binary logistic regression. Doing so might reveal a linear trend that helps reduce the outlier effect. It would also be interesting to see the results of some different models that automatically choose the variables to be included. We can already see the variation that arises with slight changes to the model or data, so perhaps there is a model we did not try is the one used to construct the `undervaluded` variable

# 04 - Are all errors equal in this setting? Briefly explain your answer.

All errors are NOT equal. For example, consider two different observation that have a `TRUE` value of `undervalued` variable. Even though both of these observations are considered undervalued, suppose that observation 1 is undervalued by 500% whereas observation 2 is only undervalued by 1%. If our model was to predict a `TRUE` value for the `undervalued` variable for observation 1 and 2, even thought the marginal cost (in terms of additional model uncertainty from errors) would be relatively similar (or the exact same), an incorrect classification of observation 1 would have a greater impact of the *true* performance strength of out model.

# 05 - Why would it be a bad idea to use a linear model here (for example plain OLS or lasso)?

Since the outcome we are predicting is a binary categorical variable rather than a variable with a continuous value. When there are potential outliers, regression models like these can also be more susceptible to the influence of outliers. Even if our data had optimal characteristics for using a regression model, there still might not be a linear trend that the model is able to properly fit. Decision trees, on the other hand, are much better at fitting non-linear trends that exist in the model.

In addition, another assumption in linear models is that the variables included in the model are independent. While we could attempt to navigate around this by using interaction variables in the model, but it would be more worth our while to utilize a different method better suited for classification problems.


```{r}
test -> testingtest
as.data.frame(cbind(metrics_glm,
                    metrics_tree1,metrics_tree2,metrics_rf)) -> comp_df
comp_df %>% rename("GLM" = 1,
                   "Tree #1" = 2,
                   "Tree #3" = 3,
                   "Random Forest"=4)
```

