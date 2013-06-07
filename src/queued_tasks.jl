using Base.Collections

export  num_remotes, prep_remotes,
        execute_worker_task, queue_worker_task, dequeue_worker_task, set_priorities, 
        WorkerTask, QueuedWorkerTask

safe_dequeue!(pq::PriorityQueue, key) = try dequeue!(pq,key) end

typealias FuncNone  Union(Function,Nothing)

##n account of the worker machines available
const _remotes = Array(Vector{ASCIIString},0)
const _all_remote_names = Set{String}()
num_remotes() = length(_remotes[1])
function prep_remotes(force::Bool=false)
    !force && (0 != length(_remotes)) && return
    empty!(_remotes)
    empty!(_all_remote_names)

    n = nprocs()
    ips = Array(ASCIIString, n-1)
    hns = Array(ASCIIString, n-1)
    for midx in 2:n
        ips[midx-1] = remotecall_fetch(midx, getipaddr)
        hns[midx-1] = remotecall_fetch(midx, gethostname)
    end

    for x in (ips, hns)
        push!(_remotes, x)
        union!(_all_remote_names, x)
        unshift!(x, "")     # to represent the default worker node
    end
end


# Worker task type. One of: map, file_info, reduce(in future)
# target can be:
#   - proc id, or a list of procids
#   - machine ip/hostname, or a list of ips/hostnames
#   - :wrkr_all, :wrkr_any
abstract WorkerTask
type QueuedWorkerTask
    wtask::WorkerTask
    remote_method::Function
    callback::FuncNone
    target::Union(Int,ASCIIString,Symbol,Vector{ASCIIString},Vector{Int})
    qtime::Float64
    function QueuedWorkerTask(wtask::WorkerTask, remote_method::Function, callback::FuncNone, target::Union(Int,ASCIIString,Symbol,Vector{ASCIIString},Vector{Int}))
        new(wtask, remote_method, callback, target, time())
    end
end


# Queues for distributing tasks
# TODO: use priorityqueues
const _machine_tasks = Dict{ASCIIString, PriorityQueue{QueuedWorkerTask,Float64}}()
const _procid_tasks = Dict{Int, PriorityQueue{QueuedWorkerTask, Float64}}()
const _any_tasks = PriorityQueue{QueuedWorkerTask,Float64}()

function _remap_macs_to_procs(macs)
    available_macs = filter(x->contains(_all_remote_names, x), macs)
    (length(available_macs) == 0) && (available_macs = filter(x->contains(_all_remote_names, x), map(x->split(x,".")[1], macs)))
    (length(available_macs) == 0) && push!(available_macs, "")
    available_macs
end

function execute_worker_task(t::QueuedWorkerTask)
    r = RemoteRef()
    function cb(w::WorkerTask, ret)
        put(r, ret)
    end
    t.callback = cb
    queue_worker_task(t)
    result = fetch(r)
    isa(result, Exception) && throw(result)
    result
end

function queue_worker_task(t::QueuedWorkerTask) 
    _queue_worker_task(t, t.target)
    _start_feeders()
end
function _queue_worker_task(t::QueuedWorkerTask, procid::Int)
    !haskey(_procid_tasks, procid) && (_procid_tasks[procid] = PriorityQueue{QueuedWorkerTask,Float64}())
    (_procid_tasks[procid])[t] = Inf
end
_queue_worker_task(t::QueuedWorkerTask, procid_list::Vector{Int}) = for procid in procid_list _queue_worker_task(t, procid) end
function _queue_worker_task(t::QueuedWorkerTask, machine::ASCIIString)
    !haskey(_machine_tasks, machine) && (_machine_tasks[machine] = PriorityQueue{QueuedWorkerTask,Float64}())
    (_machine_tasks[machine])[t] = Inf
end
_queue_worker_task(t::QueuedWorkerTask, machine_list::Vector{ASCIIString}) = for machine in _remap_macs_to_procs(machine_list) _queue_worker_task(t, machine) end
function _queue_worker_task(t::QueuedWorkerTask, s::Symbol)
    (:wrkr_all == s) && return _queue_worker_task(t::QueuedWorkerTask, [1:num_remotes()])
    (:wrkr_any == s) && return (_any_tasks[t] = Inf)
    error("unknown queue $(s)")
end

