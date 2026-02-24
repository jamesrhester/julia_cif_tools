struct LineCheck <: Visitor_Recursive
    ignore_lines::Vector{Int64}   # which lines are ignored
    no_text::Bool                 # skip multi-line text
end

LineCheck() = LineCheck(false)
LineCheck(b::Bool) = LineCheck([],b)

struct Linter <: Visitor_Recursive
    ignore_lines::Vector{Int64}
    no_text::Bool
end

Linter(l::LineCheck) = Linter(l.ignore_lines,l.no_text)

@rule semi_string(l::LineCheck,tree) = begin
    args = tree.children
    first_line = args[1].line
    last_line = args[end].line - 1
    if l.no_text
        append!(l.ignore_lines,collect(first_line:last_line))
    elseif match(r"#####",String(args[1])) != nothing || match(r"#####",String(args[end-1])) != nothing
        @debug "Adding lines from $first_line to $last_line"
        append!(l.ignore_lines,collect(first_line:last_line))
    end
end

check_column(token::Token,proper,rule_no) = begin
    if token.column != proper
        print_err(token.line,"$token should begin at $proper, begins at $(token.column)",err_code=rule_no)
    end
end

"""
    check_text_indent(val,indent,is_second,err_code)

Check that the multi-line value `val` contains `indent` spaces at the beginning of
each new line. If not, the appropriate `err_code` is provided.
"""
check_text_indent(val,indent,err_code) = begin
    if get_delimiter(val) == "\n;"
        if length(val.children[1].children) <= 2 && length(strip(val.children[1].children[1]))==1
            println("WARNING: blank semicolon field at line $(get_line(val))")
            return
        end
        for lt in val.children[1].children[2:(end-1)]
            line = String(traverse_to_value(lt))
            if match(r"^\s*\S+",line) == nothing
                # check for stray whitespace
                if length(line) > 1
                    print_err(get_line(lt),"Extra whitespace at beginning of blank line '$line'",err_code="2.1.9")
                    return
                end
            end
            good_wspace = findlast(" ",line)
            has_wspace = good_wspace !== nothing &&  good_wspace[1] <= line_length - indent
            start = match(r"^\s+",line)
            if has_wspace && (start == nothing || length(start.match) < indent) 
                print_err(get_line(lt),"Indent too small for '$line', should be at least $indent",err_code=err_code)
            end
        end
    elseif get_delimiter(val) in ["'''","\"\"\""]
        for (i,l) in enumerate(eachmatch(r"^\s*"m,traverse_to_value(val)))
            if i == 1 continue end
            if length(l.match) < indent
                print_err(get_line(val)+(i-1),"Indent too small for '$(l.match)', should be at least $indent",err_code=err_code)
            end
        end
    end
end

check_column(t::Tree,proper,rule_no) = check_column(t.children[1],proper,rule_no)

get_delimiter(value::Tree) = begin
    if value.data == "data_value" return get_delimiter(value.children[1]) end
    if value.data == "semi_string" return "\n;" end
    if value.data == "list" return "[" end
    if value.data == "table" return "{" end
    get_delimiter(traverse_to_value(value))
end

get_delimiter(value::Token) = begin
    if length(value) > 6
        if value[1:thisind(value,3)] == "'''" return "'''" end
        if value[1:thisind(value,3)] == "\"\"\"" return "\"\"\"" end
    end
    if first(value) == '\'' return "'" end
    if first(value) == '\"' return "\"" end
    if is_null(value) return nothing end
    return ""
end

get_delimiter_with_val(v) = begin
    delimiter = get_delimiter(v)
    if delimiter in ("[","{","\n;") return delimiter,v end
    if !is_null(v)
        del_len = length(delimiter)
    else
        del_len = 0
    end
    value = traverse_to_value(v)
    return delimiter,value[1+del_len:thisind(value,end-del_len)]
end

is_null(v::Tree) = length(v.children) == 1 && is_null(v.children[1])
is_null(v::Token) = String(v) == "." || String(v) == "?"
    
