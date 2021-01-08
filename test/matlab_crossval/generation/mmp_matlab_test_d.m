%%% PSEUDO-CODE OVERVIEW OF MESSAGE PASSING SCHEME USED IN SPM_MDP_VB_X.m
clear all; close all; clc;

cd .. % this brings you into the 'pymdp/tests/matlab_crossval/' super directory, since this file should be stored in 'pymdp/tests/matlab_crossval/generation'

rng(16); % ensure the saved output file for inferactively is always the same
%% VARIABLE NAMES

T = 10; % total length of time (generative process horizon)
window_len = 5; % length of inference window (in the past)
policy_horizon = 1; % temporal horizon of policies
num_iter = 5; % number of variational iterations
num_states = [2, 2]; % hidden state dimensionalities
num_factors = length(num_states); % number of hidden state factors
num_obs = [3, 2];   % observation modality dimensionalities
num_modalities = length(num_obs); % number of hidden state factors
num_actions = [2, 2]; % control factor (action) dimensionalities
num_control = length(num_actions);

qs_ppd = cell(1, num_factors); % variable to store posterior predictive density for current timestep. cell array of length num_factors, where each qs_ppd{f} is the PPD for a given factor (length [num_states(f), 1])
qs_bma = cell(1, num_factors); % variable to store bayesian model average for current timestep. cell array of length num_factors, where each xq{f} is the BMA for a given factor (length [num_states(f), 1])

states = zeros(num_factors,T); % matrix of true hidden states (separated by factor and timepoint) -- size(states) == [num_factors, T]
for f = 1:num_factors
    states(f,1) = randi(num_states(f));
end

actions = zeros(num_control, T); % history of actions along each control state factor and timestep -- size(actions) == [num_factors, T]
obs = zeros(num_modalities,T); % history of observations (separated by modality and timepoint) -- size (obs) == [num_modalities, T]
vector_obs = cell(num_modalities,T); % history of observations expressed as one-hot vectors

policy_matrix = zeros(policy_horizon, 1, num_control); % matrix of policies expressed in terms of time points, actions, and hidden state factors. size(policies) ==  [policy_horizon, num_policies, num_factors]. 
                                                                  % This gets updated over time with the actual actions/policies taken in the past
                                                                  
U = zeros(1,1,num_factors); % matrix of allowable actions per policy at each move. size(U) == [1, num_policies, num_factors]

U(1,1,:) = [1, 1];

policy_matrix(1,:,:) = U;

% likelihoods and priors

