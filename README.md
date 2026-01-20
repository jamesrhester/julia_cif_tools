# Julia CIF tools

Command-line tools for working with Crystallographic Information Framework files and dictionaries written in Julia.

# Installation

1.  [Install Julia](https://docs.julialang.org/en/v1/manual/getting-started/)
2.  Install dependencies by running `julia -e 'using Pkg, TOML; map(Pkg.add, collect(keys(TOML.parsefile("Project.toml")["deps"]))); Pkg.instantiate()'`.
3.  Copy or clone this project to a suitable location on your system. The instructions below assume that you are
    executing from this location.
4.  A help message for each of the programs below can be obtained by running `julia <program_file>` at your command prompt.

# Contents

## Linter

Verify a dictionary against layout and other style recommendations.

Execute by running `julia linter.jl <dictionary file> <reference dictionary>`. This will verify `dictionary file` 
against the current style recommendations for dictionary layout. If `reference dictionary` is not supplied,
capitalisation is not checked. The reference dictionary is usually `ddl.dic`, available from [the COMCIFS github 
repository](https://github.com/COMCIFS/cif_core). For usage information, `julia linter.jl --help`.

## Comparison

Check that two dictionaries have identical contents. Before running you will need to edit `compare.jl` to
set the locations of the DDL2 and DDLm reference dictionaries on your local filesystem (constant definitions
at the top of the file).

Execute by running `julia compare.jl --lang <lang> -w -c <dic1>
<dic2>`. If `-w`, ignore whitespace differences.  If `-c`, ignore case
differences.  `lang` is the language (`ddl2` or `ddlm`) that the
dictionaries are written in. Note that only a subset of DDL2
attributes are currently checked.

## Pretty printer

Format a dictionary according to layout style guide.

Execute by running `julia pretty_print.jl <before> <after>` where
`before` is the input dictionary file and `after` is the name of the
pretty-printed file. Option -e will expand templated imports within
the dictionary. Default is to leave the import statement untouched.
