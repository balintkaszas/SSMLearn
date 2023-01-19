function [RDInfo,R,iT,N,T] = IMDynamicsMapFractional(etaData,varargin)
% [RDInfo,R,iT,N,T] = IMDynamicsMapFractional(etaData)
% Identification of the reduced dynamics in k coordinates, i.e. the map
%
%                        x_{k+1} = R(x_k)
%
% via a weighted ridge regression. R(x) = W_r * phi(x) where phi is a
% k-variate polynomial from order 1 to order M. Cross-validation can be
% performed on random folds or on the trajectories.
% Upon request, the dynamics is returned via a coordinate change, i.e.
%
%                         R = T o N o iT
%
% where iT, T and N depend on the selected style.
% If the style is selected as modal, then the coordinate change is a linear
% map that transforms the linear part of R into the diagonal matrix of its
% eigenvalues.
% If the style is selected as normalform, then the functions seeks from
% data the maps iT, N and T such that the dynamics N is in normal form.
% This option is only available for purely oscillatory dynamics (i.e., the
% eigenvalues of the linear part of R are complex conjugated only). The
% normal form is detected by evaluating the small denominators that would
% occur when computing analytically the normal form from the knowledge of
% the vector field. These small denominators occur when the real part of
% the eigenvalues of the linear part of R is small or resonant. With small,
% it is intended to be smaller then a user-defined tolerance. To overcome
% tolerance-based issues, the user can enforce the detection of the
% coefficients of the normal form of the equivalent center manifold reduced
% order model, specifying eventual resonances among the frequencies.
%
% OUTPUTS
% R  - time-stepping map in the given coordinates of etaData
% iT - transformation from the coordinates of etaData to normal form ones
% N  - time-stepping map in the normal form coordinates
% T  - transformation from the normal form coordinates to those of etaData
% Maps_info - struct containing the information of all these mapings
%
% INPUTS
% etaData - cell array of dimension (N_traj,2) where the first column
%          contains time instances (1 x mi each) and the second column the
%          trajectories (k x mi each). Sampling time is assumed to be
%          constant
%  varargin = polynomial order of R
%     or
%  varargin = options list: 'field1', value1, 'field2', value2, ... . The
%             options fields and their default values are:
%     'c1' - error coefficient for slow manifolds weighting
%           (1+c1*exp(-c2*t)).^(-1), default 0
%     'c2' - error coefficient for slow manifolds weighting
%           (1+c1*exp(-c2*t)).^(-1), default 0
% 'l_vals' - regularizer values for the ridge regression, default 0
% 'n_folds'- number of folds for the cross validation, default 0
% 'fold_style' - either 'default' or 'traj'. The former set random folds
%               while the latter exclude 1 trajectory at time for the cross
%               validation
% 'style' - default, modal or normalform
% 'nf_style' - 'center_mfld' or 'actual eigs'
% 'tol_nf' - parameter for the tolerance in the detection of small
%            denominators in the normal form. The tolreance is set to be
%            max(abs(Eig(R)))*(1-exp(-tol_nf*max(abs(real(log(eig(R))))))).
%            Default value for tol_nf is 10
% 'frequencies_norm' - expected frequencies ratios (e.g. [1 2]) for 1:2
%                      resonance with the first and the second frequencies,
%                      by the default the code uses the actual values of
%                      of the frequencies. This option only works with the
%                      normal form style center manifold
% 'IC_nf' - initial condition for the optimization in the normal form.
%           0 (default): zero initial condition;
%           1: initial estimate based on the coefficients of R
%           2: normally distributed with the variance of case 1
% 'rescale' - rescale for the modal coordinates.
%           0: no rescale
%           1 (default): the maximum amplitude is 0.5 (ratios kept)
%           2: the maximum amplitude of all coordinates is 0.5
% 'fig_disp_nf' - display of the normal form.
%               0:  command line only
%               r:  LaTex-style figure with r terms per row (default 1).
%                   Command line also appears if the LaTex string is too
%                   long
%               -r: both command line and LaTex-style figure with r terms
%                   per row.
% 'Display' - default 'iter'
% 'OptimalityTolerance' - default 1e-4 times the number of datapoints
% 'MaxIter' - default 3e2
% 'MaxFunctionEvaluations' - default 1e4
% 'SpecifyObjectiveGradient' - default true
%     the last five options are for Matlab function fminunc.
%     For more information, check out its documentation.

if rem(length(varargin),2) > 0 && length(varargin) > 1
    error('Error on input arguments. Missing or extra arguments.')
end

% Reshape of trajectories into matrices
t   = []; % time values
X   = []; % coordinates at time k
X_1 = []; % coordinates at time k + 1
ind_traj = cell(1,size(etaData,1)); idx_end = 0;
for ii = 1:size(etaData,1)
    t_i = etaData{ii,1}; X_i = etaData{ii,2};
    t = [t t_i(1:end-1)]; X = [X X_i(:,1:end-1)]; X_1 = [X_1 X_i(:,2:end)];
    ind_traj{ii} = idx_end+[1:length(t_i)]; idx_end = length(t);
end
Dt = t(2)-t(1);
options = IMdynamics_options(nargin,varargin,ind_traj,size(X,2));
% Phase space dimension & Error Weghting
k = size(X_i,1); L2 = (1+options.c1*exp(-options.c2*t)).^(-2);
options = setfield(options,'L2',L2);

