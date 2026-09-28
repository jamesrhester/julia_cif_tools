# A Linter for DDLm dictionaries
using CrystalInfoFramework, Printf, ArgParse
using URIs      #for imports
using Downloads #for imports

using Lerche    #for our transformer

const err_record = Dict{String,Int}()

print_err(line,text;err_code="CIF") = begin
    err_record[err_code] = get(err_record,err_code,0) + 1
    @printf "%6d: rule %5s: %s\n" line err_code text
end

include("layout.jl")
include("import_parser.jl")
include("ordering.jl")
include("capitalisation.jl")
include("defaults.jl")

lint_report(filename;ref_dic="",import_dir="",warn=false,no_text=false) = begin
    println("\nLint report for $filename\n"*"="^(length(filename) + 16)*"\n\n")
    if length(import_dir)>0
        println("Imports relative to $import_dir\n\n")
    end
    println("Layout:\n")
    fulltext = read(filename,String)
    if occursin("\t",fulltext)
        firstone = findfirst('\t',fulltext)
        line = count("\n",fulltext[1:firstone])
        print_err(line,"Tabs found, please remove. Indent warnings may be incorrect",err_code="1.6")
    end

    # Get the parse tree and list of definitions
    
    ptree = Lerche.parse(CrystalInfoFramework.cif2_parser,fulltext,start="input")

    # Find lines that should be ignored

    lc = LineCheck(no_text)
    Lerche.visit(lc,ptree)

    @debug "Ignoring lines" lc.ignore_lines
    
    check_line_properties(fulltext,lc.ignore_lines)
    check_first_space(fulltext)
    check_last_char(fulltext)

    # Now check layout
    
    l = Linter(lc)
    Lerche.visit(l,ptree)
    if import_dir == "" import_dir = dirname(filename) end

    # Check ordering

    cc = CatCollector()  #get all definitions
    Lerche.visit(cc,ptree)
    @debug "All definitions:" cc.all_defs
    
    oc = OrderCheck(import_dir,warn,cc.all_defs)
    println("\nOrdering:\n")
    Lerche.visit(oc,ptree)

    # Check capitalisation
    
    if ref_dic != ""
        d = DDLm_Dictionary(ref_dic,import_dir=import_dir)
        cc = CapitalCheck(d)
    else
        cc = CapitalCheck()
    end
    println("\nCapitalisation:\n")
    Lerche.visit(cc,ptree)
    if ref_dic != ""
        dc = DefaultCheck(d)
        println("\nDefaults:\n")
        Lerche.visit(dc,ptree)
    end
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "dictname"
         help = "Dictionary to check"
         required = true
        "refdic"
         help = "DDL reference dictionary. If absent, capitalisation will not be checked"
        default = ""
        required = false
        "--import-dir","-i"
        help = "Directory to search for imported files in. Default is the same directory as the dictionary"
        arg_type = String
        default = ""
        "-w","--warn"
        help = "Warn about unrecognised DDL attributes and other non-layout issues"
        nargs = 0
        "-t","--ignore-text"
        help = "Do not check layout in multi-line text strings"
        nargs = 0
    end
    parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed_args = parse_cmdline("Check dictionary conformance to DDLm style guide.")
    @debug "$parsed_args"
    lint_report(parsed_args["dictname"],ref_dic=parsed_args["refdic"],
                import_dir=parsed_args["import-dir"],
                warn = parsed_args["warn"],
                no_text = parsed_args["ignore-text"])
    println("Total errors by style rule:")
    for k in sort(collect(keys(err_record)))
        @printf "%10s: %5d\n" k err_record[k]
    end
    println()
    length(err_record) > 0 ? exit(1) : exit(0)
end
