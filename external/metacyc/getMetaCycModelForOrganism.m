function model=getMetaCycModelForOrganism(organismID,fastaFile,...
    keepTransportRxns,keepUnbalanced,keepUndetermined,minScore,minPositives,useDiamond)
% getMetaCycModelForOrganism
%   Reconstructs a genome-scale metabolic model based on protein homology to the
%   MetaCyc pathway database
%
%   Input:
%   organismID          the query organism's abbreviation, which is defined
%                       by user
%   fastaFile           a FASTA file that contains the protein sequences of
%                       the organism for which to reconstruct a model
%   keepTransportRxns   include transportation reactions, which often have identical
%                       reactants and products that turn to be all-zero columns in
%                       the S matrix (opt, default false)
%   keepUnbalanced      include reactions cannot be unbalanced reactions, usually
%                       because they are polymeric reactions or because of a
%                       specific difficulty in balancing class structures
%                       (opt, default false)
%   keepUndetermined    include reactions that have substrates lack chemical
%                       structures or with non-numerical coefficients (e.g. n+1)
%                       (opt, default false)
%   minScore            minimum Bit scores of BLASTp search (opt, default 100)
%   minPositives        minimum Positives values of BLASTp search (opt, default 45 %)
%   useDiamond          use DIAMOND alignment tools to perform homology search
%                       if true, otherwise the BLASTP is used (opt, default true)
%
%   Output:
%   model               a model structure for the query organism
%
%   Usage: model=getMetaCycModelForOrganism(organismID,fastaFile,...
%    keepTransportRxns,keepUnbalanced,keepUndetermined,minScore,minPositives,useDiamond)

if nargin<2
    EM='No query protein fasta file is specified';
    dispEM(EM);
end
if nargin<3
    keepTransportRxns=false;
end
if nargin<4
    keepUnbalanced=false;
end
if nargin<5
    keepUndetermined=false;
end
if nargin<6
    minScore=100;
end
if nargin<7
    minPositives=45;
end
if nargin<8
    useDiamond=true;
end

if isempty(fastaFile)
    error('*** The query FASTA filename cannot be empty! ***');
else
    fprintf('\nChecking existence of query FASTA file... ');
    %Check if query fasta exists
    fastaFile=checkFileExistence(fastaFile,true,false);
    fprintf('done\n');
end

%First generate the full MetaCyc model
metaCycModel=getModelFromMetaCyc([],keepTransportRxns,keepUnbalanced,keepUndetermined);
fprintf('The full MetaCyc model loaded\n');

%Create the draft model from MetaCyc super model model=metaCycModel;
model.id=organismID;
model.description='Generated by homology with MetaCyc database';
model.rxns=metaCycModel.rxns;
model.rxnNames=metaCycModel.rxnNames;
model.eccodes=metaCycModel.eccodes;
model.subSystems=metaCycModel.subSystems;
model.rxnMiriams=metaCycModel.rxnMiriams;
model.rxnReferences=metaCycModel.rxnReferences;
model.lb=metaCycModel.lb;
model.ub=metaCycModel.ub;
model.rev=metaCycModel.rev;
model.c=metaCycModel.c;
model.equations=metaCycModel.equations;

%Get the 'external' directory for RAVEN Toolbox.
[ST I]=dbstack('-completenames');
ravenPath=fileparts(fileparts(ST(I).file));

%Generate blast strcture by either DIAMOND or BLASTP
if useDiamond
    blastStruc=getDiamond(organismID,fastaFile,{'MetaCyc'},fullfile(ravenPath,'metacyc','protseq.fsa'));
else
    blastStruc=getBlast(organismID,fastaFile,{'MetaCyc'},fullfile(ravenPath,'metacyc','protseq.fsa'));
end

%Only look the query
blastStructure=blastStruc(2);

%Remove all blast hits that are below the cutoffs
indexes=blastStructure.bitscore>=minScore & blastStructure.ppos>=minPositives;
blastStructure.toGenes(~indexes)=[];
blastStructure.fromGenes(~indexes)=[];
blastStructure.evalue(~indexes)=[];
blastStructure.aligLen(~indexes)=[];
blastStructure.identity(~indexes)=[];
blastStructure.bitscore(~indexes)=[];
blastStructure.ppos(~indexes)=[];
fprintf('Completed searching against MetaCyc protein sequences.\n');

% Get the qualified genes of query organism from blast structure
model.genes=cell(10000,1);
model.proteins=cell(10000,1);
model.bitscore=zeros(10000,1);
model.ppos=zeros(10000,1);
num=1;

