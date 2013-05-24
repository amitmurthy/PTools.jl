export pmap_shm_create, setup_shm, unlink_shm, ShmCfg

using Base.FS

# Below constants have been checked for Ubuntu. 
const PROT_READ  = 0x01
const PROT_WRITE = 0x02
const MAP_SHARED = 0x01

type ShmCfg   
    sname::Symbol
    stype::Type
    sdims::Union(Tuple, Int)
end

function pmap_shm_create(map_list, shmpfx="")
    unlink_shm(map_list, shmpfx)
    for i in 1:nprocs()
        remotecall_fetch(i, setup_shm, map_list, shmpfx)
    end
end

free_shmem(map_list::ShmCfg, shmpfx) = unlink_shm([map_list], shmpfx)
free_shmem(map_list::Symbol, shmpfx) = unlink_shm([map_list], shmpfx)
free_shmem(map_list, shmpfx) = unlink_shm(map_list, shmpfx)

get_shmem_name(shmpfx, sname) = "/julia_" * shmpfx * "_" * string(sname)


# if map_global is false, adds it to the task_local_storage
function setup_shm(map_list, shmpfx="", map_global=false)
    if !isa(shmpfx, String) shmpfx = "" end
    if isa(map_list, ShmCfg)
        map_list = [map_list]
    end
    for e in map_list
        sname = e.sname
        stype = e.stype
        sdims = e.sdims

        if isa(sdims, Tuple)
            dims = prod(sdims)
        else
            dims = sdims
        end

        numb = dims * sizeof(stype)

        fd_mem = ccall(:shm_open, Int, (Ptr{Uint8}, Int, Int), get_shmem_name(shmpfx, sname), JL_O_CREAT | JL_O_RDWR, S_IRUSR | S_IWUSR)
        if !(fd_mem > 0) error("shm_open() failed") end


        if(1 == myid())
            rc = ccall(:ftruncate, Int, (Int, Int), fd_mem, numb)
    #        println(string(myid()) * "@ftruncate, rc : " * string(rc) * ", fd_mem : " * string(fd_mem))
            if !(rc == 0) 
               ec = errno()
               error("ftruncate() failed : $ec") 
            end
        end

        x = ccall(:mmap, Ptr{Void}, (Ptr{Void}, Int, Int32, Int32, Int32, FileOffset), C_NULL, numb, PROT_READ | PROT_WRITE, MAP_SHARED, fd_mem, 0)
#        println(string(myid()) * "@mmap, x : " * string(x) * ", fd_mem : " * string(fd_mem)* ", numb : " * string(numb))
        if (x == C_NULL) error("mmap() failed") end

        if (map_global)
#            println("global " * string(sname) * " ===> " * string(x))
            eval(:(global $sname; $sname = pointer_to_array(pointer($stype, $x), $sdims)))
        else
#            println("tls " * string(sname) * " ===> " * string(x))
            task_local_storage(sname, pointer_to_array(pointer(stype, x), sdims))
        end

        ccall(:close, Int, (Int, ), fd_mem)
    end
end

function unlink_shm(map_list, shmpfx="")
    if !isa(shmpfx, String) shmpfx = "" end
    if isa(map_list, ShmCfg) map_list = [map_list] end
    for e in map_list
        v_n = isa(e, ShmCfg) ? e.sname : e
        ccall(:shm_unlink, Int, (Ptr{Uint8}, ), get_shmem_name(shmpfx, v_n))
    end
end