% Construct phi and its derivatives
% pass the precomputed powers to the multivariateFractionalPolyinomial.
% Only single valued case is implemented in this case. Defaults to
% multivariate integer polynomials if options.powers is empty. 
[phi,Expmat] = multivariateFractionalPolynomial(k,1,options.R_PolyOrd, options.powers);

if isempty(options.R_coeff) == 1
    disp('Estimation of the reduced dynamics... ')
    [W_r,l_opt,Err] = ridgeRegression(phi(X),X_1,options.L2,...
        options.idx_folds,options.l_vals);
else
    W_r =  options.R_coeff; l_opt = 0; Err = 0;
end
R = @(x) W_r*phi(x);
R_info = assembleStruct(R,W_r,phi,Expmat,l_opt,Err);
options.l = l_opt;
fprintf('\b Done. \n')
[V,D,d_cont] = eigSorted(W_r(:,1:k),Dt);
% Find the change of coordinates desired
switch options.style
    case 'modal'
        % Linear transformation
        iT = @(x) V\x; T = @(y) V*y;
        iT_info = assembleStruct(iT,inv(V),@(x) x,eye(k));
        T_info = assembleStruct(T,V,@(y) y,eye(k));
        % Nonlinear modal dynamics coefficients
        V_M = multivariatePolynomialLinTransf(V,k,options.R_PolyOrd);
        W_n = V\W_r*V_M; N = @(y) V\(W_r*phi(V*y));
        N_info = assembleStruct(N,W_n,phi,Expmat);
    case 'normalform'
        disp('Normal form style not implemented.');
    otherwise
        T = @(x) x; iT=@(y) y; N =@(y) R(y);
        T_info = assembleStruct(@(x) x,eye(k),@(x) x,eye(k));
        iT_info = T_info; N_info = R_info;
end
RDInfo = struct('reducedDynamics',R_info,'inverseTransformation',...
             iT_info,'conjugateDynamics',N_info,'transformation',T_info,...
             'conjugacyStyle',options.style,'dynamicsType','map',...
             'mapTimeStep',Dt,'eigenvaluesLinPartMap',diag(D),...
             'eigenvaluesLinPartFlow',d_cont,'eigenvectorsLinPart',V);
end

%---------------------------Subfunctions-----------------------------------

function str_out = assembleStruct(fun,W,phi,Emat,varargin)
PolyOrder = sum(Emat(end,:));
if isempty(varargin) == 0
    str_out = struct('map',fun,'coefficients',W,'polynomialOrder',...
    PolyOrder,'phi',phi,'exponents',Emat,'l_opt',varargin{1},...
    'CV_error',varargin{2});
else
   str_out = struct('map',fun,'coefficients',W,'polynomialOrder',...
                    PolyOrder,'phi',phi,'exponents',Emat);    
end
end

%- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

% Default options

function options = IMdynamics_options(nargin_o,varargin_o,idx_traj,Ndata)
options = struct('Style','default','R_PolyOrd', 1,'iT_PolyOrd',1,...
    'N_PolyOrd',1,'T_PolyOrd',1,'c1',0,'c2',0,...
    'L2',[],'n_folds',0,'l_vals',0,'idx_folds',[],'fold_style',[],...
    'style','none','nf_style','center_mfld','frequencies_norm',[],...
    'tol_nf',1e1,'R_coeff',[],'IC_nf',0,'rescale',1,'fig_disp_nf',1,...
    'Display','iter',...
    'OptimalityTolerance',10^(-4-floor(log10(Ndata))),...
    'MaxIter',300,...
    'MaxFunctionEvaluations',1000,...
    'SpecifyObjectiveGradient',true,...
    'powers', []);
% Default case
if nargin_o == 2; options.R_PolyOrd = varargin_o{:};
    options.N_PolyOrd = varargin_o{:}; end
% Custom options
if nargin_o > 2
    for ii = 1:length(varargin_o)/2
        options = setfield(options,varargin_o{2*ii-1},...
            varargin_o{2*ii});
    end
    % Some default options for polynomial degree
    if strcmp(options.style,'normalform')==1 && ...
            options.iT_PolyOrd*options.N_PolyOrd*options.T_PolyOrd == 1
        options.N_PolyOrd = options.R_PolyOrd;
    end
    if strcmp(options.style,'normalform')==1 && options.N_PolyOrd > 1
        if options.T_PolyOrd*options.T_PolyOrd == 1
            options.T_PolyOrd = options.N_PolyOrd;
            options.iT_PolyOrd = options.N_PolyOrd;
        else
            PolyOrdM = max([options.T_PolyOrd options.iT_PolyOrd]);
            options.T_PolyOrd = PolyOrdM;
            options.iT_PolyOrd = PolyOrdM;
        end
    end
    % Fold indexes
    if options.n_folds > 1
        if strcmp(options.fold_style,'traj') == 1
            options = setfield(options,'n_folds',length(idx_traj));
            idx_folds = idx_traj;
        else
            idx_folds = cell(options.n_folds,1);
            ind_perm = randperm(Ndata);
            fold_size = floor(Ndata/options.n_folds);
            for ii = 1:options.n_folds-1
                idx_folds{ii} = ind_perm(1+(ii-1)*fold_size:ii*fold_size);
            end
            ii = ii+1;
            idx_folds{ii} = ind_perm(1+(ii-1)*fold_size:length(ind_perm));
        end
        options = setfield(options,'idx_folds',idx_folds);
    end
end
end

