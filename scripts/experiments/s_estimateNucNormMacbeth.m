close all;
clear variables;
clc;

ieInit;

%%

nSamples = 24;


alpha = 0.01;
sigma = 0.009;

testFileName = 'Macbeth+multiFl3';
backgroundFileName = 'Background+multiFl';

wave = 380:4:1000;
deltaL = wave(2) - wave(1);
nWaves = length(wave);

% Load the light spectra (in photons). We scale by the maximum for
% numerical stability. This does not matter in the long run as we are
% calibrating for an unknown gain paramter.
fName = fullfile(fiToolboxRootPath,'camera','illuminants');
illuminant = ieReadSpectra(fName,wave);
illuminantPhotons = Energy2Quanta(wave,illuminant);
illuminantPhotons = illuminantPhotons/max(illuminantPhotons(:));

nChannels = size(illuminant,2);

% Load camera spectral properties
fName = fullfile(fiToolboxRootPath,'camera','filters');
filters = ieReadSpectra(fName,wave);

fName = fullfile(fiToolboxRootPath,'camera','qe');
qe = ieReadSpectra(fName,wave);

camera = diag(qe)*filters;
nFilters = size(camera,2);


% Load the calibration target reflectance
% fName = fullfile(fiToolboxRootPath,'data','experiments','chalk');
% calibRefl = ieReadSpectra(fName,wave);
% calibRefl = ones(nWaves,1);

% Load the test target reflectance
fName = fullfile(fiToolboxRootPath,'data','macbethChart');
reflRef = ieReadSpectra(fName,wave);

fName = fullfile(fiToolboxRootPath,'data','redFlTransmittance');
redTr = ieReadSpectra(fName,wave);

fName = fullfile(fiToolboxRootPath,'data','greenFlTransmittance');
greenTr = ieReadSpectra(fName,wave);

fName = fullfile(fiToolboxRootPath,'data','amberFlTransmittance');
amberTr = ieReadSpectra(fName,wave);

reflRef(:,1:4:24) = diag(amberTr)*reflRef(:,1:4:24);
reflRef(:,2:4:24) = diag(greenTr)*diag(amberTr)*reflRef(:,2:4:24);
reflRef(:,3:4:24) = diag(greenTr)*diag(redTr)*reflRef(:,3:4:24);
reflRef(:,4:4:24) = diag(redTr)*reflRef(:,4:4:24);

% Load fluorescence data and get reference spectra
fName = fullfile(fiToolboxRootPath,'data','redFl');
redFl = fiReadFluorophore(fName,'wave',wave);

fName = fullfile(fiToolboxRootPath,'data','greenFl');
greenFl = fiReadFluorophore(fName,'wave',wave);

fName = fullfile(fiToolboxRootPath,'data','amberFl');
amberFl = fiReadFluorophore(fName,'wave',wave);


fluorophores(1,1,1) = amberFl;
fluorophores(1,1,2) = amberFl;

fluorophores(2,1,1) = greenFl;
fluorophores(2,1,2) = amberFl;

fluorophores(3,1,1) = greenFl;
fluorophores(3,1,2) = redFl;

fluorophores(4,1,1) = redFl;
fluorophores(4,1,2) = redFl;


flQe(1,1,1) = 0.25/2;
flQe(1,1,2) = 0.25/2;

flQe(2,1,1) = 0.20;
flQe(2,1,2) = 0.14;

flQe(3,1,1) = 0.20;
flQe(3,1,2) = 0.14;

flQe(4,1,1) = 0.23/2;
flQe(4,1,2) = 0.23/2;

% fluorophores = [greenFl; redFl];
flScene = fluorescentSceneCreate('type','fromfluorophore','fluorophore',fluorophores,'wave',wave,'qe',flQe);

dMatRef = fluorescentSceneGet(flScene,'donaldsonReference','sceneSize',[4 6]);
exRef = fluorescentSceneGet(flScene,'excitationReference','sceneSize',[4 6]);
emRef = fluorescentSceneGet(flScene,'emissionReference','sceneSize',[4 6]);



%% Calibration
% The whole linear image formation model has an unknown gain parameter, we
% are computing this gain for every pixel by taking an image of a white
% surface with a known reflectance. The gain is just the result of the
% division between pixel intensities and linear model predictions.

