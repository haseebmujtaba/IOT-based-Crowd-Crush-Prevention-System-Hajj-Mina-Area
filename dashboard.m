function dashboard(processed_array, risk_array, label_array, eta_array, ...
                   density_history, iteration, total_iterations)
% =========================================================================
% dashboard.m
% IoT-Based Crowd Crush Prevention System — Live Visualization Dashboard
%
% PURPOSE:
%   Renders a full live MATLAB dashboard showing all 5 zones simultaneously.
%   The dashboard updates in real-time using drawnow() and displays:
%
%   PANEL 1 (top-left):  Zone Status Panel — Color-coded status indicators
%                        Green = Safe, Yellow = Warning, Red = Critical
%   PANEL 2 (top-right): Risk Score Bar Chart — Current composite scores
%   PANEL 3 (mid-left):  Density Trend + Forecast — 5-zone time series
%   PANEL 4 (mid-right): Zone Status History Heatmap — Temporal overview
%   PANEL 5 (bottom):    Sensor Gauges — Current readings per zone
%
% INPUTS:
%   processed_array   — 1×5 struct array (from process_zone_data)
%   risk_array        — 1×5 struct array (from compute_zone_risk)
%   label_array       — 1×5 cell array of classification labels
%   eta_array         — 1×5 struct array (from predict_crush_eta)
%   density_history   — N×5 matrix of past density readings (rows=time, col=zone)
%   iteration         — Current iteration number (1–60)
%   total_iterations  — Total planned iterations (60)
%
% VISUALIZATION DESIGN:
%   - Green (#00C853), Yellow (#FFD600), Red (#D50000) for status colors
%   - Zone risk scores shown as horizontal bars with gradient fill
%   - Density trend shows last 15 readings with linear regression forecast
%   - Status history heatmap shows full session zone safety timeline
% =========================================================================

    % ---- Zone short names for compact display --------------------------
    zone_short = {'Jamarat', 'TC North', 'TC South', 'Exit'};

    % ---- Status color mapping ------------------------------------------
    color_safe     = [0.00, 0.78, 0.33];  % vivid green
    color_warning  = [1.00, 0.84, 0.00];  % vivid yellow
    color_critical = [0.84, 0.00, 0.00];  % vivid red
    color_bg       = [0.12, 0.12, 0.15];  % dark background
    color_text     = [0.95, 0.95, 0.95];  % light text

    num_zones = 4;

    % ---- Initialize or retrieve figure ---------------------------------
    fig_tag = 'HajjCrowdDashboard';
    fig = findobj('Tag', fig_tag);
    if isempty(fig)
        fig = figure('Tag', fig_tag, ...
                     'Name', 'Hajj Mina Crowd Crush Prevention System — Live Dashboard', ...
                     'Color', color_bg, ...
                     'Position', [50, 50, 1400, 860], ...
                     'NumberTitle', 'off', ...
                     'MenuBar', 'none', ...
                     'ToolBar', 'none');
    end

    % ---- Helper: get status color from label string --------------------
    function c = status_color(lbl)
        switch lbl
            case 'Safe',     c = color_safe;
            case 'Warning',  c = color_warning;
            case 'Critical', c = color_critical;
            otherwise,       c = [0.5, 0.5, 0.5];
        end
    end

    % ====================================================================
    % PANEL 1: Zone Status Grid (top-left 2×3 block)
    % ====================================================================
    ax1 = subplot(3, 3, [1, 2]);
    cla(ax1); axis(ax1, 'off');
    set(ax1, 'Color', color_bg);
    hold(ax1, 'on');

    title(ax1, sprintf('ZONE STATUS  [Iteration %d / %d]', iteration, total_iterations), ...
          'Color', color_text, 'FontSize', 11, 'FontWeight', 'bold');

    % Draw each zone as a colored rectangle with status info
    panel_width  = 0.18;
    panel_height = 0.75;
    gap          = 0.02;
    y_base       = 0.1;

    for z = 1:num_zones
        x_pos = (z-1) * (panel_width + gap);
        lbl = label_array{z};
        c   = status_color(lbl);
        pz  = processed_array(z);
        rs  = risk_array(z);

        % Zone rectangle
        rectangle(ax1, 'Position', [x_pos, y_base, panel_width, panel_height], ...
                  'FaceColor', c, 'EdgeColor', 'white', 'LineWidth', 1.5);

        % Zone short name
        text(ax1, x_pos + panel_width/2, y_base + panel_height*0.88, ...
             zone_short{z}, 'Color', 'black', 'FontSize', 8, ...
             'FontWeight', 'bold', 'HorizontalAlignment', 'center');

        % Status label
        text(ax1, x_pos + panel_width/2, y_base + panel_height*0.72, ...
             upper(lbl), 'Color', 'black', 'FontSize', 9, ...
             'FontWeight', 'bold', 'HorizontalAlignment', 'center');

        % Risk score
        text(ax1, x_pos + panel_width/2, y_base + panel_height*0.56, ...
             sprintf('Risk: %.0f', rs.score), 'Color', 'black', ...
             'FontSize', 8, 'HorizontalAlignment', 'center');

        % Density reading
        text(ax1, x_pos + panel_width/2, y_base + panel_height*0.40, ...
             sprintf('D: %.2f p/m²', pz.density_smooth), 'Color', 'black', ...
             'FontSize', 7, 'HorizontalAlignment', 'center');

        % Speed reading
        text(ax1, x_pos + panel_width/2, y_base + panel_height*0.25, ...
             sprintf('S: %.2f m/s', pz.speed_smooth), 'Color', 'black', ...
             'FontSize', 7, 'HorizontalAlignment', 'center');

        % ETA indicator
        if ~eta_array(z).is_safe && eta_array(z).eta_minutes < 60
            eta_str = sprintf('ETA: %.0fm', eta_array(z).eta_minutes);
        else
            eta_str = 'ETA: Safe';
        end
        text(ax1, x_pos + panel_width/2, y_base + panel_height*0.10, ...
             eta_str, 'Color', 'black', 'FontSize', 7, ...
             'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end

    xlim(ax1, [0, num_zones * (panel_width + gap)]);
    ylim(ax1, [0, 1]);

    % ====================================================================
    % PANEL 2: Risk Score Bar Chart (top-right)
    % ====================================================================
    ax2 = subplot(3, 3, 3);
    cla(ax2);

    scores = arrayfun(@(r) r.score, risk_array);
    bar_colors = zeros(num_zones, 3);
    for z = 1:num_zones
        bar_colors(z, :) = status_color(label_array{z});
    end

    % Draw bars with individual colors
    hold(ax2, 'on');
    for z = 1:num_zones
        bar(ax2, z, scores(z), 'FaceColor', bar_colors(z,:), 'EdgeColor', 'white');
    end

    % Critical threshold line
    yline(ax2, 75, '--r', 'LineWidth', 1.5);
    yline(ax2, 40, '--y', 'LineWidth', 1.0);

    set(ax2, 'Color', [0.18, 0.18, 0.22], 'XColor', color_text, 'YColor', color_text, ...
             'XTick', 1:num_zones, 'XTickLabel', zone_short, ...
             'FontSize', 7, 'XTickLabelRotation', 15, 'GridColor', [0.4,0.4,0.4]);
    grid(ax2, 'on');
    ylim(ax2, [0, 100]);
    title(ax2, 'Risk Scores (0–100)', 'Color', color_text, 'FontSize', 9, 'FontWeight', 'bold');
    ylabel(ax2, 'Risk Score', 'Color', color_text, 'FontSize', 8);

    % Score labels on bars
    for z = 1:num_zones
        text(ax2, z, scores(z) + 2, sprintf('%.0f', scores(z)), ...
             'Color', color_text, 'FontSize', 8, 'HorizontalAlignment', 'center');
    end

    hold(ax2, 'off');

    % ====================================================================
    % PANEL 3: Density Trend + Linear Regression Forecast (mid-left)
    % ====================================================================
    ax3 = subplot(3, 3, [4, 5]);
    cla(ax3); hold(ax3, 'on');

    zone_line_colors = [color_safe; color_warning; [0.0, 0.6, 1.0]; [1.0, 0.5, 0.0]; color_critical];
    n_hist = size(density_history, 1);
    t_axis = (1:n_hist)';

    if n_hist >= 2
        for z = 1:num_zones
            plot(ax3, t_axis, density_history(:, z), '-', ...
                 'Color', zone_line_colors(z,:), 'LineWidth', 1.5, ...
                 'DisplayName', zone_short{z});

            % Add linear forecast for last 15 points (if enough data)
            win = min(15, n_hist);
            t_w = t_axis(end - win + 1 : end);
            d_w = density_history(end - win + 1 : end, z);
            if win >= 3
                p = polyfit(t_w, d_w, 1);
                if p(1) > 0   % only draw forecast if density rising
                    t_future = t_axis(end) : 0.5 : t_axis(end) + 5;
                    d_forecast = polyval(p, t_future);
                    plot(ax3, t_future, d_forecast, '--', ...
                         'Color', zone_line_colors(z,:), 'LineWidth', 0.8, ...
                         'HandleVisibility', 'off');
                end
            end
        end
    end

    % Crush threshold line
    yline(ax3, 6.0, '--r', 'LineWidth', 2.0, 'DisplayName', 'Crush Threshold (6.0)');

    set(ax3, 'Color', [0.18, 0.18, 0.22], 'XColor', color_text, 'YColor', color_text, ...
             'GridColor', [0.4, 0.4, 0.4], 'FontSize', 8);
    grid(ax3, 'on');
    title(ax3, 'Crowd Density Trend + Forecast (dashed = rising prediction)', ...
          'Color', color_text, 'FontSize', 9, 'FontWeight', 'bold');
    xlabel(ax3, 'Sample', 'Color', color_text, 'FontSize', 8);
    ylabel(ax3, 'Density (p/m²)', 'Color', color_text, 'FontSize', 8);
    legend(ax3, 'show', 'Location', 'northwest', 'TextColor', color_text, ...
           'Color', [0.2, 0.2, 0.25], 'FontSize', 7);
    ylim(ax3, [0, 10]);

    hold(ax3, 'off');

    % ====================================================================
    % PANEL 4: Zone Status History Heatmap (mid-right)
    % ====================================================================
    ax4 = subplot(3, 3, 6);
    cla(ax4);

    % Build numeric status matrix from density history
    % Threshold-based heuristic: Safe=1, Warning=2, Critical=3
    if n_hist >= 1
        status_matrix = ones(n_hist, num_zones);
        for col = 1:num_zones
            d_col = density_history(:, col);
            status_matrix(d_col >= 4.0 & d_col < 6.0, col) = 2;
            status_matrix(d_col >= 6.0, col)                = 3;
        end

        % Custom colormap: green / yellow / red
        cmap = [color_safe; color_warning; color_critical];
        imagesc(ax4, status_matrix', [1, 3]);
        colormap(ax4, cmap);
    end

    set(ax4, 'Color', [0.18, 0.18, 0.22], 'XColor', color_text, 'YColor', color_text, ...
             'YTick', 1:num_zones, 'YTickLabel', zone_short, 'FontSize', 7);
    xlabel(ax4, 'Sample', 'Color', color_text, 'FontSize', 8);
    title(ax4, 'Zone Status History', 'Color', color_text, 'FontSize', 9, 'FontWeight', 'bold');

    % ====================================================================
    % PANEL 5: Sensor Readings Table (bottom row)
    % ====================================================================
    ax5 = subplot(3, 3, [7, 8, 9]);
    cla(ax5); axis(ax5, 'off');
    set(ax5, 'Color', color_bg);

    title(ax5, 'Live Sensor Readings (Smoothed)', 'Color', color_text, ...
          'FontSize', 10, 'FontWeight', 'bold');

    % Column headers
    headers  = {'Zone', 'Density (p/m²)', 'Speed (m/s)', 'Pressure (0-1)', 'Temp (°C)', 'Risk', 'Status'};
    col_x    = [0.00, 0.18, 0.32, 0.45, 0.59, 0.70, 0.82];
    header_y = 0.88;

    for h = 1:length(headers)
        text(ax5, col_x(h), header_y, headers{h}, 'Color', [0.7, 0.7, 1.0], ...
             'FontSize', 8, 'FontWeight', 'bold', 'Units', 'normalized');
    end

    % Separator line (axes already in [0,1] range so no Units needed)
    line(ax5, [0, 1], [0.80, 0.80], 'Color', [0.5, 0.5, 0.5], ...
         'LineWidth', 0.5);

    % Data rows for each zone
    for z = 1:num_zones
        pz  = processed_array(z);
        rs  = risk_array(z);
        lbl = label_array{z};
        row_y = 0.65 - (z-1) * 0.17;

        row_color = status_color(lbl);
        row_vals = { ...
            zone_short{z}, ...
            sprintf('%.3f', pz.density_smooth), ...
            sprintf('%.3f', pz.speed_smooth), ...
            sprintf('%.3f', pz.pressure_smooth), ...
            sprintf('%.1f', pz.temp_smooth), ...
            sprintf('%.1f', rs.score), ...
            lbl  ...
        };

        % Highlight anomaly flags with indicator symbols
        if pz.flag_density,  row_vals{2} = ['▲ ', row_vals{2}]; end
        if pz.flag_speed,    row_vals{3} = ['▼ ', row_vals{3}]; end
        if pz.flag_pressure, row_vals{4} = ['⚑ ', row_vals{4}]; end
        if pz.flag_temp,     row_vals{5} = ['🌡 ', row_vals{5}]; end

        for c = 1:length(row_vals)
            txt_color = color_text;
            if c == 7   % status column — use status color
                txt_color = row_color;
            end
            text(ax5, col_x(c), row_y, row_vals{c}, ...
                 'Color', txt_color, 'FontSize', 8, ...
                 'Units', 'normalized');
        end
    end

    xlim(ax5, [0, 1]); ylim(ax5, [0, 1]);

    % ====================================================================
    % TITLE BAR with timestamp
    % ====================================================================
    sgtitle(fig, sprintf('HAJJ MINA CROWD CRUSH PREVENTION SYSTEM   |   %s   |   Sample %d/%d', ...
            datestr(now, 'HH:MM:SS'), iteration, total_iterations), ...
            'Color', color_text, 'FontSize', 12, 'FontWeight', 'bold', ...
            'BackgroundColor', [0.08, 0.08, 0.12]);

    % ---- Force immediate screen update (live dashboard) ----------------
    drawnow limitrate;

end