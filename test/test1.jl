using PTools

shmcfg = [ShmCfg(:svar1, Int32, 64*1024), ShmCfg(:svar2, Uint8, (100,100))]
h = start_stasks(shmcfg)
ntasks = count_stasks(h)

svar1 = task_local_storage(:svar1)

for i in 1:64*1024
    svar1[i]=0
end
println(svar1)

offset_list = [i for i in 1:ntasks]
ntasks_list = [ntasks for i in 1:ntasks]

resp = pmap_stasks(h, (offset, ntasks) -> begin
                        svar1 = task_local_storage(:svar1)
                        svar2 = task_local_storage(:svar2)
                        
                        mypid = myid()
                        for x in offset:ntasks:64*1024
                            svar1[x] = mypid
                        end
                        
                        true
                        
                    end,
                    
                    offset_list, ntasks_list)

println(task_local_storage(:svar1))

stop_stasks(h, shmcfg)