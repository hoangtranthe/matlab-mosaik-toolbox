classdef Simulator < MosaikAPI.SimSocketDelegate
    % SIMULATOR   Simulator superclass.
    %   Provides socket communication methods and abstract methods the simulator needs to implement.

    properties (Constant)

        api_version = 2    % API version

    end
    
    properties

        socket             % Associated socket client
        mosaik             % Assiciated mosaik proxy
        sid = 'Matlab'     % Simulator ID
        shutdown = false   % Instance shutdown toggle

    end
    
    
    methods
        
        function this = Simulator(server,varargin)
            % Constructor of the class Simulator
            %
            % Parameter:
            %  - server: String object containing server IP and port, format: 'IP:port'.
            %  - varargin: Optional parameter value list
            %              debug: false (default)|true - Create the simulator in
            %              debug mode where no socket server is started.
            %              message:output: false (default)|true - Shows socket
            %              communication messages. 
            %
            % Return:
            %  - this: Simulator object
            
            p = inputParser;
            addRequired(p,'server',@ischar);
            addOptional(p,'debug',false,@islogical);
            parse(p,server,varargin{:});
            
            server = p.Results.server;
            
            % Gets server from mosaik and start tcpclient at given host and port.
            assert(~isempty(strfind(server,':')), 'Wrong server configuration. Check server configuration.')
            [ip,port] = parse_address(this,server);

            this.mosaik = MosaikAPI.MosaikProxy(this);
            
            if ~p.Results.debug
                % Creates socket
                this.socket = MosaikAPI.SimSocket(ip,port,this);
                % Starts the socket client and waiting for messages
                this.socket.start();
                % Delete the Socket
                this.socket = [];
                % Call the finalize methode()
                this.finalize();
                % Close Matlab with timer
                if this.shutdown
                    t = timer();
                    t.StartDelay = 1;
                    t.TimerFcn = @(myTimerObj, thisEvent)exit;
                    start(t);
                end
            end
            
        end        
        
        function value = meta(this)
            % Creates meta struct with empty models struct and extra methods cell.
            %
            % Parameter:
            %  - none
            %
            % Return:
            %  - value: Struct object containing meta information.

            value.api_version = this.api_version;
            value.extra_methods = {};
            value.models = struct;

        end
        
        function response = simSocketReceivedRequest(this,request)
            % Parses request and calls simulator function.
            %
            % Parameter:
            %  - request: String object containing request message.
            %
            % Return:
            %  - response: Cell object containing simulator functions response.

            func = request{1};
            func = str2func(func);
            args = request{2};
            kwargs = request{3};
            if ~isa(args,'cell')
                args = {args};
            end
            if numel(request) > 3
                warning('Request has more than 3 arguments, these will be ignored')
            end
            if ~isempty(kwargs)
                kwargs = [fieldnames(kwargs)';struct2cell(kwargs)'];
            else
                kwargs = {};
            end

            % Calls simulator function with parsed arguments
            response = func(this,args{:},kwargs{:});

        end
        
        function stop = stop(this, ~, ~)
            % Closes socket and returns 'stop'.
            %
            % Parameter:
            %  - none
            %
            % Return:
            %  - none

            this.socket.stop();
            stop = ('stop');

        end
        
        function meta = init(this, sid, varargin)
            % Sets simulator ID, verifies input arguments. Returns meta struct.
            %
            % Parameter:
            %  - sid: String object containing simulator id.
            %  - varargin: Struct object containing optional initial parameters.
            %
            % Return:
            %  - this: Struct object containing simulators meta information.

            this.sid = sid;
            
            p = inputParser;
            p.KeepUnmatched = true;
            parse(p,varargin{:})
            
            % TODO step_size must be defined
            if ~isempty(p.Unmatched)
                prop = fieldnames(p.Unmatched);
                for i=1:numel(prop)
                    this.(prop{i}) = p.Unmatched.(prop{i});
                end
            end
            
            meta = this.meta();
            
        end
        
        function finalize(this)
            % Does nothing by default. Can be overridden.
            %
            % Parameter:
            %  - none
            %
            % Return:
            %  - none

        end
        
    end

    methods (Access=private)
        
        function null = setup_done(~)
            % Returns empty response.
            %
            % Parameter:
            %  - none
            %
            % Return:
            %  - none

            null = [];

        end
        
        function [ip, port] = parse_address(~, server)
            % Parses address string. Returns ip as string and port as integer.
            %
            % Parameter:
            %  - server: Server IP and port as char, format: 'IP:port'
            %
            % Return:
            %  - ip: String object containing socket ip adress.
            %  - port: Double object containing socket port.

            server = strsplit(server,':');
            if ~isempty(server(1))
                ip = server{1};
            else
                error('No server IP entered. Check server configuration.')
            end
            if ~isempty(server(2))
                port = server(2);
                port = str2double(port{:});
                assert(isnumeric(port), 'Wrong server port. Check server configuration.')
            else
                error('No server port entered. Check server configuration.')
            end

        end
        
    end    
    
    methods (Abstract)

        % Creates models of specified amount, type and initial parameters.
        %
        % Parameter:
        %  - num: Double object containing amount of model to be created.
        %  - model: String object containing type of models to be created.
        %  - varargin: Struct object containing optional model parameters.
        %
        % Return:
        %  - entity_list: Cell object containing structs containing model information.
        entity_list = create(this,num,model,varargin);

        % Performs simulation step.
        %
        % Parameter:
        %  - time: Double object containing time of this simulation step.
        %  - varargin: Struct object containing input values.
        %
        % Return:
        %  - time_next_step: double objectcontaining time of next simulation step.
        time_next_step = step(this,time,varargin);
        
        % Receives data for requested attributes.
        %
        % Parameter:
        %  - outputs: Struct object containing requested attributes.
        %
        % Return:
        %  - data: Struct object containing requested values.
        data = get_data(this,outputs);        

    end
    
    methods (Static)
        
        function value = concentrateInputs(inputs)
            % Sums up all inputs for each model.
            %
            % Parameter:
            %  - inputs: Struct object containing input values.
            %
            % Return:
            %  - value: Struct object containing summed up input values.

            
            % BUG: does not properly read structs sometimes
            % Workaround
            inputs = loadjson(savejson('',inputs));
            value = structfun(@(x) structfun(@(y) sum(cell2mat(struct2cell(y))),x,'UniformOutput',false), ...
                inputs,'UniformOutput',false);
            
        end

        function names = properFieldnames(struct)
            % Removes hard encoding from struct fieldnames.
            %
            % Parameter:
            %  - struct: Struct object.
            %
            % Return:
            %  - names: Cell object containing struct fieldnames.

            names = fieldnames(struct);
            names = cellfun(@(x) strrep(x, '_0x2E_','.'),names,'UniformOutput',false);
            names = cellfun(@(x) strrep(x, '_0x2D_','-'),names,'UniformOutput',false);

        end

    end

end
