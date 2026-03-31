clc; clear; close all;

%% ================================================
%% STEP 1 — Load Dataset
%% ================================================
load('Nalanchira_Master_Dataset.mat');
raw_data = table2array(ANN_Table);
fprintf('Loaded: %d rows x %d cols\n', size(raw_data));

% Column layout (76 total):
% Col 1      : Run_ID
% Col 2-73   : 72 signal features
% Col 74     : Fault_Active
% Col 75     : Fault_Type
% Col 76     : Location

Run_ID       = raw_data(:, 1);
X_raw        = double(raw_data(:, 2:73));   % 72 features
Fault_Active = raw_data(:, 74);
Fault_Type   = raw_data(:, 75);
Location     = raw_data(:, 76);

fprintf('Unique runs: %d\n', numel(unique(Run_ID)));

%% ================================================
%% STEP 2 — Verify rows per run
%% ================================================
run_ids      = unique(Run_ID);
rows_per_run = arrayfun(@(r) sum(Run_ID == r), run_ids);
fprintf('Rows per run — Min: %d | Max: %d | Mean: %.0f\n', ...
    min(rows_per_run), max(rows_per_run), mean(rows_per_run));

% Drop runs that are too short (likely failed simulations)
valid_runs = run_ids(rows_per_run > 900);
fprintf('Valid runs: %d / %d\n', numel(valid_runs), numel(run_ids));

mask     = ismember(Run_ID, valid_runs);
Run_ID       = Run_ID(mask);
X_raw        = X_raw(mask, :);
Fault_Active = Fault_Active(mask);
Fault_Type   = Fault_Type(mask);
Location     = Location(mask);

%% ================================================
%% STEP 3 — Add Pre-Fault Warning Label
%% ================================================
% PRE_FAULT_ROWS: how many rows BEFORE fault starts to warn
% ds=20, so 1 row = 20 timesteps
% 50 rows = 1000 timesteps before fault → good early warning
PRE_FAULT_ROWS = 50;

Label = zeros(size(Fault_Active), 'single');  % 0 = Normal (default)

run_ids = unique(Run_ID);
for i = 1:numel(run_ids)
    idx = find(Run_ID == run_ids(i));          % row indices for this run
    fa  = Fault_Active(idx);                   % fault active vector
    
    fault_rows = idx(fa == 1);
    
    if isempty(fault_rows)
        fprintf('Run %d: No fault found — skipping\n', run_ids(i));
        continue;
    end
    
    fault_start = fault_rows(1);
    fault_end   = fault_rows(end);
    
    % Label 2: Fault active
    Label(fault_start:fault_end) = 2;
    
    % Label 1: Pre-fault warning window
    pre_start = max(idx(1), fault_start - PRE_FAULT_ROWS);
    Label(pre_start:fault_start - 1) = 1;
end

% Check label distribution
fprintf('\n--- Label Distribution ---\n');
fprintf('Normal (0)       : %d rows (%.1f%%)\n', sum(Label==0), 100*mean(Label==0));
fprintf('Pre-fault (1)    : %d rows (%.1f%%)\n', sum(Label==1), 100*mean(Label==1));
fprintf('Fault active (2) : %d rows (%.1f%%)\n', sum(Label==2), 100*mean(Label==2));

%% ================================================
%% STEP 4 — Handle NaN and Inf
%% ================================================
X_raw(isnan(X_raw)) = 0;
X_raw(isinf(X_raw)) = 0;

%% ================================================
%% STEP 5 — Log-scale magnitude columns
%% ================================================
% Magnitude cols per 18-col bus block:
%   cols 1-9  (Va,Vb,Vc,Ia,Ib,Ic,VM_P,VM_N,VM_Z) → log1p
%   cols 10-12 (VP_P,VP_N,VP_Z)                   → keep (angles)
%   cols 13-15 (IM_P,IM_N,IM_Z)                   → log1p
%   cols 16-18 (IP_P,IP_N,IP_Z)                   → keep (angles)

