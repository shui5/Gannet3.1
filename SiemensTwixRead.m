function MRS_struct = SiemensTwixRead(MRS_struct,fname,fname_water)
%% function MRS_struct = SiemensTwixRead(MRS_struct,fname,fname_water)
%   Reads Siemens TWIX files (*.dat).
%
%   Author:
%       Dr. Georg Oeltzschner (Johns Hopkins University, 2017-03-22)
%       goeltzs1@jhmi.edu
%
%   Credits:
%
%   History:
%       2017-03-22: First version.
%       2017-04-21: Move loading module to separate function, add
%       support for loading PRESS water reference data.
%       2017-07-13: - Metabolite spectra phased according to unsuppressed
%                     MEGA-PRESS water reference acquisition
%                   - Make parsing of editing pulse frequencies available
%                     only when the fields are actually present (may depend
%                     on vendor and sequence version).
%                   - Minor improvements.
%       2018-01-06: Loading of voxel geometry parameters moved from
%                   GannetMask_SiemensTWIX to SiemensTwixRead.
%       2018-01-31: Minor fixes.
%       2018-02-23: Changed variable names for voxel geometry parameters to
%                   be consistent with Philips and GE.
%       2018-02-23: Function now reads TablePosition parameters from TWIX
%                   header.
%       2018-03-16: Function now reads in universal sequence using correct
%                   sequence string.
%       2018-05-25: Correct extraction of acquired data points before the
%                   echo for Siemens PRESS, Siemens WIP MEGA-PRESS, and
%                   Siemens CMRR MEGA-PRESS sequences.
%       2018-09-25: Correct extraction of acquired data points for
%                   custom-built MEGA-PRESS sequences.
%       2018-12-18: Bugfix in data dimension assignment.
%       2019-06-26: Bugfix in sequence origin determination.
%       2019-12-13: Added support for CMRR MEGA-sLASER sequence.

ii = MRS_struct.ii;

% Get the raw data and header info from the MEGA-PRESS files.
[MetabData, MetabHeader] = GetTwixData(fname);
% Populate MRS_struct with relevant info.
MRS_struct.p.pointsBeforeEcho           = MetabHeader.pointsBeforeEcho;
MRS_struct.p.sw(ii)                     = 1/MetabHeader.dwellTime;
MRS_struct.p.LarmorFreq(ii)             = MetabHeader.tx_freq;
MRS_struct.p.TR(ii)                     = MetabHeader.TR;
MRS_struct.p.TE(ii)                     = MetabHeader.TE;
MRS_struct.p.npoints(ii)                = size(MetabData,2);
MRS_struct.p.nrows(ii)                  = size(MetabData,3);
MRS_struct.p.Navg(ii)                   = size(MetabData,3);
MRS_struct.p.VoI_InPlaneRot(ii)         = MetabHeader.VoI_InPlaneRot;
MRS_struct.p.NormCor(ii)                = MetabHeader.NormCor;
MRS_struct.p.NormSag(ii)                = MetabHeader.NormSag;
MRS_struct.p.NormTra(ii)                = MetabHeader.NormTra;
MRS_struct.p.voxdim(ii,1)               = MetabHeader.VoI_PeFOV;
MRS_struct.p.voxdim(ii,2)               = MetabHeader.VoI_RoFOV;
MRS_struct.p.voxdim(ii,3)               = MetabHeader.VoIThickness;
MRS_struct.p.voxoff(ii,1)               = MetabHeader.PosSag;
MRS_struct.p.voxoff(ii,2)               = MetabHeader.PosCor;
MRS_struct.p.voxoff(ii,3)               = MetabHeader.PosTra;
MRS_struct.p.TablePosition(ii,1)        = MetabHeader.TablePosSag;
MRS_struct.p.TablePosition(ii,2)        = MetabHeader.TablePosCor;
MRS_struct.p.TablePosition(ii,3)        = MetabHeader.TablePosTra;
MRS_struct.p.seqorig                    = MetabHeader.seqorig;

