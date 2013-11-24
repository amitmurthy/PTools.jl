export pfork, pfork_shm

function pfork(n::Integer, f::Function, args...)
    if nprocs() > 1
        error("pfork is incompatible with worker processes. Execute a `rmprocs(workers())` and try again.")
    end
    
    pipes = cell(n)
    cpids = cell(n)
    responses=cell(n)
    
    for i in 1:n
        pipe_fds = Array(Cint,2)
        assert( 0 == ccall(:pipe, Cint, (Ptr{Cint},), pipe_fds))    
        pipes[i] = pipe_fds

        cpids[i] = ccall(:fork, Cint, ())
        
        if cpids[i] == 0
            try
                # child 
                # close the read end in the child
                ccall(:close, Cint, (Cint, ),  pipes[i][1])
                
                # seed the random number generator differently for each child...
                srand([uint32(time()), uint32(i)])
                
                rv = f(i, args...)
                
                iob=IOBuffer()
                if rv == nothing
                    serialize(iob, ())
                else
                    serialize(iob, rv)
                end
                
                arr=takebuf_array(iob)
                nb = length(arr)
                nb_pending = nb
                while nb_pending > 0
                    #ssize_t write(int fd, const void *buf, size_t count);
                    bw = ccall(:write, Csize_t, (Cint, Ptr{Uint8}, Csize_t), pipes[i][2], pointer(arr, (nb - nb_pending) + 1), nb_pending)
                    if bw <= 0
                        exit(1)
                    end
                    nb_pending -= bw
                end
                
                #println("child process exiting")
                ccall(:close, Cint, (Cint, ),  pipes[i][2])
            catch e
                println("forked child exiting with exception $e")
            finally 
                exit()
            end
        else
            # close the write end in the parent
            ccall(:close, Cint, (Cint, ),  pipes[i][2])
        end
    end

    # Read all responses and wait for children to exit
    @sync begin
        for i in 1:n
            #read all data in the pipe...
            @async begin
                buf = zeros(Uint8,65536)
                iob = IOBuffer()
                while true 
                    br = ccall(:read, Csize_t, (Cint, Ptr{Uint8}, Csize_t), pipes[i][1], buf, 65536)
                    if br > 0
                        write(iob, buf[1:br])
                    else
                        break;
                    end
                end
                
                #close the read end
                ccall(:close, Cint, (Cint, ),  pipes[i][1])
                
                #retcode = Cint[0]
                #cpid_exited = ccall(:waitpid, Cint, (Cint, Ptr{Cint}, Cint), cpids[i], retcode, 0)
                # Sometimes cpid_exited is -1 and errno is ECHILD, removing check on return value 
                # of waitpid for now.
#                assert(cpid_exited == cpids[i])
                #println("child process $(cpids[i]) exited")
                
                responses[i] = iob
            end
        end
    end
    
    for i in 1:n
        seekstart(responses[i])
        responses[i] = deserialize(responses[i])
    end
    
    responses
end

pfork_shm(n::Int, return_type::Type, return_size::Tuple, f::Function, args...) =
    pfork_shm(n::Int, {(return_type, return_size)}, f::Function, args...)[1]
# forks the current process n times, invoking f, 
# and providing a shared memory segment for the return value
# 
# n                  ... number of forks. passed to pfork
# sharedmems         ... type of the return value. passed to ShmCfg
# retreturn_sizesize ... size of the return value. passed to ShmCfg
# f                  ... function with the signature is f(ind, result, args...)
#                        where result is a shared memory segment of type return_type 
#                        and size return_size

function pfork_shm(n::Int, shmems::Array, f::Function, args...)
  # f                  ... function with the signature is f(ind, result1, .., resultN, args...)

  map(x->assert(isa(x,Tuple)),shmems)

  # set up the shared memory segment
  return_shms = map(x->ShmCfg(gensym("pfork_shm"),x[1],x[2]), shmems)
  unlink_shm(return_shms)
  setup_shm(return_shms)

  # wrap f, passing the return memory segment
  function g(ind, a...)
    rets = map(x->task_local_storage(x.sname), return_shms)
    #@show rets tuple(ind, rets..., a...)
    f(ind, rets..., a...)
    nothing
  end

  # invoke the function
  #@show n g args
  pfork(n, g, args...)

  # release the shared memory segment and return
  unlink_shm(return_shms)
  r = map(x->task_local_storage(x.sname), return_shms)
  map(x->task_local_storage(x.sname, nothing), return_shms)
  r
end