mag_cols = [];
ang_cols = [];
for bus = 0:3
    base     = bus * 18;
    mag_cols = [mag_cols, base+(1:9),   base+(13:15)];  %#ok
    ang_cols = [ang_cols, base+(10:12), base+(16:18)];  %#ok
end

X_log = X_raw;
X_log(:, mag_cols) = log1p(abs(X_raw(:, mag_cols)));
% Angle columns stay as-is (directional info)

fprintf('\nMagnitude cols log-scaled: %d\n', numel(mag_cols));
fprintf('Angle cols kept raw      : %d\n', numel(ang_cols));

%% ================================================
%% STEP 6 — Split by Run ID (NEVER by row!)
%% ================================================
run_ids   = unique(Run_ID);
n_runs    = numel(run_ids);
rng(42);  % reproducibility
shuffled  = run_ids(randperm(n_runs));

n_train   = round(0.70 * n_runs);
n_val     = round(0.10 * n_runs);
% remaining = test

train_runs = shuffled(1           : n_train);
val_runs   = shuffled(n_train+1   : n_train+n_val);
test_runs  = shuffled(n_train+n_val+1 : end);

fprintf('\n--- Run Split ---\n');
fprintf('Train runs : %d\n', numel(train_runs));
fprintf('Val runs   : %d\n', numel(val_runs));
fprintf('Test runs  : %d\n', numel(test_runs));

train_mask = ismember(Run_ID, train_runs);
val_mask   = ismember(Run_ID, val_runs);
test_mask  = ismember(Run_ID, test_runs);

X_tr = X_log(train_mask, :);
X_va = X_log(val_mask,   :);
X_te = X_log(test_mask,  :);

Y_tr = Label(train_mask);
Y_va = Label(val_mask);
Y_te = Label(test_mask);

% Also keep Fault_Type and Location for evaluation
FT_te  = Fault_Type(test_mask);
Loc_te = Location(test_mask);

%% ================================================
%% STEP 7 — Z-score Normalize (fit on train only)
%% ================================================
[X_train, mu, sigma] = zscore(X_tr);
sigma(sigma == 0)    = 1;   % avoid divide-by-zero on constant cols

X_val  = (X_va - mu) ./ sigma;
X_test = (X_te - mu) ./ sigma;

%% ================================================
%% STEP 8 — Class weights (handle imbalance)
%% ================================================
classes      = [0; 1; 2];
classWeights = zeros(3, 1);
for c = 1:3
    classWeights(c) = 1 / max(sum(Y_tr == classes(c)), 1);
end
classWeights = classWeights / sum(classWeights) * 3;

fprintf('\n--- Class Weights ---\n');
fprintf('Normal (0)    : %.4f\n', classWeights(1));
fprintf('Pre-fault (1) : %.4f\n', classWeights(2));
fprintf('Fault (2)     : %.4f\n', classWeights(3));

%% ================================================
%% STEP 9 — Save
%% ================================================
save('Preprocessed_Nalanchira.mat', ...
    'X_train', 'Y_tr',    ...
    'X_val',   'Y_va',    ...
    'X_test',  'Y_te',    ...
    'FT_te',   'Loc_te',  ...
    'mu',      'sigma',   ...
    'mag_cols','ang_cols',...
    'classWeights',       ...
    'train_runs','val_runs','test_runs', ...
    '-v7.3');

fprintf('\n========================================\n');
fprintf('  PREPROCESSING COMPLETE\n');
fprintf('========================================\n');
fprintf('Train samples : %d\n', size(X_train, 1));
fprintf('Val samples   : %d\n', size(X_val,   1));
fprintf('Test samples  : %d\n', size(X_test,  1));
fprintf('Features      : %d\n', size(X_train, 2));
fprintf('Saved → Preprocessed_Nalanchira.mat\n');
fprintf('========================================\n');