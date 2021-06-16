# A Linter for DDLm dictionaries
using CrystalInfoFramework,Printf

using Lerche   #for our transformer

print_err(line,text;err_code="CIF") = begin
    @printf "%6d: rule %5s: %s\n" line err_code text
end

include("layout.jl")
include("ordering.jl")
include("capitalisation.jl")

lint_report(filename;ref_dic="") = begin
    println("Lint report for $filename\n"*"="^(length(filename) + 16)*"\n")
    println("Layout:\n")
    fulltext = read(filename,String)
    if occursin("\t",fulltext)
        firstone = findfirst('\t',fulltext)
        line = count("\n",fulltext[1:firstone])
        print_err(line,"Tabs found, please remove. Indent warnings may be incorrect",err_code="1.6")
    end
    check_line_properties(fulltext)
    check_first_space(fulltext)
    check_last_char(fulltext)
    ptree = Lerche.parse(CrystalInfoFramework.cif2_parser,fulltext,start="input")
    l = Linter()
    Lerche.visit(l,ptree)
    oc = OrderCheck()
    println("\nOrdering:\n")
    Lerche.visit(oc,ptree)
    if ref_dic != ""
        cc = CapitalCheck(ref_dic)
    else
        cc = CapitalCheck()
    end
    println("\nCapitalisation:\n")
    Lerche.visit(cc,ptree)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage: julia linter.jl <dictionary file> <reference dictionary>")
        println("""
<dictionary file> is the file to be checked. <reference dictionary> is the DDL
reference dictionary. If absent, capitalisation of attribute values will not
be checked.""")
    else
        filename = ARGS[1]
        if length(ARGS) >= 2 ref_dic = ARGS[2] else ref_dic = "" end
        lint_report(filename,ref_dic=ref_dic)
    end
end