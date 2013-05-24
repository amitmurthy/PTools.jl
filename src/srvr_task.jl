
export stask_run, start_stasks, count_stasks, stop_stasks, pmap_stasks

typealias STasks Array{RemoteRef, 1}

function stask_run(wrr::RemoteRef)
    msg = take(wrr)

    while(true)
        # execute the function
#        println(msg)
        (msg_type, resp_rr, f, args) = msg
        local response
        if (msg_type == :execfun)
            try
                response = apply(f, args)
                put(resp_rr, (:ok, response))
            catch e
                println(e)
                put(resp_rr, (:err, "exception : " * string(e)))
            end
        elseif (msg_type == :exit)
            put(resp_rr, :ok)
            return
        end
    
        # wait for the next request
        msg = take(wrr)
    end
end


function start_stasks(shmcfg=false, shmpfx=false)
    # Creates one persistent task per Worker
    # First create remote refs for each of them...this will be used to comunicate with the tasks...
    # If nprocs > 1 then only the workers will be used for task processing.
    
    np = nprocs()
    
    wp_start = (np > 1) ? 2 : 1
    pid_add = (np > 1) ? 1 : 0
    
    stasks = [RemoteRef(i)::RemoteRef for i in wp_start:np]
    
    # start the tasks 
    [remotecall(i+pid_add, stask_run, stasks[i]) for i in 1:length(stasks)]
    
    if shmcfg != false
        unlink_shm(shmcfg, shmpfx)
        # local
        setup_shm(shmcfg, shmpfx)
        
        # Map each symbol into the stasks task_local_storage()
        pmap_stasks(stasks, () -> setup_shm(shmcfg, shmpfx, false))
    end
    
    stasks::STasks
end

function stop_stasks(stasks::STasks, shmcfg=false, shmpfx=false)
    srr_arr = cell(length(stasks))
    i = 1
    for rr in stasks
        srr_arr[i] = RemoteRef()
        put(rr, (:exit, srr_arr[i], nothing, ()))
        i += 1
    end
    
    # Just unlink shmcfg is present
    if (shmcfg != false)
        unlink_shm(shmcfg, shmpfx)    
    end
end



function pmap_stasks(stasks::STasks, f::Function, lsts...)
    nw = length(stasks)
    if lsts != ()
        if nw != length(lsts[1]) error ("dimension of persistent tasks must be same as jobs") end
    end
    
    srr_arr = cell(nw)
    i = 1
    for rr in stasks
        srr_arr[i] = RemoteRef()
        args = map(L -> L[i], lsts)
        put(rr, (:execfun, srr_arr[i], f, args))
        i += 1
    end
    
    resplist = [take(srr) for srr in srr_arr]
    statuses = [e[1] for e in resplist]
    responses = [e[2] for e in resplist]
    
    if all(x -> x == :ok, statuses) == true
        return (:ok, responses)
    else
        return (statuses, responses)
    end
end

count_stasks(stasks::STasks) = length(stasks)



