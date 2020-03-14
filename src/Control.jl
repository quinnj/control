module Control

include("Model.jl")
using .Model; export Model

include("Mapper.jl")
using .Mapper; export Mapper

include("Service.jl")
using .Service; export Service

include("Resource.jl")
using .Resource; export Resource

include("Client.jl")
using .Client; export Client

include("Play.jl")
using .Play; export Play

function init()
    Mapper.init()
    Service.init()
    Resource.init()
end

function run()
    t = time()
    println("starting Control service")
    init()
    println(raw"""
   __________  _   ____________  ____  __ 
  / ____/ __ \/ | / /_  __/ __ \/ __ \/ / 
 / /   / / / /  |/ / / / / /_/ / / / / /  
/ /___/ /_/ / /|  / / / / _, _/ /_/ / /___
\____/\____/_/ |_/ /_/ /_/ |_|\____/_____/
""")
    println("started Control service in $(round(time() - t, digits=2)) seconds")
    Resource.run()
end

end # module