if isfield(MetabHeader,'deltaFreq')
    MRS_struct.p.Siemens.deltaFreq.metab(ii)   = MetabHeader.deltaFreq;
end

if isfield(MetabHeader,'editRF')
    MRS_struct.p.Siemens.editRF.freq(ii,:)     = MetabHeader.editRF.freq;
    MRS_struct.p.Siemens.editRF.centerFreq(ii) = MetabHeader.editRF.centerFreq;
    MRS_struct.p.Siemens.editRF.bw(ii)         = MetabHeader.editRF.bw;
    if isfield(MetabHeader,'deltaFreq')
        MRS_struct.p.Siemens = reorderstructure(MRS_struct.p.Siemens, 'editRF', 'deltaFreq');
    end
end

% If additional data points have been acquired before the echo starts,
% remove these here.
MetabData = MetabData(:,(MRS_struct.p.pointsBeforeEcho+1):end,:);
% Undo phase cycling
% Seems to be needed for some of Jamie's sequences
if strcmp(MRS_struct.p.seqorig,'JN')
    corrph = repmat([-1 1], [size(MetabData,2) size(MetabData,3)/2]);
    corrph = repmat(corrph, [size(MetabData,1) 1 1]);
    corrph = reshape(corrph, [size(MetabData,1) size(MetabData,2) size(MetabData,3)]);
    MetabData = MetabData .* corrph;
end

MRS_struct.p.npoints(ii) = MRS_struct.p.npoints(ii) - MRS_struct.p.pointsBeforeEcho;

% If water reference is provided, load this one as well, and populate
% MRS_struct with water reference specific information.
if nargin == 3
    [WaterData, WaterHeader] = GetTwixData(fname_water);
    MRS_struct.p.pointsBeforeEcho_water = WaterHeader.pointsBeforeEcho;
    MRS_struct.p.sw_water(ii)           = 1/WaterHeader.dwellTime;
    MRS_struct.p.TR_water(ii)           = WaterHeader.TR;
    MRS_struct.p.TE_water(ii)           = WaterHeader.TE;
    MRS_struct.p.npoints_water(ii)      = size(WaterData,2);
    MRS_struct.p.nrows_water(ii)        = size(WaterData,3);
    MRS_struct.p.Nwateravg(ii)          = size(WaterData,3);
    MRS_struct.p.seqtype_water          = WaterHeader.seqtype;
    if isfield(WaterHeader,'deltaFreq')
        MRS_struct.p.Siemens.deltaFreq.water(ii) = WaterHeader.deltaFreq;
        if isfield(WaterHeader,'editRF')
            MRS_struct.p.Siemens = reorderstructure(MRS_struct.p.Siemens, 'editRF', 'deltaFreq');
        end
    end
    
    % If additional data points have been acquired before the echo starts,
    % remove these here.
    WaterData = WaterData(:,(MRS_struct.p.pointsBeforeEcho_water+1):end,:);
    
    % Undo phase cycling
    % Seems to be needed for some of Jamie's sequences
    if strcmp(MRS_struct.p.seqorig,'JN')
        corrph = repmat([-1 1], [size(WaterData,2) size(WaterData,3)/2]);
        corrph = repmat(corrph, [size(WaterData,1) 1 1]);
        corrph = reshape(corrph, [size(WaterData,1) size(WaterData,2) size(WaterData,3)]);
        WaterData = WaterData .* corrph;
    end
    
    MRS_struct.p.npoints_water(ii) = MRS_struct.p.npoints_water(ii) - MRS_struct.p.pointsBeforeEcho_water;
    
    % Coil combination and prephasing
    