traverse_to_value(tv::Tree;firstok=false,kwargs...) = begin
    if length(tv.children) == 1 || firstok return traverse_to_value(tv.children[1];firstok=firstok,kwargs...)
    else
        throw(error("Cannot find unique single value for $tv"))
    end
end

"""
If delims is false remove them before returning
"""
traverse_to_value(tv::Token;firstok=false,delims=true) = begin
    if !delims
        q = get_delimiter(tv)
        if isnothing(q) return tv end
        del_len = length(q)
        return tv[1+del_len:thisind(tv,end-del_len)]
    end
    return tv
end

# Return the first item of type `d` found in `tv` 
traverse_to_type(tv::Tree,d) = begin
    if tv.data == d return tv end
    for c in tv.children
        r = traverse_to_type(c,d)
        if r !== nothing return r end
    end
    return nothing
end

traverse_to_type(tv::Token, d) = begin
    if token.type_ == d return tv else return nothing end
end


get_line(t::Tree) = get_line(t.children[1])
get_column(t::Tree) = get_column(t.children[1])
get_end_column(t::Tree) = get_end_column(t.children[end])
get_last_line(t::Tree) = get_last_line(t.children[end])
get_line(t::Token) = if t.type_ == "START_SC_LINE" t.line + 1 else t.line end
get_last_line(t::Token) = t.end_line
get_column(t::Token) = if t.type_ == "START_SC_LINE" 1 else t.column end
get_end_column(t::Token) = t.end_column-1

get_width(t::Token) = begin
    if t.line != t.end_line return line_length+1 end
    return t.end_column - t.column + 1
end

get_width(t::Tree) = begin
    first_line = get_line(t)
    last_line = get_last_line(t)
    if get_line(t) == get_last_line(t)
        width = get_end_column(t) - get_column(t) + 1
        if width <= 0 throw(error("Bad width for $t, $width")) end
        return width
    end
    return line_length + 1
end

get_layout_width(t::Token) = (lower=get_width(t),upper=get_width(t))

get_layout_width(t::Tree) = begin
    c = traverse_to_type(t,"data_value")
    if c === nothing throw(error("Asked for width of non-data value")) end
    if c.children[1].data in ["quoted_string","semi_string","bare"]
        return (lower=get_width(c),upper=get_width(c))
    end
    return get_compound_width(c.children[1])
end

# Find the shortest/longest possible lines in the compound value 
get_compound_width(t::Tree) = begin
    if get_line(t.children[1]) == get_line(t.children[end])
        w = get_column(t.children[end])-get_column(t.children[1])+1
        return (lower=w,upper=w)
    end
    longest_val = 0
    total_length = 0
    for (i,v) in enumerate(t.children)
        if i == 1 continue end
        w = get_width(v)
        longest_val = w > longest_val ? w : longest_val
        total_length += w
    end
    return (lower=longest_val+1,upper=total_length)
end

has_newline(t) = get_line(t) < get_last_line(t)

# Only semicolon-delimited values have any consistent rules
@rule semi_string(l::Linter,tree) = begin
    if get_line(tree) in l.ignore_lines return end
    first_line = strip(tree.children[1])
    if length(first_line)>1 && !(first_line[end] == '\\')
        print_err(get_line(tree),"First line of semicolon-delimited string should be blank, except for prefix and folding codes",err_code="2.1.11")
    end
end

@rule loop(l::Linter,tree) = begin
    check_column(tree.children[1],text_indent+1,"3.2.2")  #loop keyword
    args = tree.children
    # count data names
    boundary = findfirst(x->!isa(x,Lerche.Token),args)
    name_list = args[2:boundary-1]
    num_names = length(name_list)
    value_list = args[boundary:end]
    nrows,m = divrem(length(value_list),num_names)
    if m!=0
        print_err(name_list[1].line,"Number of values in loop is not a multiple of number of looped names",err_code="CIF")
    end
    if nrows == 1
        print_err(name_list[1].line,"Loop should be presented as key-value pairs: only one packet",err_code="3.2.1")
        return
    end
    # check consistent delimiters
    delims = check_loop_delimiters(name_list,value_list)
    # check proper layout
    check_loop_layout(name_list,value_list,delims)
    if !(l.no_text)
        check_loop_text_indent(name_list,value_list,delims)
    end
