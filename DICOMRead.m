function MRS_struct = DICOMRead(MRS_struct,metabfile,waterfile)
%% MRS_struct = DICOMRead(MRS_struct,metabfile,waterfile)
%   This function is designed to load edited MR spectroscopy data in the 
%   general form of DICOM data into a Gannet file structure. Files usually
%   have the extension '.DCM' or '.dcm', and contain exactly 1 FID per
%   file, i.e. an acquisition of 320 averages will yield 320 DCM files.
%   
%   It is assumed that they are ordered in the order of acquisition.
%   Water-suppressed and water-unsuppressed files need to be stored in
%   separate folders, e.g. '/user/data/subject01/dcm_gaba/' and 
%   '/user/data/subject01/dcm_water/', respectively.
%
%   Example:
%       MRS_struct = DICOMRead(MRS_struct,'/user/data/subject01/dcm_gaba/metab.dcm','/user/data/subject01/dcm_water/water.dcm');
%
%   Author:
%       Dr. Georg Oeltzschner (Johns Hopkins University, 2016-11-10)
%       goeltzs1@jhmi.edu
%   
%   Credits:    
% 
%   Version history:
%   0.9: First version (2016-11-30)
%   0.91: Added function for water data loading (2017-02-03)
%   0.92: Improved header parsing (2017-03-27). Thanks to Maria Yanez Lopez
%           and Ines Violante.
%   0.93: Added batch processing function (2017-11-16). Thanks to Dieter
%           Meyerhoff.
%   0.94: Added support for CMRR sequence (Eddie Auerbach, CMRR, University
%           of Minnesota) (2017-11-20). Thanks to Jim Lagopoulos.
%   0.95: Fills missing voxel geometry parameters in DICOM header with zero
%           values. Thanks to Alen Tersakyan.
%   0.96: Fixed to accomodate batch processing of coregister/segmentation.
%           (2018-09-19)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



%%% PREPARATION %%%
% Loop over number of datasets
ii = MRS_struct.ii;

% Locate folder and find all files in it. Will usually all be either upper or
% lower case, so concatenating the results of both should be fine and with
% no overlap.
% dcm_file_list = [dir([folder,'/*.DCM']); dir([folder,'/*.dcm'])]; % may
% cause problems on win/unix systems, take out for now % GO 11/16/2016
[folder,~,~] = fileparts(metabfile); % GO 11/01/2016
dcm_file_list = dir([folder,'/*.dcm']); % GO 11/16/2016
fprintf('%d water-suppressed DCM files detected in %s.\n',length(dcm_file_list),folder);

disp('Reading water-suppressed files...')

% Ordering of these files is not correct (i.e. 1,10,100,101...). Sort
% naturally.
dcm_file_names = sort_nat({dcm_file_list.name});
% Add folder to filenames (in case GannetLoad is run outside the folder)
% GO 11/20/2016
dcm_file_names = strcat(folder, filesep, dcm_file_names); % GO 11/20/2016
%%% /PREPARATION %%%

%%% HEADER INFO PARSING %%%
DicomHeader = read_dcm_header(metabfile);
MRS_struct.p.seq = DicomHeader.sequenceFileName;
MRS_struct.p.TR(ii) = DicomHeader.TR;
MRS_struct.p.TE(ii) = DicomHeader.TE;
MRS_struct.p.npoints(ii) = DicomHeader.vectorSize;
MRS_struct.p.Navg(ii) = 2*DicomHeader.nAverages;
MRS_struct.p.nrows(ii) = 2*DicomHeader.nAverages;
MRS_struct.p.sw(ii) = 1/DicomHeader.dwellTime * 1E9 * 0.5; % check with oversampling? hence factor 0.5, need to figure out why <=> probably dataset with 512 points, oversampled is 1024
MRS_struct.p.LarmorFreq(ii) = DicomHeader.tx_freq * 1E-6;
MRS_struct.p.voxdim(ii,1) = DicomHeader.VoI_PeFOV;
MRS_struct.p.voxdim(ii,2) = DicomHeader.VoI_RoFOV;
MRS_struct.p.voxdim(ii,3) = DicomHeader.VoIThickness;
MRS_struct.p.VoI_InPlaneRot(ii) = DicomHeader.VoI_InPlaneRot;
MRS_struct.p.voxoff(ii,1) = DicomHeader.PosSag;
MRS_struct.p.voxoff(ii,2) = DicomHeader.PosCor;
MRS_struct.p.voxoff(ii,3) = DicomHeader.PosTra;
MRS_struct.p.NormCor(ii) = DicomHeader.NormCor;
MRS_struct.p.NormSag(ii) = DicomHeader.NormSag;
MRS_struct.p.NormTra(ii) = DicomHeader.NormTra;
%%% /HEADER INFO PARSING %%%

%%% DATA LOADING %%%
% Preallocate array in which the FIDs are to be extracted.
MRS_struct.fids.data = zeros(MRS_struct.p.npoints(ii),length(dcm_file_names));

% Collect all FIDs and sort them into MRS_struct
for kk = 1:length(dcm_file_names)
    
    % Open IMA
    fd = dicom_open(dcm_file_names{kk});
    
    % read the signal in as a complex FID
    MRS_struct.fids.data(:,kk) = dicom_get_spectrum_siemens(fd);

    fclose(fd);
end
disp('...complete')

% It appears that IMA stores the transients weirdly, 1-n/2 are all ONs, and
% n/2-n are all OFFS. Shuffle them below.
if size(MRS_struct.fids.data,2) > 1
    a = MRS_struct.fids.data(:,1:end/2);
    b = MRS_struct.fids.data(:,1+end/2:end);
    c = zeros(size(MRS_struct.fids.data));
    c(:,1:2:end) = a;
    c(:,2:2:end) = b;
    MRS_struct.fids.data = c;
end
%%% /DATA LOADING %%%



%%% WATER DATA LOADING %%% % GO 02/05/2017
% If a water folder name is input to the function, repeat the same loading
% procedure for these files and hand the data over to the water data array
% of the MRS_struct.

% Set up the file name array.
if nargin == 3
    [waterfolder,~,~] = fileparts(waterfile);
    water_file_list = dir([waterfolder,'/*.DCM']);
    fprintf('%d water-unsuppressed DCM files detected in %s.\n',length(water_file_list),waterfolder);
    disp('Reading water-unsuppressed files...')
    water_file_names = sort_nat({water_file_list.name});
    water_file_names = strcat(waterfolder, filesep, water_file_names);
    
    % Load the actual water-unsuppressed data.
    MRS_struct.fids.waterdata = zeros(MRS_struct.p.npoints(ii),length(water_file_names));

    % Collect all FIDs and sort them into MRS_struct
    for kk = 1:length(water_file_names)
        
        % Open IMA
        fd = dicom_open(water_file_names{kk});
        
        % read the signal in as a complex FID
        MRS_struct.fids.data_water(:,kk) = dicom_get_spectrum_siemens(fd);
        
        fclose(fd);
    end
    disp('...complete')
end
%%% /WATER DATA LOADING %%%

