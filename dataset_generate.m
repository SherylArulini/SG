clear all; close all; clc; 
%% Master Dataset Generator for Nalanchira Project
num_simulations = 2; % Change to 1000 for final run
model_name = 'Nalanchira_RMU_';

% Load model into memory
load_system(model_name);
set_param(model_name, 'Dirty', 'off');

All_Results = cell(num_simulations, 1); 
h = waitbar(0, 'Initializing Simulations...');

% Define the Mapping (Index 1-15 maps to these Location IDs)
temp_map = [101, 101, 102, 102, 103, 104, 104, 105, 106, 107, 108, 109, 110, 111, 112];

for i = 1:num_simulations
    % 1. Randomize parameters
    current_fault_id = randi([1, 15]);
    current_start    = 0.3 + (0.4 * rand); 
    current_duration = 0.3 + (0.1 * rand); 
    
    % 2. Configure Simulation Input
    simIn = Simulink.SimulationInput(model_name);
    simIn = simIn.setModelParameter('StopTime', '1');
    
    % Inject variables into Constant Blocks
    simIn = simIn.setVariable('cfg_fault_id', current_fault_id);
    simIn = simIn.setVariable('cfg_start', current_start);
    simIn = simIn.setVariable('cfg_duration', current_duration);
    
    % 3. Run Simulation
    try
        simOut = sim(simIn); 
        
        % 4. Fix Dimension Mismatch & Assign Dynamic Location
        num_pts = length(simOut.Va_grid1);
        
        % Get the specific location for this fault ID
        current_location = temp_map(current_fault_id);
        
        % Create columns that match waveform length
        f_type_col = ones(num_pts, 1) * current_fault_id;
        f_loc_col  = ones(num_pts, 1) * current_location; % <--- FIXED HERE
        
        % Combine Waveforms + Labels
        temp_matrix = [ ...
            simOut.Va_grid1, simOut.Vb_grid1, simOut.Vc_grid1, simOut.Ia_grid1, simOut.Ib_grid1, simOut.Ic_grid1, ...
            simOut.Va_grid2, simOut.Vb_grid2, simOut.Vc_grid2, simOut.Ia_grid2, simOut.Ib_grid2, simOut.Ic_grid2, ...
            simOut.Va_hos,   simOut.Vb_hos,   simOut.Vc_hos,   simOut.Ia_hos,   simOut.Ib_hos,   simOut.Ic_hos, ...
            simOut.Va_res,   simOut.Vb_res,   simOut.Vc_res,   simOut.Ia_res,   simOut.Ib_res,   simOut.Ic_res, ...
            f_type_col, f_loc_col];
        
        All_Results{i} = temp_matrix;
        
    catch ME
        fprintf('Sim %d failed: %s\n', i, ME.message);
    end
    
    waitbar(i/num_simulations, h, sprintf('Simulation %d of %d...', i, num_simulations));
end
close(h);

%% 5. Save Data
All_Data = cell2mat(All_Results); 
if ~isempty(All_Data)
    Column_Names = { ...
        'Va_G1','Vb_G1','Vc_G1','Ia_G1','Ib_G1','Ic_G1', ...
        'Va_G2','Vb_G2','Vc_G2','Ia_G2','Ib_G2','Ic_G2', ...
        'Va_Hos','Vb_Hos','Vc_Hos','Ia_Hos','Ib_Hos','Ic_Hos', ...
        'Va_Res','Vb_Res','Vc_Res','Ia_Res','Ib_Res','Ic_Res', ...
        'Fault_Type','Location'};
        
    ANN_Table = array2table(All_Data, 'VariableNames', Column_Names);
    writetable(ANN_Table, 'Nalanchira_Dataset.csv');
    save('Nalanchira_Dataset.mat', 'ANN_Table');
    disp('Success! Dataset shows varied Locations.');
end