%     firstpoint_water = conj(WaterData(:,1,:));
%     channels_scale = squeeze(sqrt(sum(firstpoint_water .* conj(firstpoint_water),1)));
%     channels_scale = repmat(channels_scale, [1 size(WaterData,1) MRS_struct.p.npoints_water(ii)]);
%     channels_scale = permute(channels_scale, [2 3 1]);
%     firstpoint_water = repmat(firstpoint_water, [1 MRS_struct.p.npoints_water(ii) 1])./channels_scale;
%     WaterData = WaterData .* firstpoint_water;
%     WaterData = conj(squeeze(sum(WaterData,1)));
%     WaterData = squeeze(mean(WaterData,2));
    
    % Calculate mean of water FID for all channels
    WaterMean = mean(WaterData,3);
    % Determine signal strength for each channel
    [~,ind] = max(abs(WaterMean),[],2);
    ind = mode(ind);
    sig = abs(WaterMean(:,ind));
    % Normalize so the sum is 1
    sig = sig/norm(sig);
    % Determine phase of each channel
    phi = angle(WaterMean(:,ind));
    % Apply changes
    WaterData = WaterData .* repmat(exp(-1i*phi) .* sig, [1 size(WaterData,2) size(WaterData,3)]);
    % Sum over coils
    WaterData = squeeze(sum(conj(WaterData),1));
    % Average across averages
    WaterData = squeeze(mean(WaterData,2));
    MRS_struct.fids.data_water = double(WaterData);
    
