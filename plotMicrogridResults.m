function plotMicrogridResults(profile, p, SOC, P_bess, P_grid, P_curtail, ...
    P_dc_served, P_res_served, P_shed, state_log)
%PLOTMICROGRIDRESULTS Plot the UpGrid controller simulation results:
%power balance, BESS dispatch, SOC trajectory and controller state
%timeline, then save the figure to the current folder as PNG and PDF.
%
%   Jay Tinsley, UpGrid (Team 39) - data centre microgrid control strategy

    t = profile.t_h;

    % Fixed categorical colours (validated palette, consistent across the
    % whole project for these signals/states).
    col.pv       = hex2rgb('#2a78d6');   % blue
    col.dc       = hex2rgb('#eb6834');   % orange
    col.res      = hex2rgb('#1baf7a');   % aqua
    col.bess     = hex2rgb('#4a3aa7');   % violet
    col.grid     = hex2rgb('#e34948');   % red
    col.soc      = hex2rgb('#2a78d6');   % blue
    col.muted    = hex2rgb('#898781');   % muted ink (reference lines)
    col.pvdirect  = hex2rgb('#1baf7a');  % aqua
    col.peakshave = hex2rgb('#eda100'); % yellow
    col.bessdis   = hex2rgb('#2a78d6'); % blue
    col.loadshed  = hex2rgb('#e34948'); % red

    fig = figure('Color', 'w', 'Position', [100 100 900 950]);

    % --- Panel 1: power balance ---
    ax1 = subplot(4, 1, 1); hold(ax1, 'on'); box(ax1, 'off');
    plot(ax1, t, profile.P_pv, 'Color', col.pv, 'LineWidth', 2, 'DisplayName', 'PV output');
    plot(ax1, t, profile.P_dc, '--', 'Color', col.dc, 'LineWidth', 1.5, 'DisplayName', 'Data centre demand');
    plot(ax1, t, profile.P_res, '--', 'Color', col.res, 'LineWidth', 1.5, 'DisplayName', 'Residential demand');
    plot(ax1, t, P_grid, 'Color', col.grid, 'LineWidth', 1.5, 'DisplayName', 'Grid import (backstop)');
    ylabel(ax1, 'Power [kW]');
    title(ax1, 'UpGrid microgrid controller: 24 h simulation  -  PV output vs. demand');
    legend(ax1, 'Location', 'eastoutside');
    grid(ax1, 'on');
    xlim(ax1, [0 24]);

    % --- Panel 2: BESS dispatch ---
    ax2 = subplot(4, 1, 2); hold(ax2, 'on'); box(ax2, 'off');
    area(ax2, t, P_bess, 'FaceColor', col.bess, 'FaceAlpha', 0.35, 'EdgeColor', col.bess, 'LineWidth', 1.5, 'DisplayName', 'BESS power (+discharge / -charge)');
    plot(ax2, [0 24], [0 0], 'Color', col.muted, 'LineWidth', 1, 'HandleVisibility', 'off');
    ylabel(ax2, 'Power [kW]');
    title(ax2, 'Battery dispatch');
    legend(ax2, 'Location', 'eastoutside');
    grid(ax2, 'on');
    xlim(ax2, [0 24]);

    % --- Panel 3: SOC trajectory ---
    ax3 = subplot(4, 1, 3); hold(ax3, 'on'); box(ax3, 'off');
    plot(ax3, t, 100*SOC, 'Color', col.soc, 'LineWidth', 2, 'DisplayName', 'BESS SOC');
    plot(ax3, [0 24], 100*p.SOC_min*[1 1], ':', 'Color', col.muted, 'LineWidth', 1.25, 'DisplayName', 'Reserve minimum');
    plot(ax3, [0 24], 100*p.SOC_max*[1 1], ':', 'Color', col.muted, 'LineWidth', 1.25, 'DisplayName', 'Maximum SOC');
    ylabel(ax3, 'SOC [%]');
    ylim(ax3, [0 100]);
    title(ax3, 'Battery state of charge');
    legend(ax3, 'Location', 'eastoutside');
    grid(ax3, 'on');
    xlim(ax3, [0 24]);

    % --- Panel 4: controller state timeline ---
    ax4 = subplot(4, 1, 4); hold(ax4, 'on'); box(ax4, 'off');
    states       = {'PV_DIRECT', 'PEAK_SHAVE', 'BESS_DISCHARGE', 'LOAD_SHED'};
    state_labels = {'PV direct', 'Peak shave', 'BESS discharge', 'Load shed'};
    state_colors = [col.pvdirect; col.peakshave; col.bessdis; col.loadshed];
    code = zeros(numel(state_log), 1);
    for i = 1:numel(states)
        code(strcmp(state_log, states{i})) = i;
    end
    for i = 1:numel(states)
        mask = code == i;
        plot(ax4, t(mask), code(mask), 's', 'Color', state_colors(i,:), ...
            'MarkerFaceColor', state_colors(i,:), 'MarkerSize', 3, ...
            'DisplayName', state_labels{i});
    end
    ylim(ax4, [0.5 4.5]);
    set(ax4, 'YTick', 1:4, 'YTickLabel', state_labels);
    xlabel(ax4, 'Time [h]');
    title(ax4, 'Controller state');
    legend(ax4, 'Location', 'eastoutside');
    grid(ax4, 'on');
    xlim(ax4, [0 24]);

    % Save the figure. exportgraphics (R2020a+) is preferred; fall back to
    % print for older MATLAB releases or Octave.
    try
        exportgraphics(fig, 'microgrid_sim_results.png', 'Resolution', 150);
        exportgraphics(fig, 'microgrid_sim_results.pdf');
    catch
        set(fig, 'PaperPositionMode', 'auto');
        print(fig, 'microgrid_sim_results.png', '-dpng', '-r150');
        print(fig, 'microgrid_sim_results.pdf', '-dpdf');
    end
end

function rgb = hex2rgb(hex)
%HEX2RGB Convert a '#rrggbb' hex string to a 1x3 RGB triplet in [0,1].
    hex = char(hex);
    hex = strrep(hex, '#', '');
    rgb = [hex2dec(hex(1:2)), hex2dec(hex(3:4)), hex2dec(hex(5:6))] / 255;
end
