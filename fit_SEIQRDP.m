function [alpha1,beta1,gamma1,delta1,Lambda1,Kappa1,lambdaFun,varargout] = fit_SEIQRDP(Q,R,D,Npop,E0,I0,time,guess,varargin)
% [alpha1,beta1,gamma1,delta1,Lambda1,Kappa1,lambdaFun,varargout] =
% fit_SEIQRDP(Q,R,D,Npop,E0,I0,time,guess,varargin) estimates the
% parameters used in the SEIQRDP function, used to model the time-evolution
% of an epidemic outbreak.
%
% Input
%
%   I: vector [1xN] of the target time-histories of the infectious cases
%   R: vector [1xN] of the target time-histories of the recovered cases
%   D: vector [1xN] of the target time-histories of the dead cases
%   Npop: scalar: Total population of the sample
%   E0: scalar [1x1]: Initial number of exposed cases
%   I0: scalar [1x1]: Initial number of infectious cases
%   time: vector [1xN] of time (datetime)
%   guess: first vector [1x6] guess for the fit
%   optionals
%       -tolFun: tolerance  option for optimset
%       -tolX: tolerance  option for optimset
%       -Display: Display option for optimset
%       -dt: time step for the fitting function
%
% Output
%
%   alpha: scalar [1x1]: fitted protection rate
%   beta: scalar [1x1]: fitted  infection rate
%   gamma: scalar [1x1]: fitted  Inverse of the average latent time
%   delta: scalar [1x1]: fitted  rate at which people enter in quarantine
%   lambda: scalar [1x1]: fitted  cure rate
%   kappa: scalar [1x1]: fitted  mortality rate
%   lambdaFun: anonymous function giving the time evolution of the recovery
%  rate
%   optional:
%       - residual
%       - Jacobian
%       - The function @SEIQRDP_for_fitting
%
% Author: E. Cheynet - UiB - last modified 27-04-2020
%
% see also SEIQRDP.m

%% Inputparseer
p = inputParser();
p.CaseSensitive = false;
p.addOptional('tolX',1e-5);  %  option for optimset
p.addOptional('tolFun',1e-5);  %  option for optimset
p.addOptional('Display','iter'); % Display option for optimset
p.addOptional('dt',0.1); % time step for the fitting
p.parse(varargin{:});
%%%%%%%%%%%%%%%%%%%%%%%%%%
tolX = p.Results.tolX ;
tolFun = p.Results.tolFun ;
Display  = p.Results.Display ;
dt  = p.Results.dt ;

%% Options for lsqcurvfit
options=optimset('TolX',tolX,'TolFun',tolFun,...
    'MaxFunEvals',1200,'Display',Display);
%% Initial conditions and basic checks

% Write the target input into a matrix
Q(Q<0)=0; % negative values are not possible
R(R<0)=0; % negative values are not possible
D(D<0)=0; % negative values are not possible

if isempty(R)
    warning(' No data available for "Recovered" ')
    input = [Q;D];
else
    input = [Q;R;D];
end

if size(time,1)>size(time,2) && size(time,2)==1,    time = time';end
if size(time,1)>1 && size(time,2)>1,  error('Time should be a vector');end

%% Definition of the new, refined, time vector for the numerical solution
fs = 1./dt;
tTarget = round(datenum(time-time(1))*fs)/fs; % Number of days with one decimal
t = tTarget(1):dt:tTarget(end); % oversample to ensure that the algorithm converges

%% Preliminary fitting
% Decide which function to use for lambda and get first estimate of lambda
%  Preliminary fitting for lambda to find the best approximation
%  The final fitting is done considering simulatneously the different
%  parameters since the equations are coupled

if ~isempty(R) % If there exists information on the recovered cases
    [guess,lambdaFun] = getLambdaFun(tTarget,Q,R,guess);
    [guess,kappaFun] = getKappaFun(tTarget,Q,D,guess);
else
    lambdaFun =  @(a,t) a(1)./(1+exp(-a(2)*(t-a(3)))); % default function
    kappaFun = @(a,t) a(1).*exp(-a(2).*t);
end

%% Main fitting

