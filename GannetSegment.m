function MRS_struct = GannetSegment(MRS_struct)

% Relies on SPM12 being installed
%
% Runs segmentation script if segmented images not present according to
% file convention of c1, c2 and c3 as prefixes on the anatomical image name
% for the GM, WM and CSF segmentations. If these files are present, they
% are loaded and used for the voxel segmentation

MRS_struct.version.segment = '200226';

warning('off'); % temporarily suppress warning messages

% First check if SPM12 is installed and on the search path
spmversion = fileparts(which('spm'));
if isempty(spmversion)
    error('SPM not found! Please install SPM12 (https://www.fil.ion.ucl.ac.uk/spm/software/spm12) and make sure it is on your search path.');
elseif strcmpi(spmversion(end-3:end),'spm8')
    error(['SPM8 detected! Gannet 3.0 no longer supports SPM8. ' ...
        'Please install SPM12 (https://www.fil.ion.ucl.ac.uk/spm/software/spm12) and make sure it is on your search path.']);
end

if MRS_struct.p.PRIAM
    vox = MRS_struct.p.Vox;
else
    vox = MRS_struct.p.Vox(1);
end

% Set up SPM for batch processing
spm('defaults','fmri');
spm_jobman('initcfg');

numscans = MRS_struct.p.numscans;

