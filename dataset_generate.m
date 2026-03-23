clear all; close all; clc; 

%% Master Dataset Generator for Nalanchira Project
num_simulations = 2; % Set your target count
model_name = 'Nalanchira_RMU_';

% Load model into memory without opening the window
if ~bdIsLoaded(model_name)
    load_system(model_name); 
end

All_Data = []; 
h = waitbar(0, 'Initializing Simulations...');

for i = 1:num_simulations
    % 1. Configure Simulation Input
    simIn = Simulink.SimulationInput(model_name);
    simIn = simIn.setModelParameter('StopTime', '1');
    
    % 2. Run Simulation
    % The model's Uniform Random Number blocks will trigger at t=0
    simOut = sim(simIn); 
    
    % 3. Extract data 
    % We use 'get' or check the fields to ensure the script is robust
    try
        % Extract values (assuming signals are logged as simple arrays/timeseries)
        % If simOut uses the 'logsout' format, you may need: simOut.get('Va_grid1')
        temp_matrix = [ ...
            simOut.Va_grid1, simOut.Vb_grid1, simOut.Vc_grid1, simOut.Ia_grid1, simOut.Ib_grid1, simOut.Ic_grid1, ...
            simOut.Va_grid2, simOut.Vb_grid2, simOut.Vc_grid2, simOut.Ia_grid2, simOut.Ib_grid2, simOut.Ic_grid2, ...
            simOut.Va_hos,   simOut.Vb_hos,   simOut.Vc_hos,   simOut.Ia_hos,   simOut.Ib_hos,   simOut.Ic_hos, ...
            simOut.Va_res,   simOut.Vb_res,   simOut.Vc_res,   simOut.Ia_res,   simOut.Ib_res,   simOut.Ic_res, ...
            simOut.Fault_Type, simOut.Fault_Location];
        
        % Append this simulation's data to the master matrix
        All_Data = [All_Data; temp_matrix];
        
    catch ME
        fprintf('Error in Simulation %d: %s\n', i, ME.message);
    end
    
    % 4. Progress update
    if mod(i, 10) == 0 % Update waitbar every 10 sims to save processing time
        waitbar(i/num_simulations, h, sprintf('Progress: %d / %d Simulations', i, num_simulations));
    end
end
   
close(h);

%% 5. Define Column Names and Save
Column_Names = { ...
    'Va_G1','Vb_G1','Vc_G1','Ia_G1','Ib_G1','Ic_G1', ...
    'Va_G2','Vb_G2','Vc_G2','Ia_G2','Ib_G2','Ic_G2', ...
    'Va_Hos','Vb_Hos','Vc_Hos','Ia_Hos','Ib_Hos','Ic_Hos', ...
    'Va_Res','Vb_Res','Vc_Res','Ia_Res','Ib_Res','Ic_Res', ...
    'Fault_Type','Location'};

if ~isempty(All_Data)
    ANN_Table = array2table(All_Data, 'VariableNames', Column_Names);
    save('Nalanchira_MultiNode_Final.mat', 'ANN_Table');
    writetable(ANN_Table, 'Nalanchira_MultiNode_Dataset.csv');
    fprintf('\nSuccess! %d scenarios captured.\n', size(All_Data, 1));
else
    warning('No data collected. Check Signal Logging settings in the Simulink Model.');
end