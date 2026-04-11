function masterData = loadMasterData()
    % Load all .csv files in directory.
    files = dir('*.csv');
    
    % Pre-allocate cell for data. +1 because wages and hours are in one file
    % but we want to split them into two timetables.
    allData = cell(length(files)+1, 1);
    for i = 1:length(files)
        try
            % Handle data based on the file name.
            % !!!Correct file naming is critical!!!
            [~, baseName, ~] = fileparts(files(i).name);
            switch baseName
                case 'interest_rate'
                    % Import the raw interest rate data, accounting for the
                    % semicolon delimiter and preserving the variable names.
                    irData = readtable(files(i).name, ...
                        detectImportOptions(files(i).name, 'Delimiter', ';', ...
                        'VariableNamingRule','preserve'));
                    
                    % Convert to a timetable, specifying date format.
                    irTT = timetable(datetime(irData.TIME_PERIOD, 'InputFormat', 'yyyy-MM'), ...
                        irData.OBS_VALUE, 'VariableNames', {baseName});
                    
                    % Convert to quarterly data for consistency, using the
                    % 3-month mean.
                    allData{i} = retime(irTT, 'quarterly', 'mean');
                case 'wages_hours'
                    % Import the raw wages and hours data, accounting for the 
                    % semicolon delimiter, ignoring the first line and
                    % preserving the variable names
                    whData = readtable(files(i).name, ...
                        detectImportOptions(files(i).name, 'NumHeaderLines', 1, ...
                        'Delimiter', ';', 'VariableNamingRule','preserve'));
                    
                    % Filter to aggregate output
                    rowIdx = contains(whData.industry, 'Total industry');
                    if ~any(rowIdx), rowIdx = 1; end % Fallback
                    
                    % Separate variables using header text
                    varNames = whData.Properties.VariableNames;
                    wageCols = contains(varNames, 'Compensation');
                    hourCols = contains(varNames, 'Total hours');
                    
                    % Parse 'YYYYK#' into MATLAB datetime (first day of the respective quarter)
                    rawTimes = cellfun(@(x) extractBefore(x, ' '), varNames(wageCols), 'UniformOutput', false);
                    years = str2double(cellfun(@(x) extractBefore(x, 'K'), rawTimes, 'UniformOutput', false));
                    qtrs  = str2double(cellfun(@(x) extractAfter(x, 'K'), rawTimes, 'UniformOutput', false));
                    dates = datetime(years, (qtrs - 1) * 3 + 1, 1)';
                    
                    % Extract numeric series and transpose to column vectors
                    wages = table2array(whData(rowIdx, wageCols))';
                    hours = table2array(whData(rowIdx, hourCols))';
                    
                    % Create two distinct timetables (using pre-allocated extra cell)
                    allData{i} = timetable(dates, wages, 'VariableNames', {'wages'});
                    allData{end} = timetable(dates, hours, 'VariableNames', {'hours'});
                otherwise
                    % All other data is in this easy format.
                    data = readtimetable(files(i).name);
    
                    % Set dependent variable column name to filename.
                    data = renamevars(data, data.Properties.VariableNames{1}, baseName);
                    allData{i} = data;
            end
        catch exception
            fprintf(2, 'Failed processing file: %s\n', files(i).name);
            disp(exception.getReport('basic'));
        end
    end
    masterData = synchronize(allData{:});
end