for ii = 1:numscans
    
    % Loop over voxels if PRIAM
    for kk = 1:length(vox)
        
        % 1 - Take nifti from GannetCoRegister and segment it in SPM
        
        [T1dir, T1name, T1ext] = fileparts(MRS_struct.mask.(vox{kk}).T1image{ii});
        anatimage = MRS_struct.mask.(vox{kk}).T1image{ii};
        
        % Check to see if segmentation already done - if not, do it
        tmp = [T1dir '/c1' T1name T1ext];
        if ~exist(tmp,'file')
            CallSPM12segmentation(anatimage);
        end
        
        % 2 - Determine GM, WM and CSF fractions for each voxel
        
        if strcmp(T1dir,'')
            T1dir = '.';
        end
        
        GM  = [T1dir '/c1' T1name T1ext];
        WM  = [T1dir '/c2' T1name T1ext];
        CSF = [T1dir '/c3' T1name T1ext];
        
        GMvol  = spm_vol(GM);
        WMvol  = spm_vol(WM);
        CSFvol = spm_vol(CSF);
        
        voxmaskvol = spm_vol(MRS_struct.mask.(vox{kk}).outfile{ii});
        [a,b,c] = fileparts(voxmaskvol.fname);
        
        % GM
        O_GMvox.fname = fullfile(a, [b '_GM' c]);
        O_GMvox.descrip = 'GMmasked_MRS_Voxel_Mask';
        O_GMvox.dim = voxmaskvol.dim;
        O_GMvox.dt = voxmaskvol.dt;
        O_GMvox.mat = voxmaskvol.mat;
        GM_voxmask_vol = GMvol.private.dat(:,:,:) .* voxmaskvol.private.dat(:,:,:);
        O_GMvox = spm_write_vol(O_GMvox, GM_voxmask_vol);
        
        % WM
        O_WMvox.fname = fullfile(a, [b '_WM' c]);
        O_WMvox.descrip = 'WMmasked_MRS_Voxel_Mask';
        O_WMvox.dim = voxmaskvol.dim;
        O_WMvox.dt = voxmaskvol.dt;
        O_WMvox.mat = voxmaskvol.mat;
        WM_voxmask_vol = WMvol.private.dat(:,:,:) .* voxmaskvol.private.dat(:,:,:);
        O_WMvox = spm_write_vol(O_WMvox, WM_voxmask_vol);
        
        % CSF
        O_CSFvox.fname = fullfile(a, [b '_CSF' c]);
        O_CSFvox.descrip = 'CSFmasked_MRS_Voxel_Mask';
        O_CSFvox.dim = voxmaskvol.dim;
        O_CSFvox.dt = voxmaskvol.dt;
        O_CSFvox.mat = voxmaskvol.mat;
        CSF_voxmask_vol = CSFvol.private.dat(:,:,:) .* voxmaskvol.private.dat(:,:,:);
        O_CSFvox = spm_write_vol(O_CSFvox, CSF_voxmask_vol);
        
        % 3 - Calculate a CSF-corrected i.u. value and output it to the structure
        
        GMsum  = sum(sum(sum(O_GMvox.private.dat(:,:,:))));
        WMsum  = sum(sum(sum(O_WMvox.private.dat(:,:,:))));
        CSFsum = sum(sum(sum(O_CSFvox.private.dat(:,:,:))));
        
        fGM  = GMsum / (GMsum + WMsum + CSFsum);
        fWM  = WMsum / (GMsum + WMsum + CSFsum);
        fCSF = CSFsum / (GMsum + WMsum + CSFsum);
        
        MRS_struct.out.(vox{kk}).tissue.fGM(ii)  = fGM;
        MRS_struct.out.(vox{kk}).tissue.fWM(ii)  = fWM;
        MRS_struct.out.(vox{kk}).tissue.fCSF(ii) = fCSF;
        
        % Correction of institutional units only feasible if water-scaling
        % is performed, skip otherwise (GO 07/13/2017)
        if strcmp(MRS_struct.p.Reference_compound,'H2O')
            target = MRS_struct.p.target;
            for jj = 1:length(target)
                if strcmp(target{jj},'GABAGlx')
                    MRS_struct.out.(vox{kk}).GABA.ConcIU_CSFcorr(ii) = ...
                        MRS_struct.out.(vox{kk}).GABA.ConcIU(ii) / (1 - fCSF);
                    MRS_struct.out.(vox{kk}).Glx.ConcIU_CSFcorr(ii) = ...
                        MRS_struct.out.(vox{kk}).Glx.ConcIU(ii) / (1 - fCSF);
                else
                    MRS_struct.out.(vox{kk}).(target{jj}).ConcIU_CSFcorr(ii) = ...
                        MRS_struct.out.(vox{kk}).(target{jj}).ConcIU(ii) / (1 - fCSF);
                end
            end
        end
        
        % 4 - Build output
        
        if ishandle(104)
            clf(104);
        end
        h = figure(104);
        % Open figure in center of screen
        scr_sz = get(0, 'ScreenSize');
        fig_w = 1000;
        fig_h = 707;
        set(h,'Position',[(scr_sz(3)-fig_w)/2, (scr_sz(4)-fig_h)/2, fig_w, fig_h]);
        set(h,'Color',[1 1 1]);
        figTitle = 'GannetSegment Output';
        set(h,'Name',figTitle,'Tag',figTitle,'NumberTitle','off');
        
        % Output results
        subplot(2,3,4:6);
        axis off;
        
        text_pos = 1;
        
        % Print correction of institutional units only feasible if
        % water-scaling is performed, skip otherwise (GO 07/13/2017)
        if strcmp(MRS_struct.p.Reference_compound,'H2O')
            target = MRS_struct.p.target;
            tmp = strcmp(target,'GABAGlx');
            if any(tmp)
                if MRS_struct.p.HERMES
                    target = {'GABA','Glx',target{~tmp}};
                else
                    target = {'GABA','Glx'};
                end
            end
            for jj = 1:length(target)
                text_pos = text_pos - 0.12;
                switch target{jj}
                    case 'GABA'
                        tmp1 = 'GABA+/Water (CSF-corrected): ';
                        tmp2 = sprintf('%.2f i.u.', MRS_struct.out.(vox{kk}).GABA.ConcIU_CSFcorr(ii));
                    case 'Lac'
                        tmp1 = 'Lac+MM/Water (CSF-corrected): ';
                        tmp2 = sprintf('%.2f i.u.', MRS_struct.out.(vox{kk}).Lac.ConcIU_CSFcorr(ii));
                    case {'Glx','GSH','EtOH'}
                        tmp1 = [target{jj} '/Water (CSF-corrected): '];
                        tmp2 = sprintf('%.2f i.u.', MRS_struct.out.(vox{kk}).(target{jj}).ConcIU_CSFcorr(ii));
                end
                text(0.5, text_pos, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
                text(0.5, text_pos, tmp2, 'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13);
            end
        end
        
        tmp1 = 'GM voxel fraction: ';
        tmp2 = sprintf('%.2f', MRS_struct.out.(vox{kk}).tissue.fGM(ii));
        text(0.5, text_pos-0.12, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
        text(0.5, text_pos-0.12, tmp2, 'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13);
        
        tmp1 = 'WM voxel fraction: ';
        tmp2 = sprintf('%.2f', MRS_struct.out.(vox{kk}).tissue.fWM(ii));
        text(0.5, text_pos-0.24, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
        text(0.5, text_pos-0.24, tmp2, 'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13);
        
        tmp1 = 'CSF voxel fraction: ';
        tmp2 = sprintf('%.2f', MRS_struct.out.(vox{kk}).tissue.fCSF(ii));
        text(0.5, text_pos-0.36, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
        text(0.5, text_pos-0.36, tmp2, 'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13);
        
        tmp1 = 'Filename: ';
        if strcmp(MRS_struct.p.vendor,'Siemens_rda')
            [~,tmp2,tmp3] = fileparts(MRS_struct.metabfile{ii*2-1});
        else
            [~,tmp2,tmp3] = fileparts(MRS_struct.metabfile{ii});
        end
        fname = [tmp2 tmp3];
        if length(fname) > 30
            fname = [fname(1:30) '...'];
        end
        text(0.5, text_pos-0.48, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
        text(0.5, text_pos-0.48, fname, 'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13, 'Interpreter', 'none');
        
        tmp1 = 'Anatomical image: ';
        [~,tmp2,tmp3] = fileparts(MRS_struct.mask.(vox{kk}).T1image{ii});
        T1image = [tmp2 tmp3];
        if length(T1image) > 30
            T1image = [T1image(1:30) '...'];
        end
        text(0.5, text_pos-0.6, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
        text(0.5, text_pos-0.6, T1image, 'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13, 'Interpreter', 'none');
        
        tmp1 = 'SegmentVer: ';
        text(0.5, text_pos-0.72, tmp1, 'FontName', 'Arial', 'HorizontalAlignment','right', 'VerticalAlignment', 'top', 'FontSize', 13);
        text(0.5, text_pos-0.72, MRS_struct.version.segment,  'FontName', 'Arial', 'VerticalAlignment', 'top', 'FontSize', 13);
        
        % Voxel segmentation (MM: 180807)
        if isfield(MRS_struct.p,'TablePosition')
            VoxOffs = MRS_struct.p.voxoff(ii,:) + MRS_struct.p.TablePosition(ii,:);
        else
            VoxOffs = MRS_struct.p.voxoff(ii,:);
        end
        
        img_t     = flipud(voxel2world_space(spm_vol(anatimage), VoxOffs));
        vox_t     = flipud(voxel2world_space(voxmaskvol, VoxOffs));
        vox_t_GM  = flipud(voxel2world_space(O_GMvox, VoxOffs));
        vox_t_WM  = flipud(voxel2world_space(O_WMvox, VoxOffs));
        vox_t_CSF = flipud(voxel2world_space(O_CSFvox, VoxOffs));
        img_t = img_t/MRS_struct.mask.(vox{kk}).T1max(ii);
        img_montage = [img_t+0.175*vox_t, img_t+0.21*vox_t_GM, img_t+0.25*vox_t_WM, img_t+0.4*vox_t_CSF];
        MRS_struct.mask.(vox{kk}).img_montage{ii} = img_montage;
        
        ha = subplot(2,3,1:3);
        imagesc(img_montage);
        colormap('gray');
        img = MRS_struct.mask.(vox{kk}).img{ii}(:);
        caxis([0 mean(img(img > 0.01)) + 3*std(img(img > 0.01))]);
        axis equal;
        axis tight;
        axis off;
        text(floor(size(vox_t,2)/2), 20, 'Voxel', 'Color', [1 1 1], 'FontSize', 20, 'HorizontalAlignment', 'center');
        text(floor(size(vox_t,2)) + floor(size(vox_t,2)/2), 20, 'GM', 'Color', [1 1 1], 'FontSize', 20, 'HorizontalAlignment', 'center');
        text(2*floor(size(vox_t,2)) + floor(size(vox_t,2)/2), 20, 'WM', 'Color', [1 1 1], 'FontSize', 20, 'HorizontalAlignment', 'center');
        text(3*floor(size(vox_t,2)) + floor(size(vox_t,2)/2), 20, 'CSF', 'Color', [1 1 1], 'FontSize', 20, 'HorizontalAlignment', 'center');
        set(ha,'pos',[0 0.17 1 1]);
        
        if strcmp(MRS_struct.p.vendor,'Siemens_rda')
            [~,tmp,tmp2] = fileparts(MRS_struct.metabfile{ii*2-1});
        else
            [~,tmp,tmp2] = fileparts(MRS_struct.metabfile{ii});
        end
        fname = [tmp tmp2];
        if length(fname) > 30
            fname = [fname(1:30) '...'];
        end
        [~,tmp3,tmp4] = fileparts(MRS_struct.mask.(vox{kk}).T1image{ii});
        T1image = [tmp3 tmp4];
        if length(T1image) > 30
            T1image = [T1image(1:30) '...'];
        end
        t = ['Voxel from ' fname ' on ' T1image];
        title(t, 'FontName', 'Arial', 'FontSize', 15, 'Interpreter', 'none');
        
        % Gannet logo
        Gannet_path = which('GannetLoad');
        Gannet_logo = [Gannet_path(1:end-13) '/Gannet3_logo.png'];
        I = imread(Gannet_logo,'png','BackgroundColor',[1 1 1]);
        axes('Position',[0.80, 0.05, 0.15, 0.15]);
        imshow(I);
        text(0.9, 0, MRS_struct.version.Gannet, 'Units', 'normalized', 'FontName', 'Arial', 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'left');
        axis off;
        axis square;
        
        % For Philips .data
        if strcmpi(MRS_struct.p.vendor,'Philips_data')
            fullpath = MRS_struct.metabfile{ii};
            fullpath = regexprep(fullpath, '.data', '_data');
            fullpath = regexprep(fullpath, '\', '_');
            fullpath = regexprep(fullpath, '/', '_');
        end
        
        % MM (180112)
        if strcmp(MRS_struct.p.vendor,'Siemens_rda')
            [~,metabfile_nopath] = fileparts(MRS_struct.metabfile{ii*2-1});
        else
            [~,metabfile_nopath] = fileparts(MRS_struct.metabfile{ii});
        end
        
        if any(strcmp(listfonts,'Arial'))
            set(findall(h,'-property','FontName'),'FontName','Arial');
        end
        
        % Create output folder
        if ~exist(fullfile(pwd, 'GannetSegment_output'),'dir')
            mkdir(fullfile(pwd, 'GannetSegment_output'));
        end
        
        % Save PDF output
        set(h,'PaperUnits','inches');
        set(h,'PaperSize',[11 8.5]);
        set(h,'PaperPosition',[0 0 11 8.5]);
        
        if strcmpi(MRS_struct.p.vendor,'Philips_data')
            pdfname = fullfile(pwd, 'GannetSegment_output', [fullpath '_' vox{kk} '_segment.pdf']);
        else
            pdfname = fullfile(pwd, 'GannetSegment_output', [metabfile_nopath '_' vox{kk} '_segment.pdf']);
        end
        saveas(h, pdfname);
        
        if ii == numscans
            if MRS_struct.p.mat % save MRS_struct as mat file
                mat_name = ['GannetSegment_output/MRS_struct_' vox{kk} '.mat'];
                save(mat_name,'MRS_struct');
            end
            if MRS_struct.p.csv % export MRS_struct fields into csv file
                ExportToCSV(MRS_struct, MRS_struct.p.target, kk, 'segment');
            end
        end
        
    end
    
end

warning('on'); % turn warnings back on

end