end

"""
    Check that loops have consistent delimiters. The value "." (ie nothing)
    is ignored, as it must always have no delimiters.
"""
check_loop_delimiters(name_list,value_list) = begin
    num_names = length(name_list)
    best_delimiters = Vector{Union{Nothing,String}}(undef,num_names)
    fill!(best_delimiters,"")
    seen_single = fill(false,num_names)
    nrows = div(length(value_list),num_names)
    delims = Array{Union{Nothing,String}}(undef,num_names)
    for n in 1:num_names
        delims[n],bare = get_delimiter_with_val(value_list[n])
        if !(delims[n] in ("[","{","\n;",nothing))
            best_delimiters[n],_ = which_delimiter(bare)
            seen_single[n] = occursin("\"",bare)
        else
            best_delimiters[n] = delims[n]
        end
    end

    for r in 2:nrows
        for n in 1:num_names
            new_delimiter,bare = get_delimiter_with_val(value_list[(r-1)*num_names + n])
            if delims[n] == nothing && new_delimiter != nothing
                delims[n] = new_delimiter
                best_delimiters[n] = new_delimiter
            end
            if new_delimiter != delims[n] && new_delimiter != nothing
                print_err(name_list[1].line,"Inconsistent delimiters for $(name_list[n]), seen $(delims[n]) and $new_delimiter",err_code="2.1.13")
            end
            if !(new_delimiter in ("[","{","\n;",nothing))
                seen_single[n] = seen_single[n] || occursin("\"",bare)
                best_delimiters[n] = choose_best_delimiter(best_delimiters[n],which_delimiter(bare)[1],seen_single[n])
            end
        end
    end

    # Now check that these are the best delimiters

    for n in 1:num_names
        if delims[n] != best_delimiters[n]
            @debug "Delimiters" name_list n delims[n] best_delimiters[n]
            print_err(name_list[n].line,"Non-optimal delimiters for $(name_list[n]), should be \" $(best_delimiters[n]) \"",err_code="2.1")
        end
    end
    return delims   #for use later
end

# Decide which delimiter is best of the proposed ones, given that we have seen
# a single double quote
choose_best_delimiter(old_best,suggested,single) = begin
    if old_best == "\n;" return old_best end
    if old_best == suggested return old_best end
    prec = ("\n;","\"\"\"","'''","\"","'","")
    if suggested in ("'","\"") && old_best == "\"" && single return "'''" end
    if suggested == "'''" && old_best == "\"\"\"" return "\n;" end
    old_order = findfirst(x->x==old_best,prec)
    new_order = findfirst(x->x==suggested,prec)
    return prec[min(old_order,new_order)]
end