%     % Generalized least squares method (MM: under dev.)
%     % Align water signal over each avg. for each coil element
%     lsqnonlinopts = optimoptions(@lsqnonlin);
%     lsqnonlinopts = optimoptions(lsqnonlinopts,'Algorithm','levenberg-marquardt','Display','off');
%     t1 = 0:(1/MRS_struct.p.sw(ii)):(size(WaterData,2)-1)*(1/MRS_struct.p.sw(ii));
%     tMax = find(t1 <= 0.2,1,'last');
%     t2 = 0:(1/MRS_struct.p.sw(ii)):(tMax-1)*(1/MRS_struct.p.sw(ii));
%
%     for jj = 1:size(WaterData,1)
%         flatdata(:,1,:) = real(WaterData(jj,1:tMax,:));
%         flatdata(:,2,:) = imag(WaterData(jj,1:tMax,:));
%         target = squeeze(flatdata(:,:,1));
%         target = target(:);
%         for kk = 2:size(WaterData,3)
%             transient = squeeze(flatdata(:,:,kk));
%             fun = @(x) SpecReg(double(transient(:)), double(target), t2, x);
%             p = lsqnonlin(fun, [0 0], [], [], lsqnonlinopts);
%             WaterData(jj,:,kk) = WaterData(jj,:,kk) .* ...
%                 exp(1i*p(1)*2*pi*t1) * exp(1i*pi/180*p(2));
%         end
%     end
%
%     WaterData_avg = mean(WaterData,3);
%     e = WaterData_avg(:,ceil(0.75*size(WaterData_avg,2)):end);
%     Psi = e*e';
%     [~,ind] = max(abs(WaterData_avg),[],2);
%     ind = mode(ind);
%     S = WaterData_avg(:,ind);
%     w = (S'*(Psi\S))^-1 * S' / Psi;
%     WaterData = w.' .* WaterData;
%     MRS_struct.fids.data_water = double(mean(conj(squeeze(sum(WaterData,1))),2));
end

% Phasing of metabolite data.
% If the water reference has been acquired with MEGA-PRESS, use the phase
% information from it to phase the metabolite data.
if isfield(MRS_struct.p,'seqtype_water') && strcmp(MRS_struct.p.seqtype_water,'MEGA-PRESS')
    disp('MEGA-PRESS water reference found!');
    disp('Phasing metabolite data with water reference phase...');
    MetabData = MetabData .* repmat(exp(-1i*phi) .* sig, [1 size(MetabData,2) size(MetabData,3)]);
    % Sum over coils
    MetabData = squeeze(sum(conj(MetabData),1));
    MRS_struct.fids.data = double(MetabData);
    
%     % Generalized least squares method (MM: under dev.)
%     MetabData_avg = mean(MetabData,3);
%     e = MetabData_avg(:,ceil(0.75*size(MetabData_avg,2)):end);
%     Psi = e*e';
%     w = (S'*(Psi\S))^-1 * S' / Psi;
%     MetabData = w.' .* MetabData;
%     MRS_struct.fids.data = double(conj(squeeze(sum(MetabData,1))));
else
    % If no water data (or PRESS water reference) provided, combine data
    % based upon first point of metabolite data (average all transients)
    if isfield(MRS_struct.p,'seqtype_water') && strcmp(MRS_struct.p.seqtype_water,'PRESS')
        disp('PRESS water reference found!');
    else
        disp('No water reference found!');
    end
    disp('Phasing metabolite data...');
    % Coil combination and prephasing (mean over all averages)
    firstpoint = mean(conj(MetabData(:,1,:)),3);
    channels_scale = squeeze(sqrt(sum(firstpoint .* conj(firstpoint))));
    firstpoint = repmat(firstpoint, [1 MRS_struct.p.npoints(ii) MRS_struct.p.nrows(ii)])/channels_scale;
    % Multiply the Multichannel data by the firstpointvector
    % zeroth order phasing of spectra
    MetabData = MetabData .* firstpoint;
    % Sum over coils
    MetabData = conj(squeeze(sum(MetabData,1)));
    MRS_struct.fids.data = double(MetabData);
end

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% SEPARATE FUNCTIONS START BELOW %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [TwixData, TwixHeader] = GetTwixData(fname)

% Pull TWIX data in with the mapVBVD tool
twix_obj = mapVBVD_Gannet(fname);

% Is the data single-RAID or multi-RAID?
% struct - single-RAID
% cell - multi-RAID, with info in the last cell element
if isstruct(twix_obj)
    disp('Loading single-RAID file...')
elseif iscell(twix_obj)
    disp('Loading multi-RAID file...')
    twix_obj = twix_obj{end};
end

% Collect a couple of useful information before starting the actual
% extraction of data and headers
TwixHeader.SiemensVersion       = twix_obj.image.softwareVersion; % Siemens software version (VA,VB,VC,VD,VE?)
TwixHeader.sequenceFileName     = twix_obj.hdr.Config.SequenceFileName; % Full sequence name
TwixHeader.sequenceString       = twix_obj.hdr.Config.SequenceString; % Short sequence name

% Determine the type
% Read information from .image part of the TWIX object
TwixHeader.sqzSize              = twix_obj.image.sqzSize; % dimensions (data points, averages, number of coils, dynamics (ON and OFF))
TwixHeader.sqzDims              = twix_obj.image.sqzDims; % variable names for dimensions
TwixData                        = squeeze(twix_obj.image()); % FID data, remove singleton dimensions

% Read information from .hdr part of the TWIX object
TwixHeader.readoutOSFactor      = twix_obj.hdr.Config.ReadoutOSFactor; % Data are oversampled by this factor compared to exam card setting
TwixHeader.removeOS             = twix_obj.hdr.Config.RemoveOversampling; % Is the oversampling removed in the RDA files?
TwixHeader.TR                   = twix_obj.hdr.Config.TR * 1e-3; % TR [ms]
TwixHeader.vectorSize           = twix_obj.hdr.Config.VectorSize; % Data points specified on exam card
TwixHeader.VoI_InPlaneRot       = twix_obj.hdr.Config.VoI_InPlaneRotAngle; % Voxel rotation in plane
TwixHeader.VoI_RoFOV            = twix_obj.hdr.Config.VoI_RoFOV; % Voxel size in readout direction [mm]
TwixHeader.VoI_PeFOV            = twix_obj.hdr.Config.VoI_PeFOV; % Voxel size in phase encoding direction [mm]
TwixHeader.VoIThickness         = twix_obj.hdr.Config.VoI_SliceThickness; % Voxel size in slice selection direction [mm]
TwixHeader.NormCor              = twix_obj.hdr.Config.VoI_Normal_Cor; % Coronal component of normal vector of voxel
TwixHeader.NormSag              = twix_obj.hdr.Config.VoI_Normal_Sag; % Sagittal component of normal vector of voxel
TwixHeader.NormTra              = twix_obj.hdr.Config.VoI_Normal_Tra; % Transversal component of normal vector of voxel
TwixHeader.PosCor               = twix_obj.hdr.Config.VoI_Position_Cor; % Coronal coordinate of voxel [mm]
TwixHeader.PosSag               = twix_obj.hdr.Config.VoI_Position_Sag; % Sagittal coordinate of voxel [mm]
TwixHeader.PosTra               = twix_obj.hdr.Config.VoI_Position_Tra; % Transversal coordinate of voxel [mm]
TwixHeader.TablePosSag          = twix_obj.hdr.Dicom.lGlobalTablePosSag; % Sagittal table position [mm]
TwixHeader.TablePosCor          = twix_obj.hdr.Dicom.lGlobalTablePosCor; % Coronal table position [mm]
TwixHeader.TablePosTra          = twix_obj.hdr.Dicom.lGlobalTablePosTra; % Transversal table position [mm]

% GO180108: If a parameter is set to zero (e.g. if no voxel rotation is
% performed), the respective field is left empty in the TWIX file. This
% case needs to be intercepted. Setting to the minimum possible value.
VoI_Params = {'VoI_InPlaneRot','VoI_RoFOV','VoI_PeFOV','VoIThickness','NormCor','NormSag','NormTra', ...
    'PosCor','PosSag','PosTra','TablePosSag','TablePosCor','TablePosTra'};
for pp = 1:length(VoI_Params)
    if isempty(TwixHeader.(VoI_Params{pp}))
        TwixHeader.(VoI_Params{pp}) = realmin('double');
    end
end

TwixHeader.SiemensSoftwareVersion = twix_obj.hdr.Dicom.SoftwareVersions; % Full software version
TwixHeader.B0                     = twix_obj.hdr.Dicom.flMagneticFieldStrength; % Nominal B0 [T]
TwixHeader.tx_freq                = twix_obj.hdr.Dicom.lFrequency * 1e-6; % Transmitter frequency [MHz]
if iscell(twix_obj.hdr.MeasYaps.alTE)
    TwixHeader.TE                 = twix_obj.hdr.MeasYaps.alTE{1} * 1e-3; % TE [ms]
elseif isstruct(twix_obj.hdr.MeasYaps.alTE)
    TwixHeader.TE                 = twix_obj.hdr.MeasYaps.alTE(1) * 1e-3; % TE [ms]
end
if iscell(twix_obj.hdr.MeasYaps.sRXSPEC.alDwellTime)
    TwixHeader.dwellTime          = twix_obj.hdr.MeasYaps.sRXSPEC.alDwellTime{1} * 1e-9; % dwell time [s]
elseif isstruct(twix_obj.hdr.MeasYaps.sRXSPEC.alDwellTime)
    TwixHeader.dwellTime          = twix_obj.hdr.MeasYaps.sRXSPEC.alDwellTime(1) * 1e-9; % dwell time [s]
end

% These may only be extractable from a few MEGA-PRESS versions
% Editing pulse parameters
if isfield(twix_obj.hdr.MeasYaps, 'sWipMemBlock')
    if isfield(twix_obj.hdr.MeasYaps.sWipMemBlock, 'adFree')
        if length(twix_obj.hdr.MeasYaps.sWipMemBlock.adFree) == 3
            param = twix_obj.hdr.MeasYaps.sWipMemBlock.adFree;
            param = param(~cellfun('isempty',param));
            TwixHeader.editRF.freq = [param{1}, param{3}+(param{3}-param{1})];
            TwixHeader.editRF.centerFreq = param{3};
            TwixHeader.editRF.bw = param{2};
        end
    end
elseif isfield(twix_obj.hdr.MeasYaps, 'sWiPMemBlock')
    if isfield(twix_obj.hdr.MeasYaps.sWiPMemBlock, 'adFree')
        if length(twix_obj.hdr.MeasYaps.sWiPMemBlock.adFree) == 3
            param = twix_obj.hdr.MeasYaps.sWiPMemBlock.adFree;
            param = param(~cellfun('isempty',param));
            TwixHeader.editRF.freq = [param{1}, param{3}+(param{3}-param{1})];
            TwixHeader.editRF.centerFreq = param{3};
            TwixHeader.editRF.bw = param{2};
        end
    end
end
% Delta frequency (center of slice selection)
if isfield(twix_obj.hdr.MeasYaps.sSpecPara, 'dDeltaFrequency')
    TwixHeader.deltaFreq = twix_obj.hdr.MeasYaps.sSpecPara.dDeltaFrequency;
else
    TwixHeader.deltaFreq = 0;
end

% Determine the origin of the sequence
if strfind(TwixHeader.sequenceFileName,'svs_edit')
    TwixHeader.seqtype = 'MEGA-PRESS';
    if strcmp(TwixHeader.sequenceFileName(end-3:end),'univ')
        TwixHeader.seqorig = 'Universal'; % Universal sequence
    else
        if ~isempty(strfind(TwixHeader.sequenceFileName,'529')) || ~isempty(strfind(TwixHeader.sequenceFileName,'859'))
            TwixHeader.seqorig = 'WIP'; % Siemens WIP
        else
            TwixHeader.seqorig = 'Custom'; % There are some custom implementations out there...
        end
    end
elseif strfind(TwixHeader.sequenceFileName,'jn_')
    TwixHeader.seqtype = 'MEGA-PRESS';
    TwixHeader.seqorig = 'JN'; % Jamie Near's sequence
elseif strfind(TwixHeader.sequenceFileName,'eja_svs_mpress')
    TwixHeader.seqtype = 'MEGA-PRESS';
    TwixHeader.seqorig = 'CMRR'; % Minnesota sequence
elseif strfind(TwixHeader.sequenceFileName,'eja_svs_mslaser') % SH 20191213
    TwixHeader.seqtype = 'MEGA-sLASER';
    TwixHeader.seqorig = 'CMRR';
elseif strfind(TwixHeader.sequenceFileName,'svs_se')
    TwixHeader.seqtype = 'PRESS'; % In case PRESS is used as water reference
    TwixHeader.seqorig = TwixHeader.sequenceString;
else
    TwixHeader.seqorig = TwixHeader.sequenceString;
    error(['Unknown sequence: ' TwixHeader.seqorig '. Please consult the Gannet team for support.'])
end

% Now reorder the FID data array according to software version and sequence
% origin and sequence type.
if strcmp(TwixHeader.seqtype,'PRESS')
    
    % For PRESS data, the first dimension of the 4D data array contains the
    % time-domain FID datapoints. The second dimension contains the number
    % of the coils. The third dimension contains the number of averages.
    % The fourth dimension is not well understood, but the second row of
    % this dimension contains all averages, while the first one is empty
    % for all averages but the first one.
    dims.points = 1;
    dims.coils = 2;
    dims.averages = 3;
    dims.dyn = 4;
    if ndims(TwixData) == 4
        TwixData = TwixData(:,:,:,2);
    end
    
    % For the standard Siemens svs_se sequence, the number of points
    % acquired before the echo maximum are stored here:
    TwixHeader.pointsBeforeEcho = twix_obj.image.freeParam(1);
    
    TwixData = permute(TwixData,[dims.coils dims.points dims.dyn dims.averages]);
    TwixData = reshape(TwixData,[size(TwixData,1) size(TwixData,2) size(TwixData,3)*size(TwixData,4)]);
    
elseif any(strcmp(TwixHeader.seqtype,{'MEGA-PRESS','MEGA-sLASER'})) % SH 20191213
    
    % For all known MEGA-PRESS implementations, the first dimension of the 4D
    % data array contains the time-domain FID datapoints.
    dims.points = 1;
    % For all known MEGA-PRESS implementations, the second dimension of the 4D
    % data array contains the the number of the coils.
    dims.coils = 2;
    % It is more difficult for the dimension that contains the averages.
    if strcmp(TwixHeader.SiemensVersion,'vb')
        dims.averages=find(strcmp(TwixHeader.sqzDims,'Set'));
    else
        if strcmp(TwixHeader.seqorig,'CMRR')
            % Averages can be in dimension 'Set' or 'Rep'
            if ~isempty(find(strcmp(TwixHeader.sqzDims,'Set'),1))
                dims.averages = find(strcmp(TwixHeader.sqzDims,'Set'));
            elseif ~isempty(find(strcmp(TwixHeader.sqzDims,'Rep'),1))
                dims.averages = find(strcmp(TwixHeader.sqzDims,'Rep'));
            else
                dims.averages = 4;
            end
        else
            dims.averages = find(strcmp(TwixHeader.sqzDims,'Ave'));
        end
    end
    % It is more difficult for the dimension that contains the dynamics.
    if strcmp(TwixHeader.SiemensVersion,'vb')
        if strcmp(TwixHeader.seqorig,'JN')
            dims.dyn = find(strcmp(TwixHeader.sqzDims,'Ida'));
        else
            dims.dyn = find(strcmp(TwixHeader.sqzDims,'Eco'));
        end
    else
        if strcmp(TwixHeader.seqorig,'CMRR')
            dims.dyn = find(strcmp(TwixHeader.sqzDims,'Eco'));
        elseif strcmp(TwixHeader.seqorig,'JN')
            dims.dyn = find(strcmp(TwixHeader.sqzDims,'Set'));
        else
            dims.dyn = find(strcmp(TwixHeader.sqzDims,'Ide'));
        end
    end
    
    % It looks like newer CMRR implementations may have another (5th)
    % dimension of the FID array:
    if strcmp(TwixHeader.seqorig,'CMRR') && length(TwixHeader.sqzDims) > 4
        dims.onoff = 4;
        TwixData = permute(TwixData,[dims.coils dims.points dims.dyn dims.onoff dims.averages]);
        TwixData = reshape(TwixData,[size(TwixData,1), size(TwixData,2), size(TwixData,3) * size(TwixData,4) * size(TwixData,5)]);
    else
        TwixData = permute(TwixData,[dims.coils dims.points dims.dyn dims.averages]);
        TwixData = reshape(TwixData,[size(TwixData,1), size(TwixData,2), size(TwixData,3) * size(TwixData,4)]);
    end
    
    % MEGA-PRESS sequences store the number of points acquired before the
    % echo maximum in different fields, depending on the origin of the
    % sequence:
    if strcmp(TwixHeader.seqorig,'CMRR')
        if strcmp(TwixHeader.seqtype,'MEGA-PRESS')
            TwixHeader.pointsBeforeEcho = twix_obj.image.iceParam(5,1);
        elseif strcmp(TwixHeader.seqtype,'MEGA-sLASER') % SH 20191213
            TwixHeader.pointsBeforeEcho = twix_obj.image.freeParam(1);
        end
    elseif strcmp(TwixHeader.seqorig,'WIP') % Siemens WIP
        TwixHeader.pointsBeforeEcho     = twix_obj.image.cutOff(1,1);
        TwixHeader.pointsAfterEcho      = twix_obj.image.cutOff(2,1);
    elseif strcmp(TwixHeader.seqorig,'Custom') % Custom
        TwixHeader.pointsBeforeEcho     = twix_obj.image.freeParam(1);
    else
        TwixHeader.pointsBeforeEcho     = twix_obj.image.freeParam(1);
    end
    
end

end



