[[masterBuilDer]]
	dmd uses -L to pass command to linker
	ld for linux
		-l/path/to/library		where library = library.a unless you PREFIX the path with :
		-L/path/to/librarydirectory
	so
	-L-l  and
	-L-L

	i think we want -ldallegro5dmd -> becomes -> libdallegro5dmd.a




    - Should we be separating runToml into profile vs global scans?

    - eventually dependency graphing, and building submodules, and... maybe... reading/parsing dub files.

    - any support for array sets on commandline? We can set say, parallel=true/on/yes
        but what about:

            dscanner:skip=120characters,undocumented
            dscanner:skip=120characters , undocumented
                - prune whitespace, ban whitespace from names.
                - also note the section header ability of setting [dscanner]
                 with SECTION:OPTION=value,value2,value3

            but what if we need to set a value with whitespace?
                specialFlags="-d -taco -rTl"
            
            quotes will have to be manually parsed. Make sure shell won't modify quote marks, single quotes, etc. Though, if you're specifying weird, long stuff, how about just edit the CONFIG FILE?

    + basic ASCII colorize.

    - we could add multiple stage compile for template string substitution phase built in. So if the first phase fails, it stops and reports.
    - 'mb' for short?

    + need to add the -- argument support and just dump the rest to the called program.



    - script:
        check for 
            version(windows)    (first letter should be capital!)
            version(linux)

    - support separate unittest files because I don't give two shits what DLang thinks is acceptable (that unittests should pollute and fill up a normal D file).
        e.g.
            myFile.d
            myFile.dunit
        or (specify different unit test directory)
            myFile.d
            unittests\myFile.dunit

    - FUZZY IMPORTER
        - remove every import statement, tries to compile. If error message shows up, adds it and only the required sub-imports (up to X number, otherwise mass import). If no 
        error, it's gone. Show diff log for [Y/n] approval.
            removes:
                import std.parallelism;
            builds:
                Error: undefined identifier `taskPool`
            adds:
                import std.parallelism : taskPool;


        source\utility.d(27,35): Error: no property `array` for type `MapResult!(__lambda2, TOMLValue[])`, perhaps `import std.array;` is needed?

            grep "perhaps `import ...` is needed?"

        we could have it auto-write those import statements anyway even WITHOUT fuzzy checking but sometimes it could be wrong.

    - function/class length warner. (is there an easy non-AST way to do this?)


    + we can COLORIZE output with ascii codes. [can we detect a proper terminal on windows?]
        - highlight output path only, in the output string. or other important info

        - not sure how 'try' would work with intermediates. it would still have to make the intermediates just not the final build.
            - also not sure it's even needed once the code works. It's basically just "build + debug logs"

    - still not properly dumping to temp directory (partially related to next point)
        - how do we handle multiple sourcepaths? 1 temp path for each source.
            - HOWEVER, what about recursive?

        - easiest could be something dumb: temp directory plus full normal path replicated.
            (but we gotta make all the folders)

            so 
                /src/
                /src/my/
                /src/my/stuff

            becomes
                /temp/src/
                /temp/src/my
                /temp/src/my/stuff
    
    + could add MULTI-THREADED intermediate compiles easily! 

    + we could make a lot of this easier if we split files into 
        {path, filename}
        or even
        {path, filename{name, extension}}
            also how do we do absolute vs relative paths?

            std.path probably does this all minus my personal flair on the API.

	tools we could add:
		- fuzzy importer. Tries to remove each import and see if it still compiles. 
		- create [init] buildscript. Dumps the default values into a TOML file!
		- scan for (remove?) too many repeating newlines (dLawn scripts)
		- [line] counts? pretty simple. Could support random scripts after succeeding builds though.
		- list any FIXME, TODO, etc in source files. also LAST if you want to mark where you worked last at end off day.
		- [unit] tests
		- support ASCII colorizing? re-implement python pygments without having to invoke it or dep on it?
		- for fun: FUZZY FIXER. Use genetic algorithm to try to match nearest wrong/mispelled string to correct one.

		- could support override= for overriding any build config. So you can specify a different
		 output target name or build line for testing stuff quickly. But lets be honest, editinng 
		 the config will be just as fast.

		 - help options
		 	- enumerate all the custom option flags that can be set. exeConfig, profileConfig, etc.

	todo:
		- figure out dmd binary file compilation import issue.
			+ specify -I/src/ for folders that get imported. May have to include all source 
				and recursiveSource folders
		+ filesList is a bunch of FILES. We need to trim each `.d` and replace it with `.obj`. 
			- Might be as simple as string replace. But what if some moron has .d _inside_ their filename?
		- what if file is REMOVED?
		- do RECURSIVE file path scans work? 
            - And also manual lib names (instead of paths)
		+ dump individual compiled files into a temp directory (specified WHERE?)
		- specify alternate cachefile name
		+ why do we SCAN FILES on alternative OS/configurations??? It's just going to exception out.

	- do we store cached files PER PROFILE??? Because if we change profile the file caches aren't updated. 
			- Maybe store each profile in its own section.

	special scripts for profiles. Kinda already supported just remove scanning.
	 - "scan" (or other name. Scans for all TODO, FIXME, etc)
	 - "lines" (lines of code)
	 - "
+/