"""
    check_loop_layout(name_list,value_list,delims)

Check the alignment and spacing of the loop values
"""
check_loop_layout(name_list,value_list,delims) = begin
    num_names = length(name_list)
    for i in 1:num_names
        check_column(name_list[i],text_indent + loop_indent + 1,"3.2.3")
    end

    col_align = [get_column(x) for x in value_list[1:num_names]]
    
    # Check columns on a single line
    
    if num_names > 1
        diffs = col_align[2:end] - col_align[1:(end-1)]
        col = argmin(diffs)
        if diffs[col]<2 && get_line(value_list[col+1]) == get_line(value_list[col])
            print_err(get_line(value_list[col]),"Columns separated by less than 2 spaces",err_code="3.2.6")
        end
    end

    # Remember nothings so we can update column alignments

    is_nothing = fill(true,num_names)
    
    nrows = div(length(value_list),num_names)
    colwidths = fill((lower=0,upper=0),num_names)
    for n in 0:(nrows-1)
        for p in 1:num_names

            my_value = value_list[n*num_names + p]

            # update required column alignment if we based it off nothing

            if is_nothing[p] && !is_null(my_value)
                col_align[p] = get_column(my_value)
                is_nothing[p] = false
            end

            if p == 1 && my_value.children[1].data != "semi_string"
                check_column(my_value,loop_align,"3.2.5")
            end
            # check first value comes after new line
            if n > 1 && p == 1
                if get_line(my_value) == get_line(value_list[n*num_names])
                    print_err(get_line(my_value), "First value in packet is not on new line",err_code="3.2.4")
                end
            end
            # check that all column line up
            if get_column(my_value) != col_align[p] && !is_null(my_value)
                print_err(get_line(my_value),"Column $p is misaligned:expected $(col_align[p]), got $(get_column(my_value))",err_code="3.2.10")
            end
            # accumulate values for column length
            colwidths[p] = (lower = max(get_layout_width(my_value).lower, colwidths[p].lower),
                            upper = max(get_layout_width(my_value).upper, colwidths[p].upper))
        end
    end
    # Now check for ideal spacing
    if num_names == 1 return end
    ideal_steps,ideal_lines = calc_ideal_spacing(colwidths)
    #println("Ideal layout for $colwidths: $ideal_steps, $ideal_lines")
    for i in 1:num_names
        if (colwidths[i].lower > line_length - loop_step) && !(delims[i] in ["\n;","[","{"])
            print_err(get_line(value_list[1]),"Delimiter for column $i should be semicolons",err_code="3.2.8")
        end
        if col_align[i] != ideal_steps[i] && !(delims[i] == "\n;")
            print_err(get_line(value_list[1]),"Column $i should start at $(ideal_steps[i]), saw $(col_align[i])",err_code="3.2.8,9")
        end
    end
end

check_loop_text_indent(name_list,value_list,delims) = begin
    indent = text_indent + loop_indent + 1
    num_names = length(name_list)
    nrows = div(length(value_list),num_names)
    delim_cond = num_names == 2 && delims[1] != "\n;" && delims[2] == "\n;"
    for n in 0:(nrows-1)
        for p in 1:num_names
            val = value_list[n*num_names + p]
            if get_delimiter(val) in ("\n;","'''","\"\"\"")
                if delim_cond && p == 2
                    check_text_indent(val,loop_align-1,"3.2.10")
                else
                    check_text_indent(val,indent,"3.2.7")
                end
            end
        end
    end
end

@rule table_entry(l::Linter,tree) = begin
    d,b = get_delimiter_with_val(tree.children[1])
    best,rule = which_delimiter(b)
    if d != "'"
        if best in ["","'"]
            print_err(get_line(tree),"Delimiter for key '$b' in table should be ' instead of $d",err_code="2.3.2")
        elseif best != d
            print_err(get_line(tree),"Delimiter for key '$b' in table should be $best instead of $d",err_code="2.3.2")
        end
    end
    if d == "'" && !(best in ["","'"])
        print_err(get_line(tree),"Delimiter for key '$b' in table should be $best instead of ' ",err_code="2.3.2")
    end
    d,b = get_delimiter_with_val(tree.children[2])
    best,rule = which_delimiter(b)
    if best != d
        print_err(get_line(tree),"Value $b in table has incorrect delimiters: should be $d",err_code="2.1")
    end
    if get_end_column(tree.children[1])+2 != get_column(tree.children[2])
        print_err(get_line(tree),"Table entry has whitespace around colon",err_code="2.3.1")
    end
end

