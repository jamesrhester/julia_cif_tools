# Check the ordering of items in a DDLm dictionary matches the order
# prescribed by the style guide.

get_atts(a) = begin
    cat = String(a.first)
    atts = map(x->"_"*cat*"."*"$x",String.(a.second))
end

get_att_order(a) = begin
    order = []
    for cat in a
        append!(order,get_atts(cat))
    end
    return order
end

const atts_as_strings = get_att_order(ddlm_attribute_order)
const toplevel_strings = get_att_order(ddlm_toplevel_order)

mutable struct OrderCheck <: Visitor_Recursive
    all_defs::Array{String,1}    #all definitions in file
    seen_items::Array{String,1}  #attributes seen in current definition
    seen_defs::Array{String,1}   #definitions seen so far
    possible_cats::Array{String,1} #categories in our tree
    cached_templates::Dict{String,Cif} #cached template files 
    top_level::Array{String,1}
    cat_info::Array{Tuple{String,String},1}
    this_def::String
    this_parent::String
    func_cat::String
    is_su::Bool
    linked::String
    origin_dir::String
    warn::Bool                 #emit warnings
end

OrderCheck() = OrderCheck(@__DIR__,false, String[])
OrderCheck(s::String,w::Bool,all_defs::Vector{String}) = OrderCheck(all_defs,[],[],[],
                                                                    Dict{String,Cif}(), [],[],"","","",false,"",s,w)

@rule scalar_item(oc::OrderCheck,tree) = begin
    att = traverse_to_value(tree.children[1],firstok=true)
    val = traverse_to_value(tree.children[2],firstok=true)
    push!(oc.seen_items,att)
    check_attribute(oc,att,val,tree)
end

@rule loop(oc::OrderCheck,tree) = begin
    boundary = findfirst(x-> !isa(x,Lerche.Token),tree.children)
    append!(oc.seen_items,tree.children[2:boundary-1])
end

@rule save_frame(oc::OrderCheck,tree) = begin
    check_order(atts_as_strings,oc.seen_items,"4.3.4",get_line(tree),warn=oc.warn)
    cats = map(x->to_cat_obj(x)[1],oc.seen_items)
    if "import_details" in cats
        print_err(get_line(tree),"No import_details attributes should be used",err_code="4.3.3")
    end
    if !(oc.this_parent in oc.seen_defs) &&
        length(oc.seen_defs) > 0 &&    #Head is first
        oc.this_parent in oc.all_defs
        print_err(get_line(tree),"Definition for child item $(oc.this_def) comes before category $(oc.this_parent)",err_code="4.1.8")
        @debug "Seen $(oc.seen_defs)" oc.all_defs
    end
    
    # Check SU is straight after parent

    if oc.is_su && oc.seen_defs[end] != oc.linked
        print_err(get_line(tree),"SU $(oc.this_def) does not immediately follow its Measurand item $(oc.linked)",err_code="4.1.10")
    end

    if oc.this_def != ""
        push!(oc.seen_defs, oc.this_def)

        # If parent == def, we have the head category and can skip it

        if oc.this_def != oc.this_parent
            push!(oc.cat_info,(oc.this_def,oc.this_parent))
        end
    end
    
    # Make sure a category definition occurs before any data names/children from that category

    if occursin(".", oc.this_def)
        previous_cat = findlast(x -> !occursin(".",x),oc.seen_defs)
        if lowercase(oc.seen_defs[previous_cat]) != oc.this_parent &&
            oc.this_parent in oc.all_defs
            print_err(get_line(tree),"Definition for data name $(oc.this_def) is not grouped after parent category $(oc.this_parent)",err_code="4.1.8")
        end
    end

    # Make sure category children of the same category are grouped together

    if length(oc.possible_cats) > 0 && !occursin(".", oc.this_def) #category definition
        if !(oc.this_parent in oc.possible_cats)
            print_err(get_line(tree), "Definition for $(oc.this_def) is separated from other members of $(oc.this_parent)", err_code="4.1.8")
        end
    end

    # Housekeeping of current category hierarchy
    
    if !occursin(".", oc.this_def)  # a category
        new_end = indexin([oc.this_parent], oc.possible_cats)[]
        if new_end != nothing
            oc.possible_cats = oc.possible_cats[1:new_end]
        end
        push!(oc.possible_cats, oc.this_def)
        @debug "New category hierarchy is: " oc.this_def oc.possible_cats
    end
    
    
    # Pretend we never saw any SU values to save order checking later

    if oc.this_def != "" && oc.is_su
        pop!(oc.seen_defs)
        pop!(oc.cat_info)
    end
    oc.this_def = ""
    oc.is_su = false
    oc.linked = ""
end

@rule block_content(oc::OrderCheck,tree) = begin
    if tree.children[1].data == "data"
        append!(oc.top_level,oc.seen_items)
    end
    oc.seen_items = []
end

