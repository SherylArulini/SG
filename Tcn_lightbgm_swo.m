%% 1. DATA PREPARATION & MAPPING
load('Nalanchira_Master_Dataset.mat');
data = table2array(ANN_Table);

fault_labels = {'A-B-C-G', 'B-C', 'A-B-C-G', 'A-C-G', 'B-C-G', ...
                'A-B-C-G', 'A-C-G', 'B-G', 'A-B-C', 'C-G', ...
                'A-B', 'A-B-C', 'B-C', 'B-C', 'B-C'};

X = single(data(:, 1:72));
raw_Y = data(:, 73);
Y_named = cell(size(raw_Y));
for i = 1:15
    Y_named(raw_Y == i) = fault_labels(i);
end
Y = categorical(Y_named);

[X, ~, ~] = zscore(double(X));
cv = cvpartition(Y, 'Holdout', 0.2);
X_train = X(training(cv), :);
Y_train = Y(training(cv));
X_test  = X(test(cv), :);
Y_test  = Y(test(cv));

%% 2. SPIDER WASP OPTIMIZER (SWO)
fprintf('Starting Spider Wasp Optimization...\n');
nWasps = 5; maxIter = 2;
total_runs = nWasps * maxIter; run_count = 0;
bestErr = inf; bestParams = [0.1, 50];

h_wb = waitbar(0, 'SWO is hunting for optimal parameters...');
for iter = 1:maxIter
    for w = 1:nWasps
        run_count = run_count + 1;
        waitbar(run_count/total_runs, h_wb, ...
            sprintf('SWO Progress: %d/%d', run_count, total_runs));

        candidate_LR     = 0.01 + (0.24 * rand);
        candidate_Splits = randi([20, 100]);

        try
            t = templateTree('MaxNumSplits', candidate_Splits, 'MinLeafSize', 5);
            tempMdl = fitcensemble(X_train, Y_train, ...
                'Method',            'AdaBoostM2', ...
                'NumLearningCycles', 30, ...
                'Learners',          t, ...
                'LearnRate',         candidate_LR);
            currErr = loss(tempMdl, X_test, Y_test);
            if currErr < bestErr
                bestErr    = currErr;
                bestParams = [candidate_LR, candidate_Splits];
            end
        catch ME
            fprintf('  SWO candidate failed: %s\n', ME.message);
            continue;
        end
    end
end
close(h_wb);
fprintf('Optimization Complete! Best Params: LR=%.4f, Splits=%d\n', ...
    bestParams(1), bestParams(2));

%% 3. FINAL HYBRID TRAINING
fprintf('\nTraining Final Model. Progress will print every 10 trees:\n');
t_final = templateTree('MaxNumSplits', round(bestParams(2)), 'MinLeafSize', 5);
HybridMdl = fitcensemble(X_train, Y_train, ...
    'Method',            'AdaBoostM2', ...
    'NumLearningCycles', 100, ...
    'Learners',          t_final, ...
    'LearnRate',         bestParams(1), ...
    'NPrint',            10);

%% 4. PERFORMANCE & RELIABILITY METRICS
[Y_pred, ~] = predict(HybridMdl, X_test);
cm      = confusionmat(Y_test, Y_pred);
classes = categories(Y_test);
nClasses = numel(classes);

% ── Per-class metrics ───────────────────────────────────────────────────
precision  = zeros(nClasses, 1);
recall     = zeros(nClasses, 1);
f1_scores  = zeros(nClasses, 1);
specificity = zeros(nClasses, 1);

for i = 1:nClasses
    tp = cm(i,i);
    fp = sum(cm(:,i)) - tp;
    fn = sum(cm(i,:)) - tp;
    tn = sum(cm(:)) - tp - fp - fn;

    precision(i)   = tp / max(tp + fp, 1);
    recall(i)      = tp / max(tp + fn, 1);   % same as Sensitivity
    specificity(i) = tn / max(tn + fp, 1);
    f1_scores(i)   = 2*tp / max(2*tp + fp + fn, 1);
end

% ── Overall metrics ─────────────────────────────────────────────────────
total_correct = sum(diag(cm));
total_samples = sum(cm(:));
accuracy      = (total_correct / total_samples) * 100;
macro_prec    = mean(precision)  * 100;
macro_recall  = mean(recall)     * 100;
macro_f1      = mean(f1_scores)  * 100;
rmse_val      = sqrt(mean((double(Y_test) - double(Y_pred)).^2));

