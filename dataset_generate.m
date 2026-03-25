clear all; close all; clc; 

%% Master Dataset Generator 
num_simulations = 1000; 
model_name = 'Nalanchira_RMU_';

% Load model into memory
load_system(model_name);
set_param(model_name, 'Dirty', 'off');

All_Results = cell(num_simulations, 1); 
h = waitbar(0, 'Initializing Simulations...');

% Define the Mapping (Index 1-15 maps to these Location IDs)
temp_map = [101, 101, 102, 102, 103, 104, 104, 105, 106, 107, 108, 109, 110, 111, 112];

% Define Downsampling Factor (ds = 10 means we keep 1 out of every 10 points)
% At 50us sample time, this results in a 500us effective sample rate (40 pts/cycle at 50Hz)
ds = 10;

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
        
        % 4. Data Extraction with Downsampling
        % This reduces memory usage during the loop and final file size
        temp_matrix = [ ...
            simOut.Va_grid1(1:ds:end), simOut.Vb_grid1(1:ds:end), simOut.Vc_grid1(1:ds:end), ...
            simOut.Ia_grid1(1:ds:end), simOut.Ib_grid1(1:ds:end), simOut.Ic_grid1(1:ds:end), ...
            simOut.Va_grid2(1:ds:end), simOut.Vb_grid2(1:ds:end), simOut.Vc_grid2(1:ds:end), ...
            simOut.Ia_grid2(1:ds:end), simOut.Ib_grid2(1:ds:end), simOut.Ic_grid2(1:ds:end), ...
            simOut.Va_hos(1:ds:end),   simOut.Vb_hos(1:ds:end),   simOut.Vc_hos(1:ds:end), ...
            simOut.Ia_hos(1:ds:end),   simOut.Ib_hos(1:ds:end),   simOut.Ic_hos(1:ds:end), ...
            simOut.Va_res(1:ds:end),   simOut.Vb_res(1:ds:end),   simOut.Vc_res(1:ds:end), ...
            simOut.Ia_res(1:ds:end),   simOut.Ib_res(1:ds:end),   simOut.Ic_res(1:ds:end)];
        
        num_pts = size(temp_matrix, 1);
        current_location = temp_map(current_fault_id);
        
        % Generate Labels
        f_type_col = ones(num_pts, 1) * current_fault_id;
        f_loc_col  = ones(num_pts, 1) * current_location;
        
        % Combine signals + labels and convert to SINGLE to save 50% more space
        All_Results{i} = single([temp_matrix, f_type_col, f_loc_col]);
        
    catch ME
        fprintf('Sim %d failed: %s\n', i, ME.message);
    end
    
    waitbar(i/num_simulations, h, sprintf('Progress: %d of %d simulations...', i, num_simulations));
end
close(h);

%% 5. Table Conversion and Export
% Combine all simulations into one large matrix
All_Data = cell2mat(All_Results); 

if ~isempty(All_Data)
    % Define Column Names
    Column_Names = { ...
        'Va_G1','Vb_G1','Vc_G1','Ia_G1','Ib_G1','Ic_G1', ...
        'Va_G2','Vb_G2','Vc_G2','Ia_G2','Ib_G2','Ic_G2', ...
        'Va_Hos','Vb_Hos','Vc_Hos','Ia_Hos','Ib_Hos','Ic_Hos', ...
        'Va_Res','Vb_Res','Vc_Res','Ia_Res','Ib_Res','Ic_Res', ...
        'Fault_Type','Location'};
    
    % Convert matrix to table
    ANN_Table = array2table(All_Data, 'VariableNames', Column_Names);
    
    % Save to CSV
    writetable(ANN_Table, 'Nalanchira_Master_Dataset.csv');
    
    % Save to MAT format using version 7.3 to support large files and compression
    save('Nalanchira_Master_Dataset.mat', 'ANN_Table', '-v7.3');
    
    disp('Success! Optimized Dataset generated with full headers.');
    head(ANN_Table) 
end

disp('All simulations completed successfully.');