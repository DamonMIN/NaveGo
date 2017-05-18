function [fb_sim] = acc_gen (ref, imu)
% acc_gen: generates simulated accelerometers measurements from reference
%           data and imu error profile.
% INPUT:
%		ref: data structure with true trajectory.
%		imu: data structure with IMU error profile.
%
% OUTPUT:
%		fb_sim: Nx3 matrix with [fx, fy, fz] simulated accelerations in the
%		body frame.
%
%   Copyright (C) 2014, Rodrigo González, all rights reserved.
%
%   This file is part of NaveGo, an open-source MATLAB toolbox for
%   simulation of integrated navigation systems.
%
%   NaveGo is free software: you can redistribute it and/or modify
%   it under the terms of the GNU Lesser General Public License (LGPL)
%   version 3 as published by the Free Software Foundation.
%
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU Lesser General Public License for more details.
%
%   You should have received a copy of the GNU Lesser General Public
%   License along with this program. If not, see
%   <http://www.gnu.org/licenses/>.
%
% Reference:
%			R. Gonzalez, J. Giribet, and H. Patiño. NaveGo: a
% simulation framework for low-cost integrated navigation systems,
% Journal of Control Engineering and Applied Informatics, vol. 17,
% issue 2, pp. 110-120, 2015. Sec. 2.2.
%
%           Aggarwal, P. et al. MEMS-Based Integrated Navigation. Artech
% House. 2010.
%
% Version: 003
% Date:    2017/03/31
% Author:  Rodrigo Gonzalez <rodralez@frm.utn.edu.ar>
% URL:     https://github.com/rodralez/navego

M = [ref.kn, 3];
N = ref.kn;

%% SIMULATE ACC

% If true accelerations are provided...
if (isfield(ref, 'fb'))
    
    acc_b = ref.fb;
    
% If not, obtain acceleration from velocity
elseif (isfield(ref, 'vel'))
    
    acc_raw = (diff(ref.vel)) ./ [diff(ref.t) diff(ref.t) diff(ref.t)];
    acc_raw = [ 0 0 0; acc_raw; ];
    acc_ned = sgolayfilt(acc_raw, 10, 45);
    acc_b = acc_nav2body(acc_ned, ref.DCMnb);
    
% If not, obtain acceleration from position
else
    
    % Method: LLH > ECEF > NED
    [~, acc_ned] = pllh2vned (ref);
    acc_b = acc_nav2body(acc_ned, ref.DCMnb);
end

%% SIMULATE GRAVITY AND CORIOLIS

% Gravity and Coriolis in nav-ref
grav_n = gravity(ref.lat, ref.h);
cor_n = coriolis(ref.lat, ref.vel, ref.h);

% Gravity and Coriolis from nav-ref to body-ref
grav_b = zeros(M);
cor_b = zeros(M);
for i = 1:N
    dcm = reshape(ref.DCMnb(i,:), 3, 3);
    gb = dcm * grav_n(i,:)';
    corb =  dcm * cor_n(i,:)';
    grav_b(i,:) = gb';
    cor_b(i,:) = corb';
end

%% SIMULATE NOISES

% Simulate static bias
a = -imu.ab_fix;
b =  imu.ab_fix;
ab_fix = (b' - a') .* rand(3,1) + a';
o = ones(N,1);
a_sbias = [ab_fix(1).* o   ab_fix(2).* o   ab_fix(3).* o];

% Simulate white noise
wn = randn(M);
a_wn = [imu.astd(1).* wn(:,1)  imu.astd(2).* wn(:,2)  imu.astd(3).* wn(:,3)];

% Simulate bias instability/dynamic bias
dt = 1/imu.freq;

% If correlation time is provided...
if (~isinf(imu.ab_corr))
    
    % Simulate a Gauss-Markov process
    % Aggarwal, Eq. 3.33, page 57.
    a_dbias = zeros(M);    
    
    for i=1:3
        
        beta  = dt / imu.ab_corr(i) ;
        sigma = imu.ab_drift(i);
        a1 = exp(-beta);
        a2 = sigma * sqrt(1 - exp(-2*beta) );
        
        b_noise = randn(N-1,1);
        for j=2:N
            a_dbias(j, i) = a1 * a_dbias(j-1, i) + a2 .* b_noise(j-1);
        end
    end
    
% If not...
else
    sigma = imu.ab_drift;
    bn = randn(M);
    a_dbias = [sigma(1).*bn(:,1) sigma(2).*bn(:,2) sigma(3).*bn(:,3)];
    
end

fb_sim = acc_b - cor_b + grav_b + a_wn + a_sbias + a_dbias;

end