%Go through the strucutre and find out the hit with the best bit score
for i=1:numel(blastStructure.fromGenes)
    if num==1
        model.genes(num)=blastStructure.fromGenes(i);
        model.proteins(num)=strrep(blastStructure.toGenes(i), 'gnl|META|', '');
        model.bitscore(num)=blastStructure.bitscore(i);
        model.ppos(num)=blastStructure.ppos(i);
        num=num+1;
        lastGene=blastStructure.fromGenes(i);
    else
        if ~isequal(lastGene,blastStructure.fromGenes(i))
            model.genes(num)=blastStructure.fromGenes(i);
            model.proteins(num)=strrep(blastStructure.toGenes(i), 'gnl|META|', '');
            model.bitscore(num)=blastStructure.bitscore(i);
            model.ppos(num)=blastStructure.ppos(i);
            num=num+1;
            lastGene=blastStructure.fromGenes(i);
        else
            if model.bitscore(num)<blastStructure.bitscore(i)
                model.bitscore(num)=blastStructure.bitscore(i);
                model.proteins(num)=strrep(blastStructure.toGenes(i), 'gnl|META|', '');
                model.ppos(num)=blastStructure.ppos(i);
            end
        end
    end
end
model.genes=model.genes(1:num-1);
model.proteins=model.proteins(1:num-1);
model.bitscore=model.bitscore(1:num-1);
model.ppos=model.ppos(1:num-1);

% Get the indexes of matched genes in the metaCycModel
% because some enzymes in the FASTA file cannot be found in the dump file
[hits, indexes]=ismember(model.proteins,metaCycModel.genes);
found = find(hits);
model.genes=model.genes(found);

% Restructure the rxnGeneMat matrix
model.rxnGeneMat=sparse(metaCycModel.rxnGeneMat(:,indexes(found)));

%Remove all reactions without genes
hasGenes=any(model.rxnGeneMat,2);
model=removeReactions(model,~hasGenes,true);

%Generate grRules, only consider the or relationship here Matched enzymes
%are stored in field rxnScores,
rxnNum=numel(model.rxns);
model.rxnConfidenceScores=NaN(rxnNum,1);
model.rxnConfidenceScores(:)=2;
model.grRules=cell(rxnNum,1);
%model.rxnScores=cell(rxnNum,1);
for j=1:rxnNum
    model.grRules{j}='';
    I=find(model.rxnGeneMat(j,:));
    for k=1:numel(I)
        if isempty(model.grRules{j})
            model.grRules(j)=model.genes(I(k));
            %model.rxnScores(j)=model.proteins(I(k));
        else
            model.grRules(j)=strcat(model.grRules(j),{' or '},model.genes(I(k)));
            %model.rxnScores(j)=strcat(model.rxnScores(j),{' or
            %'},model.proteins(I(k)));
        end
    end
end
%update genes field
model.genes=model.genes(any(model.rxnGeneMat));

%Construct the S matrix and list of metabolites
[S, mets, badRxns]=constructS(model.equations);
model.S=S;
model.mets=mets;

%model=removeReactions(model,badRxns,true,true);

%Then match up metabolites
metaCycMets=getMetsFromMetaCyc([]);

%Add information about all metabolites to the model
[a, b]=ismember(model.mets,metaCycMets.mets);
a=find(a);
b=b(a);

if ~isfield(model,'metNames')
    model.metNames=cell(numel(model.mets),1);
    model.metNames(:)={''};
end
model.metNames(a)=metaCycMets.metNames(b);

if ~isfield(model,'metFormulas')
    model.metFormulas=cell(numel(model.mets),1);
    model.metFormulas(:)={''};
end
model.metFormulas(a)=metaCycMets.metFormulas(b);

if ~isfield(model,'metCharges')
    model.metCharges=zeros(numel(model.mets),1);
end
model.metCharges(a)=metaCycMets.metCharges(b);

if ~isfield(model,'b')
    model.b=zeros(numel(model.mets),1);
end
%model.b(a)=metaCycMets.b(b);

if ~isfield(model,'inchis')
    model.inchis=cell(numel(model.mets),1);
    model.inchis(:)={''};
end
model.inchis(a)=metaCycMets.inchis(b);

if ~isfield(model,'metMiriams')
    model.metMiriams=cell(numel(model.mets),1);
end
model.metMiriams(a)=metaCycMets.metMiriams(b);

%Put all metabolites in one compartment called 's' (for system). This is
%done just to be more compatible with the rest of the code
model.comps={'s'};
model.compNames={'System'};
model.metComps=ones(numel(model.mets),1);

%It could also be that the metabolite names are empty for some reason In
%that case, use the ID instead
I=cellfun(@isempty,model.metNames);
model.metNames(I)=model.mets(I);

%Remove additional fields
model=rmfield(model,{'proteins','bitscore','ppos'});

%In the end fix grRules and rxnGeneMat
[grRules,rxnGeneMat] = standardizeGrRules(model,false); %Get detailed output
model.grRules = grRules;
model.rxnGeneMat = rxnGeneMat;
end
