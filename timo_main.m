clearvars; close all; clc;

%% 1. Import data
masterData = loadMasterData();

%% 2. Deflate wages (real wages)
masterData.wages = (masterData.wages ./ masterData.cpi) * masterData.cpi(1);
masterData = renamevars(masterData, 'wages', 'real_wages');

%% 3. Keep only common sample (CRUCIAL)
masterData = rmmissing(masterData);

%% 4. Log variables (ONLY real quantities)
varsToLog = {'gdp','consumption','investment','hours','real_wages','cpi'};

masterData{:, varsToLog} = log(masterData{:, varsToLog});
masterData = renamevars(masterData, varsToLog, strcat(varsToLog, '_log'));

%% 5. Construct TFP proxy (log form)
masterData.tfp_proxy_log = masterData.gdp_log - masterData.hours_log;

%% 6. Inflation (YoY, NOT HP filtered)
masterData.inflation_yoy = [NaN(4,1); ...
    100 * (masterData.cpi_log(5:end) - masterData.cpi_log(1:end-4))];

%% 7. Drop NaNs after constructing variables
masterData = rmmissing(masterData);

%% 8. Select variables for HP filter (ONLY real quantities)
vars_hp = {'gdp_log','consumption_log','investment_log', ...
           'hours_log','real_wages_log','tfp_proxy_log'};

data_hp = masterData(:, vars_hp);

%% 9. Apply HP filter (lambda = 1600 for quarterly)
[data_trend, data_cycle] = hpfilter(data_hp, 'Smoothing', 1600);

%% 10. Rename variables (clean naming)
data_cycle.Properties.VariableNames = strcat(vars_hp, '_cycle');

%% 11. Add NON-filtered variables
data_cycle.inflation_yoy_cycle = masterData.inflation_yoy;
data_cycle.interest_rate_cycle = masterData.interest_rate;

%% 12. FINAL DATASET (ready for moments)
data_combined = [masterData, data_trend, data_cycle];

%% Calculate interest rate according to Taylor Rule
i = @(data) 0.02 + data.inflation_yoy + 0.5*(data.inflation_yoy - data.inflation_yoy_trend + data.gdp_log_cycle);

% data_combined.nominal_rate_qtly = i(data_combined.inflation_qtly, data_combined.inflation_qtly_trend);
data_combined.nominal_rate_yoy = i(data_combined);

%% Calculate omega_std parameters for calibration
ar1_model = fitlm(data_combined.tfp_proxy_log(1:end-1), data_combined.tfp_proxy_log(2:end), 'Intercept', false);

rho = ar1_model.Coefficients.Estimate
rho_se = ar1_model.Coefficients.SE
tfp_shock_std = ar1_model.RMSE

omega = data_combined.interest_rate - data_combined.nominal_rate_yoy;
std_pct_omega = std(omega)/100; % Divide by 100 because it's a rate

% View the first few rows
head(data_combined)

% Get the base variables (no trend or cycle) and count them
baseVars = masterData.Properties.VariableNames';
numVars = length(baseVars);

% Create an 'output' folder with 'figures' and 'tables' subfolders if they don't exist
if ~exist('output/figures', 'dir'); mkdir('output/figures'); end
if ~exist('output/tables', 'dir'); mkdir('output/tables'); end

% % Loop through each base variable
% for i = 1:numVars
%     % Extract current variable name as a string
%     varName = string(baseVars{i}); 
% 
%     % No need to plot the inflation values
%     if contains(varName, 'inflation')
%         continue;
%     end
% 
%     % Construct the column names for trend and cycle
%     trendVar = varName + "_trend";
%     cycleVar = varName + "_cycle";
% 
%     % Create a new figure with a 2-row, 1-column layout
%     figure('Name', varName);
%     tiledlayout(2, 1, 'TileSpacing', 'compact'); 
% 
%     % Top plot: data and trend
%     nexttile;
%     if strcmp(varName,'interest_rate')
%         plot(data_combined, [trendVar, varName, 'nominal_rate_yoy'], 'LineWidth', 1.5);
%         legend('Trend', 'Original Data', 'Implied Taylor Rate (year-on-year)', 'Location', 'best');
%     else
%         plot(data_combined, [trendVar, varName], 'LineWidth', 1.5);
%     end
%     title(varName + " - data & trend", 'Interpreter', 'none');
% 
%     % Bottom plot: cycle
%     nexttile;
%     plot(data_combined, cycleVar, 'LineWidth', 1.5);
%     title(varName + " - cycle", 'Interpreter', 'none');
%     yline(0, 'k--'); % Add a dashed zero line
% 
%     saveas(gcf, 'output/figures/' + varName + '.png');
% end

varNames = data_cycle.Properties.VariableNames;

% Extract cycle data into a T x N matrix 
X = data_cycle{:, varNames}; 

% Calculate the unscaled standard deviations for all variables
std_devs = std(X, 'omitnan');

% Specify the variables to exclude from scaling (already in rates)
exclude_vars = {'inflation_yoy_cycle', 'interest_rate_cycle'};

% Create a logical mask for the variables that need scaling
scale_mask = ~ismember(varNames, exclude_vars);

% 4. Multiply only the log-level variables by 100
std_devs(scale_mask) = std_devs(scale_mask) * 100;

%% 1. Standard Deveiation %
std_table = array2table(std_devs, 'VariableNames', varNames, 'RowNames', {'Std_Pct'});
disp(std_table);
writetable(std_table, 'output/tables/std_table.csv');

%% 2. Cross-Correlation Matrix
% Calculate contemporaneous correlation between all combinations
corr_matrix = corr(X, 'Rows', 'pairwise');

% Set the upper triangular part to NaN
corr_matrix_lower = tril(corr_matrix);
corr_matrix_lower(triu(true(size(corr_matrix_lower)), 1)) = NaN;

corr_table = array2table(corr_matrix_lower, 'VariableNames', varNames, 'RowNames', varNames);
disp(corr_table);
writetable(corr_table, 'output/tables/corr_table.csv');

%% 3. Relative Volatility Matrix
% Create a matrix where element (i,j) is Std(i) / Std(j)
% This provides the comparison between every combination of variables
rel_vol_matrix = std_devs' ./ std_devs;

rel_vol_table = array2table(rel_vol_matrix, 'VariableNames', varNames, 'RowNames', varNames);
disp(rel_vol_table);
writetable(rel_vol_table, 'output/tables/rel_vol_table.csv');