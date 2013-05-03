module PersistentTask

export pers_task, mk_pers_tasks, pmap

function pers_task(wrr::RemoteRef)
    msg = take(wrr)

    while(true)
        # execute the function
        println(msg)
        (msg_type, resp_rr, f, args) = msg
        local response
        if (msg_type == :msg)
            try
                response = apply(f, args)
            catch e
                response = "caught : " * string(e)
            end
        end
        
        put(resp_rr, response)
    
        # wait for the next request
        msg = take(wrr)
    end
end



function mk_pers_tasks()
    # Creates one persistent task per Worker
    # First create remote refs for each of them...this will be used to comunicate with the tasks...
    # If nprocs > 1 then only the workers will be used for task processing.
    
    np = nprocs()
    
    wp_start = (np > 1) ? 2 : 1
    
    rr_list = [RemoteRef(i)::RemoteRef for i in wp_start:np]
    
    # start the tasks 
    [remotecall(i, pers_task, rr_list[i-1]) for i in wp_start:np]
    
    rr_list
end


function pmap(f::Function, t::Array{RemoteRef, 1}, lsts...)
    nw = length(t)
    if lsts != ()
        if nw != length(lsts[1]) error ("dimension of persistent tasks must be same as jobs") end
    end
    
    srr_arr = cell(nw)
    i = 1
    for rr in t
        srr_arr[i] = RemoteRef()
        args = map(L -> L[i], lsts)
        put(rr, (:msg, srr_arr[i], f, args))
        i += 1
    end
    
    [take(srr) for srr in srr_arr]
end



end

