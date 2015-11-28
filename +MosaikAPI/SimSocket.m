classdef SimSocket < handle
    % SIMSOCKET  TCP socket client for MOSAIK.
    %   Provides the basic TCP socket comunication for MOSAIK.
    
    properties

        server					% Server IP
        port					% Server Port
        delegate				% Associated delegate
        message_output = true	% Socket message output toggle

    end
    
    properties (Access=private)

        socket					% Associated tcpclient
        last_id = 0				% Last socket message id
        stopServer = false		% Server shutdown trigger

    end

    methods
        
        function this = SimSocket(server,port,varargin)
            % Constructor of the class SimSocket.
            %
            % Parameter:
            %  - server: String argument; server ip.
            %  - port: Double argument; server port.
            %  - varargin: Optional arguments; associated delegate
            %                                  instance.
            %
            % Return:
            %  - this: SimSocket object.
            
            % Validate und parse the input
            p = inputParser;
            addRequired(p,'server',@ischar);
            addRequired(p,'port',@(x)validateattributes(x,{'numeric'},{'scalar','integer','positive'}));
            addOptional(p,'delegate',[],@(x)isa(x,'MosaikAPI.SimSocketDelegate'));
            parse(p,server,port,varargin{:});
            
            this.server = p.Results.server;
            this.port = p.Results.port;
            this.delegate = p.Results.delegate;
            this.socket = tcpclient(this.server,this.port);

        end
        
        function delete(this)
        	% Remove associated delegate.
        	%
            % Parameter:
            %  - none
            %
            % Return:
            %  - none

            this.delegate = [];

        end
        
    end
    
    methods (Access=private)
        
        function main_loop(this)
        	% Waits for message, deserializes it, sends request to delegate,
        	% receives answer from delegate, serializes it, sends it socket.
        	%
            % Parameter:
            %  - none
            %
            % Return:
            %  - none
                        
            while ~this.stopServer 
                try
                    % Wait for bytes
                    while ~this.socket.BytesAvailable
                        pause(0.001);
                    end
                    
                    % Read and deserialize the request
                    request = read(this.socket);
                    [type,id,content] = this.deserialize(request);

                    % Forward the request to the Delegate
                    %response = content;
                    response = this.delegate.simSocketReceivedRequest(content);
                    
                    % Serialize and write the response
                    response = this.serialize(response,1,id);                    
                    write(this.socket,response);
                    
                catch exception
                    this.socket = [];
                    rethrow(exception)
                end
            end

        end
        
        function message = serialize(this,content,type,varargin)
        	% Converts response from Matlab data types to JSON.
        	%
            % Parameter:
            %  - content: String argument; message content.
            %  - type: Double argument; message type.
            %  - varargin: Double argument; message id.
            %
            % Return:
            %  - message: Bytes object; socket message.

            % if no id is given it is set automaticaly
            if nargin < 4
                varargin{1}=next_request_id(this);
            end
            
            message{3}=content;
            message{1}=type;
            message{2}=varargin{1};            
            
            message = savejson('',message,'ParseLogical',1,'Compact',1);
            message = strrep(message, '_0x2D_','-');
            message = strrep(message, '_0x2E_','.');
            message = strrep(message, sprintf('\t'), '');
            message = strrep(message, sprintf('\n'), '');
            message = strrep(message, ',null', '');
            message = strrep(message, 'null,', '');

            this.outp(message);

            message = [this.make_header(message) uint8(message)];

        end
        
        function [type,id,content] = deserialize(this,message)
        	% Converts request from JSON to Matlab data types.
        	%
            % Parameter:
            %  - message: Byte argument; socket message.
            %
            % Return:
            %  - type: Double object; message type;
            %  - id: Double object; message id;
            %  - content: String object; message content.
            
            this.outp(char(message(5:end)));

            message = loadjson(char(message(5:end)));
            message = savejson('',message)
            message = strrep(message, ',null', '');
            message = strrep(message, 'null,', '');
            disp(message);
            loadjson(message);

            if ~iscell(message)
                message = num2cell(message);
            end

            type = message{1};
            id = message{2};
            if ~lt(numel(message),3)
                content = message{3};
            else
                content = struct;
            end

            this.last_id = id;
            
        end

        function header = make_header(this,message)
        	% Creates byte header for socket message.
        	%
            % Parameter:
            %  - message: String argument; socket message.
            %
            % Return:
            %  - header: Byte object; message size;

            sizeMessage = numel(message);
            header = typecast(swapbytes(uint32(sizeMessage)),'uint8');

        end
        
        function value = next_request_id(this)
        	% Creates next message id.

        	%
            % Parameter:
            %  - none
            %
            % Return:
            %  - value: Double object; message id.

            this.last_id = this.last_id+1;
            value = this.last_id;

        end
        
        function outp(this,message)
        	% If toggled, prints socket messages.
        	%
            % Parameter:
            %  - message: String argument; socket message.
            %
            % Return:
            %  - none

            if this.message_output
                disp(message);
            end

        end
        
    end
    
    methods
        
        function start(this)
        	% Starts main loop.
        	%
            % Parameter:
            %  - none
            %
            % Return:
            %  - none

            assert(~isempty(this.delegate),'You need to specify a delegate before starting the socket');
            this.main_loop();

        end
        
        
        function stop(this)
        	% Activates server stop toggle.
        	%
            % Parameter:
            %  - none
            %
            % Return:
            %  - none

            this.stopServer = true;
        end

        
        
        function response = send_request(this,content)
        	% Sends request to socket server.
        	%
            % Parameter:
            %  - content: Struct argument; socket request message.
            %
            % Return:
            %  - response: Struct argument; socket return message.

            % Serialize and write the request
            request = this.serialize(content,0);
            write(this.socket,request);
            
            % Wait for response
            while ~this.socket.BytesAvailable
                pause(0.001);
            end
            
            % Read and deserialize the response
            response = read(this.socket);
            [~,~,content] = this.deserialize(response);
            response = content;
        end

    end

end