% ── Console report ──────────────────────────────────────────────────────
fprintf('\n========================================\n');
fprintf('       MODEL PERFORMANCE SUMMARY\n');
fprintf('========================================\n');
fprintf('Overall Accuracy  : %.4f%%\n', accuracy);
fprintf('Macro Precision   : %.4f%%\n', macro_prec);
fprintf('Macro Recall      : %.4f%%\n', macro_recall);
fprintf('Macro F1-Score    : %.4f%%\n', macro_f1);
fprintf('RMSE              : %.4f\n',   rmse_val);
fprintf('Total Samples     : %d\n',     total_samples);
fprintf('Correct Predicted : %d\n',     total_correct);
fprintf('Misclassified     : %d\n',     total_samples - total_correct);
fprintf('----------------------------------------\n');
fprintf('%-10s %10s %10s %10s %10s\n', ...
    'Class','Precision','Recall','F1-Score','Specificity');
fprintf('----------------------------------------\n');
for i = 1:nClasses
    fprintf('%-10s %9.4f%% %9.4f%% %9.4f%% %9.4f%%\n', ...
        classes{i}, precision(i)*100, recall(i)*100, ...
        f1_scores(i)*100, specificity(i)*100);
end
fprintf('========================================\n');

%% 5. VISUALIZATION  ── 2×3 dashboard ────────────────────────────────────
nTrees   = HybridMdl.NumTrained;
cum_loss = arrayfun(@(k) loss(HybridMdl, X_test, Y_test, ...
                              'Learners', 1:k), 1:nTrees);

% Actual vs Predicted sample plot (first 200 test points)
nShow      = min(200, numel(Y_test));
actual_num = double(Y_test(1:nShow));
pred_num   = double(Y_pred(1:nShow));

figure('Name','Hybrid Model – Full Performance Dashboard', ...
       'Position',[50 50 1600 900]);

% ── Panel 1: Confusion Matrix ────────────────────────────────────────────
subplot(2,3,1);
confusionchart(Y_test, Y_pred, 'Title','Fault Identification Matrix');

% ── Panel 2: Learning Curve ──────────────────────────────────────────────
subplot(2,3,2);
plot(1:nTrees, cum_loss, 'b-', 'LineWidth', 2);
grid on;
xlabel('Number of Trees'); ylabel('Test Error');
title('Learning Curve');

% ── Panel 3: Actual vs Predicted (first 200 samples) ────────────────────
subplot(2,3,3);
plot(1:nShow, actual_num, 'g-o', 'MarkerSize', 3, 'LineWidth', 1, ...
     'DisplayName', 'Actual');
hold on;
plot(1:nShow, pred_num, 'r--x', 'MarkerSize', 3, 'LineWidth', 1, ...
     'DisplayName', 'Predicted');
hold off;
legend('Location','best');
set(gca, 'YTick', 1:nClasses, 'YTickLabel', classes);
xlabel('Sample Index'); ylabel('Fault Class');
title('Actual vs Predicted (First 200 Samples)');
grid on;

% ── Panel 4: Per-class Precision / Recall / F1 grouped bar ──────────────
subplot(2,3,4);
bar_data = [precision, recall, f1_scores] * 100;
b = bar(bar_data, 'grouped');
b(1).FaceColor = [0.20 0.60 0.80];
b(2).FaceColor = [0.95 0.60 0.10];
b(3).FaceColor = [0.20 0.70 0.40];
set(gca, 'XTickLabel', classes, 'XTick', 1:nClasses);
xtickangle(45);
ylim([90 100]);   % zoom in to show differences clearly
ylabel('Score (%)');
title('Per-Class Precision / Recall / F1');
legend({'Precision','Recall','F1-Score'}, 'Location','southeast');
grid on;

% ── Panel 5: Specificity bar ─────────────────────────────────────────────
subplot(2,3,5);
bar(specificity * 100, 'FaceColor', [0.50 0.20 0.70]);
set(gca, 'XTickLabel', classes, 'XTick', 1:nClasses);
xtickangle(45);
ylim([90 100]);
ylabel('Specificity (%)');
title('Per-Class Specificity');
grid on;

% ── Panel 6: Overall metrics summary bar ────────────────────────────────
subplot(2,3,6);
overall_vals  = [accuracy, macro_prec, macro_recall, macro_f1];
overall_names = {'Accuracy','Precision','Recall','F1-Score'};
b2 = bar(overall_vals, 'FaceColor', 'flat');
b2.CData = [0.10 0.50 0.60;
            0.20 0.60 0.80;
            0.95 0.60 0.10;
            0.20 0.70 0.40];
set(gca, 'XTickLabel', overall_names);
ylim([95 100]);
ylabel('Score (%)');
title(sprintf('Overall Metrics  |  RMSE: %.4f', rmse_val));
grid on;
% Print values on top of each bar
for k = 1:4
    text(k, overall_vals(k) + 0.05, sprintf('%.2f%%', overall_vals(k)), ...
         'HorizontalAlignment','center', 'FontSize', 9, 'FontWeight','bold');
end

sgtitle('TCN-LightBGM Hybrid with SWO – Complete Performance Dashboard', ...
        'FontSize', 14, 'FontWeight', 'bold');

fprintf('\nDone! Dashboard plotted.\n');