function [adjusted_params, fit_results] = interactiveParameterAdjustment(data_V, data_JD, initial_params, config)
   % Ensure required folders are on the path
    scriptDir = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(scriptDir, 'io')));
    addpath(genpath(fullfile(scriptDir, 'model')));
    addpath(genpath(fullfile(scriptDir, 'plots')));
    addpath(genpath(fullfile(scriptDir, 'utils')));
    addpath(genpath(fullfile(scriptDir, 'fit')));
    
    % 复制初始参数
    adjusted_params = initial_params;
    adjustment_factor = 1.0;
    
    % 确保初始参数物理合理性
    if adjusted_params(2) <= 0  % Rs必须为正
        fprintf('警告: 初始Rs为负值或零，已自动调整为正值\n');
        adjusted_params(2) = 10; % 使用一个合理的默认值
    end
    
    % 计算初始拟合和误差
    %fit_results.JD = diodeModel(data_V, adjusted_params, config);
    currents = calculateCurrents(data_V, adjusted_params, config);
    fit_results.JD = currents.total;
    errors = abs((fit_results.JD - data_JD) ./ (abs(data_JD) + eps)) * 100;
    nz_idx = data_V ~= 0;
    avg_error = mean(errors(nz_idx));

    % 创建实时更新的图表 - 拟合结果与误差分开显示
    fitFig = figure('Name','拟合结果','Position',[100 100 600 600]);
    errFig = figure('Name','误差分析','Position',[750 100 600 400]);

    % 定义颜色并绘制初始拟合结果
    figure(fitFig);
    c_data   = [107,174,214]/255; % #6BAED6
    c_total  = [251,106, 74]/255; % #FB6A4A
    c_ohmic  = [144,186, 72]/255; % #90BA48
    c_diode  = [ 19,106,238]/255; % #136AEE
    c_tunnel = [172,209,230]/255; % #ACD1E6
    c_nonohm = [223, 66,227]/255; % #DF42E3

    h_data = semilogy(data_V, abs(data_JD), 'o', 'Color', c_data, 'DisplayName', '测量数据');
    hold on;
    h_fit = semilogy(data_V, abs(currents.total), 'o', 'Color', c_total, 'DisplayName', '拟合结果');
    h_diode = semilogy(data_V, abs(currents.diode), '--', 'Color', c_diode, 'DisplayName', '二极管电流');
    h_tunnel = semilogy(data_V, abs(currents.tunnel), '--', 'Color', c_tunnel, 'DisplayName', '隧穿电流');
    h_ohmic = semilogy(data_V, abs(currents.ohmic), '--', 'Color', c_ohmic, 'DisplayName', '欧姆电流');
    h_nonohmic = semilogy(data_V, abs(currents.nonohmic), '--', 'Color', c_nonohm, 'DisplayName', '非欧姆电流');
   xlim([-0.5 0.3]);
    ylim([1e-11 1e-3]);
    axis square;
    xlabel('电压 (V)');
    ylabel('电流密度 (A)');
    title('电流-电压特性 (对数尺度)');
    legend('Location', 'best');
    grid on;
    
    figure(errFig);
    error_idx = data_V ~= 0;  % 误差计算时忽略零电压点
    h_error = bar(data_V(error_idx), errors(error_idx));
    xlabel('电压 (V)');
    ylabel('相对误差 (%)');
    title(sprintf('拟合误差 (平均: %.2f%%)', avg_error));
    xlim([-0.5 0.3]);
    grid on;
    
    % 在拟合图中显示当前参数值
    set(0,'CurrentFigure',fitFig);
    annotation('textbox', [0.01, 0.01, 0.98, 0.08], ...
        'String', sprintf('J01: %.2e A   Rs: %.2e Ohm   Rsh: %.2e Ohm   k: %.2e   J02: %.2e A   调整步长: %.2f', ...
        adjusted_params(1), adjusted_params(2), adjusted_params(3), adjusted_params(4), adjusted_params(5), adjustment_factor), ...
        'EdgeColor', 'none', 'FontSize', 10, 'HorizontalAlignment', 'center');
    
    % 持续调整直到用户满意
    while true
        % 显示调整选项
        fprintf('\n当前参数: J01=%.2e, Rs=%.2e, Rsh=%.2e, k=%.2e, J02=%.2e\n', ...
            adjusted_params(1), adjusted_params(2), adjusted_params(3), adjusted_params(4), adjusted_params(5));
        fprintf('平均相对误差: %.2f%%\n', avg_error);
        fprintf('\n参数调整选项:\n');
        fprintf('1: 增加 J01 2: 减少 J01\n');
        fprintf('3: 增加 Rs   4: 减少 Rs\n');
        fprintf('5: 增加 Rsh  6: 减少 Rsh\n');
        fprintf('7: 增加 k    8: 减少 k\n');
        fprintf('9: 增加 J02 10: 减少 J02\n');
        fprintf('11: 更改调整步长 (当前: %.2f)\n', adjustment_factor);
        fprintf('0: 结束调整并保存结果\n');
        
        % 获取用户输入并确保是数值类型
        choice_str = input('请选择操作 (0-11): ', 's');
        choice = str2double(choice_str);
        
        % 检查是否为有效数字输入
        if isnan(choice)
            fprintf('请输入有效的数字(0-9)\n');
            continue;
        end
        
        if choice == 0
            % Compute currents with the final parameters before saving
            currents = calculateCurrents(data_V, adjusted_params, config);
            fit_results.JD = currents.total;
            % Save results and optionally the adjusted parameters
            saveResults(data_V, data_JD, adjusted_params, fit_results, currents);
            saveAdjustedParameters(adjusted_params);
            break;
        elseif choice == 11
            % 调整步长
            new_factor_str = input(sprintf('输入新的调整步长 (当前: %.2f): ', adjustment_factor), 's');
            new_factor = str2double(new_factor_str);
            if ~isnan(new_factor) && new_factor > 0
                adjustment_factor = new_factor;
            else
                fprintf('输入无效，保持当前步长: %.2f\n', adjustment_factor);
            end
            continue;
        elseif choice >= 1 && choice <= 10
            % 确定要调整的参数索引
            param_idx = ceil(choice / 2);
            
            % 确定调整方向
            if mod(choice, 2) == 1
                direction = 1;
            else
                direction = -1;
            end
            
            % 计算调整量
            delta = adjusted_params(param_idx) * 0.1 * adjustment_factor * direction;
            
            % 更新参数
            adjusted_params(param_idx) = adjusted_params(param_idx) + delta;
            
            % 确保参数在合理范围内
            if param_idx == 1 % J0
                adjusted_params(param_idx) = max(1e-12, adjusted_params(param_idx));
            elseif param_idx == 2 % Rs - 特别强调必须为正值
                adjusted_params(param_idx) = max(1, adjusted_params(param_idx));
                if adjusted_params(param_idx) <= 0
                    fprintf('警告: Rs不能为负值或零。已调整为正值。\n');
                    adjusted_params(param_idx) = 1; % 确保为正值
                end
            elseif param_idx == 3 % Rsh
                adjusted_params(param_idx) = max(1e4, adjusted_params(param_idx));
            elseif param_idx == 4 % k
                adjusted_params(param_idx) = max(1e-10, adjusted_params(param_idx));
            elseif param_idx == 5 % J02
                adjusted_params(param_idx) = min(max(1e-12, adjusted_params(param_idx)), 1e-3);
            end
            
            % 重新计算拟合和误差
            %fit_results.JD = diodeModel(data_V, adjusted_params, config);
            currents = calculateCurrents(data_V, adjusted_params, config);
            fit_results.JD = currents.total;
            errors = abs((fit_results.JD - data_JD) ./ (abs(data_JD) + eps)) * 100;
            
            avg_error = mean(errors(nz_idx));

            % 更新图表
            set(0,'CurrentFigure',fitFig);
            set(h_fit, 'YData', abs(currents.total));
            set(h_diode, 'YData', abs(currents.diode));
            set(h_tunnel, 'YData', abs(currents.tunnel));
            set(h_ohmic, 'YData', abs(currents.ohmic));
            xlim([-0.5 0.3]);
            ylim([1e-11 1e-3]);
            axis square;
            delete(findall(gcf, 'Type', 'annotation'));
            annotation('textbox', [0.01, 0.01, 0.98, 0.08], ...
                'String', sprintf('J01: %.2e A   Rs: %.2e Ohm   Rsh: %.2e Ohm   k: %.2e   J02: %.2e A   调整步长: %.2f', ...
                adjusted_params(1), adjusted_params(2), adjusted_params(3), adjusted_params(4), adjusted_params(5), adjustment_factor), ...
                'EdgeColor', 'none', 'FontSize', 10, 'HorizontalAlignment', 'center');
                
            set(0,'CurrentFigure',errFig);
            set(h_error, 'YData', errors(error_idx));
            title(sprintf('拟合误差 (平均: %.2f%%)', avg_error));
            xlim([-0.5 0.3]);
            drawnow;
        else
            fprintf('无效的选择，请输入0-11之间的数字\n');
        end
    end
    
    
    % 计算最终拟合结果
    %fit_results.JD = diodeModel(data_V, adjusted_params, config);
    final_currents = calculateCurrents(data_V, adjusted_params, config);
    fit_results.JD = final_currents.total;
    fit_results.resnorm = sum(((fit_results.JD - data_JD) ./ (abs(data_JD) + eps)).^2);
end
