function version = getToolboxVersion(toolbox,fileID,masterFlag)
% getToolboxVersion
%   Returns the version of a given toolbox, or if not available the latest
%   commit hash (7 characters).
%
%   toolbox         string with the toolbox name (e.g. "RAVEN")
%   fileID          string with the name of a file that is only found in
%                   the corresponding toolbox (e.g. "ravenCobraWrapper.m").
%   masterFlag      logical, if true, function will error if the toolbox is
%                   not on the master branch (opt, default false).
%
%   version         string containing either the toolbox version or latest
%                   commit hash (7 characters).
%
%   Usage: version = getToolboxVersion(toolbox,fileID,masterFlag)

if nargin<3
    masterFlag = false;
end

currentPath = pwd;
version     = '';

%Try to find root of toolbox:
try
    toolboxPath = which(fileID);                %full file path
    slashPos    = getSlashPos(toolboxPath);
    toolboxPath = toolboxPath(1:slashPos(end)); %folder path
    %Go up until the root is found:
    D = dir(toolboxPath);
    while ~ismember({'.git'},{D.name})
        slashPos    = getSlashPos(toolboxPath);
        toolboxPath = toolboxPath(1:slashPos(end-1));
        D           = dir(toolboxPath);
    end
    cd(toolboxPath);
catch
    disp([toolbox ' toolbox cannot be found'])
    version = 'unknown';
end
%Check if in master:
if masterFlag
    currentBranch = git('rev-parse --abbrev-ref HEAD');
    if ~strcmp(currentBranch,'master')
        cd(currentPath);
        error(['ERROR: ' toolbox ' not in master. Check-out the master branch of ' toolbox ' before submitting model for Git.'])
    end
end
%Try to find version file of the toolbox:
if isempty(version)
    try
        fid     = fopen([toolboxPath 'version.txt'],'r');
        version = fscanf(fid,'%s');
        fclose(fid);
    catch
        %If no file available, look up the tag:
        try
            version = git('describe --tags');
            commit  = git('log -n 1 --format=%H');
            commit = commit(1:7);
            %If no tag available or commit is part of tag, get commit instead:
            if ~isempty(strfind(version,'fatal')) || ~isempty(strfind(version,commit))
                version = ['commit ' commit];
            else
                version = strrep(version,'v','');
            end
        catch
            version = 'unknown';
        end
    end
end
cd(currentPath);
end

function slashPos = getSlashPos(path)
slashPos = strfind(path,'\');       %Windows
if isempty(slashPos)
    slashPos = strfind(path,'/');   %MAC/Linux
end
end
