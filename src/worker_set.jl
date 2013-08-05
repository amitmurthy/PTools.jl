
import Base.remotecall
import Base.remotecall_fetch
import Base.remotecall_wait


const WS_MODE_RR = 1    # Round Robin
const WS_MODE_FF = 2    # First Free

export WS_MODE_RR, WS_MODE_FF
export WorkerSet

type WorkerSet
    idset::Array{Int,1}
    freeset::Array{Int,1}
    nextidx::Int
    mode::Int
    req_wait::RemoteRef
    worker_wait::RemoteRef
    
    WorkerSet(w, mode) = begin
        ws = new(w, w, 1, mode, RemoteRef(), RemoteRef())
        if (mode == WS_MODE_FF)
            # start a new task that will manage the request Q
            @schedule begin
                manage_q(ws)
            end
        end
        ws
    end
end

WorkerSet(w) = WorkerSet(w, WS_MODE_RR)


function remotecall(ws::WorkerSet, f, args...) 
    if (ws.mode != WS_MODE_RR)
        error("remotecall(WorkerSet) only supported in WS_MODE_RR mode")
    end
    
    remotecall(chooseproc(ws), f, args...)
end

remotecall_fetch(ws::WorkerSet, f, args...) = remotecall_internal(ws, :FETCH, f, args...) 
remotecall_wait(ws::WorkerSet, f, args...) = remotecall_internal(ws, :WAIT, f, args...) 

function remotecall_internal(ws::WorkerSet, rrtype, f, args...) 
    if (ws.mode == WS_MODE_RR)
        if (rrtype == :FETCH)
            return remotecall_fetch(chooseproc(ws), f, args...)
        else
            return remotecall_wait(chooseproc(ws), f, args...)
        end
    elseif (ws.mode == WS_MODE_FF)
        if length(ws.freeset) > 0
            id = shift!(ws.freeset)
            if rrtype == :FETCH
                resp = remotecall_fetch(id, f, args...)
            else
                resp = remotecall_wait(id, f, args...)
            end
            push_and_notify(ws, id)
            return resp
        else
            rr = RemoteRef()
            put(ws.req_wait, (rr, () -> f(args...), rrtype))
            return take(rr)
        end
    end
    error("Unsupported WorkerSet mode $(ws.mode)")
end 


function chooseproc(ws::WorkerSet)
    nextidx = ws.nextidx
    if nextidx > length(ws.idset)
        p = ws.idset[1]
        ws.nextidx = 2
    else 
        p = ws.idset[nextidx]
        ws.nextidx += 1
    end
    p
end


function manage_q(ws::WorkerSet)
#    println("Started manage_q")
    while (true)
    
        # Tuple of remoteref, remotefunction and type.
        (rr, c, t) = take(ws.req_wait)
#        println("Got a Queued request")
        if length(ws.freeset) == 0
#            println("Waiting for a free worker")
            take(ws.worker_wait)
        end
        if length(ws.freeset) == 0
            println("FIXME: No Free Worker found")
            continue
        end
        
        id = shift!(ws.freeset)
        @async let id=id,c=c,rr=rr
            if t == :FETCH
                resp = remotecall_fetch(id, c)
            else
                resp = remotecall_wait(id, c)
            end
            push_and_notify(ws, id)
            put(rr, resp)
        end
    end
end

function push_and_notify(ws, id)
    push!(ws.freeset, id)
    if (!isready(ws.worker_wait))
        put(ws.worker_wait, true)
    end
end