% Predict the response of a target surface
prediction = deltaL*((camera')*illuminantPhotons);

% Generate the gain map for every pixel
fName = fullfile(fiToolboxRootPath,'data','experiments',backgroundFileName);
[RAW, ~, scaledRAW, shutterBackground] = fiReadImageStack(fName);
hh = size(scaledRAW,1);
ww = size(scaledRAW,2);

%{
for f=1:nFilters
    figure;
    for c=1:nChannels
        subplot(4,4,c);
        imagesc(RAW(:,:,f,c));
    end
end
%}

% For every illuminant channel and the monochromatic filter pick a
% reference point (say in the middle). Compute how would you need to scale
% other pixels so that the image intensity is uniform. We are using the
% monochromatic channel for the computations and then using the same map
% across all the channels
refPt = scaledRAW(hh/2,ww/2,1,:);
refImg = repmat(refPt,[hh ww 1 1]);
scaleMap = refImg./scaledRAW(:,:,1,:);
scaleMap = repmat(scaleMap,[1 1 nFilters 1]);

nonuniformityCorrected = scaledRAW.*scaleMap;

% Now for each channel compute the gain parameter, that represents the
% precise value of the light intensity.
avgIntensity = squeeze(mean(mean(nonuniformityCorrected(:,:,1,:),1),2));
gains = avgIntensity'./prediction(1,:);

% Assume that the light intensity is constant, we can apply the same gain
% to different camera filters.
cameraGain = repmat(gains,[nFilters, 1, nSamples]);
cameraOffset = zeros([nFilters, nChannels, nSamples]);
[reflValsRef, flValsRef] = fiComputeReflFlContrib(camera,illuminantPhotons,cameraGain(:,:,1)*deltaL,reflRef,dMatRef);


%% Extract data from a Macbeth image
fName = fullfile(fiToolboxRootPath,'data','experiments',testFileName);
[RAW, ~, scaledMacbeth, shutterMacbeth] = fiReadImageStack(fName);
linearVals = scaledMacbeth.*scaleMap;

% Read the sensor data
cp = [51 846;1275 873;1278 81;58 61];
measVals = zeros(nFilters,nChannels,24);
for f=1:nFilters
    sensor = createCameraModel(f);

    for i=1:nChannels
       
        sensor = sensorSet(sensor,'volts',linearVals(:,:,f,i));
        % sensor = sensorSet(sensor,'volts',RAW(:,:,f,i));
        ieAddObject(sensor);

        if isempty(cp)
            sensorWindow('scale',1);
            [tmp, ~, ~, cp] = macbethSelect(sensor,1,1,cp);
        else
            [tmp, ~, ~, cp] = macbethSelect(sensor,0,1,cp);
        end
        measVals(f,i,:) = cellfun(@(x) mean(x(~isnan(x) & ~isinf(x))),tmp);
    end 
end

% Normalize the measured pixel intensities, so that the maxium for each 
% patch is 1. To preserve the image formation model we need to scale camera
% gains accordingly.
nF = max(max(measVals,[],1),[],2);
nF = repmat(nF,[nFilters nChannels 1]);
measVals = measVals./nF;
cameraGain = cameraGain./nF;


%% Estimate the reflectance and single fluorescence

[ reflEst, emEst, exEst, dMatEst, reflValsEst, flValsEst, hist ] = fiRecReflAndFlNucNorm( measVals,...
    camera, cameraGain*deltaL, cameraOffset, illuminantPhotons, alpha, sigma, 'maxIter',500 );

dirName = fullfile(fiToolboxRootPath,'results','experiments');
if ~exist(dirName,'dir'), mkdir(dirName); end;

fName = fullfile(dirName,sprintf('nucNorm_%s.mat',testFileName));
save(fName,'reflEst','emEst','exEst','dMatEst','reflValsEst','flValsEst','hist',...
            'wave','alpha','sigma','reflRef','exRef','emRef','dMatRef','measVals');
                     
                     
                     
measValsEst = reflValsEst + flValsEst;


[err, std] = fiComputeError(reshape(measValsEst,[nChannels*nFilters,nSamples]), reshape(measVals - cameraOffset,[nChannels*nFilters,nSamples]), 'default');
fprintf('Total pixel error %.3f, std %.3f\n',err,std);

[err, std] = fiComputeError(reshape(reflValsEst,[nChannels*nFilters,nSamples]), reshape(reflValsRef,[nChannels*nFilters,nSamples]), 'default');
fprintf('Reflected pixel error %.3f, std %.3f\n',err,std);

[err, std] = fiComputeError(reshape(flValsEst,[nChannels*nFilters,nSamples]), reshape(flValsRef,[nChannels*nFilters,nSamples]), 'default');
fprintf('Fluoresced pixel error %.3f, std %.3f\n',err,std);

[err, std] = fiComputeError(reflEst, reflRef, '');
fprintf('Reflectance error %.3f, std %.3f\n',err,std);

[err, std] = fiComputeError(dMatEst, dMatRef, '');
fprintf('Donaldson matrix error %.3f, std %.3f\n',err,std);

[err, std] = fiComputeError(dMatEst, dMatRef, 'normalized');
fprintf('Donaldson matrix error (normalized) %.3f, std %.3f\n',err,std);



%% Plot the results

fName = fullfile(fiToolboxRootPath,'data','flCmap');
load(fName);

figure;
hold all; grid on; box on;
plot(measValsEst(:),measVals(:),'.');
xlabel('Model predicted pixel value');
ylabel('ISET pixel value');

% Prediction for a specific filter
fID = 1;
tmp1 = squeeze(measValsEst(fID,:,:))';
tmp2 = squeeze(measVals(fID,:,:))';
maxVal = max([tmp1(:); tmp2(:)]);

figure;
for c=1:nChannels
    subplot(4,4,c);
    hold all; grid on; box on;
    plot(tmp1(:,c),tmp2(:,c),'.');
    plot(linspace(0,maxVal,10),linspace(0,maxVal,10),'r');
    xlim([0 maxVal]);
    ylim([0 maxVal]);
    xlabel('Model');
    ylabel('Measured');
    title(sprintf('F: %i, C: %i',fID,c));
end

% Prediction for different filters
tmp1 = reshape(measValsEst,[nFilters nChannels*nSamples])';
tmp2 = reshape(measVals,[nFilters nChannels*nSamples])';
maxVal = max([tmp1(:); tmp2(:)]);

figure;
for f=1:nFilters
    subplot(3,3,f);
    hold all; grid on; box on;
    plot(tmp1(:,f),tmp2(:,f),'.');
    plot(linspace(0,maxVal,10),linspace(0,maxVal,10),'r');
    xlabel('Model');
    ylabel('Measured');
    title(sprintf('F: %i',f));
    xlim([0 maxVal]);
    ylim([0 maxVal]);
end


% Prediction for different chanels
tmp1 = reshape(permute(measValsEst,[2 3 1]),[nChannels nFilters*nSamples])';
tmp2 = reshape(permute(measVals,[2 3 1]),[nChannels nFilters*nSamples])';
maxVal = max([tmp1(:); tmp2(:)]);

figure;
for c=1:nChannels
    subplot(4,4,c);
    hold all; grid on; box on;
    plot(tmp1(:,c),tmp2(:,c),'.');
    plot(linspace(0,maxVal,10),linspace(0,maxVal,10),'r');
    xlabel('Model');
    ylabel('Measured');
    title(sprintf('C: %i',c));
    xlim([0 maxVal]);
    ylim([0 maxVal]);
end

% Pixel prediction per patch
figure;
for xx=1:6
for yy=1:4

    plotID = (yy-1)*6 + xx;
    sampleID = (xx-1)*4 + yy;

    subplot(4,6,plotID);
    hold all; grid on; box on;
    
    tmp1 = measValsEst(:,:,sampleID)';
    tmp2 = measVals(:,:,sampleID)';
    
    plot(tmp1,tmp2,'.');

end
end

% Convergence
figure;
for xx=1:6
for yy=1:4

    plotID = (yy-1)*6 + xx;
    sampleID = (xx-1)*4 + yy;

    subplot(4,6,plotID);
    hold all; grid on; box on;
    plot([hist{sampleID}.prRes, hist{sampleID}.dualRes],'LineWidth',2);
    xlim([0 length(hist{sampleID}.prRes)]);
    ylim([1e-5 10]);
    set(gca,'yscale','log');
end
end

% Estimated vs. ground truth reflectance
figure;
for xx=1:6
for yy=1:4

    plotID = (yy-1)*6 + xx;
    sampleID = (xx-1)*4 + yy;

    subplot(4,6,plotID);
    hold all; grid on; box on;
    plot(wave,diag(reflEst{sampleID}),'g','LineWidth',2);
    plot(wave,reflRef(:,sampleID),'b--','LineWidth',2);
    xlim([min(wave) max(wave)]);
    ylim([-0.05 1.05]);

    rmse = sqrt(mean((diag(reflEst{sampleID}) - reflRef(:,sampleID)).^2));
    title(sprintf('RMSE %.2f',rmse));

end
end

% Estimated vs. ground truth Donaldson matrices: scatter plot
figure;
for xx=1:6
for yy=1:4

    plotID = (yy-1)*6 + xx;
    sampleID = (xx-1)*4 + yy;

    subplot(4,6,plotID);
    hold all; grid on; box on;

    plot(dMatEst{sampleID}(:),dMatRef{sampleID}(:),'.');

    rmse = sqrt(mean((dMatEst{sampleID}(:) - dMatRef{sampleID}(:)).^2));
    title(sprintf('RMSE %.2e',rmse));
end
end

% Estimated vs. ground truth Donaldson matrics: scale
figure;
set(gcf,'Colormap',flCmap);
for xx=1:6
for yy=1:4

    plotID = (yy-1)*6 + xx;
    sampleID = (xx-1)*4 + yy;

    subplot(4,6,plotID);
    
    data = [dMatEst{sampleID} dMatRef{sampleID}];
    imagesc(wave, [wave wave], data);

end
end


% Estimated vs. ground truth Donaldson matrics: shape
figure;
set(gcf,'Colormap',flCmap);
for xx=1:6
for yy=1:4

    plotID = (yy-1)*6 + xx;
    sampleID = (xx-1)*4 + yy;

    subplot(4,6,plotID);
    
    data = [dMatEst{sampleID}/max(dMatEst{sampleID}(:)) dMatRef{sampleID}/max(dMatRef{sampleID}(:))];
    imagesc(wave,[wave wave],data);

end
end