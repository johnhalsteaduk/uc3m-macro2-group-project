clearvars; close all; clc;

% 1. Import Data
masterData = loadMasterData();

% Deflate wages to real terms using the first CPI value as the base
masterData.wages = (masterData.wages ./ masterData.cpi) * masterData.cpi(1);
masterData = renamevars(masterData, 'wages', 'real_wages');

% Find all variables EXCEPT the interest rate
varsToLog = setdiff(masterData.Properties.VariableNames, 'interest_rate');

% Apply the natural log to just those columns 
masterData{:, varsToLog} = log(masterData{:, varsToLog});
masterData = renamevars(masterData, varsToLog, strcat(varsToLog, '_log'));

% Calculate log(tfp_proxy)
masterData.tfp_proxy_log = masterData.gdp_log - masterData.hours_log;

[data_trend, data_cycle] = hpfilter(masterData, 'Smoothing', 1600);

% Rename the variables so they don't clash when combined
data_trend.Properties.VariableNames = strcat(masterData.Properties.VariableNames, '_trend');
data_cycle.Properties.VariableNames = strcat(masterData.Properties.VariableNames, '_cycle');

% Horizontally concatenate them into one large timetable
data_combined = [masterData, data_trend, data_cycle];

% View the first few rows
head(data_combined)

baseVars = masterData.Properties.VariableNames;

% Loop through each base variable
for i = 1:length(baseVars)
    % Extract current variable name as a string
    varName = string(baseVars{i}); 
    
    % Construct the column names for trend and cycle
    trendVar = varName + "_trend";
    cycleVar = varName + "_cycle";
    
    % Create a new figure with a 2-row, 1-column layout
    figure('Name', varName);
    tiledlayout(2, 1, 'TileSpacing', 'compact'); 
    
    % Top Plot: Trend
    nexttile;
    plot(data_combined, [trendVar, varName], 'LineWidth', 1.5);
    title(varName + " - data & trend", 'Interpreter', 'none');
    
    % Bottom Plot: Cycle
    nexttile;
    plot(data_combined, cycleVar, 'LineWidth', 1.5);
    title(varName + " - cycle", 'Interpreter', 'none');
    yline(0, 'k--'); % Adds a dashed zero line, standard for cycle plots
end