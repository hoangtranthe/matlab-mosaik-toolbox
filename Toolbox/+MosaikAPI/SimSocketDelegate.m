classdef SimSocketDelegate < MosaikAPI.Handle
    % SIMSOCKETDELEGATE   Abstract delegate class for SimSocket
    %   Required delegate methods are:
    %    - response = simSocketReceivedRequest(this,simSocket,request);
    
    methods (Abstract)

    	% Abstract request parse and call method.
        simSocketReceivedRequest(this,request);

    end
    
end