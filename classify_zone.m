function [label, classifier] = classify_zone(processed_zone, classifier)
% =========================================================================
% classify_zone.m
% IoT-Based Crowd Crush Prevention System — ML Classification Module
%
% PURPOSE:
%   Trains a Decision Tree (fitctree) classifier on synthetic labeled data
%   representing realistic crowd condition scenarios. Classifies each zone
%   into one of three safety levels: Safe / Warning / Critical.
%
%   On the first call (when classifier is empty), the model is trained and
%   5-fold cross-validation accuracy is printed. On subsequent calls, the
%   pre-trained model is reused — no re-training needed each iteration.
%
% INPUTS:
%   processed_zone — Single processed zone struct (one element from
%                    process_zone_data output) with smoothed sensor fields
%   classifier     — Pre-trained fitctree model (pass [] on first call)
%
% OUTPUTS:
%   label          — Predicted class: 'Safe', 'Warning', or 'Critical'
%   classifier     — Trained/reused Decision Tree model object
%
% FEATURE VECTOR (order must match training data):
%   [density_smooth, speed_smooth, pressure_smooth, temp_smooth]
%
% CLASS LABELS:
%   1 = Safe       — All sensors within normal operating range
%   2 = Warning    — One or more sensors approaching danger zone
%   3 = Critical   — One or more sensors in dangerous range
% =========================================================================

    % ---- Train classifier on first call (classifier is empty) ----------
    if isempty(classifier)

        fprintf('\n[ML] Training Decision Tree classifier on synthetic data...\n');

        % ----------------------------------------------------------------
        % Generate synthetic labeled training dataset
        % Each row = [density, speed, pressure, temperature, label]
        %
        % SAFE scenarios:   density < 4, speed > 0.7, pressure < 0.5, temp < 38
        % WARNING scenarios: density 4–5.5, speed 0.3–0.7, pressure 0.5–0.75
        % CRITICAL scenarios: density > 5.5, speed < 0.4, pressure > 0.75
        % ----------------------------------------------------------------

        rng(42);  % Fixed seed for reproducibility

        % --- Generate SAFE samples (label = 1) --------------------------
        n_safe = 300;
        safe_density  = 0.5 + 3.4 * rand(n_safe, 1);         % 0.5–3.9
        safe_speed    = 0.8 + 1.2 * rand(n_safe, 1);          % 0.8–2.0
        safe_pressure = 0.05 + 0.44 * rand(n_safe, 1);        % 0.05–0.49
        safe_temp     = 30 + 7.9 * rand(n_safe, 1);           % 30–37.9
        safe_labels   = ones(n_safe, 1);                       % label = 1

        % Add small noise to safe samples
        safe_density  = safe_density  + 0.1 * randn(n_safe, 1);
        safe_speed    = safe_speed    + 0.05 * randn(n_safe, 1);
        safe_pressure = safe_pressure + 0.02 * randn(n_safe, 1);
        safe_temp     = safe_temp     + 0.3 * randn(n_safe, 1);

        % --- Generate WARNING samples (label = 2) -----------------------
        n_warn = 300;
        warn_density  = 3.8 + 1.7 * rand(n_warn, 1);          % 3.8–5.5
        warn_speed    = 0.25 + 0.55 * rand(n_warn, 1);         % 0.25–0.80
        warn_pressure = 0.45 + 0.34 * rand(n_warn, 1);         % 0.45–0.79
        warn_temp     = 37.5 + 3.4 * rand(n_warn, 1);          % 37.5–40.9
        warn_labels   = 2 * ones(n_warn, 1);

        warn_density  = warn_density  + 0.15 * randn(n_warn, 1);
        warn_speed    = warn_speed    + 0.04 * randn(n_warn, 1);
        warn_pressure = warn_pressure + 0.03 * randn(n_warn, 1);
        warn_temp     = warn_temp     + 0.4  * randn(n_warn, 1);

        % --- Generate CRITICAL samples (label = 3) ----------------------
        n_crit = 300;
        crit_density  = 5.3 + 4.6 * rand(n_crit, 1);          % 5.3–9.9
        crit_speed    = 0.0 + 0.39 * rand(n_crit, 1);          % 0.0–0.39
        crit_pressure = 0.72 + 0.27 * rand(n_crit, 1);         % 0.72–0.99
        crit_temp     = 39.5 + 10.4 * rand(n_crit, 1);         % 39.5–49.9
        crit_labels   = 3 * ones(n_crit, 1);

        crit_density  = crit_density  + 0.2 * randn(n_crit, 1);
        crit_speed    = crit_speed    + 0.03 * randn(n_crit, 1);
        crit_pressure = crit_pressure + 0.02 * randn(n_crit, 1);
        crit_temp     = crit_temp     + 0.5  * randn(n_crit, 1);

        % --- Concatenate all samples into training matrix ---------------
        X = [ safe_density,  safe_speed,  safe_pressure,  safe_temp; ...
              warn_density,  warn_speed,  warn_pressure,  warn_temp; ...
              crit_density,  crit_speed,  crit_pressure,  crit_temp  ];

        Y = [safe_labels; warn_labels; crit_labels];

        % Clamp features to physical limits to avoid boundary issues
        X(:,1) = max(0.1, min(10.0, X(:,1)));   % density
        X(:,2) = max(0.0, min(2.5,  X(:,2)));   % speed
        X(:,3) = max(0.0, min(1.0,  X(:,3)));   % pressure
        X(:,4) = max(25.0, min(50.0, X(:,4)));  % temperature

        % --- Train Decision Tree ----------------------------------------
        % MinLeafSize=5 prevents overfitting on synthetic data
        classifier = fitctree(X, Y, ...
            'ClassNames', [1; 2; 3], ...
            'MinLeafSize', 5, ...
            'MaxNumSplits', 20);

        % --- 5-Fold Cross-Validation ------------------------------------
        cv_model   = crossval(classifier, 'KFold', 5);
        cv_loss    = kfoldLoss(cv_model);
        cv_accuracy = (1 - cv_loss) * 100;

        fprintf('[ML] Decision Tree trained on %d samples (%d Safe, %d Warning, %d Critical)\n', ...
            n_safe + n_warn + n_crit, n_safe, n_warn, n_crit);
        fprintf('[ML] 5-Fold Cross-Validation Accuracy: %.2f%%\n', cv_accuracy);
        fprintf('[ML] Features: [density, speed, pressure, temperature]\n');
        fprintf('[ML] Classifier ready. Model will be reused each iteration.\n\n');

    end

    % ---- Classify current zone using trained model ----------------------
    % Build feature vector from smoothed sensor readings
    features = [processed_zone.density_smooth, ...
                processed_zone.speed_smooth, ...
                processed_zone.pressure_smooth, ...
                processed_zone.temp_smooth];

    predicted_class = predict(classifier, features);

    % ---- Map numeric label to readable string --------------------------
    label_map = {'Safe', 'Warning', 'Critical'};

    if predicted_class >= 1 && predicted_class <= 3
        label = label_map{predicted_class};
    else
        label = 'Unknown';
        warning('classify_zone: unexpected predicted class %d', predicted_class);
    end

end