modelFun1 = @SEIQRDP_for_fitting; % transform a nested function into anonymous function
lambdaMax = [1 5 100]; % lambdaMax(3) has the dimension of a time
lambdaMin = [0 0 0]; % lambdaMax(3) has the dimension of a time
kappaMax = [2 2];
ub = [1, 3, 1, 1, lambdaMax, kappaMax]; % upper bound of the parameters
lb = [0, 0, 0, 0, lambdaMin, 0, 0]; % lower bound of the parameters
% call Lsqcurvefit
[Coeff,~,residual,~,~,~,jacobian] = lsqcurvefit(@(para,t) modelFun1(para,t),...
    guess,tTarget(:)',input,lb,ub,options);


%% Write the fitted coeff in the outputs
alpha1 = abs(Coeff(1));
beta1 = abs(Coeff(2));
gamma1 = abs(Coeff(3));
delta1 = abs(Coeff(4));
Lambda1 = abs(Coeff(5:7));
Kappa1 = abs(Coeff(8:9));

%% optional outputs
if nargout ==7
    varargout{1} = residual;
elseif nargout==8
    varargout{1} = residual;
    varargout{2} = jacobian;
elseif nargout==9
    varargout{1} = residual;
    varargout{2} = jacobian;
    varargout{3} = modelFun1;
elseif nargout>9
    error('Too many outputs specified')
end



%% nested functions

    function [output] = SEIQRDP_for_fitting(para,t0)
        
        % I simply rename the inputs
        alpha = abs(para(1));
        beta = abs(para(2));
        gamma = abs(para(3));
        delta = abs(para(4));
        lambda0 = abs(para(5:7));
        kappa0 = abs(para(8:9));
        
        
        %% Initial conditions
        N = numel(t);
        Y = zeros(7,N); %  There are seven different states
        Y(2,1) = E0;
        Y(3,1) = I0;
        Y(4,1) = Q(1);
        if ~isempty(R)
            Y(5,1) = R(1);
            Y(1,1) = Npop-Q(1)-R(1)-D(1)-E0-I0;
        else
            Y(1,1) = Npop-Q(1)-D(1)-E0-I0;
        end
        Y(6,1) = D(1);
        
        if round(sum(Y(:,1))-Npop)~=0
            error(['the sum must be zero because the total population',...
                ' (including the deads) is assumed constant']);
        end
        %%
        modelFun = @(Y,A,F) A*Y + F;
        lambda = lambdaFun(lambda0,t);
        kappa = kappaFun(kappa0,t);
        
        % Very large recovery rate should not occur but can lead to
        % numerical errors.
        if lambda>10, warning('lambda is abnormally high'); end
        
        % ODE resolution
        for ii=1:N-1
            A = getA(alpha,gamma,delta,lambda(ii),kappa(ii));
            SI = Y(1,ii)*Y(3,ii);
            F = zeros(7,1);
            F(1:2,1) = [-beta/Npop;beta/Npop].*SI;
            Y(:,ii+1) = RK4(modelFun,Y(:,ii),A,F,dt);
        end
        
        Q1 = Y(4,1:N);
        R1 = Y(5,1:N);
        D1 = Y(6,1:N);
        
        Q1 = interp1(t,Q1,t0);
        R1 = interp1(t,R1,t0);
        D1 = interp1(t,D1,t0);
        if ~isempty(R)
            output = [Q1;R1;D1];
        else
            output = [Q1+R1;D1];
        end
        
    end
    function [A] = getA(alpha,gamma,delta,lambda,kappa)
        %  [A] = getA(alpha,gamma,delta,lambda,kappa) computes the matrix A
        %  that is found in: dY/dt = A*Y + F
        %
        %   Inputs:
        %   alpha: scalar [1x1]: protection rate
        %   beta: scalar [1x1]: infection rate
        %   gamma: scalar [1x1]: Inverse of the average latent time
        %   delta: scalar [1x1]: rate of people entering in quarantine
        %   lambda: scalar [1x1]: cure rate
        %   kappa: scalar [1x1]: mortality rate
        %   Output:
        %   A: matrix: [7x7]
        
        A = zeros(7);
        % S
        A(1,1) = -alpha;
        % E
        A(2,2) = -gamma;
        % I
        A(3,2:3) = [gamma,-delta];
        % Q
        A(4,3:4) = [delta,-kappa-lambda];
        % R
        A(5,4) = lambda;
        % D
        A(6,4) = kappa;
        % P
        A(7,1) = alpha;
        
    end
    function [Y] = RK4(Fun,Y,A,F,dt)
        % NUmerical trick: the parameters are assumed constant between
        % two time steps.
        
        % Runge-Kutta of order 4
        k_1 = Fun(Y,A,F);
        k_2 = Fun(Y+0.5*dt*k_1,A,F);
        k_3 = Fun(Y+0.5*dt*k_2,A,F);
        k_4 = Fun(Y+k_3*dt,A,F);
        % output
        Y = Y + (1/6)*(k_1+2*k_2+2*k_3+k_4)*dt;
    end

    function [guess,kappaFun] = getKappaFun(tTarget,Q,D,guess)
        % [guess,kappaFun] = getKappaFun(tTarget,Q,D,guess) provides a first
        % estimate of the  death rate, to faciliate convergence of the main
        % algorithm.
        %
        % Input:
        %
        % tTarget: vector [1xN]: time as double
        % Q: vector [1xN] of the target time-histories of the quarantined cases
        % D: vector [1xN] of the target time-histories of the dead cases
        % guess: vector [1x9] Initial guess for kappa
        %
        % Output
        % guess: vector [1x9]  Updated intial guess
        % kappaFun: Empirical fucntion for the death rate
        
        % If less than 20 reported deceased, the death rate won't be
        % reliable. Therefore, no preliminary fitting is done.
        if max(D)<20
            kappaFun = @(a,t) a(1).*exp(-a(2).*t);
        else
            
            try
                opt=optimset('TolX',1e-6,'TolFun',1e-6,'Display','off');
                
                kappaFun = @(a,t) a(1).*exp(-a(2).*t);
                
                rate = (diff(D)./median(diff(tTarget(:))))./Q(2:end);
                x = tTarget(2:end);
                
                % A death rate larger than 3 is abnormally high. It is not
                % used for the fitting.                 
                rate(abs(rate)>3)=nan;
                [kappaGuess] = lsqcurvefit(@(para,t) kappaFun(para,t),...
                    guess(8:9),x(~isnan(rate)),rate(~isnan(rate)),[0 0],[2 2],opt);
                
                guess(8:9) = kappaGuess; % update guess
                
            catch exceptionK
                disp(exceptionK)
                kappaFun = @(a,t) a(1).*exp(-a(2).*t);
            end
            
        end
    end

    function [guess,lambdaFun] = getLambdaFun(tTarget,Q,R,guess)
        %  [guess,lambdaFun] = getLambdaFun(tTarget,Q,R,guess) provides a first
        % estimate of the  death rate, to faciliate convergence of the main
        % algorithm.
        %
        % Input:
        %
        % tTarget: vector [1xN]: time as double
        % Q: vector [1xN] of the target time-histories of the quarantined cases
        % R: vector [1xN] of the target time-histories of the recovered cases
        % guess: vector [1x9] Initial guess for kappa
        %
        % Output
        % guess: vector [1x9]  Updated intial guess
        % lambdaFun: Empirical fucntion for the recovery rate
        
        % If less than 20 reported deceased, the death rate won't be
        % reliable. Therefore, no preliminary fitting is done.
        
        % If less than 20 reported recovered, the death rate won't be
        % reliable. Therefore, no preliminary fitting is done.
        if max(R)<20
            lambdaFun =  @(a,t) a(1)./(1+exp(-a(2)*(t-a(3))));
        else
            
            try
                
                opt=optimset('TolX',1e-6,'TolFun',1e-6,'Display','off');
                
                % Two empirical functions are evaluated
                myFun1 = @(a,t) a(1)./(1+exp(-a(2)*(t-a(3))));
                myFun2 = @(a,t) a(1) + exp(-a(2)*(t+a(3)));
                
                % Compute the recovery rate from the data (noisy data)
                rate = diff(R)./median(diff(tTarget(:)))./Q(2:end);
                x = tTarget(2:end);
                
                % A daily rate larger than one is abnormally high. It is not
                % used for the fitting. A daily recovered rate of zero is
                % either abnormally low or reflects an insufficient number
                % of recovered cases. It is not used either for the fitting
                rate(abs(rate)>1|abs(rate)==0)=nan;
                
                [coeff1,r1] = lsqcurvefit(@(para,t) myFun1(para,t),...
                    [0.2,0.1,1],x(~isnan(rate)),rate(~isnan(rate)),[0 0 0],[1 2 100],opt);
                [coeff2,r2] = lsqcurvefit(@(para,t) myFun2(para,t),...
                    [0.2,0.1,min(x(~isnan(rate)))],x(~isnan(rate)),rate(~isnan(rate)),[0 0 0],[1 2 100],opt);
                
                
                % myFun1 is more stable on a long term persepective
%               % If coeff2 have reached the upper boundaries, myFUn1 is
%               chosen
                if r1<r2 || coeff2(1)>0.99 || coeff2(2)>4.9
                    lambdaGuess = coeff1;
                    lambdaFun = myFun1;
                else
                    lambdaGuess = coeff2;
                    lambdaFun = myFun2;
                end
                guess(5:7) = lambdaGuess; % update guess
                
                
            catch exceptionL
                disp(exceptionL)
                lambdaFun =  @(a,t) a(1)./(1+exp(-a(2)*(t-a(3))));
            end
        end
    end


end

