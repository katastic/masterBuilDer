module help;
import std.stdio;

/// Display help prompt
void displayHelp(){
	writeln("");
	writeln("  mb[.exe] [command] [option=value] [option=value] -- args");
	writeln("");
	writeln("\tinit  - create a default build config. TODO.");
	writeln("\trun   - run the program");
	writeln("\tbuild - actually build");
	writeln("\tclean - clean up temporary files");
	writeln("\tcheck - check if any files have changed and list them.");
	writeln("\ttry   - see if the build config would produce a compiler command");
	writeln("\tlint  - run DScanner");
	writeln("\tquote - recieve a verse about the Master Builder");
	writeln("\thelp  - this help screen.");
	writeln("");
	writeln("\tOptions:");
	writeln("\t\tparallel=yes  - run compile in parallel.");
	writeln("\t\tcached=true   - compile temp obj files for caching.");
    writeln("\t\t ^---use yes/true/on or no/false/off");
    writeln("\t\t");
	writeln("\t\tprofile=name/of/profile (profile=release, profile=debug, etc)");
	writeln("\t\ttarget=windows/linux (Use commands for a different OS. Default: Your host OS.)");
	writeln("\t\tcompilerflags=\"taco is a bad man\" (use shell quotes for strings with spaces) ");
	writeln("\t\tlinkerflags=--test                  (quotes not required if no spaces)");
	writeln("");
	writeln("\tFor passing commandline arguments to the program, use -- to end");
	writeln("\t  internal processing of args and send them to the program.");
	writeln("");
	writeln("\tExample usage:");
	writeln("");
	writeln("\t masterBuilder build profile=debug -- hello!");
	writeln("\t  - build profile named debug, run, and pass it \"hello!\" ");
	}