@rule table(l::Linter,tree) = begin
    previous_entry = nothing
    has_compound = false
    total_width = 0
    # check alphabetical order and brace separation
    for i in 2:length(tree.children)-1
        one_entry = tree.children[i]
        total_width += get_width(one_entry)
        if one_entry.children[2].data in ["list","table"]
            if get_line(one_entry) != get_last_line(one_entry) && get_width(one_entry) < line_length-value_indent
                print_err(get_line(one_entry),"Internal compound value split over more than one line unnecessarily",err_code="2.4")
            end
        end
        if i == 2
            newline = get_line(tree.children[1]) != get_line(one_entry)
            previous_entry = one_entry
            if !newline && (get_column(tree.children[1])+1 != get_column(one_entry))
                print_err(get_line(tree),"Whitespace after opening brace of table",err_code="2.3.5")
            end
            continue
        end
        newline = get_line(previous_entry) != get_line(one_entry)
        if !newline && (get_end_column(previous_entry) != get_column(one_entry)-min_whitespace-1)
            print_err(get_line(tree),"Table entries not separated by $min_whitespace blanks",err_code="2.3.3")
        end
        _,p_bare = get_delimiter_with_val(previous_entry.children[1])
        _,c_bare = get_delimiter_with_val(one_entry.children[1])
        if cmp(p_bare,c_bare) != -1   #not ordered correctly
            print_err(get_line(one_entry),"Table keys not in alphabetical order: $p_bare, $c_bare",err_code="2.3.4")
        end
        previous_entry = one_entry
        if i == length(tree.children)
            if !newline && (get_column(tree.children[end])-1 != get_end_column(one_entry))
                print_err(get_line(tree),"Whitespace before closing brace of table",err_code="2.3.5")
            end
        end
    end
    total_width += min_whitespace*(length(tree.children)-1)
end

@rule list(l::Linter,tree) = begin
    previous_entry = nothing
    has_compound = false
    total_width = 0
    contains_newline = get_line(tree) != get_last_line(tree)
    # check brace separation
    for i in 2:length(tree.children)-1
        # avoid iteration of the tree as that is recursive
        one_entry = tree.children[i]
        total_width += get_width(one_entry)
        if one_entry.children[1].data in ["list","table"]
            if get_line(one_entry) != get_last_line(one_entry) && get_width(one_entry) < line_length-value_indent
                print_err(get_line(one_entry),"Internal compound value split over more than one line unnecessarily",err_code="2.4")
            end
        end
        if i == 2
            newline = get_line(tree.children[1]) != get_line(one_entry)
            previous_entry = one_entry
            if !newline && (get_column(tree.children[1])+1 != get_column(one_entry))
                print_err(get_line(tree),"Whitespace after opening bracket of list",err_code="2.2.1")
            end
            if contains_newline && !newline && one_entry.children[1].data in ["list","table"]
                print_err(get_line(one_entry),"Nested compound items should be on separate lines for multi-line compound values",err_code="2.4.5")
            end
            continue
        end
        newline = get_line(previous_entry) != get_line(one_entry)
        if !newline && (get_end_column(previous_entry) != get_column(one_entry)-min_whitespace-1)
            print_err(get_line(tree),"List entries not separated by $min_whitespace blanks",err_code="2.2.2")
        end
        previous_entry = one_entry
        if i == length(tree.children)
            if !newline && (get_column(tree.children[end])-1 != get_end_column(one_entry))
                print_err(get_line(tree),"Whitespace before closing bracket of list",err_code="2.2.1")
            end
        end
    end
    total_width += min_whitespace*(length(tree.children)-1)
end

@rule scalar_item(l::Linter,tree) = begin
    name = tree.children[1]
    check_column(name,text_indent+1,"3.1.1")
    val = tree.children[2]
    if val.children[1].data in ["quoted_string","bare"]
        check_delimiter(val)
    end
    delim = get_delimiter(val)
    if delim in ["'","\"",nothing,"[","{"]
        if name.line == get_line(val) 
            check_column(val,value_col,"3.1.2")
        else
            if get_width(val) <= line_length - value_col + 1
                print_err(get_line(val),"Value should appear on same line as data name",err_code="3.1.2")
            else
                check_column(val,value_indent,"3.1.3")
            end
        end
    elseif delim in ["'''","\"\"\"","\n;"] && !(get_line(val) in l.ignore_lines)
        check_text_indent(val,text_indent,"2.1.9")
    end
end