A = cell(1,num_modalities); % generative process observation likelihood (cell array of length num_modalities -- each A{g} is a matrix of size [num_modalities(g), num_states(:)]
B = cell(1,num_factors); % generative process transition likelihood (cell array of length num_factors -- each B{f} is a matrix of size [num_states(f), num_states(f), num_actions(f)]
C = cell(1,num_modalities);
for g= 1:num_modalities
    C{g} = rand(num_obs(g),T);
end

D = cell(1,num_factors); % prior over hidden states -- a cell array of size [1, num_factors] where each D{f} is a vector of length [num_states(f), 1]
for f = 1:num_factors
    D{f} = ones(num_states(f),1)/num_states(f);
end


for g = 1:num_modalities
    A{g} = spm_norm(rand([num_obs(g),num_states]));
end

a = A; % generative model == generative process


for f = 1:num_factors
    B{f} = spm_norm(rand(num_states(f), num_states(f), num_actions(f)));
end


b = B; % generative model transition likelihood (cell array of length num_factors -- each b{f} is a matrix of size [num_states(f), num_states(f), num_actions(f)]
b_t = cell(1,num_factors);

for f = 1:num_factors
    for u = 1:num_actions(f)
        b_t{f}(:,:,u) = spm_norm(b{f}(:,:,u)');% transpose of generative model transition likelihood
    end
end

%% INITIALIZATION of beliefs

% initialise different posterior beliefs used in message passing
for f = 1:num_factors
    
    xn{f} = zeros(num_iter,num_states(f),window_len,T,1);
    
    vn{f} = zeros(num_iter,num_states(f),window_len,T,1);
    
    x{f}  = zeros(num_states(f),T,1) + 1/num_states(f);    
    qs_ppd{f}  = zeros(num_states(f), T, 1)      + 1/num_states(f);
    
    qs_bma{f}  = repmat(D{f},1,T);

    x{f}(:,1,1) = D{f};
    qs_ppd{f}(:,1,1) = D{f};
    
end

%%
for t = 1:T
    
    
    % posterior predictive density over hidden (external) states
    %--------------------------------------------------------------
    for f = 1:num_factors       
        % Bayesian model average (xq)
        %----------------------------------------------------------
        xq{f} =  qs_bma{f}(:,t);       
    end
    
    % sample state, if not specified
    %--------------------------------------------------------------
    for f = 1:num_factors

        % the next state is generated by action on external states
        %----------------------------------------------------------

        if t > 1
            ps = B{f}(:,states(f,t - 1),actions(f,t - 1));
        else
            ps =  D{f};
        end
        states(f,t) = find(rand < cumsum(ps),1);

    end
    
    % sample observations, if not specified
    %--------------------------------------------------------------
    for g = 1:num_modalities
        
        % if observation is not given
        %----------------------------------------------------------
        if ~obs(g,t)
            
            % sample from likelihood given hidden state
            %--------------------------------------------------
            ind           = num2cell(states(:,t));
            p_obs            = A{g}(:,ind{:}); % gets the probability over observations, under the current hidden state configuration
            obs(g,t) = find(rand < cumsum(p_obs),1);
            vector_obs{g,t} = sparse(obs(g,t),1,1,num_obs(g),1);
        end
    end
    
    % Likelihood of observation under the various configurations of hidden states
    %==================================================================
    L{t} = 1;
    for g = 1:num_modalities
        L{t} = L{t}.*spm_dot(a{g},vector_obs{g,t});
    end
   
    % reset
    %--------------------------------------------------------------
    for f = 1:num_factors
        x{f} = spm_softmax(spm_log(x{f})/4);
    end
    
    if t == 10
        debug_flag = true;
    end  
    
    [F, G, x, xq, vn, xn] = run_mmp(num_iter, window_len, policy_matrix, t, xq, x, L, D, b, b_t, xn, vn);
    
    if t == 10
        save_dir = 'output/mmp_d.mat';
        policy = squeeze(policy_matrix(end,1,:))';
        previous_actions = squeeze(policy_matrix(1:(end-1),1,:));
        t_horizon = window_len;
        qs = xq;
        obs_idx = obs(:,1:t);
        likelihoods = L(1:t);
        save(save_dir,'A','B','obs_idx','policy','t','t_horizon','previous_actions','qs','likelihoods')
    end

   
    % pretend you took a random action and supplement policy matrix with it
    if t < T
        for u = 1:num_control
            actions(u,t) = randi(num_actions(u));
        end
                
        if (t+1) < T
            policy_matrix(t+1,1,:) = actions(:,t);
        end
        % and re-initialise expectations about hidden states
        %------------------------------------------------------
        for f = 1:num_factors
            x{f}(:,:,1) = 1/num_states(f);
        end
    end
    
    if t == T
        obs  = obs(:,1:T);        % outcomes at 1,...,T
        states  = states(:,1:T);        % states   at 1,...,T
        actions  = actions(:,1:T - 1);    % actions  at 1,...,T - 1
        break;
    end
          
end
%%
% auxillary functions
%==========================================================================

function A  = spm_log(A)
% log of numeric array plus a small constant
%--------------------------------------------------------------------------
A  = log(A + 1e-16);
end

function A  = spm_norm(A)
% normalisation of a probability transition matrix (columns)
%--------------------------------------------------------------------------
A           = bsxfun(@rdivide,A,sum(A,1));
A(isnan(A)) = 1/size(A,1);
end

function A  = spm_wnorm(A)
% summation of a probability transition matrix (columns)
%--------------------------------------------------------------------------
A   = A + 1e-16;
A   = bsxfun(@minus,1./sum(A,1),1./A)/2;
end

function sub = spm_ind2sub(siz,ndx)
% subscripts from linear index
%--------------------------------------------------------------------------
n = numel(siz);
k = [1 cumprod(siz(1:end-1))];
for i = n:-1:1
    vi       = rem(ndx - 1,k(i)) + 1;
    vj       = (ndx - vi)/k(i) + 1;
    sub(i,1) = vj;
    ndx      = vi;
end
end

function [X] = spm_dot(X,x,i)
% Multidimensional dot (inner) product
% FORMAT [Y] = spm_dot(X,x,[DIM])
%
% X   - numeric array
% x   - cell array of numeric vectors
% DIM - dimensions to omit (asumes ndims(X) = numel(x))
%
% Y  - inner product obtained by summing the products of X and x along DIM
%
% If DIM is not specified the leading dimensions of X are omitted.
% If x is a vector the inner product is over the leading dimension of X

% initialise dimensions
%--------------------------------------------------------------------------
if iscell(x)
    DIM = (1:numel(x)) + ndims(X) - numel(x);
else
    DIM = 1;
    x   = {x};
end

% omit dimensions specified
%--------------------------------------------------------------------------
if nargin > 2
    DIM(i) = [];
    x(i)   = [];
end

% inner product using recursive summation (and bsxfun)
%--------------------------------------------------------------------------
for d = 1:numel(x)
    s         = ones(1,ndims(X));
    s(DIM(d)) = numel(x{d});
    X         = bsxfun(@times,X,reshape(full(x{d}),s));
    X         = sum(X,DIM(d));
end

% eliminate singleton dimensions
%--------------------------------------------------------------------------
X = squeeze(X);
end

function [y] = spm_softmax(x,k)
% softmax (e.g., neural transfer) function over columns
% FORMAT [y] = spm_softmax(x,k)
%
% x - numeric array array
% k - precision, sensitivity or inverse temperature (default k = 1)
%
% y  = exp(k*x)/sum(exp(k*x))
%
% NB: If supplied with a matrix this routine will return the softmax
% function over colums - so that spm_softmax([x1,x2,..]) = [1,1,...]

% apply
%--------------------------------------------------------------------------
if nargin > 1,    x = k*x; end
if size(x,1) < 2; y = ones(size(x)); return, end

% exponentiate and normalise
%--------------------------------------------------------------------------
x  = exp(bsxfun(@minus,x,max(x)));
y  = bsxfun(@rdivide,x,sum(x));
end
