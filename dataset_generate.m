clear all; close all; clc;

%% Master Dataset Generator for Nalanchira Project

num_simulations = 1000;

model_name = 'Nalanchira_RMU_';

load_system(model_name); % Load model into memory without opening window

All_Data = [];

h = waitbar(0, 'Initializing Simulations...');

for i = 1:num_simulations

% 1. Randomize parameters

current_fault_id = randi([1, 15]);

current_start = 0.05 + (0.1 * rand);

current_duration = 0.05 + (0.03 * rand);


% 2. Configure Simulation Input

simIn = Simulink.SimulationInput(model_name);


% Set the StopTime inside the simIn object

simIn = simIn.setModelParameter('StopTime', '1');


% Inject the variables

simIn = simIn.setVariable('cfg_fault_id', current_fault_id);

simIn = simIn.setVariable('cfg_start', current_start);

simIn = simIn.setVariable('cfg_duration', current_duration);


% 3. Run Simulation (Note: only simIn is passed now)

simOut = sim(simIn);


% 4. Extract data (Assuming your Outport/Logging names match these)

temp_matrix = [ ...

simOut.Va_grid1, simOut.Vb_grid1, simOut.Vc_grid1, simOut.Ia_grid1, simOut.Ib_grid1, simOut.Ic_grid1, ...

simOut.Va_grid2, simOut.Vb_grid2, simOut.Vc_grid2, simOut.Ia_grid2, simOut.Ib_grid2, simOut.Ic_grid2, ...

simOut.Va_hos, simOut.Vb_hos, simOut.Vc_hos, simOut.Ia_hos, simOut.Ib_hos, simOut.Ic_hos, ...

simOut.Va_res, simOut.Vb_res, simOut.Vc_res, simOut.Ia_res, simOut.Ib_res, simOut.Ic_res, ...

simOut.Fault_Type, simOut.Fault_Location];


All_Data = [All_Data; temp_matrix];


% Progress update

if mod(i, 5) == 0

waitbar(i/num_simulations, h, sprintf('Simulation %d of %d complete...', i, num_simulations));

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

ANN_Table = array2table(All_Data, 'VariableNames', Column_Names);

save('Nalanchira_MultiNode_1000.mat', 'ANN_Table');

writetable(ANN_Table, 'Nalanchira_MultiNode_Dataset.csv');

disp('Success! 1000 unique fault scenarios captured.');