dequeue_worker_task(t::QueuedWorkerTask) = _dequeue_worker_task(t::QueuedWorkerTask, t.target)
_dequeue_worker_task(t::QueuedWorkerTask, procid::Int) = haskey(_procid_tasks, procid) && safe_dequeue!(_procid_tasks[procid], t)
_dequeue_worker_task(t::QueuedWorkerTask, procid_list::Vector{Int}) = for procid in procid_list _dequeue_worker_task(t, procid) end
_dequeue_worker_task(t::QueuedWorkerTask, machine::ASCIIString) = haskey(_machine_tasks, machine) && safe_dequeue!(_machine_tasks[machine], t)
_dequeue_worker_task(t::QueuedWorkerTask, machine_list::Vector{ASCIIString}) = for machine in _remap_macs_to_procs(machine_list) _dequeue_worker_task(t, machine) end
function _dequeue_worker_task(t::QueuedWorkerTask, s::Symbol)
    (:wrkr_all == s) && return _dequeue_worker_task(t, [1:num_remotes()])
    (:wrkr_any == s) && return safe_dequeue!(_any_tasks, t)
    error("unknown queue $(s)")
end
function dequeue_worker_task(filter_fn::Function)
    del_set = Set{QueuedWorkerTask}()

    function filter_from(pq)
        for (k1,v1) in pq
            !filter_fn(k1) && add!(del_set, k1)
        end
    end

    for (_,v) in _machine_tasks filter_from(v) end
    for (_,v) in _procid_tasks filter_from(v) end
    filter_from(_any_tasks)
    for dt in del_set dequeue_worker_task(dt) end
end

##
# scheduler function
function set_priorities(calc_prio::Function)
    for (k,v) in _machine_tasks for (k1,v1) in v v[k1] = calc_prio(k, k1, v1) end end
    for (k,v) in _procid_tasks for (k1,v1) in v v[k1] = calc_prio(k, k1, v1) end end
    for (k1, v1) in _any_tasks _any_tasks[k1] = calc_prio(:wrkr_any, k1, v1) end
end

const _feeders = Dict{Int,RemoteRef}()
function _start_feeders()
    _debug && println("starting feeders...")
    # start feeder tasks if required
    for procid in 1:num_remotes()
        haskey(_feeders, procid) && !isready(_feeders[procid]) && continue
        ip, hn = map(x->x[procid], _remotes)
        (nothing == _fetch_tasks(procid, ip, hn, true)) && continue
        _debug && println("\tstarting feeder for $(procid)")
        _feeders[procid] = @async _push_to_worker(procid)
    end
end

function _fetch_tasks(proc_id::Int, ip::String, hn::String, onlypeek::Bool=false)
    v = PriorityQueue{PriorityQueue,Float64}()
    function add_to_fp(q)
        (length(q) > 0) && (v[q] = peek(q)[2])
    end

    !((proc_id == 1) && (num_remotes() > 1)) && add_to_fp(_any_tasks)
    haskey(_procid_tasks, proc_id) && add_to_fp(_procid_tasks[proc_id])
    haskey(_machine_tasks, ip) && add_to_fp(_machine_tasks[ip])
    haskey(_machine_tasks, hn) && add_to_fp(_machine_tasks[hn])

    ((v == nothing) || (0 == length(v))) && return nothing

    onlypeek && (return ((length(v) > 0) ? peek(peek(v)[1]) : nothing))

    qtask = dequeue!(dequeue!(v))
    (:wrkr_all != qtask.target) && dequeue_worker_task(qtask)
    qtask
end


function _push_to_worker(procid)
    ip, hn = map(x->x[procid], _remotes)

    while(true)
        # if no tasks, exit task
        qtask = _fetch_tasks(procid, ip, hn)
        (qtask == nothing) && return

        wtask = qtask.wtask

        # call method at worker
        _debug && println("-> $(procid) $(wtask)")
        ret = remotecall_fetch(procid, qtask.remote_method, wtask)
        _debug && println("<- $(procid) $(wtask)")

        try
            if(nothing != qtask.callback) 
                _debug && println("0> $(procid) $(wtask) $(typeof(ret))")
                qtask.callback(wtask, ret)
                _debug && println("<0 $(procid) $(wtask) $(typeof(ret))")
            end
        catch ex
            _debug && println("error in callback $(ex)")
            _debug && println("returned value: $(ret)")
        end
    end
end


