%RUNMICROGRIDSIM Driver script: simulates the UpGrid microgrid controller
%over a 24-hour synthetic PV/load profile and reports/plots the results.
%
%   Swap initMicrogridParams() for a version that reads real SAM/measured
%   PV, load and BESS data once available; the controller and the rest of
%   this script do not need to change.
%
%   Jay Tinsley, UpGrid (Team 39) - data centre microgrid control strategy

clear; clc; close all;

[p, profile] = initMicrogridParams();
n = numel(profile.t_h);

% --- Preallocate logs ---
SOC          = zeros(n, 1);
P_bess_log   = zeros(n, 1);
P_grid_log   = zeros(n, 1);
P_curtail_log = zeros(n, 1);
P_dc_served  = zeros(n, 1);
P_res_served = zeros(n, 1);
P_shed_log   = zeros(n, 1);
state_log    = cell(n, 1);

SOC(1) = p.SOC_init;

% --- Simulation loop: one call to the controller per control interval ---
for k = 1:n
    in.P_pv  = profile.P_pv(k);
    in.P_dc  = profile.P_dc(k);
    in.P_res = profile.P_res(k);
    in.SOC   = SOC(k);

    out = microgridController(in, p);

    state_log{k}     = out.state;
    P_bess_log(k)    = out.P_bess;
    P_grid_log(k)    = out.P_grid;
    P_curtail_log(k) = out.P_curtail;
    P_dc_served(k)   = out.P_dc_served;
    P_res_served(k)  = out.P_res_served;
    P_shed_log(k)    = out.P_shed;

    % --- Battery SOC dynamics for the next interval ---
    % out.P_bess > 0 : discharging (SOC falls, losses reduce delivered energy)
    % out.P_bess < 0 : charging    (SOC rises, losses reduce stored energy)
    if out.P_bess >= 0
        dSOC = -(out.P_bess * p.dt_h) / (p.E_bess_cap * p.eta_dis);
    else
        dSOC = -(out.P_bess * p.dt_h * p.eta_ch) / p.E_bess_cap;
    end

    if k < n
        SOC(k+1) = min(max(SOC(k) + dSOC, 0), 1);
    end
end

%% --- Summary metrics ---
E_grid_import_kWh = sum(P_grid_log)    * p.dt_h;
E_curtail_kWh     = sum(P_curtail_log) * p.dt_h;
E_shed_kWh        = sum(P_shed_log)    * p.dt_h;
E_dc_demand_kWh   = sum(profile.P_dc)  * p.dt_h;
E_res_demand_kWh  = sum(profile.P_res) * p.dt_h;

fprintf('--- UpGrid microgrid controller: 24 h summary ---\n');
fprintf('Data centre energy demand:      %8.1f kWh\n', E_dc_demand_kWh);
fprintf('Residential energy demand:      %8.1f kWh\n', E_res_demand_kWh);
fprintf('Grid import energy (backstop):  %8.1f kWh (%.2f%% of total demand)\n', ...
    E_grid_import_kWh, 100*E_grid_import_kWh/(E_dc_demand_kWh+E_res_demand_kWh));
fprintf('PV curtailed/exported energy:   %8.1f kWh\n', E_curtail_kWh);
fprintf('Residential load shed energy:   %8.1f kWh (%.2f%% of residential demand)\n', ...
    E_shed_kWh, 100*E_shed_kWh/E_res_demand_kWh);
continuity_ok = all(P_dc_served >= profile.P_dc - 1e-6);
if continuity_ok
    continuity_str = 'true';
else
    continuity_str = 'false';
end
fprintf('Data centre load continuity:    %s\n', continuity_str);
fprintf('Final SOC: %.1f%%  (min %.1f%%, max %.1f%%)\n', ...
    100*SOC(end), 100*min(SOC), 100*max(SOC));

fprintf('\nTime spent in each controller state:\n');
states = {'PV_DIRECT', 'PEAK_SHAVE', 'BESS_DISCHARGE', 'LOAD_SHED'};
for i = 1:numel(states)
    pct = 100 * sum(strcmp(state_log, states{i})) / n;
    fprintf('  %-15s %5.1f %%\n', states{i}, pct);
end

%% --- Plot results ---
plotMicrogridResults(profile, p, SOC, P_bess_log, P_grid_log, ...
    P_curtail_log, P_dc_served, P_res_served, P_shed_log, state_log);
