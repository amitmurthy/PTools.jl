PTools
======

A collection of utilities for parallel computation in Julia

Currently the following are available.

- ```WorkerSet``` - The ability to logically pool a set of workers for specific tasks.

- ```pfork``` - Parallelism using the UNIX ```fork``` system call.

- ServerTasks - These are long running tasks that simply processes incoming requests in a loop. Useful in situations where 
  state needs to be maintained across function calls. State can be maintained and retrieved using the task_local_storage methods.
  
- SharedMemory - Useful in the event of parallel procesing on a single large multi-core machine. Avoids the overhead associated 
  with sending/recieving large data sets.

- [QueuedTasks](QUEUEDTASKS.md) - Schedule tasks to be executed by remote worker processes. Set/change priorities on the task to control order of execution.

Platforms
=========
- Tested on Ubuntu 13.04
- Should work on OSX
- SharedMemory will not work on Windows. ServerTasks should.
- pfork is a UNIX only implementation


WorkerSet
=========
- A WorkerSet is just an array of process ids

- A WorkerSet is created using ```WorkerSet(w::Array{Integer}, mode)``` where ```mode``` is either of 
  WS_MODE_RR or WS_MODE_FF where 
  
- WS_MODE_RR enables the workers to be used in a round-robin fashion

- WS_MODE_FF tracks which of the workers are busy and sends the request only to a free one.
  It queues the requests if all the workers in the set are busy. 
  
- The ```remotecall*``` functions have been extended to support WorkerSet

```
remotecall(ws::WorkerSet, f, args...) 
remotecall_fetch(ws::WorkerSet, f, args...) 
remotecall_wait(ws::WorkerSet, f, args...) 
```

- The behaviour is the same, except that the functions are executed only on the processes belonging to the 
  WorkerSet and follow the model as specified by ```mode```.
  
pfork
=====

- It uses the UNIX ```fork()``` system call to execute a function in parallel.

- ```pfork(nforks::Integer, f::Function, args...)``` forks ```nforks``` times and executes ```f``` in each child.

- The first parameter to ```f``` is the forked child index.

- ```pfork``` returns an array of size ```nforks```, where the nth element is the value returned by the nth forked child.

- Passing huge amounts of data to the function in the child process is a non-issue since it is a fork.

- In the event the parent process has a shared memory segment, the children have full visibility 
  into the same and can modify the segment in place. They don't have to bother with returning huge 
  amounts of data either.
  
- Currently can only be executed when nprocs() == 1, i.e., this model is incompatible with the worker model.

- Unpredictable behavior if the function to be executed in the forked children calls yield() AND other I/O tasks 
  are concurrently active. Can be used only where f is fully compute bound.



Usage of Server Tasks
=====================
Typical usage pattern will be 

- ```start_stasks``` - Start Server Tasks, optionally with shared memory mappings.

- Execute a series of functions in parallel on these tasks using multiple invocations of ```pmap_stasks```

- SomeFunction 
- SomeOtherFunction
- SomeOtherFunction
.
.
.

- ```stop_stasks``` - Stop all Server Tasks and free shared memory if required.


The user specified functions in pmap_stasks can store and retrieve state information using the task_local_storage functions.

  
  
Example for shared memory and server tasks
==========================================
The best way to understand what is available is by example:

- specify shared memory configuration. 

```
using PTools

shmcfg = [ShmCfg(:svar1, Int32, 64*1024), ShmCfg(:svar2, Uint8, (100,100))]
```
- the above line requests for a 64K Int32 array bound to ```svar1```, and a 100x100 Uint8 array bound to ```svar2```


- Start tasks. 
```
h = start_stasks(shmcfg)
ntasks = count_stasks(h)
```
- The tasks are started and symbols pointing to shared memory segments are added as task local storage. A handle is returned.
- The shared memory segments are also mapped in the current tasks local storage.
- NOTE: If nprocs() > 1, then only the Worker Julia processes are used to start the Server Tasks, i.e., if nprocs() == 5, then ntasks above would be 4.


- Prepare arguments for our pmap call
```
offset_list = [i for i in 1:ntasks]
ntasks_list = [ntasks for i in 1:ntasks]
```

- Execute our function in parallel.
```
resp = pmap_stasks(h, (offset, ntasks) -> begin
                        # get local refernces to shared memory mapped arrays
                        svar1 = task_local_storage(:svar1)
                        svar2 = task_local_storage(:svar2)
                        
                        mypid = myid()
                        for x in offset:ntasks:64*1024
                            svar1[x] = mypid
                        end
                        
                        true
                        
                    end,
                    
                    offset_list, ntasks_list)
```

- Access shared memory segments and view changes

```
svar1 = task_local_storage(:svar1)
println(svar1)
```
svar1 will the values as updated by the Server Tasks.


- Finally stop the tasks

```
stop_stasks(h, shmcfg)
```

This causes all tasks to be stopped and the shared memory unmapped.
 

Exported functions for ServerTasks
==================================
```start_stasks(shmcfg=false, shmpfx=false)``` where shmcfg is an optional parameter. It is either a ShmCfg(name::Symbol, t::Type, d::dims) or Array{ShmCfg, 1}. 
Returns a handle to the set of ServerTasks.

```pmap_stasks(h::STasks, f::Function, lsts...)``` is similar to pmap, except that the first parameter is the handle returned by start_tasks. 
NOTE: that the length of ```lsts``` and number of ServerTasks must be identical. 

```stop_stasks(h::STasks, shmcfg=false, shmpfx=false)``` stops all tasks and also frees the shared memory

```count_stasks(h::STasks)``` returns the number of ServerTasks - can be used to partition the compute job.

NOTE: shmpfx should be set to a distinct string in case you are sharing the server with other users or have multiple self concurrent jobs active.

Exported functions for Shared Memory support
============================================
```pmap_shm_create(shmcfg, shmpfx="")``` - creates and maps the shared memory segments to global symbols in each Julia process. shmcfg 
can be ShmCfg(name::Symbol, t::Type, d::dims) or Array{ShmCfg, 1}

```unlink_shm(shmcfg, shmpfx="")``` - frees the shared memory

NOTE: For a single run, it is important that shmpfx is passed with same value to all the methods.


Under Linux, you can view the shared memory mappings under /dev/shm
In the event of abnormal program termination, where unlink_shm has not been called it is important 
to manually delete all segments allocated by the program. The name of the segments will be 
of the form ```/dev/julia_<shmpfx>_<symbol_name>```

