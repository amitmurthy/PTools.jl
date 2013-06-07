## Queued Tasks
Queue tasks to be executed by worker processes. Task priorities determine order of execution. Tasks can be selectively targeted to all workers, any worker or a specified subset of the workers.

File `test/test_queued_tasks.jl` has examples that illustrate API usage.

### Types
#### WorkerTask
Abstract type. All user defined tasks must extend from WorkerTask.

#### QueuedWorkerTask
````
type QueuedWorkerTask
    # the data for the task
    wtask::WorkerTask
    # the remote method to be executed with the data. signature: remote_method(wtask) -> response
    remote_method::Function
    # optional callback to be executed on receipt of response from the remote method. signature: callback(wtask, response)
    callback::Union(Function,Nothing)
    # :wrkr_any, :wrkr_all, one or more of procid / remote hostname / remote IP
    target::Union(Int,ASCIIString,Symbol,Vector{ASCIIString},Vector{Int})
    # time when job was queued
    qtime::Float64
    ...
end

# constructor:
QueuedWorkerTask(wtask, remote_method, callback, target)
````

### APIs
#### Initializing
````
# initialize this library. all worker processes must be started prior to this call
prep_remotes()

# returns the number of remote workers (currently same as nprocs())
num_remotes()

````

#### Execute/Queue/Dequeue Tasks
````
# execute a task at a remote worker and fetch the results
# if any exceptions were thrown by the remote method, the same would be thrown by this method as well
execute_worker_task(t::QueuedWorkerTask)

# queue a task to be executed by a worker at a later point of time
queue_worker_task(t::QueuedWorkerTask)

# remove a task that was queued earlier (and which has not been submitted to any worker yet)
dequeue_worker_task(t::QueuedWorkerTask)

````

#### Setting Task Priorities
````
# set/reset the priorities of tasks queued. 
# calc_prio function returns the current priority value (a Float64) for a given task, target and the current task priority.
# target can either be a single procid, hostname, IP address, or :wrkr_any 
# e.g: calc_prio(target, qt::QueuedWorkerTask, curr_prio::Float64)
set_priorities(calc_prio::Function)
````

