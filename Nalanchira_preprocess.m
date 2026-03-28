%% 1. Load Raw Dataset
load('Nalanchira_Master_Dataset.mat'); 

% Convert Table to Matrix for faster processing
raw_data = table2array(ANN_Table);

%% 2. Separate Features from Labels
% Column 1 to 72: Voltage/Current signals (The Inputs)
% Column 73: Fault_Type (Target 1)
% Column 74: Location (Target 2)

X_raw = single(raw_data(:, 1:72)); 
Y_type = categorical(raw_data(:, 73)); 
Y_loc  = categorical(raw_data(:, 74));

%% 3. Data Normalization (Z-Score)
% Electrical signals vary in scale (Volts vs Amps). 
% Normalizing helps the TCN and Booster converge much faster.
[X_scaled, mu, sigma] = zscore(X_raw);

%% 4. Handle Outliers or NaNs (Safety Check)
% Replace any NaN values (from simulation crashes) with 0
X_scaled(isnan(X_scaled)) = 0;

%% 5. Save Preprocessed Data
% We save the Scaling Parameters (mu, sigma) so you can use them 
% for real-time data in Simulink later.
save('Preprocessed_Input.mat', 'X_scaled', 'Y_type', 'Y_loc', 'mu', 'sigma', '-v7.3');

fprintf('Preprocessing Complete!\n');
fprintf('Features: %d columns (Sensors Only)\n', size(X_scaled, 2));
fprintf('Labels: Fault Type and Location separated.\n');