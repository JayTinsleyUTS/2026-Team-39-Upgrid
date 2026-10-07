function [p, profile] = initMicrogridParams()
%INITMICROGRIDPARAMS Default controller/BESS parameters and a synthetic
%24-hour PV, data-centre and residential load profile for testing
%microgridController.m end to end.
%
%   [p, profile] = initMicrogridParams()
%
%   p        Parameter struct consumed by microgridController.m
%   profile  Struct of time-series inputs (t_h, P_pv, P_dc, P_res) at the
%            controller's sample interval
%
%   IMPORTANT: the numeric values below (PV array size, BESS capacity and
%   power rating, load magnitudes) are placeholders for development and
%   testing only. Replace them with the actual PV/BESS sizing and the
%   representative data centre load profile once those are finalised
%   (per the UpGrid milestones), and replace the synthetic profile below
%   with real irradiance/load data or a SAM export.
%
%   Jay Tinsley, UpGrid (Team 39) - data centre microgrid control strategy

    %% Controller / BESS parameters
    p.dt_h            = 5/60;   % control interval, 5 minutes [h]
    p.SOC_min         = 0.20;   % reserve minimum SOC (battery protection)
    p.SOC_max         = 0.95;   % maximum SOC (battery protection)
    p.SOC_init        = 0.55;   % initial SOC at simulation start
    p.E_bess_cap      = 800000; % usable battery energy capacity [kWh] (800 MWh)
    p.P_bess_ch_max   = 200000; % maximum battery charge power [kW] (200 MW)
    p.P_bess_dis_max  = 200000; % maximum battery discharge power [kW] (200 MW)
    p.eta_ch          = 0.97;   % charge efficiency
    p.eta_dis         = 0.97;   % discharge efficiency (round-trip ~0.94)

    %% Synthetic 24 h profile, sampled at p.dt_h resolution
    t_h = (0:p.dt_h:24-p.dt_h)';   % hour-of-day vector, one full day
    n   = numel(t_h);

    % --- PV output ---
    % Clear-sky bell curve between sunrise (06:00) and sunset (18:00),
    % scaled to a rated array output, with a few short cloud-transient
    % dips added to exercise the peak-shaving / variability response.
    P_pv_rated = 400000;                   % rated PV array output [kW] (400 MW)
    sunrise = 6; sunset = 18;
    daylight = (t_h > sunrise) & (t_h < sunset);
    P_pv = zeros(n, 1);
    P_pv(daylight) = P_pv_rated * sin(pi * (t_h(daylight) - sunrise) / (sunset - sunrise)).^1.2;

    % Deterministic "cloud" dips (fixed, so results are reproducible
    % without relying on a particular random-seed implementation across
    % MATLAB/Octave): brief multiplicative reductions around midday.
    cloud_centres = [10.5, 12.0, 13.75, 15.25];  % hour-of-day
    cloud_widths  = [0.15, 0.25, 0.10, 0.20];    % hours
    cloud_depths  = [0.45, 0.70, 0.30, 0.55];    % fraction removed at peak
    for k = 1:numel(cloud_centres)
        dip = cloud_depths(k) * exp(-((t_h - cloud_centres(k)) / cloud_widths(k)).^2);
        P_pv = P_pv .* (1 - dip);
    end
    P_pv = max(P_pv, 0);

    % --- Data centre load (critical, non-sheddable) ---
    % Near-constant baseload typical of continuously-running IT/cooling
    % equipment, with small quasi-random fluctuation.
    P_dc_base = 200000;                    % [kW] (200 MW)
    dc_ripple = 8000 * sin(2*pi*t_h/1.7 + 0.4) + 4000 * sin(2*pi*t_h/0.6);
    P_dc = P_dc_base + dc_ripple;

    % --- Residential load (sheddable) ---
    % Typical double-peak diurnal shape: morning peak, evening peak,
    % overnight trough.
    P_res_base   = 20000;                  % overnight base [kW]
    morning_peak = 33333 * exp(-((t_h - 7.5)  / 1.2).^2);
    evening_peak = 73333 * exp(-((t_h - 19.0) / 1.8).^2);
    P_res = P_res_base + morning_peak + evening_peak;

    profile.t_h  = t_h;
    profile.P_pv = P_pv;
    profile.P_dc = P_dc;
    profile.P_res = P_res;
end
