clearvars; close all; clc;

% Import data
masterData = loadMasterData();

% Deflate wages to real terms using the first CPI value as the base
masterData.wages = (masterData.wages ./ masterData.cpi) * masterData.cpi(1);
masterData = renamevars(masterData, 'wages', 'real_wages');

% Find all variables except interest rate
varsToLog = setdiff(masterData.Properties.VariableNames, 'interest_rate');

% Log those variables 
masterData{:, varsToLog} = log(masterData{:, varsToLog});
masterData = renamevars(masterData, varsToLog, strcat(varsToLog, '_log'));

% Calculate log(tfp_proxy)
masterData.tfp_proxy_log = masterData.gdp_log - masterData.hours_log;

% Calculate year-on-year inflation
masterData.inflation_yoy  = [NaN(4, 1); 100 * (masterData.cpi_log(5:end) - masterData.cpi_log(1:end-4))];

% Delete rows with null values. Done here so that lagged cpi data was
% available to calculate inflation beforehand
masterData = rmmissing(masterData);

[data_trend, data_cycle] = hpfilter(masterData, 'Smoothing', 1600);

% Rename the variables so they don't clash when combined
data_trend.Properties.VariableNames = strcat(masterData.Properties.VariableNames, '_trend');
data_cycle.Properties.VariableNames = strcat(masterData.Properties.VariableNames, '_cycle');

% Concatenate them into one timetable
data_combined = [masterData, data_trend, data_cycle];

%% Calculate interest rate according to Taylor Rule
i = @(data) 0.02 + data.inflation_yoy + 0.5*(data.inflation_yoy - data.inflation_yoy_trend + data.gdp_log_cycle);

data_combined.nominal_rate_yoy = i(data_combined);

%% Calculate parameters for NKM calibration
tfp_L0 = data_combined.tfp_proxy_log(2:end); % tfp_t
tfp_L1 = data_combined.tfp_proxy_log(1:end-1); % tfp_{t-1} (first lag)
ar1_model = fitlm(tfp_L1, tfp_L0); % Regress tfp on its first lag

rho = ar1_model.Coefficients.Estimate(2); % Get the slope
rho_se = ar1_model.Coefficients.SE(2); % Slope standard error

omega = data_combined.interest_rate - data_combined.nominal_rate_yoy; % Interest rate shock
std_omega = std(omega);

% Create an 'output' folder with 'figures' and 'tables' subfolders if they don't exist
if ~exist('output/figures', 'dir'); mkdir('output/figures'); end
if ~exist('output/tables', 'dir'); mkdir('output/tables'); end

writetable(table(rho, rho_se, std_omega), 'output/tables/nkm_params_table.csv');

% View the first few rows
head(data_combined)

% Get the base variables (no trend or cycle) and count them
baseVars = masterData.Properties.VariableNames';

% Loop through each base variable
for i = 1:length(baseVars)
    % Extract current variable name as a string
    varName = string(baseVars{i});

    if contains(varName, 'inflation')
        continue;
    end

    cleanName = strrep(varName, '_log', '');
    cleanName = strrep(cleanName, '_', ' ');
    cleanName = regexprep(cleanName, '(\<\w)', '${upper($1)}');
    cleanName = regexprep(cleanName, 'gdp', 'GDP', 'ignorecase');
    cleanName = regexprep(cleanName, 'cpi', 'CPI', 'ignorecase');
    cleanName = regexprep(cleanName, 'tfp', 'TFP', 'ignorecase');

    % Construct the column names for trend and cycle
    trendVar = varName + "_trend";
    cycleVar = varName + "_cycle";

    % Create a new figure with a 2-row, 1-column layout
    figure('Name', varName);
    tiledlayout(2, 1, 'TileSpacing', 'compact'); 

    % Top plot: data and trend
    nexttile;
    if strcmp(varName,'interest_rate')
        plot(data_combined, [trendVar, varName, 'nominal_rate_yoy'], 'LineWidth', 1.5);
        legend('Trend', 'Realised', 'Predicted (Taylor Rule)', 'Location', 'best');
        title(cleanName + " - Trend, Data & Taylor Rule Prediction");
        yTop = "Percent (%)";
        yBottom = "Deviation (pp)";
    else
        plot(data_combined, [trendVar, varName], 'LineWidth', 1.5);
        title(cleanName + " - Trend & Data");
        yTop = "Log Level";
        yBottom = "Fractional Deviation";
    end

    ylabel(yTop);
    xlabel("");

    % Bottom plot: cycle
    nexttile;
    plot(data_combined, cycleVar, 'LineWidth', 1.5);
    title(cleanName + " - Cycle");
    yline(0, 'k--'); % Add a dashed zero line
    ylabel(yBottom);
    xlabel("Date")

    saveas(gcf, 'output/figures/' + varName + '.png');
end

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