check_delimiter(value) = begin
    value = traverse_to_value(value)
    quotechar = ""
    if value.type_ == "SINGLE_QUOTE_DATA_VALUE"
        quotechar = value[1:1]
        test_val = value[2:prevind(value,end-1)]
    elseif value.type_ == "TRIPLE_QUOTE_DATA_VALUE"
        quotechar = value[1:3]
        test_val = value[4:prevind(value,end-4)]
    else
        quotechar = ""
        test_val = value
        if test_val == "." || test_val == "?"
            return
        end
    end
    best_delimiter,rule_no = which_delimiter(test_val)
    if best_delimiter != quotechar
        @debug "Found bad quotes" test_val best_delimiter
        printval = test_val
        if length(printval) > 20
            printval = value[1:prevind(value,20)]*"..."
        end
        print_err(value.line,"Incorrect delimiters for $(printval): should be `$best_delimiter`",err_code=rule_no)
    end
end

@rule dblock(l::Linter,tree) = begin
    # check space after header
    line_diff = get_line(tree.children[2]) - get_line(tree.children[1])
    if line_diff == 1
        print_err(get_line(tree.children[2]), "No blank line after data block header",err_code="4.1.5")
    end
    blks = tree.children[2:end]   #list of block_contents
    for i in 2:length(blks)
        t = blks[i]
        if t.children[1].data == "save_frame"
            line_diff = get_line(t.children[1]) - get_last_line(blks[i-1])
            if line_diff == 1
                print_err(get_line(t),"No blank line before save frame header",err_code="4.3.1")
            end
        end
    end 
end

@rule save_frame(l::Linter,tree) = begin
    if get_line(tree.children[2]) < get_line(tree.children[1])+2
        print_err(get_line(tree.children[2]),"No blank line after save frame header",err_code="4.3.1")
    end
    if get_line(tree.children[end]) < get_line(tree.children[end-1])+2
        print_err(get_line(tree.children[end]),"No blank line before save frame end",err_code="4.3.1")
    end
    # check that imports have a space before and after
    for i in 2:(length(tree.children)-1)
        di = tree.children[i]
        if di.children[1].data == "scalar_item" && di.children[1].children[1] == "_import.get"
            if i > 2 && get_line(di) != get_last_line(tree.children[i-1]) + 2
                print_err(get_line(di),"_import.get is not separated by a blank line from previous item",err_code="4.3.2")
            end
            if i < length(tree.children)-2
                if get_last_line(di) + 2 != get_line(tree.children[i+1])
                    print_err(get_line(di),"_import.get is not separated by a blank line from next item",err_code="4.3.2")
                end
            end
        end
    end
end

# Non-grammar based checks

check_line_properties(fulltext,ignore_list) = begin
    double_lines = findall(r"\n\n\n",fulltext)
    for d in double_lines
        if count(r"\n",fulltext[1:d.start]) in ignore_list continue end
        print_err(count(r"\n",fulltext[1:d.start]),"Double blank lines",err_code="1.4")
    end
    as_lines = collect(enumerate(split(fulltext,"\n")))
    line_lengths = map(x->(x[1],length(x[2])),as_lines)
    bad = filter(x->x[2]>80 && !(x[1] in ignore_list),line_lengths)
    if length(bad) > 0
        for (n,b) in bad
            print_err(n,"Line too long: $b characters",err_code="1.1")
        end
    end
    trailing = filter(x->length(x[2])>0 && x[2][end] == ' ' && !(x[1] in ignore_list),as_lines)
    for (n,b) in trailing
        print_err(n,"Trailing whitespace",err_code="1.3")
    end
end

check_first_space(fulltext) = begin
    finder = r"^(#(.+)\n)+\n\s*data_"m
    if match(finder,fulltext) == nothing
        print_err(1,"Data block is not preceded by optional comment and single blank line",err_code="4.1.3")
    end
end

check_last_char(fulltext) = begin
    if fulltext[end] != '\n'
        print_err(0,"Final character is not newline",err_code="4.1.4")
    end
end

