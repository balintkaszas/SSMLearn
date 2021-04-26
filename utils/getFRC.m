function FRC_data = getFRC(M, C, K, fnl, fext, outdof, omegaRange, orders)
% Use SSMTool to extract forced response curves from a dynamical system. 
% fext is a vector containing the periodic forcing
% outdof is the index of the plotted degree of freedom
% orders is a scalar/vector of the degree of Taylor expansions to be plotted

SSMOrder = 17;
[DS, S, ~] = getSSM(M, C, K, fnl, 2, SSMOrder);

epsilon = 1;
kappas = [-1; 1];


set(S.Options, 'reltol', 1, 'IRtol', 0.02, 'notation', 'multiindex', 'contribNonAuto', true)
set(S.FRCOptions, 'nt', 2^7, 'nRho', 400, 'nPar', 400, 'nPsi', 400, 'rhoScale', 2)
set(S.FRCOptions, 'method', 'continuation ep', 'z0', 1e-4*[1; 1]) % 'level set' 
set(S.FRCOptions, 'outdof', outdof,'nCycle',300)

coeffs = [fext fext]/2;
DS.add_forcing(coeffs, kappas, epsilon);
FRC = S.extract_FRC('freq', omegaRange, orders);

FRC_data = struct('Freq',[FRC.Omega],'Amp',[FRC.Aout],'Nf_Amp',...
                       [FRC.rho],'Nf_Phs',[FRC.th],'Stab',[FRC.stability]);
end