PTools
======

A collection of utilities for parallel computation in Julia

Currently the following are available.

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

  
Usage
=====
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

  
  
Example
=======
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