@rule dblock(oc::OrderCheck,tree) = begin
    check_order(toplevel_strings,oc.top_level,"4.2.1",get_line(tree))
    # check that looped items are after save frames
    saves_seen = false
    for b in tree.children[2]
        if b.data == "save_frame"
            saves_seen = true
            continue
        end
        if b.data == "data" && saves_seen
            if b.children[2].children[1].data != "loop"
                print_err(get_line(b.children[2].children[1]),"Non-looped top level items appear after save frames",err_code="4.2.2")
            end
        end
    end
    check_def_order(oc.cat_info,oc.func_cat)
end

# Collect a list of all cats so we only flag bad ordering when cats are present

mutable struct CatCollector <: Visitor_Recursive
    all_defs::Array{String,1}
end

CatCollector() = CatCollector([])

@rule scalar_item(cc::CatCollector,tree) = begin
    att = traverse_to_value(tree.children[1],firstok=true)
    val = traverse_to_value(tree.children[2],firstok=true)
    if att == "_definition.id"
        push!(cc.all_defs, lowercase(val))
    end
end

to_cat_obj(v) = begin
    s = split(v,".")
    if length(s) < 2
        return "", lowercase(v)
    else
        c, o = s
        return lowercase(c[2:end]),lowercase(o)
    end
end

check_order(right,observed,err_code,line;warn=false) = begin
    known = filter(x->x in right,observed)
    checked = filter(x->x in observed,right)
    if warn
        unknown = setdiff(observed,right)
        if length(unknown) > 0
            println("WARNING: unknown attributes $unknown")
        end
    end
    if known != checked
        print_err(line,"Order of items in definition incorrect:",err_code=err_code)
        @printf "\n%-30s%-30s\n" "Actual" "Expected"
        for i in 1:minimum(length,[known,checked])
            @printf "%-30s%-30s\n" known[i] checked[i]
        end
        println()
    end
end

check_def_order(cat_tuples,func_cat) = begin
    def_order = lowercase.([x[1] for x in cat_tuples])
    all_cats = unique!(filter(x-> !occursin(".",x),def_order))
    for one_cat in all_cats
        children = filter(x->x[2] == one_cat && x[1] in all_cats && x[1] != func_cat,cat_tuples)
        children = [x[1] for x in children]
        if sort(children) != children
            print_err(0,"Child categories of category $one_cat not in alphabetical order", err_code="4.1.9")
            for (s,c) in zip(sort(children),children)
                @printf "%-30s%-30s\n" s c
            end
        end
        children = filter(x->x[2] == one_cat && !(x[1] in all_cats),cat_tuples)
        children = [x[1] for x in children]
        if sort(children) != children
            print_err(0,"Child data names of category $one_cat not in alphabetical order", err_code="4.1.8")
            for (s,c) in zip(sort(children),children)
                @printf "%-30s%-30s\n" s c
            end
        end
    end
    if func_cat != "" && all_cats[end] != func_cat
        print_err(0,"Function category is not the final category",err_code="4.1.11")
    end
end

# Extract necessary information from imported contents
process_import(oc::OrderCheck,val,tree) = begin
    if get(val,"mode","Contents") == "Full" return end
    templ_file = cif_from_uri(oc, val["file"])
    templates = get_frames(first(templ_file)[end])
    target_block = templates[val["save"]]
    # Now check for items we care about
    for (a,v) in target_block
        if length(v) > 1 continue end   #we only care about single-valued items
        check_attribute(oc,a,v[],tree)
    end
end

# Utility routine to download template files if necessary
cif_from_uri(oc::OrderCheck, ss) =  begin

    ss = String(ss)    #Token type caused infinite recursion in URIs

    if haskey(oc.cached_templates, ss)
        # @debug "Using cached file for $ss"
        return oc.cached_templates[ss]
    end

    u = URI(ss)

    if u.scheme == ""
        templ_file_name = joinpath(oc.origin_dir, ss)
    else
        templ_file_name = Downloads.download(ss)
    end

    templ_file = nothing
    try
        templ_file = Cif(templ_file_name)
    catch
        @warn "unable to resolve $templ_file_name to a filename"
        return
    end

    @debug "Caching CIF for $ss"
    oc.cached_templates[ss] = templ_file
    return templ_file
end

# Placed here so it can be called from import routine and
# from main routine
check_attribute(oc::OrderCheck,att,val,tree) = begin
    if att == "_definition.id"
        oc.this_def = lowercase(val)
    elseif att == "_name.category_id"
        oc.this_parent = lowercase(val)
    elseif att == "_definition.class"
        if val == "Head" && length(oc.seen_defs) != 0
            print_err(get_line(tree),"Head category should be the first definition",err_code="4.1.7")
        end
        if val == "Functions" oc.func_cat = oc.this_def end #assume comes after
    elseif att == "_name.linked_item_id"
        oc.linked = lowercase(val)
    elseif att == "_type.purpose"
        oc.is_su = val == "SU"
    elseif att == "_import.get"
        process_import(oc,read_import_spec(tree.children[2]),tree)
    end
end

